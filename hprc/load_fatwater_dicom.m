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

% The bipolar graph-cut separator pairs odd/even readout echoes and therefore
% needs an EVEN number of echoes (Function_Bipolar_GC allocates numte/2). This
% data has 7 echoes, so drop the LAST echo to keep a clean bipolar pairing
% (echoes 1-6: odd {1,3,5} / even {2,4,6}). Dropping the last (not the first)
% echo preserves the polarity-to-index relationship the correction assumes.
if cfg.force_even_echoes && mod(nTE, 2) == 1
    warning('load_fatwater_dicom:oddEchoes', ...
        ['%s: %d echoes is odd; bipolar separation needs an even count. ', ...
         'Dropping the last echo (using %d).'], folder_name(mag_folder), nTE, nTE-1);
    nTE    = nTE - 1;
    iField = iField(:,:,:,1:nTE);
    mag    = mag(:,:,:,1:nTE);
    TE     = TE(1:nTE);
end

% Legacy "zipped" step: 2x in-plane k-space zero-fill (sinc interpolation) of
% the complex multi-echo image, reproducing GRMD/DogAnalysis.m so the whole
% separation runs at 384x384 like the old pipeline. Applied BEFORE separation,
% and the body mask magnitude is taken from the interpolated complex image.
if cfg.zipped
    iField = kspace_zerofill2x(iField);   % [2X 2Y Z nTE] complex
    mag    = abs(iField);                 % magnitude for make_bodymask, at 2x
end

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
if cfg.zipped
    d.voxelSize(1:2) = d.voxelSize(1:2) / 2;   % 2x interpolation halves in-plane spacing
end

% B0 as seen by protons = imaging frequency (MHz) / gyro (MHz/T). This is
% what the fat-frequency (Hz) conversion inside the toolbox expects.
d.FieldStrength = double(hdr0.ImagingFrequency) / cfg.gyro;

d.sliceLocations = sliceLoc;
d.mag_hdr   = hdr0;
d.phase_hdr = hdrP0;
end

% -----------------------------------------------------------------------
function out = kspace_zerofill2x(in)
%KSPACE_ZEROFILL2X 2x in-plane k-space zero-fill (sinc interpolation).
%   Replicates GRMD/DogAnalysis.m's "zipped" preprocessing: pad the image to
%   suppress ghosting, FFT to k-space, zero-fill, inverse FFT, and crop back.
%   in/out: [X Y Z nTE] complex; out is [2X 2Y Z nTE].
[nx, ny, nz, nte] = size(in);
psize = [nx, ny];
out = zeros(2*nx, 2*ny, nz, nte, 'like', in);
for j = 1:nte
    for i = 1:nz
        img = padarray(in(:,:,i,j), psize/2, 0, 'both');   % image-space pad -> [2X 2Y]
        k   = ifftshift(ifft2(ifftshift(img)));
        k   = padarray(k, psize, 0, 'both');                % zero-fill k-space
        im  = fftshift(fft2(fftshift(k)));
        out(:,:,i,j) = im(nx+1:end-nx, ny+1:end-ny);        % crop back -> [2X 2Y]
    end
end
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
