function convertModel(obj, newType, wb)
% CONVERTMODEL - Convert the segmentation model to a different storage type.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.convertModel(newType)
%       obj.convertModel(newType, wb)
%
% Converts the pixel data and layer objects between the packed types 63 and
% 16383 (``core.MibLabels63``, uint8 and uint16 layouts) and the separate-layer
% representations (``core.MibLabels``, types 255 / 65535 / 4294967295).
% Also performs connected-component labelling to generate indexed-object
% models (types 2.4, 2.8, 3.6, 3.26).
%
% Packed models store material, mask, and selection in a single array:
% type 63 in uint8 (bits 1-6 = material index 0-63, bit 7 = mask, bit 8 =
% selection), type 16383 in uint16 (bits 1-14 = instance index, bit 15 = mask,
% bit 16 = selection). Type 16383 is an instance model like 65535: two
% material-name slots and generated colours.
% Converting to a higher type unpacks these bits into separate layer
% objects.  Converting back packs them again.
%
% A conversion to a type that cannot hold the largest index in use clips the
% larger indices onto the top index of the target (a packed target clamps them
% explicitly, so they cannot spill into the mask/selection bits). Undo relies
% on this when it brings a layer back to the type a snapshot was taken at.
% The user-facing ``models.MibModel.convertModel`` refuses such a conversion
% before it reaches this method.
%
% Input Arguments:
%   - **newType** - numeric target model type:
%
%     - ``63``         - packed uint8 (``core.MibLabels63``)
%     - ``16383``      - packed uint16 instance model (``core.MibLabels63``)
%     - ``255``        - separate uint8 labels (``core.MibLabels``)
%     - ``65535``      - separate uint16 labels (``core.MibLabels``)
%     - ``4294967295`` - separate uint32 labels (``core.MibLabels``)
%     - ``2.4``        - 2D connected components, connectivity 4
%     - ``2.8``        - 2D connected components, connectivity 8
%     - ``3.6``        - 3D connected components, connectivity 6
%     - ``3.26``       - 3D connected components, connectivity 26
%
%     The result records how its objects are numbered in
%     ``labels.objects3D``: false for ``2.4``/``2.8`` (the labelling restarts
%     on every slice), true for ``3.6``/``3.26`` and for 63/255 converted to
%     16383, 65535 or 4294967295 (a material spans the volume), and kept as it
%     was between the instance types 16383, 65535 and 4294967295
%
%   - **wb** *(optional)* - ``uiprogressdlg`` handle; pass ``[]`` to skip
%     progress reporting
%
% Output Arguments:
%   (none)
%
% **Example 1** - convert to 255-material type
%
%   .. code-block:: matlab
%
%      obj.convertModel(255);
%
% **Example 2** - detect 2D connected components (connectivity 8)
%
%   .. code-block:: matlab
%
%      obj.convertModel(2.8);
%

% Updates
% Ported from MIB2 mibImage.convertModel

if nargin < 3; wb = []; end

currentType = obj.labels.maxMaterials;
if newType == currentType; return; end

% Build metadata descriptor reused for all new layer allocations
meta = core.MibImage.initializeImgInfo( ...
    'pixSize', obj.image.pixSize, ...
    'Height',  obj.image.height, ...
    'Width',   obj.image.width,  ...
    'Depth',   obj.image.depth,  ...
    'Time',    obj.image.time,   ...
    'Colors',  1);
dims = [obj.image.height, obj.image.width, obj.image.depth, 1, obj.image.time];

% Preserve material metadata before replacing the labels object
existingMaterialColors = obj.labels.materialColors;
existingMaterialNames  = obj.labels.materialNames;
% The MibLabels/MibLabels63 constructors reset filename to 'Labels_none.model',
% so keep the current model filename and mat-file variable name and restore
% them on the new layer object - conversion does not change where the model came from
existingFilename       = obj.labels.filename;
existingLabelsVariable = obj.labels.labelsVariable;
% Instance models only (see core.MibLabels.objects3D); a 63-type layer has no such property
existingObjects3D      = isprop(obj.labels, 'objects3D') && obj.labels.objects3D;

