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
% **already** per-slice indexed 2D instances - typically the raw output of a 2D
% instance-segmentation prediction.
%
% The filename of the source model is carried over to the stitched one with
% ``options.filenameSuffix`` (``'_3d'``) added, so the result stays associated
% with the data it came from without being able to overwrite it on save.
%
% Input Arguments:
%   - **options** *(optional)* - structure passed through to
%     :func:`utils.stitchInstances2Dto3D` (``method``, ``splitDisconnected2D``,
%     ``iouThreshold``, ``ioaThreshold``, ``minOverlapPixels``,
%     ``absOverlapPixels``, ``zLookback``, ``minObjectVoxels``,
%     ``minObjectSlices``, ``bidirectional``); missing fields take that
%     function's defaults. One field is consumed here rather than passed on:
%
%     - ``.filenameSuffix`` - appended to the stem of the current model
%       filename, which is otherwise carried over unchanged [*default*
%       ``'_3d'``]. ``Labels_stack.model`` becomes ``Labels_stack_3d.model``,
%       so a save after stitching does not silently overwrite the 2D instance
%       model the result was built from. Pass ``''`` to keep the name as it is.
%       A model that was never loaded or saved has no name to propagate and is
%       left alone, as is a stem that already ends with the suffix
%   - **wb** *(optional)* - ``uiprogressdlg`` handle; pass ``[]`` to skip
%     progress reporting. When it was created with ``'Cancelable', 'on'`` the
%     stitching can be interrupted - the handle is forwarded to
%     :func:`utils.stitchInstances2Dto3D`, which polls it in its own loops
%
% Output Arguments:
%   - **stats** - structure from the last processed timepoint with
%     ``.numInput2DObjects``, ``.numOutput3DObjects``, ``.objectVoxelCounts``
%     and ``.cancelled``. When ``.cancelled`` is ``true`` the method returns
%     without touching the dataset, so a cancelled run leaves the model exactly
%     as it was - nothing is half-stitched
%
% **Example** - stitch the current model with default settings
%
%   .. code-block:: matlab
%
%      obj.stitchModelInstances();
%

% Updates
%

if nargin < 3; wb = []; end
if nargin < 2; options = struct(); end
if ~isfield(options, 'filenameSuffix'); options.filenameSuffix = '_3d'; end

% Where the model came from. The MibLabels constructor resets filename to
% 'Labels_none.model', so without this the name of the 2D instance model that
% was stitched is lost and a later save has nothing to suggest (convertModel
% restores it for the same reason). Unlike a conversion, stitching produces a
% genuinely different model, so the stem takes a suffix instead of being reused
% verbatim - saving must not silently overwrite the 2D model it came from.
existingFilename       = obj.labels.filename;
existingLabelsVariable = obj.labels.labelsVariable;

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
stats = struct('numInput2DObjects', 0, 'numOutput3DObjects', 0, 'objectVoxelCounts', [], ...
    'cancelled', false);

readOpt = struct('blockModeSwitch', 0);
for timePoint = 1:obj.image.time
    % whole indexed model for this timepoint as [height, width, depth]
    volume = cell2mat(obj.getData3D('labels', timePoint, 3, NaN, readOpt));

    [stitched, stats] = utils.stitchInstances2Dto3D(volume, options, wb);
    % Cancelled: return before anything below writes to the dataset, so the
    % existing model survives untouched rather than being replaced by a stack
    % in which only the first timepoints were stitched.
    if stats.cancelled; return; end

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
obj.labels.filename       = iSuffixFilename(existingFilename, options.filenameSuffix);
obj.labels.labelsVariable = existingLabelsVariable;
obj.selectedMaterial = 3;
obj.selectedAddToMaterial = 3;
end

function newFilename = iSuffixFilename(filename, suffix)
% Insert the suffix before the extension: Labels_stack.model -> Labels_stack_3d.model.
%
% Left alone in three cases. An empty name is a model created in MIB and never
% saved (core.MibDataset.createModel sets ''), and 'Labels_none.model' is the
% MibLabels default from before any model was loaded - neither carries a name to
% propagate, and inventing one would make the Save As dialog stop suggesting a
% name derived from the image. A stem that already ends with the suffix is left
% as it is so stitching a second time cannot build up '..._3d_3d'.
if isempty(filename) || strcmp(filename, 'Labels_none.model') || isempty(suffix)
    newFilename = filename;
    return;
end
[folder, stem, ext] = fileparts(filename);
if endsWith(stem, suffix, 'IgnoreCase', true)
    newFilename = filename;
    return;
end
newFilename = fullfile(folder, [stem, suffix, ext]);
end
