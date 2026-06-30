function segmentationMagicWand(obj, yxzCoordinate, BatchOptIn)
% SEGMENTATIONMAGICWAND - Do segmentation using the Magic Wand tool.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.segmentationMagicWand(yxzCoordinate)
%      obj.segmentationMagicWand(yxzCoordinate, BatchOptIn)
%
% Selects pixels connected to the clicked point whose intensity falls
% within the specified threshold range. Supports 2D and 3D modes,
% optional radius limit, and connectivity filtering.
%
% Input Arguments:
%   - **yxzCoordinate** — [vector] coordinates of the starting point: ``[y, x]`` for 2D or ``[y, x, z]`` for 3D
%   - **BatchOptIn** *(optional)* — [struct|char] batch processing mode structure, or modifier key for interactive calls
%     When ``NaN``, returns default structure via "syncBatch" event:
%
%     - ``.Coordinate`` — [char] seed point as ``'y; x'`` (2D) or ``'y; x; z'`` (3D)
%     - ``.Mode`` — [char] ``'Slice'`` (2D, current slice) or ``'Stack'`` (3D, whole stack)
%     - ``.ThresholdLow`` — [numeric] low threshold shift from seed intensity
%     - ``.ThresholdHigh`` — [numeric] high threshold shift from seed intensity
%     - ``.ColorChannel`` — [numeric] color channel to use for thresholding
%     - ``.Radius`` — [numeric] effective radius limit (``0`` = no limit)
%     - ``.Connectivity`` — [char] connectivity: ``'8/26'``, ``'4/6'``, or ``'None'``
%     - ``.Action`` — [char] ``'Add'``, ``'Subtract'``, or ``'Replace'``
%     - ``.FillHoles`` — [logical] fill holes in resulting selection
%     - ``.FixSelectionToMask`` — [logical] apply selection only to masked area
%     - ``.FixSelectionToMaterial`` — [logical] apply selection only to selected material area
%     - ``.showWaitbar`` — [logical] show progress bar during execution
%
% Output Arguments:
%   (none)
%
% **Example 1** — interactive magic wand with shift modifier:
%
%   .. code-block:: matlab
%
%      obj.segmentationMagicWand([50, 75], 'shift');  % wand from [y,x]=50,75 and add to selection
%
% **Example 2** — batch processing mode:
%
%   .. code-block:: matlab
%
%      obj.segmentationMagicWand([50, 75], BatchOpt);  % batch mode with options
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
    BatchOpt.Coordinate = BatchOpt.Coordinate(1:end-1);    % remove trailing '; '
end

BatchOpt.Mode = {'2D, Slice'};
if obj.mibModel.applySegmentationIn3D; BatchOpt.Mode = {'3D, Stack'}; end
BatchOpt.Mode{2} = {'2D, Slice', '3D, Stack'};

BatchOpt.ThresholdLow = num2str(segmHandles.magicRange1.Value);
BatchOpt.ThresholdHigh = num2str(segmHandles.magicRange2.Value);

BatchOpt.ColorChannel{2} = arrayfun(@(x) sprintf('ColCh %d', x), 1:obj.mibModel.I{BatchOpt.id}.image.colors, 'UniformOutput', false);
colCh = obj.mibModel.I{BatchOpt.id}.selectedColorChannel;
if colCh == 0; colCh = 1; end
BatchOpt.ColorChannel{1} = BatchOpt.ColorChannel{2}{colCh};

BatchOpt.Radius = num2str(segmHandles.magicRadius.Value);

connectTag = segmHandles.magicConnect.SelectedObject.Tag;
if strcmp(connectTag, 'magicConnect4')
    BatchOpt.Connectivity = {'4/6-connected'};
else
    BatchOpt.Connectivity = {'8/26-connected'};
end
BatchOpt.Connectivity{2} = {'8/26-connected', '4/6-connected'};

BatchOpt.Action = {'Add'};
BatchOpt.Action{2} = {'Add', 'Subtract', 'Replace'};

BatchOpt.FillHoles = logical(obj.mibModel.autoFillSelection);
BatchOpt.FixSelectionToMask = logical(obj.mibModel.I{BatchOpt.id}.restrictSelectionToMask);
BatchOpt.FixSelectionToMaterial = logical(obj.mibModel.I{BatchOpt.id}.restrictSelectionToMaterial);
BatchOpt.showWaitbar = true;

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName = 'Magic Wand';

% tooltips
BatchOpt.mibBatchTooltip.Coordinate = 'Seed point coordinates as "y; x" (2D) or "y; x; z" (3D)';
BatchOpt.mibBatchTooltip.Mode = 'Apply for the current slice (2D) or the whole stack (3D)';
BatchOpt.mibBatchTooltip.ThresholdLow = 'Low threshold shift from the seed point intensity';
BatchOpt.mibBatchTooltip.ThresholdHigh = 'High threshold shift from the seed point intensity';
BatchOpt.mibBatchTooltip.ColorChannel = 'Color channel to use for thresholding';
BatchOpt.mibBatchTooltip.Radius = 'Effective radius limit in pixels (0 = no limit)';
BatchOpt.mibBatchTooltip.Connectivity = 'Connectivity type: 8/26-connected, 4/6-connected, or None';
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
    % called with only yxzCoordinate, no modifier → Replace
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

