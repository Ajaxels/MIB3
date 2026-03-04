function insertSlice(obj, img, insertPosition, meta, options)
% function insertSlice(obj, img, insertPosition, meta, options)
% Insert a slice or a dataset into the existing volume
%
% Parameters:
% img: new 2D-5D image stack to insert, dimensions [height, width, depth, colors, time]
% insertPosition: [@em optional] position where to insert the new slice/volume
%   starting from @b 1. When omitted, @em NaN, or @em 0 - appends to the end
% meta: [@em optional] containers.Map or dictionary with dataset parameters,
%   used to retrieve 'SliceName' entries for the inserted slices; can be @em []
% options: [@em optional] structure with additional parameters
%   @li .dim - string defining insertion dimension: 'depth' (default) or 'time'
%   @li .BackgroundColorIntensity - background fill value for dimension mismatches
%   @li .silentMode - logical; when @b true no dialogs are shown
%   @li .showWaitbar - logical; @b true (default) shows a progress waitbar
%   @li .ParentFigure - handle to parent figure; if provided, dialog is centered on parent window (default: []).
%
% Return values:
%   none

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.insertSlice(img, 1);           // insert img at the beginning @endcode
% @code obj.mibModel.I{obj.mibModel.id}.insertSlice(img, NaN);         // append img to the end @endcode
% @code options.dim = 'time'; obj.mibModel.I{obj.mibModel.id}.insertSlice(img, 1, [], options); @endcode

% Updates
% Converted from MIB2; annotation shift corrected to +D2_z/+D2_t (was +1 in MIB2)

if nargin < 5; options = struct; end
if nargin < 4; meta = []; end
if nargin < 3; insertPosition = NaN; end
if insertPosition == 0; insertPosition = NaN; end

if ~isfield(options, 'dim');                       options.dim = 'depth';       end
if ~isfield(options, 'showWaitbar');               options.showWaitbar = true;  end
if ~isfield(options, 'BackgroundColorIntensity');  options.BackgroundColorIntensity = 0; end
if ~isfield(options, 'silentMode');                options.silentMode = false;  end
if ~isfield(options, 'ParentFigure');              options.ParentFigure = [];  end

% ensure img is 5D [height, width, depth, colors, time]
switch ndims(img)
    case 2; img = reshape(img, [size(img,1), size(img,2), 1, 1, 1]);
    case 3; img = reshape(img, [size(img,1), size(img,2), size(img,3), 1, 1]);
    case 4; img = reshape(img, [size(img,1), size(img,2), size(img,3), size(img,4), 1]);
end

% get image dimensions
[D2_y, D2_x, D2_z, D2_c, D2_t] = size(img);

% existing dataset dimensions
D1_y = obj.image.height;
D1_x = obj.image.width;
D1_z = obj.image.depth;
D1_c = obj.image.colors;
D1_t = obj.image.time;

BackgroundColorIntensity = options.BackgroundColorIntensity;

% check for dimension mismatch
if D1_y ~= D2_y || D1_x ~= D2_x || D1_c ~= D2_c
    if obj.datasetType(1) == 'V'
        utils.dlgs.showErrorDialog([], sprintf('!!! Error !!!\n\nImage dimensions mismatch'), 'insertSlice');
        return;
    end
    if ~options.silentMode
        dlgOptions.LabelPosition = 'top';
        dlgOptions.Header = sprintf('Warning!\nSome of the image dimensions mismatch!');
        dlgOptions.HeaderLines = 2;
        dlgOptions.OkBtnText    = 'Continue anyway';
        dlgOptions.WindowHeight = 160;
        dlgOptions.ParentFigure = options.ParentFigure;
        maxVal = obj.image.maxInt;

        prompts = {sprintf('Background color (0-%d):', obj.image.maxInt)};
        defAns = {struct('Spinner', true, 'Value', maxVal, 'Limits', [0 maxVal], 'Step', 1, 'Round', true)};
        answer = utils.dlgs.mibInputUniversalDlg([], prompts, defAns, 'Wrong dimensions', dlgOptions);
        if isempty(answer); return; end
        BackgroundColorIntensity = answer{1};
    end
