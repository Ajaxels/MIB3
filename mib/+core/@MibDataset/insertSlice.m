function insertSlice(obj, img, insertPosition, meta, options)
% function insertSlice(obj, img, insertPosition, meta, options)
% Insert a slice or a dataset into the existing volume
%
% This is the interactive wrapper: it handles user dialogs, a waitbar and
% annotation / slice-name bookkeeping, then delegates the actual array
% manipulation to core.MibImage.insertSlice for each layer
% (image, labels, mask, selection).
%
% Parameters:
% img: new 2D-5D image stack to insert, dimensions [height, width, depth, colors, time]
% insertPosition: [@em optional] position where to insert the new slice/volume
%   starting from @b 1. When omitted, @em NaN, or @em 0 - appends to the end
% meta: [@em optional] dictionary with dataset parameters,
%   used to retrieve 'SliceName' entries for the inserted slices; can be @em []
% options: [@em optional] structure with additional parameters
%   @li .dim - string defining insertion dimension: 'depth' (default) or 'time'
%   @li .BackgroundColorIntensity - background fill value for dimension mismatches
%   @li .silentMode - logical; when @b true no dialogs are shown
%   @li .showWaitbar - logical; @b true (default) shows a progress waitbar
%   @li .parentFigure - handle to parent figure for dialog centering (default: [])
%   @lo .mibPath - path to MIB installation directory
%
% Return values:
%   none

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.insertSlice(img, 1);           // insert img at the beginning @endcode
% @code obj.mibModel.I{obj.mibModel.id}.insertSlice(img, NaN);         // append img to the end @endcode
% @code options.dim = 'time'; obj.mibModel.I{obj.mibModel.id}.insertSlice(img, 1, [], options); @endcode

% Updates
% Annotation shift corrected to +D2_z/+D2_t (was +1 in MIB2)

if nargin < 5; options = struct; end
if nargin < 4; meta = []; end
if nargin < 3; insertPosition = NaN; end
if insertPosition == 0; insertPosition = NaN; end

if ~isfield(options, 'dim');                       options.dim = 'depth';       end
if ~isfield(options, 'showWaitbar');               options.showWaitbar = true;  end
if ~isfield(options, 'BackgroundColorIntensity');  options.BackgroundColorIntensity = 0; end
if ~isfield(options, 'silentMode');                options.silentMode = false;  end
if ~isfield(options, 'parentFigure');              options.parentFigure = [];   end
if ~isfield(options, 'mibPath');                   options.mibPath = [];   end

% ensure img is 5D [height, width, depth, colors, time]
switch ndims(img)
    case 2; img = reshape(img, [size(img,1), size(img,2), 1, 1, 1]);
    case 3; img = reshape(img, [size(img,1), size(img,2), size(img,3), 1, 1]);
    case 4; img = reshape(img, [size(img,1), size(img,2), size(img,3), size(img,4), 1]);
end

% inserted dataset dimensions
[D2_y, D2_x, D2_z, D2_c, D2_t] = size(img);

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
        utils.dlgs.showErrorDialog(options.parentFigure, 'Image dimensions mismatch!', 'MibDataset.insertSlice');
        return;
    end
    if ~options.silentMode
        dlgOpts.LabelPosition = 'top';
        dlgOpts.Header        = sprintf('Some of the image dimensions mismatch!\nTo continue define background color');
        dlgOpts.HeaderLines   = 2;
        dlgOpts.OkBtnText     = 'Try to insert';
        dlgOpts.WindowHeight  = 160;
        dlgOpts.parentFigure  = options.parentFigure;
        answer = utils.dlgs.inputUniversalDlg([], ...
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
    wb = uiprogressdlg(options.parentFigure, 'Title', 'Insert dataset...', ...
        'Message', sprintf('Insert dataset to position: %d\nPlease wait...', insertPosition)); %, ...
        %'Indeterminate', 'on');
end