%% Indexed-object detection (types 2.4, 2.8, 3.6, 3.26)
if newType < 4

    % Indexed-object detection requires a fully unpacked model
    if currentType == 63
        obj.convertModel(255, wb);
        currentType = 255; %#ok<NASGU>
    end

    switch newType
        case 2.4;  conn = 4;
        case 2.8;  conn = 8;
        case 3.6;  conn = 6;
        case 3.26; conn = 26;
    end

    noMaterials = numel(obj.labels.materialNames);
    newModel = zeros(dims, 'uint16');
    newModelType = 65535;

    if newType < 3   % 2D connected components
        totalSlices = obj.image.time * obj.image.depth;
        for timePoint = 1:obj.image.time
            for sliceNo = 1:obj.image.depth
                CC = struct( ...
                    'Connectivity', conn, ...
                    'ImageSize',    [obj.image.height, obj.image.width], ...
                    'NumObjects',   0, ...
                    'PixelIdxList', {{}});
                for matId = 1:noMaterials
                    img = cell2mat(obj.getData2D('labels', sliceNo, 3, matId, struct('t', timePoint, 'blockModeSwitch', 0)));
                    CC2 = bwconncomp(img, conn);
                    CC.NumObjects = CC.NumObjects + CC2.NumObjects;
                    CC.PixelIdxList = [CC.PixelIdxList, CC2.PixelIdxList];
                end
                if CC.NumObjects > 65535
                    newModel = uint32(newModel);
                    newModelType = 4294967295;
                end
                newModel(:, :, sliceNo, 1, timePoint) = labelmatrix(CC);
                if ~isempty(wb)
                    wb.Value = ((timePoint - 1) * obj.image.depth + sliceNo) / totalSlices;
                end
            end
        end
    else             % 3D connected components
        for timePoint = 1:obj.image.time
            CC = struct( ...
                'Connectivity', conn, ...
                'ImageSize',    [obj.image.height, obj.image.width, obj.image.depth], ...
                'NumObjects',   0, ...
                'PixelIdxList', {{}});
            for matId = 1:noMaterials
                volume = cell2mat(obj.getData3D('labels', timePoint, 3, matId, struct('blockModeSwitch', 0)));
                CC2 = bwconncomp(volume, conn);
                CC.NumObjects = CC.NumObjects + CC2.NumObjects;
                CC.PixelIdxList = [CC.PixelIdxList, CC2.PixelIdxList];
            end
            if CC.NumObjects > 65535
                newModel = uint32(newModel);
                newModelType = 4294967295;
            end
            dummyVolume = zeros([obj.image.height, obj.image.width, obj.image.depth], class(newModel));
            for objId = 1:CC.NumObjects
                dummyVolume(CC.PixelIdxList{objId}) = objId;
            end
            newModel(:, :, :, 1, timePoint) = dummyVolume;
            if ~isempty(wb); wb.Value = timePoint / obj.image.time; end
        end
    end

    meta{'imgClass'} = class(newModel);
    obj.labels = core.MibLabels(newModel, meta);
    obj.labels.maxMaterials   = newModelType;
    obj.labels.materialNames  = {'1'; '2'};
    obj.labels.materialColors = rand(65535, 3);
    obj.labels.filename       = existingFilename;
    obj.labels.labelsVariable = existingLabelsVariable;
    obj.labels.objects3D      = newType >= 3;    % per-slice components restart their numbering on every slice
    obj.selectedMaterial = 3;
    obj.selectedAddToMaterial = 3;
    return;
end

