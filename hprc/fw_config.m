function cfg = fw_config()
%FW_CONFIG Central configuration for the HPRC bipolar fat-water pipeline.
%
%   cfg = FW_CONFIG() returns a struct with every path and parameter used by
%   the batch driver. Edit the values in the "USER SETTINGS" block below, or
%   override any path at run time with an environment variable (handy on the
%   cluster, where you do not want to edit code):
%
%       FWSEP_DICOM_ROOT   -> cfg.dicom_root
%       FWSEP_OUTPUT_ROOT  -> cfg.output_root
%
%   This file contains NO interactive calls and NO hard-coded Windows-only
%   separators, so it runs unchanged on Windows and on Linux (TAMU HPRC).

% ----------------------------------------------------------------------
% USER SETTINGS
% ----------------------------------------------------------------------

% Root folder that holds the per-date DICOM folders (the folder that
% directly contains 20250506/GRE2D_FATWATER_SUSHI_0012, etc.).
default_dicom_root = fullfile('C:','Users','apad2','Desktop', ...
    'Fat_water_separation','DICOM_Files','DICOM');

% Where result .mat files are written (one per series). Created if missing.
default_output_root = fullfile('C:','Users','apad2','Desktop', ...
    'Fat_water_separation','Results');

% The series that MUST be processed and reviewed first (relative to
% dicom_root). Last SUSHI date, per changes.txt.
cfg.first_series = fullfile('20250506','GRE2D_FATWATER_SUSHI_0012');

% Series folders are named GRE2D_FATWATER_<name>_<NNNN>. The magnitude
% images live in the "mag" series; the phase images live in the very next
% series number (mag+1), matching the scanner export and loadima.m.
cfg.series_glob = 'GRE2D_FATWATER_*';
cfg.mag_series_is_even = true;   % magnitude folders end in an even 4-digit id

% Slices to reconstruct. [] means "all slices in the volume".
cfg.slices = [];

% Print slice-by-slice progress from the separator to the log (helps monitor
% long runs with `tail -f`). Set false for quieter logs.
cfg.verbose = true;

% The bipolar separator requires an EVEN number of echoes (it pairs odd/even
% readout echoes). This data has 7, so drop the last echo to make it 6. Set
% false only if your data already has an even echo count.
cfg.force_even_echoes = true;

% Legacy "zipped" behaviour: 2x in-plane k-space zero-fill of the complex
% images BEFORE separation, so everything runs at 384x384 like the old
% pipeline (GRMD/DogAnalysis.m). This ~4x's the voxel count and therefore the
% runtime (~3 h/series vs ~44 min). Set false for native 192x192.
cfg.zipped = true;

% Parallel pool. NOTE: the current separation code is entirely serial (no
% parfor anywhere), so a pool does not speed anything up and just adds startup
% overhead and holds Parallel Computing Toolbox licenses. Left off by default;
% set true only if a future version adds parfor-based work.
cfg.use_parpool = false;

% Write a lightweight PNG montage of PDFF next to each .mat so results can be
% eyeballed without MATLAB. Off by default (changes.txt asked for .mat), but
% forced on for the first/review series so you can confirm before batching.
cfg.save_preview = false;

% ----------------------------------------------------------------------
% Fat-water separation parameters (Function_Bipolar_GC / ISMRM toolbox)
% ----------------------------------------------------------------------
% Two-species model. Water at 4.7 ppm; fat is a 6-peak model. These are the
% values from the reference example (peanut-oil fat model). If you have an
% in-vivo canine fat model, change species(2).frequency / relAmps here.
cfg.species(1).name      = 'water';
cfg.species(1).frequency = 4.7;
cfg.species(1).relAmps   = 1;
cfg.species(2).name      = 'fat';
cfg.species(2).frequency = [0.80 1.20 2.00 2.66 4.21 5.20];
cfg.species(2).relAmps   = [0.087 0.694 0.128 0.004 0.039 0.048];

% Graph-cut algorithm parameters (see Example_fat_water_separation... .m).
cfg.algo.size_clique          = 1;
cfg.algo.range_r2star         = [0 100];
cfg.algo.NUM_R2STARS          = 26;
cfg.algo.range_fm             = [-500 500];
cfg.algo.NUM_FMS              = 501;
cfg.algo.NUM_ITERS            = 80;
cfg.algo.SUBSAMPLE            = 0;
cfg.algo.DO_OT                = 0;
cfg.algo.LMAP_POWER           = 2;
cfg.algo.lambda               = 0.05;
cfg.algo.LMAP_EXTRA           = 0.05;
cfg.algo.TRY_PERIODIC_RESIDUAL = 0;
cfg.algo.THRESHOLD            = 0.01;
cfg.algo.tik_reg              = 0;
cfg.algo.weight               = 0.5;
cfg.algo.fm_init              = 0;
cfg.algo.plot_debug           = 0;   % headless: never pop figures
cfg.algo.crameri_colormap     = 0;

% Sign convention for the scanner phase. Set to +1 for this data. If fat and
% water come out swapped everywhere in the review series, flip to -1.
cfg.PrecessionIsClockwise = 1;

% Gyromagnetic ratio (MHz/T) used to convert imaging frequency -> B0.
cfg.gyro = 42.5774780505984;

% ----------------------------------------------------------------------
% Resolve paths (environment overrides win; then make absolute).
% ----------------------------------------------------------------------
cfg.dicom_root  = env_or('FWSEP_DICOM_ROOT',  default_dicom_root);
cfg.output_root = env_or('FWSEP_OUTPUT_ROOT', default_output_root);

% Project root = parent of the folder holding this file (the repo that this
% hprc/ folder lives in). Its siblings are the cloned dependency repos.
this_dir     = fileparts(mfilename('fullpath'));
cfg.hprc_dir = this_dir;
cfg.root     = fileparts(this_dir);

% Bipolar separator repo (provides Function_Bipolar_GC and its Functions/).
% Default: sibling clone `bipolar_fat_water_separation`. Override with
% FWSEP_BIPOLAR_PATH on the cluster.
cfg.bipolar_path = env_or('FWSEP_BIPOLAR_PATH', ...
    fullfile(cfg.root, 'bipolar_fat_water_separation'));

% ISMRM (Hernando) fat-water toolbox: the base graph-cut engine. Default: the
% `hernando` folder in the sibling CREAM_PDFF clone. Override with
% FWSEP_ISMRM_PATH on the cluster.
cfg.ismrm_toolbox_path = env_or('FWSEP_ISMRM_PATH', ...
    fullfile(cfg.root, 'CREAM_PDFF', 'hernando'));

if ~exist(cfg.output_root, 'dir')
    mkdir(cfg.output_root);
end
end

function v = env_or(name, default)
v = getenv(name);
if isempty(v)
    v = default;
end
end
