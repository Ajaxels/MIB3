function result = cropDataset(obj, cropF, options)
% CROPDATASET - Crop image and all corresponding layers of the opened dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.cropDataset(cropF, options)
%
% Orchestrates cropping across the *image,* *labels,* *mask* and
% *selection* layers, handles the Virtual → Standard conversion for
% virtual datasets, resets viewing coordinates, and updates the physical
% bounding box.
%
% Input Arguments:
%   - **cropF** — a vector ``[x1, y1, dx, dy, z1, dz, t1, dt]`` in pixels
%
%     - *x1,* *y1* — top-left corner of the crop region
%     - *dx,* *dy* — width and height of the crop region
%     - *z1,* *dz* — first slice index and number of slices
%     - *t1,* *dt* — first time point and number of time points
%     - when ``numel(cropF)`` < 7, *t1* and *dt* default to ``[1, obj.image.time]``
%
%   - **options** — *(optional)* structure with additional parameters
%
%     - ``.showWaitbar`` — logical, show a progress dialog (default: **true)**
%     - ``.UIFigure`` — handle to the parent UIFigure for the progress dialog;
%       when empty or absent the dialog is silently skipped
%     - ``.pyramidLevel`` — numeric, OME-Zarr pyramid level for virtual datasets
%       (default: **1)**
%
% Output Arguments:
%   - **result** — **1** on success, **0** on cancel or error
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{obj.mibModel.id}.cropDataset([10 20 100 200 1 5 1 1]);% crop Standard dataset
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{bufferId}.cropDataset(crop_factor, BatchOptLoc);% call from CropDataset controller
%

% Updates
% Ported from MIB2 mibImage.cropDataset

result = 0;

if nargin < 3; options = struct(); end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'UIFigure');     options.UIFigure     = [];   end
if ~isfield(options, 'pyramidLevel'); options.pyramidLevel = 1;    end

% default time range when not supplied
if numel(cropF) < 7; cropF(7:8) = [1, obj.image.time]; end

x1 = cropF(1);  dx = cropF(3);
y1 = cropF(2);  dy = cropF(4);
z1 = cropF(5);  dz = cropF(6);
t1 = cropF(7);  dt = cropF(8);

% Optional progress dialog — only possible when a UIFigure is provided
wb = [];
if options.showWaitbar && ~isempty(options.UIFigure)
    wb = uiprogressdlg(options.UIFigure, ...
        'Value', 0.05, 'Message', 'Please wait...', 'Title', 'Cropping...');
end

bbUpdated = false;   % set true inside Virtual/BigData path once BB is handled there

% =========================================================================
%  Standard (memory-resident) path
% =========================================================================
if strcmp(obj.datasetType(1), 'S')

    % --- image layer -----------------------------------------------------
    obj.image.crop(cropF);
    if ~isempty(wb); wb.Value = 0.4; end

    % --- label / mask / selection layers ---------------------------------
    if isa(obj.labels, 'core.MibLabels63')
        % Packed model: single array holds model + mask + selection bits.
        % Only crop when data is present (not a NaN sentinel).
        if obj.labels.exists && ~isnan(obj.labels.data(1))
            obj.labels.crop(cropF);
        end
    else
        if obj.modelExist
            obj.labels.crop(cropF);
        end
        if obj.maskExist
            obj.mask.crop(cropF);
        end
        if obj.enableSelection && obj.selection.exists && ~isnan(obj.selection.data(1))
            obj.selection.crop(cropF);
        end
    end
    if ~isempty(wb); wb.Value = 0.7; end

