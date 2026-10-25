function targets = computeTargets(labelMap, config, method)
% COMPUTETARGETS - StarDist training targets (object probability and ray distances) from an instance label map.
%
% Syntax:
%   .. code-block:: matlab
%
%      targets = deepmib.stardist.computeTargets(labelMap, config)
%      targets = deepmib.stardist.computeTargets(labelMap, config, method)
%
% Reproduces the targets of the StarDist 0.9.2 training generator (``StarDistData2D``) for a
% label patch, so that a model fine-tuned in MIB learns exactly what the pretrained models
% learned:
%
% - **channel 1, probability** = ``edt_prob`` of the label map subsampled with the grid,
%   ``labelMap(1:g:end, 1:g:end)``: inside each object the Euclidean distance to the nearest
%   pixel of another label or the background, divided by the maximum within that object
%   (``+1e-10``); 0 in the background. The image border is **not** treated as background, so an
%   object cut by the patch border keeps a high probability at the border. It is computed on the
%   subsampled map, not subsampled from a full-resolution transform.
% - **channels 2..nRays+1, distances** = ``star_dist`` from every grid pixel
%   ``((i-1)*g+1, (j-1)*g+1)`` of the full-resolution map (no offset): along ray
%   ``k = 0..nRays-1`` at angle ``phi = 2*pi*k/nRays``, step ``(row, col) = (sin phi, cos phi)``
%   in single precision, rounding each position half-to-even (C ``lrint``), until the pixel
%   lies outside the image or has a **different label value** (a touching object stops the
%   ray, not only the background). The overshoot is then corrected:
%   ``dist = |(n - 1 + 0.5/max(|sin phi|, |cos phi|)) * step|`` after ``n`` steps. Background
%   pixels get 0. Distances are in full-resolution pixels.
%
% The output size is ``ceil([H W] ./ grid)``, the same as the network output for a patch whose
% size is divisible by the grid.
%
% The distances are computed by StarDist's own C++ (``stardistMex`` in ``mib/external/stardist``)
% when that MEX file exists, otherwise by a vectorised MATLAB port that
% gives the same values to about 1e-6 px but is much slower (about 0.1-0.2 s per 256x256 patch
% of dense nuclei, enough to stall the GPU during training). The probability channel is always
% computed in MATLAB.
%
% Differences from StarDist, both deliberate: label ids are used as given instead of being cast
% to ``uint16`` (StarDist wraps ids above 65535); negative labels ("ignore" in StarDist) are not
% supported, MIB label maps are unsigned.
%
% Targets must be computed **after** geometric augmentation, because rotation and scaling change
% the ray distances.
%
% Input Arguments:
%   - **labelMap** - [integer] instance label map ``[height, width]``, 0 = background, each
%     object a unique positive id
%   - **config** - [struct] configuration, see deepmib.stardist.defaultConfig; uses ``.grid``
%     and ``.nRays``
%   - **method** *(optional)* - [char] ``'auto'`` (the MEX when it exists and the ids fit in
%     ``uint32``, otherwise MATLAB), ``'mex'`` or ``'matlab'`` (default: ``'auto'``)
%
% Output Arguments:
%   - **targets** - [single] ``[ceil(H/gRow), ceil(W/gCol), 1+nRays]``, probability in channel 1,
%     ray distances in channels ``2:nRays+1``
%
% **Example** - targets of one object:
%
%   .. code-block:: matlab
%
%      labelMap = zeros(64, 64, 'uint16');
%      labelMap(20:40, 15:45) = 1;
%      config = deepmib.stardist.defaultConfig(struct('grid', [2 2]));
%      targets = deepmib.stardist.computeTargets(labelMap, config);
%      size(targets)   % 32 32 33

if nargin < 3; method = 'auto'; end
config = deepmib.stardist.defaultConfig(config);
grid = config.grid;
subsampled = labelMap(1:grid(1):end, 1:grid(2):end);
prob = edtProbability(subsampled);
if strcmp(method, 'auto')
    if exist('stardistMex', 'file') == 3 && max(labelMap(:)) <= intmax('uint32')
        method = 'mex';
    else
        method = 'matlab';
    end
end
switch method
    case 'mex'
        dist = stardistMex('starDist', uint32(labelMap), config.nRays, grid(1), grid(2));
    case 'matlab'
        dist = rayDistances(labelMap, subsampled, grid, config.nRays);
    otherwise
        error('stardist:computeTargets:method', 'Unknown method "%s"; use ''auto'', ''mex'' or ''matlab''', method);
end
targets = cat(3, prob, dist);
end