end

% clamp insertPosition
if strcmp(options.dim, 'depth')
    if isnan(insertPosition) || insertPosition > D1_z; insertPosition = D1_z + 1; end
else
    if isnan(insertPosition) || insertPosition > D1_t; insertPosition = D1_t + 1; end
end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, 'Title', 'Insert dataset...',...
        'Message', sprintf('Insert dataset to position: %d\nPlease wait...', insertPosition), ...
        'Cancelable', 'off');
end

cMax = max([D1_c, D2_c]);
xMax = max([D1_x, D2_x]);
yMax = max([D1_y, D2_y]);
zMax = max([D1_z, D2_z]);
tMax = max([D1_t, D2_t]);

% -----------------------------------------------------------------------
if strcmp(options.dim, 'depth')  % insert into depth
% -----------------------------------------------------------------------
    if obj.datasetType(1) == 'V'
        % if insertPosition == 1  % insert dataset in the beginning of the opened dataset
        %     obj.img = [img; obj.img];
        %     obj.Virtual.filenames = [meta('Virtual_filenames'); obj.Virtual.filenames];     % update filenames
        %     obj.Virtual.objectType = [meta('Virtual_objectType'); obj.Virtual.objectType];
        %     obj.Virtual.readerId = [meta('Virtual_readerId'); obj.Virtual.readerId+max(meta('Virtual_readerId'))];
        %     obj.Virtual.seriesName = [meta('Virtual_seriesName'); obj.Virtual.seriesName];
        %     obj.Virtual.slicesPerFile = [meta('Virtual_slicesPerFile'); obj.Virtual.slicesPerFile];
        % elseif insertPosition == D1_z+1 % add dataset to the end of the existing dataset
        %     obj.img = [obj.img; img];
        %     obj.Virtual.filenames = [obj.Virtual.filenames; meta('Virtual_filenames')];     % update filenames
        %     obj.Virtual.objectType = [obj.Virtual.objectType; meta('Virtual_objectType')];
        %     obj.Virtual.readerId = [obj.Virtual.readerId; meta('Virtual_readerId')+max(obj.Virtual.readerId)];
        %     obj.Virtual.seriesName = [obj.Virtual.seriesName; meta('Virtual_seriesName')];
        %     obj.Virtual.slicesPerFile = [obj.Virtual.slicesPerFile; meta('Virtual_slicesPerFile')];
        %
        % else        % insert dataset inside the existing dataset
        %     obj.img = [obj.img(1:insertPosition-1); img; obj.img(insertPosition:end)];
        %     obj.Virtual.filenames = [obj.Virtual.filenames(1:insertPosition-1); meta('Virtual_filenames'); obj.Virtual.filenames(insertPosition:end) ];     % update filenames
        %     obj.Virtual.objectType = [obj.Virtual.objectType(1:insertPosition-1); meta('Virtual_objectType'); obj.Virtual.objectType(insertPosition:end)];
        %     obj.Virtual.readerId = [obj.Virtual.readerId(1:insertPosition-1); ...
        %         meta('Virtual_readerId')+max(obj.Virtual.readerId(1:insertPosition-1));...
        %         obj.Virtual.readerId(insertPosition:end)+max(meta('Virtual_readerId'))];
        %     obj.Virtual.seriesName = [obj.Virtual.seriesName(1:insertPosition-1); meta('Virtual_seriesName'); obj.Virtual.seriesName(insertPosition:end)];
        %     obj.Virtual.slicesPerFile = [obj.Virtual.slicesPerFile(1:insertPosition-1); meta('Virtual_slicesPerFile'); obj.Virtual.slicesPerFile(insertPosition:end)];
        % end
    else
        % index ranges for the existing dataset around the insertion point
        if insertPosition == 1
            Z1_part1 = [D2_z+1, D2_z+D1_z];
            Z1_part2 = [];
            Z2_part1 = [1, D2_z];
        elseif insertPosition == D1_z+1
            Z1_part1 = [1, D1_z];
            Z1_part2 = [];
            Z2_part1 = [D1_z+1, D1_z+D2_z];
        else
            Z1_part1 = [1, insertPosition-1];
            Z1_part2 = [insertPosition+D2_z, D2_z+D1_z];
            Z2_part1 = [insertPosition, insertPosition+D2_z-1];
        end

        % --- image layer [y, x, z, c, t] ---
        if BackgroundColorIntensity ~= 0
            imgOut = zeros([yMax, xMax, D1_z+D2_z, cMax, tMax], obj.image.dataClass) + BackgroundColorIntensity;
        else
            imgOut = zeros([yMax, xMax, D1_z+D2_z, cMax, tMax], obj.image.dataClass);
        end
        if options.showWaitbar; waitbar(0.05, wb); end
        % --- labels/model layer [y, x, z, c, t] ---
        labelCols = size(obj.labels.data{1}, 4);   % 1 for standard labels, packed for labels63
        if obj.labels.maxMaterials < 255   % labels63 stores model+mask+selection together
            if obj.modelExist
                imgOut = zeros([yMax, xMax, D1_z+D2_z, labelCols, tMax], 'uint8');
                imgOut(1:D1_y, 1:D1_x, Z1_part1(1):Z1_part1(2), :, 1:D1_t) = ...
                    obj.labels.data{1}(:, :, 1:Z1_part1(2)-Z1_part1(1)+1, :, :);
                if ~isempty(Z1_part2)
                    imgOut(1:D1_y, 1:D1_x, Z1_part2(1):Z1_part2(2), :, 1:D1_t) = ...
                        obj.labels.data{1}(:, :, Z1_part1(2)+1:end, :, :);
                end
                obj.labels.data{1} = imgOut;
                if options.showWaitbar; waitbar(0.9, wb); end
            end
        else   % separate model, mask, selection layers
            if obj.modelExist
                imgOut = zeros([yMax, xMax, D1_z+D2_z, labelCols, tMax], 'uint8');
                imgOut(1:D1_y, 1:D1_x, Z1_part1(1):Z1_part1(2), :, 1:D1_t) = ...
                    obj.labels.data{1}(:, :, 1:Z1_part1(2)-Z1_part1(1)+1, :, :);
                if ~isempty(Z1_part2)
                    imgOut(1:D1_y, 1:D1_x, Z1_part2(1):Z1_part2(2), :, 1:D1_t) = ...
                        obj.labels.data{1}(:, :, Z1_part1(2)+1:end, :, :);
                end
                obj.labels.data{1} = imgOut;
            end
            if options.showWaitbar; waitbar(0.6, wb); end

            if obj.maskExist
                maskCols = size(obj.mask.data{1}, 4);
                imgOut = zeros([yMax, xMax, D1_z+D2_z, maskCols, tMax], 'uint8');
                imgOut(1:D1_y, 1:D1_x, Z1_part1(1):Z1_part1(2), :, 1:D1_t) = ...
                    obj.mask.data{1}(:, :, 1:Z1_part1(2)-Z1_part1(1)+1, :, :);
                if ~isempty(Z1_part2)
                    imgOut(1:D1_y, 1:D1_x, Z1_part2(1):Z1_part2(2), :, 1:D1_t) = ...
                        obj.mask.data{1}(:, :, Z1_part1(2)+1:end, :, :);
                end
                obj.mask.data{1} = imgOut;
            end
            if options.showWaitbar; waitbar(0.8, wb); end

            if obj.selection.exists
                selCols = size(obj.selection.data{1}, 4);
                imgOut = zeros([yMax, xMax, D1_z+D2_z, selCols, tMax], 'uint8');
                imgOut(1:D1_y, 1:D1_x, Z1_part1(1):Z1_part1(2), :, 1:D1_t) = ...
                    obj.selection.data{1}(:, :, 1:Z1_part1(2)-Z1_part1(1)+1, :, :);
                if ~isempty(Z1_part2)
                    imgOut(1:D1_y, 1:D1_x, Z1_part2(1):Z1_part2(2), :, 1:D1_t) = ...
                        obj.selection.data{1}(:, :, Z1_part1(2)+1:end, :, :);
                end
                obj.selection.data{1} = imgOut;
            end
            if options.showWaitbar; waitbar(0.9, wb); end
        end

        % shift annotations: labelPositions columns = [z, x, y, t]
        [labelsList, labelValues, labelPositions, ~] = obj.annotations.getLabels();
        if ~isempty(labelsList)
            shift = labelPositions(:,1) >= insertPosition;
            labelPositions(shift, 1) = labelPositions(shift, 1) + D2_z;
            obj.annotations.replaceLabels(labelsList, labelPositions, labelValues);
        end

        % update SliceNames
        if ~isempty(obj.image.sliceName)
            sliceNames = obj.image.sliceName;
            if numel(sliceNames) == 1; sliceNames = repmat(sliceNames, [D1_z 1]); end

            sliceNamesNew = {''};
            if ~isempty(meta)
                if isa(meta, 'containers.Map') && isKey(meta, 'SliceName')
                    sliceNamesNew = meta('SliceName');
                elseif isa(meta, 'dictionary') && isKey(meta, 'SliceName')
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
else   % insert a new time point
    % -----------------------------------------------------------------------

    if insertPosition == 1
        T1_part1 = [D2_t+1, D2_t+D1_t];
        T1_part2 = [];
        T2_part1 = [1, D2_t];
    elseif insertPosition == D1_t+1
        T1_part1 = [1, D1_t];
        T1_part2 = [];
        T2_part1 = [D1_t+1, D1_t+D2_t];
    else
        T1_part1 = [1, insertPosition-1];
        T1_part2 = [insertPosition+D2_t, D2_t+D1_t];
        T2_part1 = [insertPosition, insertPosition+D2_t-1];
    end

    % --- image layer [y, x, z, c, t] ---
    if BackgroundColorIntensity ~= 0
        imgOut = zeros([yMax, xMax, zMax, cMax, D1_t+D2_t], obj.image.dataClass) + BackgroundColorIntensity;
    else
        imgOut = zeros([yMax, xMax, zMax, cMax, D1_t+D2_t], obj.image.dataClass);
    end
    if options.showWaitbar; waitbar(0.05, wb); end

    imgOut(1:D1_y, 1:D1_x, 1:D1_z, 1:D1_c, T1_part1(1):T1_part1(2)) = ...
        obj.image.data{1}(:, :, :, :, 1:T1_part1(2)-T1_part1(1)+1);
    imgOut(1:D2_y, 1:D2_x, 1:D2_z, 1:D2_c, T2_part1(1):T2_part1(2)) = img;
    if ~isempty(T1_part2)
        imgOut(1:D1_y, 1:D1_x, 1:D1_z, 1:D1_c, T1_part2(1):T1_part2(2)) = ...
            obj.image.data{1}(:, :, :, :, T1_part1(2)+1:end);
    end
    obj.image.data{1} = imgOut;
    if options.showWaitbar; waitbar(0.4, wb); end

    % --- labels/model layer [y, x, z, c, t] ---
    labelCols = size(obj.labels.data{1}, 4);
    if obj.labels.maxMaterials < 255   % labels63
        if obj.modelExist
            imgOut = zeros([yMax, xMax, zMax, labelCols, D1_t+D2_t], 'uint8');
            imgOut(1:D1_y, 1:D1_x, 1:D1_z, :, T1_part1(1):T1_part1(2)) = ...
                obj.labels.data{1}(:, :, :, :, 1:T1_part1(2)-T1_part1(1)+1);
            if ~isempty(T1_part2)
                imgOut(1:D1_y, 1:D1_x, 1:D1_z, :, T1_part2(1):T1_part2(2)) = ...
                    obj.labels.data{1}(:, :, :, :, T1_part1(2)+1:end);
            end
            obj.labels.data{1} = imgOut;
            if options.showWaitbar; waitbar(0.9, wb); end
        end
    else   % separate layers
        if obj.modelExist
            imgOut = zeros([yMax, xMax, zMax, labelCols, D1_t+D2_t], 'uint8');
            imgOut(1:D1_y, 1:D1_x, 1:D1_z, :, T1_part1(1):T1_part1(2)) = ...
                obj.labels.data{1}(:, :, :, :, 1:T1_part1(2)-T1_part1(1)+1);
            if ~isempty(T1_part2)
                imgOut(1:D1_y, 1:D1_x, 1:D1_z, :, T1_part2(1):T1_part2(2)) = ...
                    obj.labels.data{1}(:, :, :, :, T1_part1(2)+1:end);
            end
            obj.labels.data{1} = imgOut;
        end
        if options.showWaitbar; waitbar(0.6, wb); end

        if obj.maskExist
            maskCols = size(obj.mask.data{1}, 4);
            imgOut = zeros([yMax, xMax, zMax, maskCols, D1_t+D2_t], 'uint8');
            imgOut(1:D1_y, 1:D1_x, 1:D1_z, :, T1_part1(1):T1_part1(2)) = ...
                obj.mask.data{1}(:, :, :, :, 1:T1_part1(2)-T1_part1(1)+1);
            if ~isempty(T1_part2)
                imgOut(1:D1_y, 1:D1_x, 1:D1_z, :, T1_part2(1):T1_part2(2)) = ...
                    obj.mask.data{1}(:, :, :, :, T1_part1(2)+1:end);
            end
            obj.mask.data{1} = imgOut;
        end
        if options.showWaitbar; waitbar(0.8, wb); end

        if obj.selection.exists
            selCols = size(obj.selection.data{1}, 4);
            imgOut = zeros([yMax, xMax, zMax, selCols, D1_t+D2_t], 'uint8');
            imgOut(1:D1_y, 1:D1_x, 1:D1_z, :, T1_part1(1):T1_part1(2)) = ...
                obj.selection.data{1}(:, :, :, :, 1:T1_part1(2)-T1_part1(1)+1);
            if ~isempty(T1_part2)
                imgOut(1:D1_y, 1:D1_x, 1:D1_z, :, T1_part2(1):T1_part2(2)) = ...
                    obj.selection.data{1}(:, :, :, :, T1_part1(2)+1:end);
            end
            obj.selection.data{1} = imgOut;
        end
        if options.showWaitbar; waitbar(0.9, wb); end
    end

    % shift annotations: labelPositions columns = [z, x, y, t]
    [labelsList, labelValues, labelPositions, ~] = obj.annotations.getLabels();
    if ~isempty(labelsList)
        shift = labelPositions(:,4) >= insertPosition;
        labelPositions(shift, 4) = labelPositions(shift, 4) + D2_t;
        obj.annotations.replaceLabels(labelsList, labelPositions, labelValues);
    end