% =========================================================================
%  Virtual (HDD-resident) path — load subvolume then switch to Standard
% =========================================================================
else
    loadOpts.x            = [x1, x1+dx-1];
    loadOpts.y            = [y1, y1+dy-1];
    loadOpts.z            = [z1, z1+dz-1];
    loadOpts.t            = [t1, t1+dt-1];
    loadOpts.pyramidLevel = options.pyramidLevel;

    % Load the subvolume from the virtual source (MibVirtualImage.getData
    % handles both BioFormats-style virtual stacks and OME-Zarr pyramids)
    img = obj.image.getData('image', 3, [], loadOpts);

    % Save image metadata before switchDatasetMode/initialize resets them to defaults.
    % xyzShiftBB uses s0 voxel size because x1/y1/z1 are always in s0 pixel coords.
    srcFilename    = obj.image.filename;
    srcPixSize     = obj.image.pixSize;
    srcBoundingBox = obj.image.boundingBox;
    xyzShiftBB     = [(x1-1)*srcPixSize.x, (y1-1)*srcPixSize.y, (z1-1)*srcPixSize.z];

    % Scale voxel size to the selected pyramid level (e.g. s1 doubles x/y voxel size).
    % Level index 1 = finest (s0, scale [1 1 1]), level 2 = s1, etc.
    scaledPixSize = srcPixSize;
    sfMatrix = obj.image.pyramid.levelScaleFactors;
    if ~isempty(sfMatrix) && options.pyramidLevel >= 1 && options.pyramidLevel <= size(sfMatrix, 1)
        sf = sfMatrix(options.pyramidLevel, :);   % [sfY sfX sfZ]
        scaledPixSize.x = srcPixSize.x * sf(2);
        scaledPixSize.y = srcPixSize.y * sf(1);
        scaledPixSize.z = srcPixSize.z * sf(3);
    end

    % Read packed model from BigData BEFORE switchDatasetMode replaces MibBigDataLabels
    packedBigDataModel = [];
    savedMaterialNames  = {};
    savedMaterialsCount = 0;
    savedLabelsFilename = '';
    savedMaterialColors = [];
    if isa(obj.labels, 'core.MibBigDataLabels') && obj.labels.exists
        modelReadOpts.x            = loadOpts.x;
        modelReadOpts.y            = loadOpts.y;
        modelReadOpts.z            = loadOpts.z;
        modelReadOpts.pyramidLevel = options.pyramidLevel;
        packedBigDataModel   = obj.labels.getData63('everything', 3, [], modelReadOpts);
        savedMaterialNames   = obj.labels.materialNames;
        savedMaterialsCount  = obj.labels.materialsCount;
        savedLabelsFilename  = obj.labels.filename;
        savedMaterialColors  = obj.labels.materialColors;
    end

    % Switch from virtual to memory-resident mode; returns [] on cancel
    % switchDatasetMode uses 1=Standard, 2=Virtual, 3=BigData
    newMode = obj.switchDatasetMode(1, true);
    if isempty(newMode)
        if ~isempty(wb); delete(wb); end
        return;
    end

    % Store the loaded subvolume in the now-Standard image layer
    obj.image.setData(img, 'image', 3, []);

    % Restore scaled pixSize, source bounding box, and filename (all reset by initialize)
    obj.image.filename    = srcFilename;
    obj.image.pixSize     = scaledPixSize;
    obj.image.boundingBox = srcBoundingBox;

    % Allocate service layers sized to the loaded subvolume
    emptyDims = [size(img,1), size(img,2), size(img,3), 1, size(img,5)];
    if obj.enableSelection
        if isa(obj.labels, 'core.MibLabels63')
            % Populate with cropped BigData model if available; else blank
            if ~isempty(packedBigDataModel)
                obj.labels.data = packedBigDataModel;
                obj.modelExist  = true;
                obj.labels.materialNames  = savedMaterialNames;
                obj.labels.materialsCount = savedMaterialsCount;
                obj.labels.filename       = savedLabelsFilename;
                if ~isempty(savedMaterialColors)
                    obj.labels.materialColors = savedMaterialColors;
                end
            else
                obj.labels.data = zeros(emptyDims, 'uint8');
            end
            obj.labels.height    = emptyDims(1);
            obj.labels.width     = emptyDims(2);
            obj.labels.depth     = emptyDims(3);
            obj.labels.time      = emptyDims(5);
            obj.labels.dim_yxzct = emptyDims;
        else
            obj.labels.data    = NaN;
            obj.mask.data      = zeros(emptyDims, 'uint8');
            obj.selection.data = zeros(emptyDims, 'uint8');
        end
    else
        obj.labels.data    = NaN;
        obj.mask.data      = NaN;
        obj.selection.data = NaN;
    end
    % Apply bounding box here (uses s0 xyzShift with scaled pixSize for correct extent)
    obj.updateBoundingBox([], xyzShiftBB);
    bbUpdated = true;

    if ~isempty(wb); wb.Value = 0.7; end
end

% =========================================================================
%  Update MibDataset metadata (both paths)
% =========================================================================
if ~isempty(wb); wb.Value = 0.9; end

% Clamp current position to new dimensions
if obj.image.height < obj.current_yxz(1); obj.current_yxz(1) = obj.image.height; end
if obj.image.width  < obj.current_yxz(2); obj.current_yxz(2) = obj.image.width;  end
if obj.image.depth  < obj.current_yxz(3); obj.current_yxz(3) = obj.image.depth;  end

% Sync dim_yxzct from the (already updated) image layer
obj.dim_yxzct = obj.image.dim_yxzct;

% Reset viewing slices to the full new extents
current_layer = obj.slices{obj.orientation}(1);
obj.slices{1} = [1, obj.image.height];
obj.slices{2} = [1, obj.image.width];
obj.slices{3} = [1, obj.image.depth];   % depth is index 3 in MIB3 (was 4 in MIB2)
obj.slices{5} = repmat(min([obj.slices{5}, obj.image.time]), 1, 2);

% Clamp the orientation-specific current slice to the new dimension
% dim_yxzct(orientation): orient 3→depth, orient 1→height, orient 2→width
obj.slices{obj.orientation} = repmat( ...
    min(obj.dim_yxzct(obj.orientation), current_layer), 1, 2);

% Shift the physical bounding box by the crop offset — Standard path only;
% Virtual/BigData path handled the BB earlier (with correctly scaled pixSize).
if ~bbUpdated
    xyzShift = [(x1-1)*obj.image.pixSize.x, ...
                (y1-1)*obj.image.pixSize.y, ...
                (z1-1)*obj.image.pixSize.z];
    obj.updateBoundingBox([], xyzShift);    % propagates pixSize to all layers
end

if ~isempty(wb); wb.Value = 1; delete(wb); end
result = 1;
end
