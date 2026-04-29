function segmentationRegionGrowing(obj, yxzCoordinate, BatchOptIn)
% SEGMENTATIONREGIONGROWING - Do segmentation using the Region Growing method.
%
% Syntax:
%   function segmentationRegionGrowing(obj, yxzCoordinate, BatchOptIn)
%
% Based on Fast 3D/2D Region Growing (MEX), written by Christian Wuerslin,
% Stanford University.
% Requires: compiled RegionGrowing_mex.cpp
%
% Input Arguments:
%   - **yxzCoordinate** — vector with [y, x, z] coordinates of the starting point;
%     for the 2D case [y, x] is sufficient
%   - **BatchOptIn** — *(optional)* a structure for batch processing mode, when NaN return
%     a structure with default options via "syncBatch" event, or a char modifier
%     for interactive calls
%     - .Coordinate - Seed point as 'y; x' (2D) or 'y; x; z' (3D)
%     - .Mode - Apply for the current slice (2D, Slice) or the whole stack (3D, Stack)
%     - .IntensityVariation - Maximum intensity variation for region growing
%     - .ColorChannel - Color channel to use
%     - .Radius - Effective radius limit (0 = no limit)
%     - .Action - Action: Add, Subtract, or Replace
%     - .FillHoles - Fill holes in the resulting selection
%     - .FixSelectionToMask - Apply selection only to the masked area
%     - .FixSelectionToMaterial - Apply selection only to the area of the selected material
%     - .showWaitbar - Show or not the progress bar during execution
%
% Output Arguments:
%   (none)
%
% Usage:
%   Example 1::
%
%     obj.segmentationRegionGrowing([50, 75], 'shift');     // region growing from [y,x]=50,75 and add to selection
%
%   Example 2::
%
%     obj.segmentationRegionGrowing([50, 75], BatchOpt);    // batch mode
%

% Updates
%

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

% get handles alias for segmentation panel widgets
segmHandles = obj.mibController.cSegmentation.handles;

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.id = obj.mibModel.getActiveId();

BatchOpt.Coordinate = '';
if nargin >= 2 && ~isempty(yxzCoordinate)
    BatchOpt.Coordinate = num2str(yxzCoordinate, '%d; ');
    BatchOpt.Coordinate = BatchOpt.Coordinate(1:end-1);
end

BatchOpt.Mode = {'2D, Slice'};
if obj.mibModel.applySegmentationIn3D; BatchOpt.Mode = {'3D, Stack'}; end
BatchOpt.Mode{2} = {'2D, Slice', '3D, Stack'};

BatchOpt.IntensityVariation = num2str(segmHandles.magicRange1.Value);

BatchOpt.ColorChannel{2} = arrayfun(@(x) sprintf('ColCh %d', x), 1:obj.mibModel.I{BatchOpt.id}.image.colors, 'UniformOutput', false);
colCh = obj.mibModel.I{BatchOpt.id}.selectedColorChannel;
if colCh == 0; colCh = 1; end
BatchOpt.ColorChannel{1} = BatchOpt.ColorChannel{2}{colCh};

BatchOpt.Radius = num2str(segmHandles.magicRadius.Value);

BatchOpt.Action = {'Add'};
BatchOpt.Action{2} = {'Add', 'Subtract', 'Replace'};

BatchOpt.FillHoles = logical(obj.mibModel.autoFillSelection);
BatchOpt.FixSelectionToMask = logical(obj.mibModel.I{BatchOpt.id}.restrictSelectionToMask);
BatchOpt.FixSelectionToMaterial = logical(obj.mibModel.I{BatchOpt.id}.restrictSelectionToMaterial);
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName = 'Region Growing';

