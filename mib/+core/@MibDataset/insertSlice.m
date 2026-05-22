function insertSlice(obj, img, insertPosition, meta, options)
% INSERTSLICE - Insert a slice or a dataset into the existing volume.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.insertSlice(img, insertPosition, meta, options)
%
% This is the interactive wrapper: it handles user dialogs, a waitbar and
% annotation bookkeeping, then delegates the actual array manipulation to
% core.MibImage.insertSlice (standard) or core.MibVirtualImage.insertSlice
% (virtual) for the image layer, and to MibImage.insertSlice for each
% auxiliary layer (labels, mask, selection).
%
% Input Arguments:
%   - **img** — new 2D-5D image stack to insert, dimensions [height, width, depth, colors, time]
%   - **insertPosition** — *(optional)* position where to insert the new slice/volume
%     starting from **1.** When omitted, *NaN,* or *0* - appends to the end
%   - **meta** — *(optional)* dictionary with dataset parameters,
%     used to retrieve ``'SliceName'`` and ``'SliceSize'`` entries for the
%     inserted slices; can be ``[]``.  When not provided and the dataset
%     already has per-slice filenames, slice names are auto-generated from
%     the neighboring slice name with an ``_empty_NNN`` suffix.
%   - **options** — *(optional)* structure with additional parameters
%
%     - ``.dim`` — string defining insertion dimension: 'depth' (default) or 'time'
%     - ``.BackgroundColorIntensity`` — background fill value for dimension mismatches
%     - ``.silentMode`` — logical; when **true** no dialogs are shown
%     - ``.showWaitbar`` — logical; **true** (default) shows a progress waitbar
%     - ``.ParentFigure`` — handle to parent figure for dialog centering (default: ``[]``)
%     - ``.mibPath`` — path to MIB installation directory
%
% Output Arguments:
%   none
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.insertSlice(img, 1);% insert img at the beginning
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.insertSlice(img, NaN);% append img to the end
%
%   **Example 3**
%
%   .. code-block:: matlab
%
%
%     options.dim = 'time'; obj.mibModel.I{obj.mibModel.id}.insertSlice(img, 1, [], options);
%

% Updates
% Annotation shift corrected to +D2_z/+D2_t (was +1 in MIB2)

if nargin < 5; options = struct; end
if nargin < 4; meta = []; end
if nargin < 3; insertPosition = NaN; end
if insertPosition == 0; insertPosition = NaN; end  % 0 means append to the end

if ~isfield(options, 'dim');                       options.dim = 'depth';       end
if ~isfield(options, 'showWaitbar');               options.showWaitbar = true;  end
if ~isfield(options, 'BackgroundColorIntensity');  options.BackgroundColorIntensity = 0; end
if ~isfield(options, 'silentMode');                options.silentMode = false;  end
if ~isfield(options, 'ParentFigure');              options.ParentFigure = [];   end
if ~isfield(options, 'mibPath');                   options.mibPath = [];        end

% ensure img is 5D [height, width, depth, colors, time]
if obj.datasetType(1) ~= 'V'
    switch ndims(img)
        case 2; img = reshape(img, [size(img,1), size(img,2), 1, 1, 1]);
        case 3; img = reshape(img, [size(img,1), size(img,2), size(img,3), 1, 1]);
        case 4; img = reshape(img, [size(img,1), size(img,2), size(img,3), size(img,4), 1]);
    end
    % inserted dataset dimensions
    [D2_y, D2_x, D2_z, D2_c, D2_t] = size(img);
else
    D2_y = meta{'Height'};
    D2_x = meta{'Width'};
    D2_c = meta{'Colors'};
    D2_z = meta{'Depth'};
    D2_t = meta{'Time'};
end

% existing dataset dimensions
D1_y = obj.image.height;
D1_x = obj.image.width;
D1_z = obj.image.depth;
D1_c = obj.image.colors;
D1_t = obj.image.time;

BackgroundColorIntensity = options.BackgroundColorIntensity;