% -----------------------------------------------------------------------
if strcmp(options.dim, 'depth')
% -----------------------------------------------------------------------
    if obj.datasetType(1) == 'V'
        % Virtual stack insertion — not yet implemented in MIB3.
        % Kept as a placeholder mirroring MIB2 logic for future use.
        %
        % if insertPosition == 1
        %     obj.img = [img; obj.img];
        %     obj.Virtual.filenames    = [meta('Virtual_filenames');    obj.Virtual.filenames];
        %     obj.Virtual.objectType   = [meta('Virtual_objectType');   obj.Virtual.objectType];
        %     obj.Virtual.readerId     = [meta('Virtual_readerId');     obj.Virtual.readerId+max(meta('Virtual_readerId'))];
        %     obj.Virtual.seriesName   = [meta('Virtual_seriesName');   obj.Virtual.seriesName];
        %     obj.Virtual.slicesPerFile = [meta('Virtual_slicesPerFile'); obj.Virtual.slicesPerFile];
        % elseif insertPosition == D1_z+1
        %     obj.img = [obj.img; img];
        %     obj.Virtual.filenames    = [obj.Virtual.filenames;    meta('Virtual_filenames')];
        %     obj.Virtual.objectType   = [obj.Virtual.objectType;   meta('Virtual_objectType')];
        %     obj.Virtual.readerId     = [obj.Virtual.readerId;     meta('Virtual_readerId')+max(obj.Virtual.readerId)];
        %     obj.Virtual.seriesName   = [obj.Virtual.seriesName;   meta('Virtual_seriesName')];
        %     obj.Virtual.slicesPerFile = [obj.Virtual.slicesPerFile; meta('Virtual_slicesPerFile')];
        % else
        %     obj.img = [obj.img(1:insertPosition-1); img; obj.img(insertPosition:end)];
        %     obj.Virtual.filenames    = [obj.Virtual.filenames(1:insertPosition-1);    meta('Virtual_filenames');    obj.Virtual.filenames(insertPosition:end)];
        %     obj.Virtual.objectType   = [obj.Virtual.objectType(1:insertPosition-1);   meta('Virtual_objectType');   obj.Virtual.objectType(insertPosition:end)];
        %     obj.Virtual.readerId     = [obj.Virtual.readerId(1:insertPosition-1); ...
        %                                  meta('Virtual_readerId')+max(obj.Virtual.readerId(1:insertPosition-1)); ...
        %                                  obj.Virtual.readerId(insertPosition:end)+max(meta('Virtual_readerId'))];
        %     obj.Virtual.seriesName   = [obj.Virtual.seriesName(1:insertPosition-1);   meta('Virtual_seriesName');   obj.Virtual.seriesName(insertPosition:end)];
        %     obj.Virtual.slicesPerFile = [obj.Virtual.slicesPerFile(1:insertPosition-1); meta('Virtual_slicesPerFile'); obj.Virtual.slicesPerFile(insertPosition:end)];
        % end
    else
        % ---- image layer ----
        obj.image.insertSlice(img, insertPosition, 'depth', BackgroundColorIntensity);
        if options.showWaitbar; wb.Value = 0.3; end

        % ---- label layers (insert zeros at the same position) ----
        if obj.labels.maxMaterials < 255   % labels63: model+mask+selection packed together
            if obj.modelExist
                emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
                obj.labels.insertSlice(emptyLayer, insertPosition, 'depth', 0);
            end
        else   % separate model / mask / selection layers
            if obj.modelExist
                emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], obj.labels.dataClass);
                obj.labels.insertSlice(emptyLayer, insertPosition, 'depth', 0);
            end
            if options.showWaitbar; wb.Value = 0.6; end
            if obj.maskExist
                emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
                obj.mask.insertSlice(emptyLayer, insertPosition, 'depth', 0);
            end
            if options.showWaitbar; wb.Value = 0.8; end
            if obj.selection.exists
                emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
                obj.selection.insertSlice(emptyLayer, insertPosition, 'depth', 0);
            end
        end
        if options.showWaitbar; wb.Value = 0.85; end

        % ---- shift annotations: labelPositions = [z, x, y, t] ----
        [labelsList, labelValues, labelPositions, ~] = obj.annotations.getLabels();
        if ~isempty(labelsList)
            shift = labelPositions(:,1) >= insertPosition;
            labelPositions(shift, 1) = labelPositions(shift, 1) + D2_z;
            obj.annotations.replaceLabels(labelsList, labelPositions, labelValues);
        end

        % ---- update SliceNames ----
        if ~isempty(obj.image.sliceName)
            sliceNames = obj.image.sliceName;
            if numel(sliceNames) == 1; sliceNames = repmat(sliceNames, [D1_z 1]); end %#ok<*ISCL>

            sliceNamesNew = {''};
            if ~isempty(meta)
                if isa(meta, 'dictionary') && isKey(meta, 'SliceName')
                    sliceNamesNew = meta{'SliceName'};
                end
            end
            if numel(sliceNamesNew) == 1; sliceNamesNew = repmat(sliceNamesNew, [D2_z 1]); end

            if insertPosition == D1_z+1
                sliceNames = [sliceNames; sliceNamesNew];
            elseif insertPosition == 1
                sliceNames = [sliceNamesNew; sliceNames];
            else
                sliceNames = [sliceNames(1:insertPosition-1); sliceNamesNew; sliceNames(insertPosition:end)];
            end
            obj.image.sliceName = sliceNames;
        end
    end

% -----------------------------------------------------------------------
else  % insert a new time point
% -----------------------------------------------------------------------
    % ---- image layer ----
    obj.image.insertSlice(img, insertPosition, 'time', BackgroundColorIntensity);
    if options.showWaitbar; wb.Value = 0.3; end

    % ---- label layers ----
    if obj.labels.maxMaterials < 255   % labels63
        if obj.modelExist
            emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
            obj.labels.insertSlice(emptyLayer, insertPosition, 'time', 0);
        end
    else
        if obj.modelExist
            emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], obj.labels.dataClass);
            obj.labels.insertSlice(emptyLayer, insertPosition, 'time', 0);
        end
        if options.showWaitbar; wb.Value = 0.6; end
        if obj.maskExist
            emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
            obj.mask.insertSlice(emptyLayer, insertPosition, 'time', 0);
        end
        if options.showWaitbar; wb.Value = 0.8; end
        if obj.selection.exists
            emptyLayer = zeros([D2_y, D2_x, D2_z, 1, D2_t], 'uint8');
            obj.selection.insertSlice(emptyLayer, insertPosition, 'time', 0);
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
    obj.boundingBox(6) = obj.boundingBox(5) + (obj.image.depth - 1) * obj.pixSize.z;
end

% ---- update action log ----
obj.actionLog{end+1} = sprintf('Insert dataset [%dx%dx%dx%dx%d] at position %s=%d', ...
    D2_y, D2_x, D2_z, D2_c, D2_t, options.dim, insertPosition);

if options.showWaitbar; wb.Value = 1; delete(wb); end

end
