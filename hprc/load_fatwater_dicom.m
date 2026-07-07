function d = load_fatwater_dicom(mag_folder, cfg)
%LOAD_FATWATER_DICOM Load a bipolar multi-echo GRE fat-water series.
%
%   d = LOAD_FATWATER_DICOM(mag_folder, cfg) reads a Siemens *.IMA series
%   from mag_folder (the magnitude series, e.g. ..._0012) together with its
%   sibling phase series (mag series number + 1, e.g. ..._0013) and returns
%   a struct with the complex image and acquisition parameters ready for
%   Function_Bipolar_GC.
%
%   Output struct d:
%       d.images       [X Y Z 1 nTE] complex (magnitude .* exp(1i*phase))
%       d.magnitude    [X Y Z nTE]   magnitude only
%       d.TE           [1 nTE]       echo times in SECONDS
%       d.deltaTE      scalar        mean echo spacing (s)
%       d.voxelSize    [1 3]         mm
%       d.matrixSize   [1 3]
%       d.FieldStrength scalar       Tesla (derived from imaging frequency)
%       d.name         char          series folder name
%
%   The echo/slice layout, phase rescaling and slice ordering mirror the
%   lab's own loadima.m so results match the existing pipeline.

if nargin < 2, cfg = fw_config(); end

mag_folder = char(mag_folder);
phase_folder = sibling_phase_folder(mag_folder);
if ~isfolder(phase_folder)
    error('load_fatwater_dicom:noPhase', ...
        'Phase series folder not found next to magnitude series:\n  %s', phase_folder);
end

[mag, TE, sliceLoc, hdr0]  = read_series(mag_folder, false, cfg);
[phs, ~,  ~,        hdrP0] = read_series(phase_folder, true, cfg);

if ~isequal(size(mag), size(phs))
    error('load_fatwater_dicom:sizeMismatch', ...
        'Magnitude %s and phase %s have different sizes.', ...
        mat2str(size(mag)), mat2str(size(phs)));
end

% Avoid killing phase where magnitude is exactly zero (see loadima.m).
if min(mag(:)) == 0
    mag = mag + 1/max(mag(:));
end

iField = mag .* exp(1i*phs);                 % [X Y Z nTE]
nTE = size(iField, 4);

d.name        = folder_name(mag_folder);
d.magnitude   = mag;
d.images      = reshape(iField, [size(iField,1), size(iField,2), size(iField,3), 1, nTE]);
d.TE          = TE(:).' / 1000;              % ms -> s
if nTE > 1
    d.deltaTE = mean(diff(d.TE));
else
    d.deltaTE = 0;
end
d.matrixSize  = size(mag, 1:3);

% Voxel size (mm): in-plane from PixelSpacing, through-plane from spacing.
ps = hdr0.PixelSpacing(:).';
if isfield(hdr0, 'SpacingBetweenSlices')
    zsp = double(hdr0.SpacingBetweenSlices);
else
    zsp = double(hdr0.SliceThickness);
end
d.voxelSize = [double(ps), zsp];

% B0 as seen by protons = imaging frequency (MHz) / gyro (MHz/T). This is
% what the fat-frequency (Hz) conversion inside the toolbox expects.
d.FieldStrength = double(hdr0.ImagingFrequency) / cfg.gyro;

d.sliceLocations = sliceLoc;
d.mag_hdr   = hdr0;
d.phase_hdr = hdrP0;
end

% -----------------------------------------------------------------------
function pf = sibling_phase_folder(mag_folder)
% GRE2D_FATWATER_<name>_<NNNN> -> replace NNNN with NNNN+1.
[parent, name] = fileparts(strip_trailing_sep(mag_folder));
tok = regexp(name, '^(.*_)(\d{4})$', 'tokens', 'once');
if isempty(tok)
    error('load_fatwater_dicom:badName', ...
        'Series folder does not end in a 4-digit id: %s', name);
end
pf = fullfile(parent, sprintf('%s%04d', tok{1}, str2double(tok{2}) + 1));
end

function n = folder_name(p)
[~, n] = fileparts(strip_trailing_sep(p));
end

function p = strip_trailing_sep(p)
while ~isempty(p) && (p(end) == filesep || p(end) == '/' || p(end) == '\')
    p(end) = [];
end
end

% -----------------------------------------------------------------------
function [vol, TE, sliceLoc, hdr0] = read_series(folder, is_phase, cfg) %#ok<INUSD>
% Read every *.IMA in a folder into a [X Y nSlice nTE] volume, grouping by
% EchoNumbers and ordering slices by SliceLocation. For phase series the
% raw values are rescaled to [-pi, pi] exactly as loadima.m does.

files = dir(fullfile(folder, '*.IMA'));
files = files(~[files.isdir]);
if isempty(files)
    error('load_fatwater_dicom:empty', 'No *.IMA files in %s', folder);
end
nf = numel(files);

echoNum  = zeros(nf,1);
echoTime = zeros(nf,1);
sliceLc  = zeros(nf,1);
hdrs     = cell(nf,1);
for i = 1:nf
    h = dicominfo(fullfile(folder, files(i).name));
    hdrs{i}     = h;
    echoNum(i)  = double(h.EchoNumbers);
    echoTime(i) = double(h.EchoTime);
    sliceLc(i)  = double(h.SliceLocation);
end
hdr0 = hdrs{1};

echoes = unique(echoNum);
nTE = numel(echoes);
locs = unique(round(sliceLc, 3));
nSl = numel(locs);

if nSl * nTE ~= nf
    warning('load_fatwater_dicom:count', ...
        ['%s: %d files but %d slices x %d echoes = %d. ', ...
         'Duplicates/extras will be overwritten (last wins).'], ...
        folder, nf, nSl, nTE, nSl*nTE);
end

rows = double(hdr0.Rows);
cols = double(hdr0.Columns);
vol  = zeros(rows, cols, nSl, nTE);

% Rescale factors for phase (per loadima.m: default slope 2, intercept -4096).
if is_phase
    if isfield(hdr0, 'RescaleSlope'),     RS = double(hdr0.RescaleSlope);     else, RS = 2;     end
    if isfield(hdr0, 'RescaleIntercept'), RI = double(hdr0.RescaleIntercept); else, RI = -4096; end
    raw_max = 0;
end

for i = 1:nf
    ie = find(echoes == echoNum(i), 1);
    is = find(locs   == round(sliceLc(i), 3), 1);
    img = double(dicomread(fullfile(folder, files(i).name)));
    vol(:,:,is,ie) = img;
    if is_phase
        raw_max = max(raw_max, max(img(:)));
    end
end

if is_phase
    vol = (vol * RS + RI) / raw_max * pi;     % -> [-pi, pi]
end

% Echo time per echo index, sorted to match `echoes`.
TE = zeros(1, nTE);
for k = 1:nTE
    TE(k) = echoTime(find(echoNum == echoes(k), 1));
end
sliceLoc = locs(:).';
end
