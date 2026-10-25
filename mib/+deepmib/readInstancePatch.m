function out = readInstancePatch(filename, options)
% READINSTANCEPATCH - Read one native-resolution training patch for 2D instance segmentation (SOLOv2 or StarDist).
%
% Syntax:
%   .. code-block:: matlab
%
%      out = deepmib.readInstancePatch(filename, options)
%
% Loads a preprocessed instance label map (see deepmib.saveInstanceLabelsParFor) and its
% corresponding image, then crops a single native-resolution patch and rebuilds the SOLOv2
% ground truth for that patch. Cropping from the 2D label map on-the-fly (rather than from a
% pre-generated full-image mask stack) keeps memory usage low for large / whole-slide images.
%
% Patch sampling is a mix of object-seeded and uniform-random windows:
%   - with probability ``options.objectFraction`` a random object is picked and the patch is
%     placed with a random offset (**coordinate jitter**) so the object lands anywhere in the
%     patch - never forced to the centre (which would teach a false "object-in-centre" prior);
%   - otherwise a uniform-random window is taken (may be pure background).
%
% Input Arguments:
%   - **filename** - [string] full path to the preprocessed ``*.mat`` (``imageFilename`` +
%     ``instanceLabelMap``)
%   - **options** - struct with fields:
%
%     - ``.imageDir`` - folder holding the source images (e.g. ``TrainImages``)
%     - ``.patchSize`` - ``[height width]`` patch size (= network input H×W)
%     - ``.objectFraction`` - fraction of patches that are object-seeded (e.g. ``0.9``)
%     - ``.minObjectArea`` - minimum object area (pixels) kept after cropping
%     - ``.getImageOptions`` - struct passed to deepmib.storeLoadImages
%     - ``.patchSeed`` - *optional* seed for a private random stream. When present the same
%       call always crops the same window, which is what the validation set needs: its loss
%       is only comparable between evaluations if the patches do not change underneath it.
%       Training leaves this out, so every epoch re-samples fresh windows from the global
%       stream (that resampling is a large part of what "patches per image" buys). The
%       private stream is used instead of ``rng`` so that seeding a validation read never
%       disturbs the global stream feeding the training patches.
%     - ``.outputFormat`` - *optional* ``'solov2'`` (default) or ``'labelMap'`` (StarDist)
%     - ``.normalizePercentiles`` - ``[low high]`` percentiles, required for ``'labelMap'``
%     - ``.margin`` - *optional* pixels of image read around the patch on every side, from
%       deepmib.instanceAugmentationMargin; default 0. Only the training read sets it, together
%       with the augmentation transform: deepmib.augmentInstanceData2D warps the larger patch
%       and crops it back to ``.patchSize``, so rotation, scaling and shear bring real image
%       into the patch instead of fill. The window is picked exactly as without a margin; the
%       margin is added around it afterwards. Where it reaches past the image border, the image
%       gets ``.fillValue`` and the labels 0, as an augmentation would fill it.
%     - ``.fillValue`` - *optional* image value outside the image, ``AugOpt2D.FillValue``;
%       default 0; used only with ``.margin``
%
% With ``'labelMap'`` the image keeps its native channel count (no RGB expansion), no
% ground truth is rebuilt (StarDist computes its targets after augmentation, see
% deepmib.stardist.computeTargets), and ``.minObjectArea`` is not used. The image is not
% normalised here, because the intensity augmentations of deepmib.augmentInstanceData2D work
% on raw values; instead the low/high percentiles of the **whole** image are returned, which
% is what StarDist normalises with. They are cached per file (persistent ``dictionary``),
% since every patch reloads the whole image.
%
% Output Arguments:
%   - **out** - for ``'solov2'``: ``1×4`` cell ``{image HxWx3, boxes Kx4 [x y w h],
%     labels Kx1 categorical, masks HxWxK logical}`` as required by ``trainSOLOV2``;
%     for ``'labelMap'``: ``1×3`` cell ``{image HxWxC (original class), labelPatch HxW,
%     normValues 2xC}`` with ``normValues(1, :)`` the low and ``normValues(2, :)`` the high
%     percentile of each channel. With ``.margin``, ``H`` and ``W`` are the patch size plus
%     twice the margin; for SOLOv2 the masks, boxes and ``.minObjectArea`` filter then refer to
%     the larger patch, and deepmib.augmentInstanceData2D re-applies the filter after its crop.

