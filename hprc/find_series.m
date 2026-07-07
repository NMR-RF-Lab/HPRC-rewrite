function series = find_series(cfg)
%FIND_SERIES Locate all magnitude fat-water series under the DICOM root.
%
%   series = FIND_SERIES(cfg) scans cfg.dicom_root/<date>/GRE2D_FATWATER_*
%   and returns a cell array of full paths to the MAGNITUDE series (the ones
%   whose 4-digit id is even; the odd sibling holds phase). The series named
%   by cfg.first_series is placed first so the batch driver can process and
%   review it before the rest.

if nargin < 1, cfg = fw_config(); end

root = cfg.dicom_root;
if ~isfolder(root)
    error('find_series:noRoot', 'DICOM root does not exist:\n  %s', root);
end

% Recurse: most dates put the series directly under <date>/, but at least one
% (20240711) nests them under a dog-name subfolder, so search all depths.
found = dir(fullfile(root, '**', cfg.series_glob));
found = found([found.isdir]);

hits = {};
for j = 1:numel(found)
    tok = regexp(found(j).name, '_(\d{4})$', 'tokens', 'once');
    if isempty(tok), continue; end
    is_even = mod(str2double(tok{1}), 2) == 0;
    if cfg.mag_series_is_even == is_even
        hits{end+1} = fullfile(found(j).folder, found(j).name); %#ok<AGROW>
    end
end
hits = unique(hits, 'stable');

% Move cfg.first_series to the front.
first_full = fullfile(root, cfg.first_series);
is_first = strcmp(hits, first_full);
if any(is_first)
    series = [hits(is_first), hits(~is_first)];
else
    warning('find_series:noFirst', ...
        'Configured first series not found, using scan order:\n  %s', first_full);
    series = hits;
end
series = series(:);
end