%% Convert TO a packed type (63 = uint8, 16383 = uint16): pack selection and mask bits
if newType == 63 || newType == 16383
    if newType == 63; targetClass = 'uint8'; else; targetClass = 'uint16'; end
    % the constructor selects the layout from the class of the data
    newLabels = core.MibLabels63(zeros(dims, targetClass), meta);

    % material indices and the two flags, from the packed bits or the separate layers
    modelData = [];
    selectionData = [];
    maskData = [];
    if isa(obj.labels, 'core.MibLabels63')
        if obj.labels.exists
            modelData     = bitand(obj.labels.data, obj.labels.materialMask);
            selectionData = bitget(obj.labels.data, obj.labels.selectionBit);
            maskData      = bitget(obj.labels.data, obj.labels.maskBit);
        end
    else
        if obj.labels.exists; modelData = obj.labels.data; end
        if obj.selection.exists; selectionData = obj.selection.data; end
        if obj.maskExist && obj.mask.exists; maskData = obj.mask.data; end
    end
    if ~isempty(wb); wb.Value = 0.2; end

    packedData = newLabels.data;
    maxIndex = 0;
    if ~isempty(modelData)
        maxIndex = min(double(max(modelData, [], 'all')), newLabels.materialMask);
        % clamp onto the top index: a larger value would spill into the flag bits
        packedData = cast(min(modelData, newLabels.materialMask), targetClass);
    end
    if ~isempty(selectionData)
        packedData = bitor(packedData, cast(selectionData, targetClass) * cast(newLabels.selectionValue, targetClass));
    end
    if ~isempty(wb); wb.Value = 0.5; end
    if ~isempty(maskData)
        packedData = bitor(packedData, cast(maskData, targetClass) * cast(newLabels.maskValue, targetClass));
    end
    newLabels.data = packedData;
    clear packedData modelData selectionData maskData;
    if ~isempty(wb); wb.Value = 0.8; end

    obj.labels    = newLabels;
    obj.selection = core.MibLabels([], meta);
    obj.mask      = core.MibLabels([], meta);
    obj.labels.filename       = existingFilename;
    obj.labels.labelsVariable = existingLabelsVariable;

    if newType == 63
        % When downgrading from a large type, rebuild material names from the indices in use
        if currentType > 255 && maxIndex > 0
            existingMaterialNames = arrayfun(@num2str, (1:maxIndex)', 'UniformOutput', false);
        end
        obj.labels.materialNames = existingMaterialNames;
        if ~isempty(existingMaterialColors) && size(existingMaterialColors, 2) == 3
            obj.labels.materialColors = existingMaterialColors;
        else
            obj.labels.materialColors = rand(max(63, numel(existingMaterialNames)), 3);
        end
        obj.selectedMaterial = 2;
        obj.selectedAddToMaterial = 2;
    else
        % 16383 is an instance model: two name slots and generated colours, like 65535
        if currentType < 256
            obj.labels.materialNames  = {'1'; '2'};
            obj.labels.materialColors = rand(65535, 3);
            obj.labels.objects3D      = true;     % a material is numbered through the volume
        else
            obj.labels.materialNames  = existingMaterialNames;
            obj.labels.materialColors = existingMaterialColors;
            obj.labels.objects3D      = existingObjects3D;
        end
        obj.labels.materialsCount = maxIndex;
        obj.selectedMaterial = 3;
        obj.selectedAddToMaterial = 3;
    end
    return;
end

%% Convert FROM a packed type or between high types (target: 255 / 65535 / 4294967295)

% Unpack selection and mask from the packed bits when coming from type 63 or 16383
if isa(obj.labels, 'core.MibLabels63') && obj.labels.exists
    rawData = obj.labels.data;
    selectionData = uint8(bitget(rawData, obj.labels.selectionBit));
    obj.selection = core.MibLabels(selectionData, meta);
    if obj.maskExist
        maskData = uint8(bitget(rawData, obj.labels.maskBit));
        obj.mask = core.MibLabels(maskData, meta);
    end
    rawModel = bitand(rawData, obj.labels.materialMask);
else
    rawModel = obj.labels.data;
end
if ~isempty(wb); wb.Value = 0.4; end

switch newType
    case 255
        newData = uint8(rawModel);
        meta{'imgClass'} = 'uint8';
    case 65535
        newData = uint16(rawModel);
        meta{'imgClass'} = 'uint16';
    case 4294967295
        newData = uint32(rawModel);
        meta{'imgClass'} = 'uint32';
end
if ~isempty(wb); wb.Value = 0.7; end

obj.labels = core.MibLabels(newData, meta);
obj.labels.maxMaterials = newType;
% A material is numbered through the volume, so materials upgraded to an
% instance type are 3D objects; between instance types the numbering is kept
obj.labels.objects3D = currentType < 256 || existingObjects3D;
obj.labels.filename       = existingFilename;
obj.labels.labelsVariable = existingLabelsVariable;
obj.maskExist = 1;

% Adjust material names and colors for type boundary crossings
if currentType < 256 && newType > 255
    % Upgrading to large type: reset to generic indexed names
    obj.labels.materialNames  = {'1'; '2'};
    obj.labels.materialColors = rand(65535, 3);
    obj.selectedMaterial = 3;
    obj.selectedAddToMaterial = 3;
elseif currentType > 255 && newType < 256
    % Downgrading from large type: rebuild names from actual pixel range
    maxMaterialIndex = max(newData(:));
    if maxMaterialIndex > 0
        obj.labels.materialNames  = arrayfun(@num2str, (1:maxMaterialIndex)', 'UniformOutput', false);
        obj.labels.materialsCount = maxMaterialIndex;
    end
    if ~isempty(existingMaterialColors) && size(existingMaterialColors, 2) == 3
        obj.labels.materialColors = existingMaterialColors;
    else
        obj.labels.materialColors = rand(max(255, double(maxMaterialIndex)), 3);
    end
    obj.selectedMaterial = 2;
    obj.selectedAddToMaterial = 2;
else
    % Same tier (63↔255, 255↔255, 65535↔4294967295, etc.): carry colors forward
    obj.labels.materialNames = existingMaterialNames;
    if ~isempty(existingMaterialColors) && size(existingMaterialColors, 2) == 3
        obj.labels.materialColors = existingMaterialColors;
    else
        obj.labels.materialColors = rand(max(255, numel(existingMaterialNames)), 3);
    end
    obj.selectedMaterial = 2;
    obj.selectedAddToMaterial = 2;
end
end