% ---- dimension mismatch check + optional user dialog ----
if D1_y ~= D2_y || D1_x ~= D2_x || D1_c ~= D2_c
    if obj.datasetType(1) == 'V'
        utils.dlgs.showErrorDialog(options.ParentFigure, 'Image dimensions mismatch!', 'MibDataset.insertSlice');
        return;
    end
    if ~options.silentMode
        dlgOpts.LabelPosition = 'top';
        header        = sprintf('Some of the image dimensions mismatch!\nTo continue define background color');
        dlgOpts.HeaderLines   = 2;
        dlgOpts.OkBtnText     = 'Try to insert';
        dlgOpts.WindowHeight  = 160;
        dlgOpts.ParentFigure  = options.ParentFigure;
        answer = utils.dlgs.inputUniversalDlg([], header, ...
            {sprintf('Background color (0-%d):', obj.image.maxInt)}, ...
            {struct('Spinner', true, 'Value', obj.image.maxInt, ...
                    'Limits', [0 obj.image.maxInt], 'Step', 1, 'Round', true)}, ...
            'Wrong dimensions', dlgOpts);
        if isempty(answer); return; end
        BackgroundColorIntensity = answer{1};
    end
end

% ---- clamp insertPosition ----
if strcmp(options.dim, 'depth')
    if isnan(insertPosition) || insertPosition > D1_z; insertPosition = D1_z + 1; end
else
    if isnan(insertPosition) || insertPosition > D1_t; insertPosition = D1_t + 1; end
end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, 'Title', 'Insert dataset...', ...
        'Message', sprintf('Insert dataset to position: %d\nPlease wait...', insertPosition));
end

% ---- extract slice names from meta (used by image.insertSlice) ----
sliceNames = {};
if ~isempty(meta) && isa(meta, 'dictionary') && isKey(meta, 'SliceName')
    sliceNames = meta{'SliceName'};
end

% ---- extract slice sizes from meta (used by image.insertSlice) ----
sliceSizes = [];
if ~isempty(meta) && isa(meta, 'dictionary') && isKey(meta, 'SliceSize')
    sliceSizes = meta{'SliceSize'};
end

% -----------------------------------------------------------------------
if strcmp(options.dim, 'depth')
% -----------------------------------------------------------------------
    % ---- auto-generate slice names when the dataset has per-slice filenames
    %      and none were provided via meta ----
    if isempty(sliceNames) && obj.datasetType(1) ~= 'V' && ...
            ~isempty(obj.image.sliceName) && numel(obj.image.sliceName) > 1
        % Use the slice just before the insertion point as the name template.
        % When inserting at position 1, borrow from the first existing slice;
        % when appending, borrow from the last.
        refIdx = min(max(insertPosition - 1, 1), D1_z);
        [refPath, refBase, refExt] = fileparts(obj.image.sliceName{refIdx});
        sliceNames = cell(D2_z, 1);
        for sliceIdx = 1:D2_z
            sliceNames{sliceIdx} = fullfile(refPath, ...
                [refBase sprintf('_empty_%03d', sliceIdx) refExt]);
        end
    end

    % ---- auto-fill slice sizes when the dataset has per-slice sizes
    %      and none were provided via meta (inserted image size is used) ----
    if isempty(sliceSizes) && obj.datasetType(1) ~= 'V' && ...
            ~isempty(obj.image.sliceSize) && size(obj.image.sliceSize, 1) > 1
        sliceSizes = repmat([D2_y, D2_x], [D2_z, 1]);
    end

    imgOpts.BackgroundColorIntensity = BackgroundColorIntensity;
    imgOpts.sliceNames               = sliceNames;
    imgOpts.sliceSizes               = sliceSizes;

    if obj.datasetType(1) == 'V'
        obj.image.insertSlice(img, insertPosition, 'depth', meta{'Virtual'}, imgOpts);
    else
        obj.image.insertSlice(img, insertPosition, 'depth', imgOpts);
    end
    if options.showWaitbar; wb.Value = 0.3; end

    if obj.datasetType(1) ~= 'V'
        % ---- label layers (insert zeros at the same position) ----
        if obj.labels.maxMaterials < 255   % labels63: model+mask+selection packed together
            if obj.modelExist || obj.maskExist || obj.selection.exists
                emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
                obj.labels.insertSlice(emptyLayer, insertPosition, 'depth');
            end
        else   % separate model / mask / selection layers
            if obj.modelExist
                emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], obj.labels.dataClass);
                obj.labels.insertSlice(emptyLayer, insertPosition, 'depth');
            end
            if options.showWaitbar; wb.Value = 0.6; end
            if obj.maskExist
                emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
                obj.mask.insertSlice(emptyLayer, insertPosition, 'depth');
            end
            if options.showWaitbar; wb.Value = 0.8; end
            if obj.selection.exists
                emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
                obj.selection.insertSlice(emptyLayer, insertPosition, 'depth');
            end
        end
        if options.showWaitbar; wb.Value = 0.85; end

        % ---- sync sliceSize from image to label layers ----
        if ~isempty(obj.image.sliceSize)
            if obj.labels.exists; obj.labels.sliceSize = obj.image.sliceSize; end
            if isa(obj, 'core.MibDataset') && ~isa(obj.labels, 'core.MibLabels63')
                if obj.maskExist; obj.mask.sliceSize = obj.image.sliceSize; end
            end
        end

        % ---- shift annotations: labelPositions = [z, x, y, t] ----
        [labelsList, labelValues, labelPositions, ~] = obj.annotations.getLabels();
        if ~isempty(labelsList)
            shift = labelPositions(:,1) >= insertPosition;
            labelPositions(shift, 1) = labelPositions(shift, 1) + D2_z;
            obj.annotations.replaceLabels(labelsList, labelPositions, labelValues);
        end
    end