function prob = edtProbability(labelMap)
% per-object EDT normalised to max 1, as stardist.utils._edt_prob_scipy
[height, width] = size(labelMap);
prob = zeros(height, width, 'single');
if ~any(labelMap(:)); return; end
pixelLists = label2idx(labelMap);
for objectId = 1:numel(pixelLists)
    pixels = pixelLists{objectId};
    if isempty(pixels); continue; end
    [rows, cols] = ind2sub([height width], pixels);
    % bounding box grown by one pixel, except at the image border
    rowFrom = max(1, min(rows) - 1);  rowTo = min(height, max(rows) + 1);
    colFrom = max(1, min(cols) - 1);  colTo = min(width, max(cols) + 1);
    mask = labelMap(rowFrom:rowTo, colFrom:colTo) == objectId;
    if all(mask(:))
        % object fills the whole image: StarDist pads with background in this case
        distance = bwdist(~padarray(mask, [1 1], false));
        distance = distance(2:end-1, 2:end-1);
    else
        distance = bwdist(~mask);
    end
    values = double(distance(mask));
    window = prob(rowFrom:rowTo, colFrom:colTo);
    window(mask) = single(values / (max(values) + 1e-10));
    prob(rowFrom:rowTo, colFrom:colTo) = window;
end
end

function dist = rayDistances(labelMap, subsampled, grid, nRays)
% star_dist (stardist2d.cpp c_star_dist), vectorised over all (foreground grid pixel, ray)
% pairs; each loop iteration advances every ray that has not stopped by one step
[height, width] = size(labelMap);
dist = zeros([size(subsampled) nRays], 'single');
foreground = find(subsampled > 0);
if isempty(foreground); return; end
[gridRows, gridCols] = ind2sub(size(subsampled), foreground);
nPixels = numel(foreground);

% the C code computes the angles and steps in single precision
angleStep = single(2*pi / nRays);
phi = single(0:nRays-1) * angleStep;
stepRowPerRay = single(sin(phi));
stepColPerRay = single(cos(phi));
overshootPerRay = single(0.5) ./ max(abs(stepRowPerRay), abs(stepColPerRay)) - single(1);

% one element per (pixel, ray), pixel index fastest - the layout of dist(:, :, ray). The
% working vectors hold only the rays still moving and are compacted after every step, so
% each step costs in proportion to the rays left
elementId = (1:nPixels * nRays)';
rayOfElement = repelem((1:nRays)', nPixels);
startRow = repmat(single((gridRows - 1) * grid(1)), nRays, 1);   % 0-based full resolution
startCol = repmat(single((gridCols - 1) * grid(2)), nRays, 1);
startLabel = repmat(subsampled(foreground), nRays, 1);
stepRow = stepRowPerRay(rayOfElement)';
stepCol = stepColPerRay(rayOfElement)';
overshoot = overshootPerRay(rayOfElement)';
offsetRow = zeros(nPixels * nRays, 1, 'single');
offsetCol = zeros(nPixels * nRays, 1, 'single');
rayLength = zeros(nPixels * nRays, 1, 'single');
labelMap = labelMap(:);

while ~isempty(elementId)
    offsetRow = offsetRow + stepRow;
    offsetCol = offsetCol + stepCol;
    row = roundHalfEven(startRow + offsetRow);
    col = roundHalfEven(startCol + offsetCol);
    stopped = row < 0 | row >= height | col < 0 | col >= width;
    inside = ~stopped;
    stopped(inside) = labelMap(double(row(inside)) + 1 + double(col(inside)) * height) ~= startLabel(inside);
    if ~any(stopped); continue; end
    finalRow = offsetRow(stopped) + overshoot(stopped) .* stepRow(stopped);
    finalCol = offsetCol(stopped) + overshoot(stopped) .* stepCol(stopped);
    rayLength(elementId(stopped)) = sqrt(finalRow.^2 + finalCol.^2);
    moving = ~stopped;
    elementId = elementId(moving);
    startRow = startRow(moving);  startCol = startCol(moving);  startLabel = startLabel(moving);
    stepRow = stepRow(moving);  stepCol = stepCol(moving);  overshoot = overshoot(moving);
    offsetRow = offsetRow(moving);  offsetCol = offsetCol(moving);
end
planeSize = numel(subsampled);
dist(foreground + (0:nRays-1) * planeSize) = reshape(rayLength, nPixels, nRays);
end

function rounded = roundHalfEven(values)
% C lrint in the default rounding mode; MATLAB round() rounds ties away from zero
rounded = round(values);
ties = abs(values - fix(values)) == 0.5;
if any(ties)
    rounded(ties) = 2 * round(values(ties) / 2);
end
end