global mibDeepTrainingProgressStruct

% Emergency brake. This ReadFcn is the only DeepMIB code that trainSOLOV2 calls directly
% from its training loop (SerialTrainer/fit -> next(DataQueue)), rather than through a
% listener. images.dltrain routes its OutputFcn through notify(), and notify() catches
% errors thrown by a listener and downgrades them to a warning - so an abort raised there
% is swallowed and, worse, prevents the stop request from reaching the trainer. Raising it
% here propagates normally, out through trainSOLOV2 to
% controllers.MibDeep/startTrainingInstances, which restores the network from the most
% recent checkpoint.
if isfield(mibDeepTrainingProgressStruct, 'emergencyBrake') && mibDeepTrainingProgressStruct.emergencyBrake
    error('DeepMIB:userEmergencyStop', 'Training was stopped by the Emergency brake button');
end

% Graceful stop. The trainer has already been told to stop, so its inner per-iteration loop
% is skipped from here on and nothing read by this function will ever be trained on again -
% but minibatchqueue still prefetches a mini-batch on each reset/shuffle, and the trainer
% does one of those per remaining epoch. Loading and augmenting a full image for each of
% those throwaway prefetches is what makes a stop take minutes. Hand back a correctly shaped
% placeholder instead.
%
% Keyed on spinDownActive rather than on mibDeepStopTraining: the button can be pressed
% during the drawnow at the end of an OutputFcn call, after that call has already returned
% "keep going", so one more genuine training iteration still follows the button press.
% spinDownActive is only set once the OutputFcn has actually requested the stop, which
% guarantees no real iteration is ever fed a placeholder.
if isfield(mibDeepTrainingProgressStruct, 'spinDownActive') && mibDeepTrainingProgressStruct.spinDownActive
    out = localPlaceholderObservation(options.patchSize);
    return;
end

labelMapOutput = isfield(options, 'outputFormat') && strcmp(options.outputFormat, 'labelMap');

data = load(filename);      % imageFilename, instanceLabelMap
labelMap = data.instanceLabelMap;

% load the corresponding image and squeeze to [H W C]
imageFilename = fullfile(options.imageDir, data.imageFilename);
image = squeeze(deepmib.storeLoadImages(imageFilename, options.getImageOptions));
if labelMapOutput
    % StarDist keeps the native channel count; the whole-image percentiles are what StarDist
    % normalises with, and they are cached because every patch reloads the whole image
    normValues = localNormalizationValues(imageFilename, image, options.normalizePercentiles);
elseif size(image, 3) == 1      % grayscale -> RGB (SOLOv2 backbone expects 3 channels)
    image = repmat(image, [1, 1, 3]);
end

[height, width, ~] = size(image);
ph = options.patchSize(1);
pw = options.patchSize(2);

% pad symmetrically when the image is smaller than the patch
if height < ph || width < pw
    padH = max(0, ph - height);
    padW = max(0, pw - width);
    image = padarray(image, [padH, padW, 0], 0, 'post');
    labelMap = padarray(labelMap, [padH, padW], 0, 'post');
    [height, width, ~] = size(image);
end

% a seeded private stream makes this call reproducible without touching the global stream
if isfield(options, 'patchSeed') && ~isempty(options.patchSeed)
    patchStream = RandStream('threefry4x64_20', 'Seed', options.patchSeed);
else
    patchStream = RandStream.getGlobalStream();
end

objectList = unique(labelMap(labelMap > 0));
useObjectSeed = ~isempty(objectList) && rand(patchStream) <= options.objectFraction;

% pick a patch window; for object-seeded patches retry until the window holds an object
maxAttempts = 10;
y1 = 1; x1 = 1;
for attempt = 1:maxAttempts
    if useObjectSeed
        objId = objectList(randi(patchStream, numel(objectList)));
        [ptsR, ptsC] = find(labelMap == objId);
        anchorIdx = randi(patchStream, numel(ptsR));
        % jitter: place the anchor pixel at a random position inside the patch
        y1 = ptsR(anchorIdx) - randi(patchStream, ph) + 1;
        x1 = ptsC(anchorIdx) - randi(patchStream, pw) + 1;
    else
        y1 = randi(patchStream, height - ph + 1);
        x1 = randi(patchStream, width - pw + 1);
    end
    y1 = min(max(y1, 1), height - ph + 1);
    x1 = min(max(x1, 1), width - pw + 1);
    labelPatch = labelMap(y1:y1+ph-1, x1:x1+pw-1);
    if any(labelPatch(:)) || ~useObjectSeed; break; end