% -----------------------------------------------------------------------
else  % insert a new time point
% -----------------------------------------------------------------------
    imgOpts.BackgroundColorIntensity = BackgroundColorIntensity;

    obj.image.insertSlice(img, insertPosition, 'time', imgOpts);
    if options.showWaitbar; wb.Value = 0.3; end

    % ---- label layers ----
    if obj.labels.maxMaterials < 255   % labels63
        if obj.modelExist || obj.maskExist || obj.selection.exists
            emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
            obj.labels.insertSlice(emptyLayer, insertPosition, 'time');
        end
    else
        if obj.modelExist
            emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], obj.labels.dataClass);
            obj.labels.insertSlice(emptyLayer, insertPosition, 'time');
        end
        if options.showWaitbar; wb.Value = 0.6; end
        if obj.maskExist
            emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
            obj.mask.insertSlice(emptyLayer, insertPosition, 'time');
        end
        if options.showWaitbar; wb.Value = 0.8; end
        if obj.selection.exists
            emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
            obj.selection.insertSlice(emptyLayer, insertPosition, 'time');
        end
    end
    if options.showWaitbar; wb.Value = 0.85; end

    % ---- shift annotations: labelPositions = [z, x, y, t] ----
    [labelsList, labelValues, labelPositions, ~] = obj.annotations.getLabels();
    if ~isempty(labelsList)
        shift = labelPositions(:,4) >= insertPosition;
        labelPositions(shift, 4) = labelPositions(shift, 4) + D2_t;
        obj.annotations.replaceLabels(labelsList, labelPositions, labelValues);
    end
end

% ---- sync dataset-level dimension cache ----
obj.dim_yxzct = obj.image.dim_yxzct;

% ---- update slices (view range) ----
if obj.orientation == 3        % YX
    obj.slices{1} = [1, obj.image.height];
    obj.slices{2} = [1, obj.image.width];
elseif obj.orientation == 1    % XZ
    obj.slices{2} = [1, obj.image.width];
    obj.slices{3} = [1, obj.image.depth];
elseif obj.orientation == 2    % YZ
    obj.slices{1} = [1, obj.image.height];
    obj.slices{3} = [1, obj.image.depth];
end

% ---- update bounding box ----
if strcmp(options.dim, 'depth')
    obj.image.boundingBox(6) = obj.image.boundingBox(5) + (obj.image.depth - 1) * obj.image.pixSize.z;
end

% ---- update action log ----
obj.image.actionLog{end+1} = sprintf('Insert dataset [%dx%dx%dx%dx%d] at position %s=%d', ...
    D2_y, D2_x, D2_z, D2_c, D2_t, options.dim, insertPosition);

if options.showWaitbar; wb.Value = 1; delete(wb); end

end
