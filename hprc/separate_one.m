function res = separate_one(d, mask, cfg)
%SEPARATE_ONE Bipolar graph-cut fat-water separation for one loaded series.
%
%   res = SEPARATE_ONE(d, mask, cfg) runs Function_Bipolar_GC on the complex
%   data in d (from load_fatwater_dicom) restricted to the voxels in `mask`,
%   and returns a struct of maps. No QSM / MEDI stages are involved.
%
%   res fields (all [X Y Z]):
%       Water, Fat        complex species amplitudes
%       PDFF              proton-density fat fraction, [0 1], masked
%       FieldMap          B0 field map (Hz)
%       R2star            R2* map (1/s)
%       Mask              the mask used
%   res also carries d.TE, d.voxelSize, d.name for provenance.

if nargin < 3, cfg = fw_config(); end

sz = d.matrixSize;
if isempty(cfg.slices)
    vec_slices = 1:sz(3);
else
    vec_slices = cfg.slices(:).';
end

% ---- imDataParams ----------------------------------------------------
imDataParams.images   = d.images;                 % [X Y Z 1 nTE] complex
imDataParams.TE       = d.TE;                      % seconds
imDataParams.voxelSize = d.voxelSize;
imDataParams.FieldStrength = d.FieldStrength;      % Tesla
imDataParams.PrecessionIsClockwise = cfg.PrecessionIsClockwise;
imDataParams.mask_fwseparation = logical(mask);

% ---- algoParams ------------------------------------------------------
algoParams = cfg.algo;
algoParams.species = cfg.species;
algoParams.gyro    = cfg.gyro;
algoParams.slice_image = vec_slices(max(1, round(numel(vec_slices)/2)));

% ---- run -------------------------------------------------------------
% Pass VERBOSE so slice-by-slice progress prints to the SLURM .out log.
verbose = isfield(cfg, 'verbose') && cfg.verbose;
out = Function_Bipolar_GC(imDataParams, algoParams, vec_slices, verbose);
if isempty(out)
    error('separate_one:failed', 'Function_Bipolar_GC returned empty for %s', d.name);
end

Water = zeros(sz);
Fat   = zeros(sz);
Field = zeros(sz);
R2s   = zeros(sz);
Water(:,:,vec_slices) = out.species(1).amps(:,:,vec_slices);
Fat(:,:,vec_slices)   = out.species(2).amps(:,:,vec_slices);
Field(:,:,vec_slices) = out.fieldmap(:,:,vec_slices);
R2s(:,:,vec_slices)   = out.r2starmap(:,:,vec_slices);

% ---- automatic fat/water swap correction -----------------------------
% Bipolar graph-cut separation intermittently flips fat<->water on
% individual slices. Undo it with the same in-mask energy heuristic the GRMD
% pipeline used (only the amplitude maps are swapped, before PDFF). Field map
% and R2* are left as-is, matching the legacy automatic check.
[Water, Fat, swapped] = correct_fatwater_swaps(Water, Fat, logical(mask), vec_slices, verbose);

% ---- PDFF ------------------------------------------------------------
denom = abs(Fat) + abs(Water);
PDFF = zeros(sz);
nz = denom > 0;
PDFF(nz) = abs(Fat(nz)) ./ denom(nz);
PDFF = PDFF .* logical(mask);

res.name       = d.name;
res.Water      = Water;
res.Fat        = Fat;
res.PDFF       = PDFF;
res.FieldMap   = Field;
res.R2star     = R2s;
res.Mask       = logical(mask);
res.SwappedSlice = swapped;    % slices auto-corrected for fat/water swap
res.TE         = d.TE;
res.voxelSize  = d.voxelSize;
res.FieldStrength = d.FieldStrength;
res.slices     = vec_slices;
end
