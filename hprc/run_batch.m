function run_batch(mode)
%RUN_BATCH Headless batch driver for bipolar fat-water separation on HPRC.
%
%   RUN_BATCH('first')  Process ONLY the review series (last SUSHI date) and
%                       write a PDFF preview so you can confirm it looks right.
%   RUN_BATCH('rest')   Process every OTHER series (run after you approve).
%   RUN_BATCH('all')    Process the review series first, then all the rest.
%
%   With no argument the mode is taken from the FWSEP_MODE environment
%   variable (default 'all'), so it can be driven from a SLURM script with
%       matlab -batch "run_batch"
%
%   Results are written as one .mat per series to cfg.output_root:
%       <date>__<seriesname>.mat   containing struct `res`
%   No QSM / MEDI stages are run; this produces Fat, Water, PDFF, FieldMap,
%   R2* only.

if nargin < 1
    mode = getenv('FWSEP_MODE');
    if isempty(mode), mode = 'all'; end
end
mode = lower(char(mode));

cfg = fw_config();

% Make the hprc code, the bipolar separator repo, and the Hernando ISMRM
% toolbox visible.
addpath(cfg.hprc_dir);
if isfolder(cfg.bipolar_path)
    addpath(genpath(cfg.bipolar_path));
else
    warning('run_batch:bipolarPath', ...
        'Bipolar repo not found:\n  %s\nClone it or set FWSEP_BIPOLAR_PATH.', ...
        cfg.bipolar_path);
end
if isfolder(cfg.ismrm_toolbox_path)
    addpath(genpath(cfg.ismrm_toolbox_path));
else
    warning('run_batch:ismrmPath', ...
        'ISMRM toolbox not found:\n  %s\nClone CREAM_PDFF or set FWSEP_ISMRM_PATH.', ...
        cfg.ismrm_toolbox_path);
end

fprintf('==========================================================\n');
fprintf(' Bipolar fat-water batch  |  mode = %s\n', mode);
fprintf(' DICOM root : %s\n', cfg.dicom_root);
fprintf(' Output root: %s\n', cfg.output_root);
fprintf(' Bipolar    : %s\n', cfg.bipolar_path);
fprintf(' ISMRM path : %s\n', cfg.ismrm_toolbox_path);
fprintf('==========================================================\n');

check_dependencies();

series = find_series(cfg);
if isempty(series)
    error('run_batch:noSeries', 'No GRE2D_FATWATER magnitude series found under %s', cfg.dicom_root);
end

switch mode
    case 'first'
        todo = series(1);
        force_preview = true;
    case 'rest'
        todo = series(2:end);
        force_preview = cfg.save_preview;
    case 'all'
        todo = series;
        force_preview = cfg.save_preview;
    otherwise
        error('run_batch:mode', 'Unknown mode "%s" (use first|rest|all).', mode);
end

fprintf('Series to process: %d of %d found.\n\n', numel(todo), numel(series));

maybe_start_pool(cfg);

nok = 0; nfail = 0;
for i = 1:numel(todo)
    mag_folder = todo{i};
    tag = series_tag(cfg, mag_folder);
    fprintf('----- [%d/%d] %s -----\n', i, numel(todo), tag);
    t0 = tic;
    try
        d    = load_fatwater_dicom(mag_folder, cfg);
        mask = make_bodymask(d.magnitude);
        res  = separate_one(d, mask, cfg);
        res.source_folder = mag_folder;
        res.processed_on  = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));

        out_mat = fullfile(cfg.output_root, [tag '.mat']);
        save(out_mat, 'res', '-v7');   % match the legacy pipeline's default format
        fprintf('  saved %s\n', out_mat);

        if force_preview || cfg.save_preview
            png = fullfile(cfg.output_root, [tag '_PDFF.png']);
            save_pdff_preview(res, png);
            fprintf('  preview %s\n', png);
        end
        nok = nok + 1;
    catch ME
        nfail = nfail + 1;
        fprintf(2, '  FAILED: %s\n', ME.message);
        if ~isempty(ME.stack)
            fprintf(2, '  (%s line %d)\n', ME.stack(1).name, ME.stack(1).line);
        end
    end
    fprintf('  elapsed %.1f s\n\n', toc(t0));
end

fprintf('==========================================================\n');
fprintf(' Done. %d succeeded, %d failed.\n', nok, nfail);
if strcmp(mode, 'first')
    fprintf('\n REVIEW STEP: inspect the *_PDFF.png / .mat in\n   %s\n', cfg.output_root);
    fprintf(' If it looks right, launch the rest with mode "rest".\n');
end
fprintf('==========================================================\n');
end

% -----------------------------------------------------------------------
function tag = series_tag(cfg, mag_folder)
% Unique, informative tag from the path relative to dicom_root, with path
% separators turned into "__". Flat series ->  20250506__GRE2D_FATWATER_SUSHI_0012
% Nested series -> 20240711__Aphrodite__GRE2D_FATWATER_APHRODITE_0012
mag_folder = regexprep(char(mag_folder), '[\\/]+$', '');
root = regexprep(char(cfg.dicom_root), '[\\/]+$', '');
rel = mag_folder;
if strncmpi(mag_folder, root, numel(root))
    rel = mag_folder(numel(root)+1:end);
end
rel = regexprep(rel, '^[\\/]+', '');
tag = regexprep(rel, '[\\/]+', '__');
end

function check_dependencies()
need = {'image_toolbox','Image Processing Toolbox';
        'optimization_toolbox','Optimization Toolbox';
        'distrib_computing_toolbox','Parallel Computing Toolbox'};
for i = 1:size(need,1)
    if ~license('test', need{i,1})
        warning('run_batch:toolbox', ...
            '%s not licensed/available. On Grace ensure the MATLAB module exposes it.', need{i,2});
    end
end
if isempty(which('Function_Bipolar_GC'))
    error('run_batch:noFunc', ...
        'Function_Bipolar_GC not on path. Check cfg.repo_root in fw_config.m.');
end
% Base graph-cut engine from the Hernando toolbox.
if isempty(which('graphCutIterations')) || isempty(which('getPhiMatrixMultipeak'))
    error('run_batch:ismrm', ...
        ['Hernando ISMRM toolbox not on path (graphCutIterations / ', ...
         'getPhiMatrixMultipeak missing). Check cfg.ismrm_toolbox_path.']);
end
end

function maybe_start_pool(cfg)
if ~cfg.use_parpool, return; end
if ~license('test', 'distrib_computing_toolbox'), return; end
try
    if isempty(gcp('nocreate'))
        n = str2double(getenv('SLURM_CPUS_PER_TASK'));
        if isnan(n) || n < 1, n = feature('numcores'); end
        parpool('local', n);
        fprintf('Started parpool with %d workers.\n\n', n);
    end
catch ME
    warning('run_batch:pool', 'Could not start parpool (%s). Continuing serial.', ME.message);
end
end