% tooltips
BatchOpt.mibBatchTooltip.Coordinate = 'Seed point coordinates as "y; x" (2D) or "y; x; z" (3D)';
BatchOpt.mibBatchTooltip.Mode = 'Apply for the current slice (2D) or the whole stack (3D)';
BatchOpt.mibBatchTooltip.IntensityVariation = 'Maximum intensity variation for region growing';
BatchOpt.mibBatchTooltip.ColorChannel = 'Color channel to use';
BatchOpt.mibBatchTooltip.Radius = 'Effective radius limit in pixels (0 = no limit)';
BatchOpt.mibBatchTooltip.Action = 'Add to, Subtract from, or Replace current selection';
BatchOpt.mibBatchTooltip.FillHoles = 'Fill holes in the resulting selection using imfill';
BatchOpt.mibBatchTooltip.FixSelectionToMask = 'Apply selection only to the masked area';
BatchOpt.mibBatchTooltip.FixSelectionToMaterial = 'Apply selection only to the area of the selected material';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check actions
if nargin == 3
    if ischar(BatchOptIn)
        % interactive call with modifier string
        keyModifier = BatchOptIn; % store the state
        BatchOptIn = struct;
        if strcmp(keyModifier, 'shift') 
            BatchOptIn.Action{1} = 'Add';
        elseif strcmp(keyModifier, 'control')
            BatchOptIn.Action{1} = 'Subtract';
        else
            BatchOptIn.Action{1} = 'Replace';
        end
    elseif isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
            return;
        elseif isempty(BatchOptIn)
            BatchOptIn.Action{1} = 'Replace';
        else
            dlgOpt.MsgBoxOnly = true;
            header = 'A structure as the 3rd parameter is required!';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Error', dlgOpt);
            return;
        end
    end
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
elseif nargin == 2
    BatchOpt.Action{1} = 'Replace';
end

%% Parse BatchOpt values
id = BatchOpt.id;
coords = str2num(BatchOpt.Coordinate); %#ok<ST2NM>
if isempty(coords) || numel(coords) < 2
    dlgOpt.MsgBoxOnly = true;
    header = 'Invalid seed point coordinates!';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Error', dlgOpt);
    return;
end

dMaxDif = str2double(BatchOpt.IntensityVariation);
magicWandRadius = str2double(BatchOpt.Radius);
col_channel = find(ismember(BatchOpt.ColorChannel{2}, BatchOpt.ColorChannel{1}));
selcontour = obj.mibModel.I{id}.getSelectedMaterialIndex();
switch3d = strcmp(BatchOpt.Mode{1}, '3D, Stack');

if obj.mibModel.I{id}.image.depth < 3; switch3d = false; end

%% 2D mode
if ~switch3d
    x = coords(2);
    y = coords(1);
    obj.mibModel.backup('selection', 0);

    if magicWandRadius > 0
        options.x = [x-magicWandRadius x+magicWandRadius];
        options.y = [y-magicWandRadius y+magicWandRadius];
        x = magicWandRadius + min([options.x(1) 1]);
        y = magicWandRadius + min([options.y(1) 1]);
        options.blockModeSwitch = 0;
    else
        options = struct();
    end
    options.id = id;

    currImage = cell2mat(obj.mibModel.getData2D('image', [], [], col_channel, options));
    selarea = uint8(regiongrowing(currImage, dMaxDif, [y, x]));

    % limit to the selected material of the model
    if BatchOpt.FixSelectionToMaterial && selcontour >= 0
        currModel = cell2mat(obj.mibModel.getData2D('labels', [], [], selcontour, options));
        selarea = bitand(selarea, currModel);
    end

    % limit selection to the masked area
    if BatchOpt.FixSelectionToMask && obj.mibModel.I{id}.maskExist
        currModel = cell2mat(obj.mibModel.getData2D('mask', [], [], [], options));
        selarea = bitand(selarea, currModel);
    end

    if magicWandRadius > 0
        distMap = zeros([size(currImage, 1), size(currImage, 2)], 'uint8');
        distMap(y, x) = 1;
        distMap = bwdist(distMap);
        selarea(distMap > magicWandRadius) = 0;
    end

    % fill holes in the selection
    if BatchOpt.FillHoles
        selarea = imfill(selarea, 'holes');
    end

    switch BatchOpt.Action{1}
        case 'Add'
            currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], options));
            obj.mibModel.setData2D(bitor(currSelection, selarea), 'selection', [], [], [], options);
        case 'Subtract'
            currSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], options));
            currSelection(selarea==1) = 0;
            obj.mibModel.setData2D(currSelection, 'selection', [], [], [], options);
        case 'Replace'
            obj.mibModel.clearSelection('2D, Slice');
            obj.mibModel.setData2D(selarea, 'selection', [], [], [], options);
    end

