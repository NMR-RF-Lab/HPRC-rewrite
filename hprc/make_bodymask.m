function mask = make_bodymask(magnitude)
%MAKE_BODYMASK Automatic binary body mask from multi-echo magnitude data.
%
%   mask = MAKE_BODYMASK(magnitude) returns a logical [X Y Z] mask marking
%   the leg (signal) region for each slice. This replaces the interactive
%   ROI drawing / active-contour seeding in the original pipeline so the
%   batch can run headless. Uses the Image Processing Toolbox.
%
%   magnitude may be [X Y Z] or [X Y Z nTE]; the first echo is used.

if ndims(magnitude) == 4
    m = magnitude(:,:,:,1);
else
    m = magnitude;
end
m = double(m);

[nx, ny, nz] = size(m);
mask = false(nx, ny, nz);
se = strel('disk', 3);

for k = 1:nz
    sl = m(:,:,k);
    mx = max(sl(:));
    if mx <= 0
        continue
    end
    sl = sl / mx;

    % Otsu threshold, then relax slightly so we do not clip low-signal muscle.
    t = graythresh(sl);
    bw = sl > 0.6 * t;

    % Clean up: close gaps, fill interior, drop specks, keep largest blob.
    bw = imclose(bw, se);
    bw = imfill(bw, 'holes');
    bw = bwareaopen(bw, round(0.01 * nx * ny));
    cc = bwconncomp(bw);
    if cc.NumObjects > 1
        np = cellfun(@numel, cc.PixelIdxList);
        keep = false(size(bw));
        keep(cc.PixelIdxList{np == max(np)}) = true;
        bw = keep;
    end
    mask(:,:,k) = bw;
end
end