threshold1 = str2double(BatchOpt.ThresholdLow);
threshold2 = str2double(BatchOpt.ThresholdHigh);
magicWandRadius = str2double(BatchOpt.Radius);
col_channel = find(ismember(BatchOpt.ColorChannel{2}, BatchOpt.ColorChannel{1}));
selcontour = obj.mibModel.I{id}.getSelectedMaterialIndex();
switch3d = strcmp(BatchOpt.Mode{1}, '3D, Stack');

if obj.mibModel.I{id}.image.depth < 3; switch3d = false; end

%% 2D mode
if ~switch3d
    x = coords(2);
    y = coords(1);

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
    % Pyramidal (BigData/Virtual): read the image at FULL resolution. getData2D
    % otherwise returns the slice at the displayed pyramid level (downsampled by
    % magFactor) while the seed coordinates (x,y) are full-res — so currImage(y,x)
    % and bwselect would sample/seed the wrong pixel.
    if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B']); options.magFactor = 1; end
    % WSI safety net (warn-only): a radius-less wand reads the whole full-res slice.
    if magicWandRadius == 0 && any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B'])
        utils.warnLargeFullResRead(obj.mibModel.I{id}.image.height, obj.mibModel.I{id}.image.width);
    end
    % backup AFTER the options window is set so it is bounded to the radius region
    % (radius=0 has no window → full-slice backup, already warned above).
    obj.mibModel.backup('selection', 0, options);

    currImage = cell2mat(obj.mibModel.getData2D('image', [], [], col_channel, options));
    val = currImage(y, x);
    upper = val + threshold2;
    lower = val - threshold1;
    selarea = zeros([size(currImage, 1), size(currImage, 2)], 'uint8') + 1;

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

    selarea(currImage < lower) = 0;
    selarea(currImage > upper) = 0;

    % select connected regions based on connectivity setting
    switch BatchOpt.Connectivity{1}
        case '8/26-connected'
            selarea = uint8(bwselect(selarea, x, y, 8));
        case '4/6-connected'
            selarea = uint8(bwselect(selarea, x, y, 4));
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
        wb = uiprogressdlg(obj.view.gui, 'Value', 0, 'Message', 'Please wait...', 'Title', 'Doing Magic Wand in 3D');
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
    % full-resolution read for pyramidal datasets (getData3D does not inject
    % magFactor, but set it explicitly so seed coords match the data and to stay
    % robust if that changes).
    if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B']); options.magFactor = 1; end
    % WSI safety net (warn-only): a radius-less wand reads the whole full-res volume.
    if magicWandRadius == 0 && any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B'])
        utils.warnLargeFullResRead(obj.mibModel.I{id}.image.height, obj.mibModel.I{id}.image.width);
    end
    if BatchOpt.showWaitbar; wb.Value = 0.05; end

    datasetImage = cell2mat(obj.mibModel.getData3D('image', [], 3, col_channel, options));

    val = datasetImage(h, w, z);
    upper = val + threshold2;
    lower = val - threshold1;
    selarea = zeros([size(datasetImage, 1) size(datasetImage, 2) size(datasetImage, 3)], 'uint8');
    if BatchOpt.showWaitbar; wb.Value = 0.3; end
    selarea(datasetImage >= lower & datasetImage <= upper) = 1;

    % limit to the selected material of the model
    if BatchOpt.FixSelectionToMaterial && selcontour >= 0
        datasetImage = cell2mat(obj.mibModel.getData3D('labels', [], 3, selcontour, options));
        selarea(datasetImage ~= 1) = 0;
    end
    if BatchOpt.showWaitbar; wb.Value = 0.4; end

    % limit selection to the masked area
    if BatchOpt.FixSelectionToMask && obj.mibModel.I{id}.maskExist
        datasetImage = cell2mat(obj.mibModel.getData3D('mask', [], 3, [], options));
        selarea(datasetImage ~= 1) = 0;
    end
    if BatchOpt.showWaitbar; wb.Value = 0.5; end

    % select connected regions based on connectivity setting
    if strcmp(BatchOpt.Connectivity{1}, '4/6-connected')
        CC = bwconncomp(selarea, 6);
    else
        CC = bwconncomp(selarea, 26);
    end

    if CC.NumObjects == 0
        if BatchOpt.showWaitbar; close(wb); end
        return;
    end
    xyz_index = sub2ind(size(selarea), h, w, z);
    foundId = 0;
    for ii = 1:numel(CC.PixelIdxList)
        if ~isempty(find(CC.PixelIdxList{ii} == xyz_index, 1, 'first'))
            foundId = ii;
            break;
        end
    end
    if foundId == 0
        if BatchOpt.showWaitbar; close(wb); end
        return;
    end
    selarea = zeros(size(selarea), 'uint8');
    selarea(CC.PixelIdxList{foundId}) = 1;

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
    if BatchOpt.showWaitbar; wb.Value = 0.9; end

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