%% 3D mode
else
    if BatchOpt.showWaitbar
        wb = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait...', 'Title', 'Doing Region Growing in 3D');
    end
    h = coords(1);
    w = coords(2);
    z = coords(3);

    if magicWandRadius > 0
        options.x = [w-magicWandRadius w+magicWandRadius];
        options.y = [h-magicWandRadius h+magicWandRadius];
        options.z = [z-magicWandRadius z+magicWandRadius];
        w = magicWandRadius + min([options.x(1) 1]);
        h = magicWandRadius + min([options.y(1) 1]);
        z = magicWandRadius + min([options.z(1) 1]);
        obj.mibModel.backup('selection', 1, options);
        options.blockModeSwitch = 0;
    else
        options = struct();
        if obj.mibModel.I{id}.orientation ~= 3
            options.blockModeSwitch = 0;
        end
        obj.mibModel.backup('selection', 1);
    end
    options.id = id;
    if BatchOpt.showWaitbar; wb.Value = 0.05; end

    datasetImage = squeeze(cell2mat(obj.mibModel.getData3D('image', [], 3, col_channel, options)));
    if BatchOpt.showWaitbar; wb.Value = 0.3; end
    selarea = uint8(regiongrowing(datasetImage, dMaxDif, [h, w, z]));
    if BatchOpt.showWaitbar; wb.Value = 0.65; end

    % limit to the selected material of the model
    if BatchOpt.FixSelectionToMaterial && selcontour >= 0
        datasetImage = cell2mat(obj.mibModel.getData3D('labels', [], 3, selcontour, options));
        selarea(datasetImage ~= 1) = 0;
    end
    if BatchOpt.showWaitbar; wb.Value = 0.75; end

    % limit selection to the masked area
    if BatchOpt.FixSelectionToMask && obj.mibModel.I{id}.maskExist
        datasetImage = cell2mat(obj.mibModel.getData3D('mask', [], 3, [], options));
        selarea(datasetImage ~= 1) = 0;
    end
    if BatchOpt.showWaitbar; wb.Value = 0.85; end

    if magicWandRadius > 0
        distMap = zeros(size(selarea), 'uint8');
        distMap(h, w, z) = 1;
        distMap = bwdist(distMap);
        selarea(distMap > magicWandRadius) = 0;
    end

    % fill holes in the selection slice-by-slice
    if BatchOpt.FillHoles
        for sliceId = 1:size(selarea, 3)
            selarea(:,:,sliceId) = imfill(selarea(:,:,sliceId), 'holes');
        end
    end
    if BatchOpt.showWaitbar; wb.Value = 0.95; end

    switch BatchOpt.Action{1}
        case 'Add'
            currSelection = cell2mat(obj.mibModel.getData3D('selection', [], 3, [], options));
            obj.mibModel.setData3D(bitor(currSelection, selarea), 'selection', [], 3, [], options);
        case 'Subtract'
            currSelection = cell2mat(obj.mibModel.getData3D('selection', [], 3, [], options));
            currSelection(selarea==1) = 0;
            obj.mibModel.setData3D(currSelection, 'selection', [], 3, [], options);
        case 'Replace'
            obj.mibModel.clearSelection('3D, Stack');
            obj.mibModel.setData3D(selarea, 'selection', [], 3, [], options);
    end
    if BatchOpt.showWaitbar; close(wb); end
end

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfMagicWands = obj.mibModel.preferences.Users.Tiers.numberOfMagicWands + 1;
notify(obj.mibModel, 'UpdateUserScore');

notify(obj.mibModel, 'ShowImage');

% notify the batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj.mibModel, 'SyncBatch', eventdata);

end
