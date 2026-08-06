function out = readInstancePatch(filename, options)
% READINSTANCEPATCH - Read one native-resolution training patch for 2D instance segmentation (SOLOv2).
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
%
% Output Arguments:
%   - **out** - ``1×4`` cell ``{image HxWx3, boxes Kx4 [x y w h], labels Kx1 categorical,
%     masks HxWxK logical}`` as required by ``trainSOLOV2``.

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
    out = iPlaceholderObservation(options.patchSize);
    return;
end

data = load(filename);      % imageFilename, instanceLabelMap
labelMap = data.instanceLabelMap;

% load the corresponding image and squeeze to [H W C]
imageFilename = fullfile(options.imageDir, data.imageFilename);
image = squeeze(deepmib.storeLoadImages(imageFilename, options.getImageOptions));
if size(image, 3) == 1      % grayscale -> RGB (SOLOv2 backbone expects 3 channels)
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

objectList = unique(labelMap(labelMap > 0));
useObjectSeed = ~isempty(objectList) && rand <= options.objectFraction;

% pick a patch window; for object-seeded patches retry until the window holds an object
maxAttempts = 10;
y1 = 1; x1 = 1;
for attempt = 1:maxAttempts
    if useObjectSeed
        objId = objectList(randi(numel(objectList)));
        [ptsR, ptsC] = find(labelMap == objId);
        anchorIdx = randi(numel(ptsR));
        % jitter: place the anchor pixel at a random position inside the patch
        y1 = ptsR(anchorIdx) - randi(ph) + 1;
        x1 = ptsC(anchorIdx) - randi(pw) + 1;
    else
        y1 = randi(height - ph + 1);
        x1 = randi(width - pw + 1);
    end
    y1 = min(max(y1, 1), height - ph + 1);
    x1 = min(max(x1, 1), width - pw + 1);
    labelPatch = labelMap(y1:y1+ph-1, x1:x1+pw-1);
    if any(labelPatch(:)) || ~useObjectSeed; break; end
end

imagePatch = image(y1:y1+ph-1, x1:x1+pw-1, :);

% rebuild the SOLOv2 ground truth from the cropped label map
stats = regionprops(labelPatch, {'Area', 'PixelIdxList'});
stats = stats(arrayfun(@(s) ~isempty(s.PixelIdxList) && s.Area >= options.minObjectArea, stats));
numObjects = numel(stats);

boxes = zeros(numObjects, 4);
masks = false([ph, pw, numObjects]);
for k = 1:numObjects
    masks(stats(k).PixelIdxList + ph*pw*(k-1)) = true;
    [rr, cc] = find(masks(:, :, k));
    boxes(k, :) = [min(cc), min(rr), max(cc)-min(cc)+1, max(rr)-min(rr)+1];
end
% categories must equal the network ClassNames ({'object'}); keep them fixed
labels = categorical(repmat({'object'}, [numObjects, 1]), {'object'});

out = {imagePatch, boxes, labels, masks};
end

% -------------------------------------------------------------------------------------
function out = iPlaceholderObservation(patchSize)
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
