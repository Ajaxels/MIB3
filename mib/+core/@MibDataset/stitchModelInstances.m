function stats = stitchModelInstances(obj, options, wb)
% STITCHMODELINSTANCES - Stitch per-slice 2D instance labels into a 3D instance model.
%
% Syntax:
%   .. code-block:: matlab
%
%       stats = obj.stitchModelInstances()
%       stats = obj.stitchModelInstances(options)
%       stats = obj.stitchModelInstances(options, wb)
%
% Treats the current labels layer as a stack of **independently generated 2D
% instance segmentations** (each z-slice carries its own instance indices, not
% consistent across slices) and links objects that overlap between neighbouring
% slices into single 3D instances with one consistent index through the whole
% stack. The heavy lifting is done by :func:`utils.stitchInstances2Dto3D`; this
% method wraps it with the per-timepoint read/write and rebuilds the labels
% object at a capacity large enough for the resulting instance count (mirrors
% the indexed-object branch of :func:`core.MibDataset.convertModel`). When the
% source model is the bit-packed type-63 layer, the selection and mask layers
% are unpacked into standalone layers first, because the new indexed model can
% no longer carry them in its bits.
%
% Unlike the connected-component options in ``convertModel`` (which turn a
% *semantic* model into indexed objects), this expects a model whose slices are
% **already** per-slice indexed 2D instances — typically the raw output of a 2D
% instance-segmentation prediction.
%
% Input Arguments:
%   - **options** *(optional)* — structure passed through to
%     :func:`utils.stitchInstances2Dto3D` (``method``, ``iouThreshold``,
%     ``ioaThreshold``, ``minOverlapPixels``, ``zLookback``, ``minObjectVoxels``,
%     ``bidirectional``); missing fields take that function's defaults
%   - **wb** *(optional)* — ``uiprogressdlg`` handle; pass ``[]`` to skip
%     progress reporting
%
% Output Arguments:
%   - **stats** — structure from the last processed timepoint with
%     ``.numInput2DObjects``, ``.numOutput3DObjects``, ``.objectVoxelCounts``
%
% **Example** — stitch the current model with default settings
%
%   .. code-block:: matlab
%
%      obj.stitchModelInstances();
%

% Updates
%

if nargin < 3; wb = []; end
if nargin < 2; options = struct(); end

% Build metadata descriptor reused for the new labels allocation
meta = core.MibImage.initializeImgInfo( ...
    'pixSize', obj.image.pixSize, ...
    'Height',  obj.image.height, ...
    'Width',   obj.image.width,  ...
    'Depth',   obj.image.depth,  ...
    'Time',    obj.image.time,   ...
    'Colors',  1);
dims = [obj.image.height, obj.image.width, obj.image.depth, 1, obj.image.time];

% Start with a uint16 model; promote to uint32 only if an instance count
% exceeds the uint16 range (same policy as the indexed-object path).
newModel = zeros(dims, 'uint16');
newModelType = 65535;
stats = struct('numInput2DObjects', 0, 'numOutput3DObjects', 0, 'objectVoxelCounts', []);

readOpt = struct('blockModeSwitch', 0);
for timePoint = 1:obj.image.time
    % whole indexed model for this timepoint as [height, width, depth]
    volume = cell2mat(obj.getData3D('labels', timePoint, 3, NaN, readOpt));

    [stitched, stats] = utils.stitchInstances2Dto3D(volume, options);

    if stats.numOutput3DObjects > 65535 && ~isa(newModel, 'uint32')
        newModel = uint32(newModel);
        newModelType = 4294967295;
    end
    newModel(:, :, :, 1, timePoint) = cast(stitched, class(newModel));

    if ~isempty(wb); wb.Value = timePoint / obj.image.time; end
end

% In a type-63 model the selection and mask layers are packed into bits 7-8
% of obj.labels and obj.selection/obj.mask are empty placeholders. Unpack
% them into standalone layers before the labels object is replaced with the
% large-type model, otherwise they stay empty and every later
% getData2D('selection', ...) call errors out (mirrors createModel and
% convertModel).
if obj.labels.maxMaterials == 63 && obj.labels.exists
    packedData = obj.labels.data;
    obj.selection = core.MibLabels(uint8(bitand(packedData, uint8(128)) / 128), meta);
    if obj.maskExist
        obj.mask = core.MibLabels(uint8(bitand(packedData, uint8(64)) / 64), meta);
    end
end

% Replace the labels layer with the stitched instance model
meta{'imgClass'} = class(newModel);
obj.labels = core.MibLabels(newModel, meta);
obj.labels.maxMaterials   = newModelType;
obj.labels.materialNames  = {'1'; '2'};
obj.labels.materialColors = rand(65535, 3);
obj.selectedMaterial = 3;
obj.selectedAddToMaterial = 3;
end