end   % depth / time

clear imgOut;

% ------- update MibImage dimension properties -------
obj.image.height = yMax;
obj.image.width  = xMax;
obj.image.colors = cMax;
if strcmp(options.dim, 'depth')
    obj.image.depth = D1_z + D2_z;
else
    obj.image.time  = D1_t + D2_t;
end
obj.image.dim_yxzct = [obj.image.height, obj.image.width, obj.image.depth, obj.image.colors, obj.image.time];
obj.dim_yxzct = obj.image.dim_yxzct;

% ------- update slices (view range) -------
if obj.orientation == 3       % YX: expand h/w if dataset grew
    obj.slices{1} = [1, obj.image.height];
    obj.slices{2} = [1, obj.image.width];
elseif obj.orientation == 1   % XZ: expand w and full depth
    obj.slices{2} = [1, obj.image.width];
    obj.slices{3} = [1, obj.image.depth];
elseif obj.orientation == 2   % YZ: expand h and full depth
    obj.slices{1} = [1, obj.image.height];
    obj.slices{3} = [1, obj.image.depth];
end

% ------- update bounding box -------
if strcmp(options.dim, 'depth')
    obj.boundingBox(6) = obj.boundingBox(5) + (obj.image.depth - 1) * obj.pixSize.z;
end

% ------- update action log -------
obj.actionLog{end+1} = sprintf('Insert dataset [%dx%dx%dx%dx%d] at position %s=%d', ...
    D2_y, D2_x, D2_z, D2_c, D2_t, options.dim, insertPosition);

if options.showWaitbar; waitbar(1, wb); delete(wb); end

end