end

imagePatch = image(y1:y1+ph-1, x1:x1+pw-1, :);

if isfield(options, 'margin') && options.margin > 0
    % the same window plus real image around it for the geometric augmentations; outside
    % the image, fill as an augmentation would
    fillValue = 0;
    if isfield(options, 'fillValue'); fillValue = options.fillValue; end
    rows = y1 - options.margin : y1 + ph - 1 + options.margin;
    cols = x1 - options.margin : x1 + pw - 1 + options.margin;
    rowsInside = rows >= 1 & rows <= height;
    colsInside = cols >= 1 & cols <= width;
    imagePatch = repmat(cast(fillValue, 'like', image), [numel(rows), numel(cols), size(image, 3)]);
    imagePatch(rowsInside, colsInside, :) = image(rows(rowsInside), cols(colsInside), :);
    labelPatch = zeros(numel(rows), numel(cols), 'like', labelMap);
    labelPatch(rowsInside, colsInside) = labelMap(rows(rowsInside), cols(colsInside));
end

if labelMapOutput
    % StarDist: the label patch itself, plus the normalisation values of the whole image
    out = {imagePatch, labelPatch, normValues};
    return;
end

% rebuild the SOLOv2 ground truth from the cropped label map
stats = regionprops(labelPatch, {'Area', 'PixelIdxList'});
stats = stats(arrayfun(@(s) ~isempty(s.PixelIdxList) && s.Area >= options.minObjectArea, stats));
numObjects = numel(stats);

[patchHeight, patchWidth] = size(labelPatch);   % larger than [ph pw] with a margin
boxes = zeros(numObjects, 4);
masks = false([patchHeight, patchWidth, numObjects]);
for k = 1:numObjects
    masks(stats(k).PixelIdxList + patchHeight*patchWidth*(k-1)) = true;
    [rr, cc] = find(masks(:, :, k));
    boxes(k, :) = [min(cc), min(rr), max(cc)-min(cc)+1, max(rr)-min(rr)+1];
end
% categories must equal the network ClassNames ({'object'}); keep them fixed
labels = categorical(repmat({'object'}, [numObjects, 1]), {'object'});

out = {imagePatch, boxes, labels, masks};
end

% -------------------------------------------------------------------------------------
function out = localPlaceholderObservation(patchSize)
% minimal correctly shaped observation, handed to the prefetches of a stopping trainer
%
% Shape and categories must still match what trainSOLOV2 expects - the categories in
% particular have to equal the network ClassNames ({'object'}) - because minibatchqueue
% batches and formats the data before anything discards it. Cached so the idle epochs do
% not even repeat the allocation.

persistent cachedObservation
persistent cachedPatchSize

if isempty(cachedObservation) || ~isequal(cachedPatchSize, patchSize(1:2))
    patchHeight = patchSize(1);
    patchWidth = patchSize(2);
    objectHeight = min(8, patchHeight);
    objectWidth = min(8, patchWidth);

    imagePatch = zeros([patchHeight, patchWidth, 3], 'uint8');
    masks = false([patchHeight, patchWidth, 1]);
    masks(1:objectHeight, 1:objectWidth) = true;
    boxes = [1, 1, objectWidth, objectHeight];
    labels = categorical({'object'}, {'object'});

    cachedObservation = {imagePatch, boxes, labels, masks};
    cachedPatchSize = patchSize(1:2);
end

out = cachedObservation;

end

% -------------------------------------------------------------------------------------
function normValues = localNormalizationValues(imageFilename, image, percentiles)
% [2, C] low/high percentiles of the whole image, cached per file and percentile pair
persistent cache
if isempty(cache); cache = dictionary(string.empty, {}); end
key = string(imageFilename) + "|" + strjoin(string(percentiles), ",");
if isKey(cache, key)
    normValues = cache{key};
    return;
end
[~, lowValues, highValues] = deepmib.stardist.normalizeImage(image, percentiles);
normValues = [lowValues; highValues];
cache{key} = normValues;
end
