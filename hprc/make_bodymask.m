function mask = make_bodymask(magnitude)
%MAKE_BODYMASK Automatic binary body mask (faithful port of GRMD Operations.Mask).
%
%   mask = MAKE_BODYMASK(magnitude) returns a logical [X Y Z] mask marking the
%   leg (signal) region for each slice. This is a direct port of the legacy
%   GRMD pipeline's Operations.Mask (Images/+Operations/Mask.m) as invoked for
%   the bipolar fat-water separation, so the mask fed to Function_Bipolar_GC
%   matches the reference exactly.
%
%   Provenance / which GRMD call this reproduces:
%     For the 'BipolarIGC' method, DogAnalysis.m runs the separation on D_raw
%     (line "D = D_raw;"), whose mask is the 5-argument call created during
%     preprocessing:
%         Operations.Mask(Image, WeightedMagnitude, verbose, 3, nobone)
%     with thresh = 3 (percent of max) and nobone = false. The later 6-argument
%     re-mask with NoiseSTD (Fit_ppm_complex) is computed for D_bpc but DISCARDED
%     for BipolarIGC, so it is intentionally NOT reproduced here (no MEDI /
%     Fit_ppm_complex dependency needed). Bone removal is off (nobone = false),
%     so the MaskBone branch is omitted.
%
%   magnitude may be [X Y Z] or [X Y Z nTE]; multi-echo input is combined with
%   an echo MIP (root-sum-of-squares across echoes), matching get_echoMIP.
%
%   Requires the Image Processing Toolbox (activecontour, bwconncomp, imfill,
%   imdilate, imerode, strel) — already a hard dependency of this pipeline.

% ---- Echo MIP (root-sum-of-squares across echoes), matching get_echoMIP -----
if ndims(magnitude) >= 4
    mag = sqrt(sum(abs(double(magnitude)).^2, 4));
else
    mag = abs(double(magnitude));
end

% Guard against an empty/zero volume (Operations.Mask assumes real signal;
% activecontour on an all-zero image is undefined).
mmax = max(mag(:));
if isempty(mmax) || mmax <= 0
    mask = false(size(mag));
    return
end

thresh = 3;   % percent of max (GRMD Operations.Mask default for this pipeline)

% ---- Basic 3D threshold mask -----------------------------------------------
mask1 = mag >= (thresh/100 * mmax);

% Fill holes slice by slice.
for z = 1:size(mask1, 3)
    mask1(:,:,z) = imfill(mask1(:,:,z), 'holes');
end

% Remove large noise regions: keep connected components larger than 10% of the
% total masked volume. This retains BOTH legs (each is a large blob) rather
% than only the single largest one.
CC = bwconncomp(mask1);
if CC.NumObjects > 1
    numRegPixels = cellfun(@numel, CC.PixelIdxList);
    numPixels    = sum(mask1, 'all');
    included     = numRegPixels > numPixels/10;
    mask1 = false(size(mask1));
    for i = 1:numel(numRegPixels)
        if included(i)
            mask1(CC.PixelIdxList{i}) = true;
        end
    end
end

% ---- Active-contour (Chan-Vese) refinement ---------------------------------
% Generous initial contour, then evolve it to the true body boundary.
mask_basic = mag > mmax/10;
mask_basic = imfill(mask_basic, 'holes');
mask_basic = imdilate(mask_basic, strel('disk', 20));

mask2 = activecontour(mag, mask_basic, 'Chan-vese');
mask2 = imfill(mask2, 'holes');

% Combine the threshold and active-contour masks.
mask = (mask1 + mask2) > 0;

% (GRMD removes bone here only when nobone = true; this pipeline runs
%  nobone = false, so no bone removal.)

% Fill holes on every slice. Matches GRMD's hardcoded "for i = 1:50"; these
% series always contain exactly 50 slices (the mask is built from the full
% volume regardless of cfg.slices, which only limits what separate_one runs).
for i = 1:50
    mask(:,:,i) = imfill(mask(:,:,i), 'holes');
end

% Remove any sections significantly smaller than the main one (< 5% of largest).
CC = bwconncomp(mask);
NumPixels = cellfun(@numel, CC.PixelIdxList);
msk = false(size(mask));
for i = 1:numel(NumPixels)
    if NumPixels(i) > max(NumPixels) * 0.05
        msk(CC.PixelIdxList{i}) = true;
    end
end

% ---- Final revisions -------------------------------------------------------
msk = imfill(msk, 'holes');
msk = imerode(msk, strel('disk', 1));
msk = imdilate(msk, strel('disk', 1));
mask = msk > 0;   % ensure logical
end
