function [Water, Fat, swapped] = correct_fatwater_swaps(Water, Fat, mask, slices, verbose)
%CORRECT_FATWATER_SWAPS Automatic per-slice fat/water swap correction.
%
%   [Water, Fat, swapped] = CORRECT_FATWATER_SWAPS(Water, Fat, mask, slices,
%   verbose) flips the water and fat maps on any slice whose in-mask fat
%   energy exceeds 1.5x its water energy. This is the same automatic heuristic
%   the legacy GRMD pipeline used (DogAnalysis.m, "Check for fat/water swaps -
%   automatic").
%
%   Bipolar graph-cut separation intermittently assigns fat to the water map
%   (and water to the fat map) on individual slices. Because the two species
%   are otherwise interchangeable to the separator, whole slices can come out
%   flipped; this undoes that.
%
%   Inputs
%       Water, Fat   [X Y Z] complex species amplitude maps
%       mask         [X Y Z] logical body mask (energy is summed in-mask only)
%       slices       vector of slice indices to check (default: all)
%       verbose      logical, print which slices were flipped (default false)
%
%   Outputs
%       Water, Fat   maps with swapped slices corrected
%       swapped      1xZ logical, true for each slice that was flipped
%
%   Only the amplitude maps are swapped; the field map and R2* map are left
%   untouched, matching the legacy automatic check. The 1.5x (rather than 1.0x)
%   threshold avoids flipping slices that are genuinely fat-dominant.

if nargin < 4 || isempty(slices), slices = 1:size(Water, 3); end
if nargin < 5, verbose = false; end

mask = logical(mask);
swapped = false(1, size(Water, 3));

for sl = slices(:).'
    m  = mask(:,:,sl);
    wE = sum(abs(Water(:,:,sl)).^2 .* m, 'all');
    fE = sum(abs(Fat(:,:,sl)).^2   .* m, 'all');

    if fE > 1.5 * wE
        tmp             = Water(:,:,sl);
        Water(:,:,sl)   = Fat(:,:,sl);
        Fat(:,:,sl)     = tmp;
        swapped(sl)     = true;
    end
end

if verbose && any(swapped)
    fprintf('  swap-correct: flipped %d slice(s): %s\n', ...
        nnz(swapped), mat2str(find(swapped)));
end
end
