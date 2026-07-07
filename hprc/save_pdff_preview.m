function save_pdff_preview(res, png_path)
%SAVE_PDFF_PREVIEW Write a PNG montage of the PDFF maps (no display needed).
%
%   SAVE_PDFF_PREVIEW(res, png_path) tiles the reconstructed PDFF slices into
%   a grid, applies a colormap, and writes an RGB PNG with imwrite. It never
%   opens a figure, so it is safe on headless HPRC compute nodes.

pdff = res.PDFF;
sl = res.slices;
pdff = pdff(:,:,sl);
[nx, ny, nz] = size(pdff);

cols = ceil(sqrt(nz));
rows = ceil(nz / cols);
tile = zeros(rows*nx, cols*ny);
for k = 1:nz
    r = floor((k-1)/cols);
    c = mod(k-1, cols);
    tile(r*nx + (1:nx), c*ny + (1:ny)) = pdff(:,:,k);
end

% PDFF is already in [0 1]; map to an indexed image then to RGB.
cmap = parula(256);
idx = round(tile * 255) + 1;
idx = min(max(idx, 1), 256);
rgb = ind2rgb(idx, cmap);

imwrite(rgb, png_path);
end
