function output = segmentationClickTracker(obj, yxzCoordinate, yx, modifier)
% SEGMENTATIONCLICKTRACKER - Trace membranes and draw straight lines in 2D and 3D.
%
% Syntax:
%   .. code-block:: matlab
%
%      output = obj.segmentationClickTracker(yxzCoordinate, yx, modifier)
%
% Uses the Membrane Click Tracker tool to connect two user-clicked points
% either by tracing along minimum intensity gradients (fast marching) or by
% drawing a straight line segment. In 3D mode only straight lines are supported.
%
% Input Arguments:
%   - **yxzCoordinate** — [vector] ``[y, x, z]`` coordinates of starting point (voxel coordinates of dataset)
%   - **yx** — [vector] ``[y, x]`` coordinates of clicked point in display coordinate system (before magnification)
%   - **modifier** — [char] specify action with generated selection:
%
%     - ``''`` — trace membrane from starting to selected point
%     - ``'control'`` — define starting point of membrane (2D mode)
%     - ``'shift'`` — define starting point of membrane (3D straight-line mode)
%
% Output Arguments:
%   - **output** — [char] define next action in ``gui_WindowButtonDownFcn``:
%
%     - ``'continue'`` — continue with script
%     - ``'return'`` — stop execution and return
%
% **Example 1** — define starting point (2D mode, Ctrl+click):
%
%   .. code-block:: matlab
%
%      output = obj.segmentationClickTracker([50, 75, 1], [25, 38], {'control'});
%
% **Example 2** — trace to endpoint:
%
%   .. code-block:: matlab
%
%      output = obj.segmentationClickTracker([50, 75, 1], [25, 38], '');
%

% Updates
%

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

% get handles alias for segmentation panel widgets
segmHandles = obj.mibController.cSegmentation.handles;
id = obj.mibModel.getActiveId();

switch3d = obj.mibModel.applySegmentationIn3D;
output = 'continue';

% Pyramidal (Virtual/BigData) datasets: read/write the visible block at FULL
% resolution. This tool maps the screen click to data coordinates as yx*magFactor
% (full-res) and offsets the stored start point against the full-res axes origin;
% if getData2D/getData3D returned the downsampled (displayed-level) block instead,
% the traced line/point would land shifted and rescaled. magFactor=1 forces the
% block to full resolution so both conventions line up (Standard behaviour).
isPyramidalDataset = any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B']);

if obj.mibModel.I{id}.blockModeSwitch
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    header = 'Please switch off the BlockMode using the button in the toolbar';
    dlgOpt.HeaderLines = 2;
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Not compatible with the BlockMode', dlgOpt);
    return;
end

if switch3d && ~segmHandles.membraneStraightLine.Value
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_error';
    header = sprintf('The automatic line tracking is only available for the 2D mode; please switch off the 3D mode in the Selection panel\n\nNote: the 3D mode can be used to generate straight line segments when the "Straight line" option of the Membrane ClickTracker tool is selected');
    dlgOpt.HeaderLines = 6;
    dlgOpt.WindowHeight = 220;
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Error', dlgOpt);
    return;
end

line_width = segmHandles.membraneWidth.Value;
orient = 3;

magFactor = obj.mibModel.getMagFactor();
if switch3d
    h = yxzCoordinate(1);
    w = yxzCoordinate(2);
    z = yxzCoordinate(3);
    if any(strcmp(modifier, 'shift'))    % defines first point for the tracer, with the Shift button
        obj.mibModel.backup('selection', 0);

        obj.trackerYXZ = [h; w; z];
        options.blockModeSwitch = 1;
        options.id = id;
        if isPyramidalDataset; options.magFactor = 1; end
        currentSelection = cell2mat(obj.mibModel.getData2D('selection', [], orient, [], options));
        selarea = zeros(size(currentSelection), 'uint8');
        selarea(ceil(yx(1)*magFactor), ceil(yx(2)*magFactor)) = 1;
        obj.mibModel.setData2D(bitor(selarea, currentSelection), 'selection', [], orient, [], options);
    else
        if isnan(obj.trackerYXZ(1))
            dlgOpt.MsgBoxOnly = true;
            dlgOpt.Icon = 'puffin_warning';
            dlgOpt.WindowStyle = 'modal';
            header = 'Please use Shift+Mouse click to define the starting point!';
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Missing the starting point', dlgOpt);
            return;
        end

        [height, width, thick] = obj.mibModel.I{id}.image.getDatasetDimensions(3);
        p1 = obj.trackerYXZ(:,end);
        p2 = [h; w; z];
        dv = p2 - p1;

        % generate structural element for dilation
        orientation = obj.mibModel.I{id}.orientation;
        pixSize = obj.mibModel.I{id}.image.pixSize;
        if orientation == 1
            se_size(1) = line_width; % x
            se_size(2) = round(se_size(1)*pixSize.x/pixSize.z); % y
            se_size(3) = line_width; % for z
        elseif orientation == 2
            se_size(2) = line_width; % y
            se_size(3) = line_width; % for z
            se_size(1) = round(line_width*pixSize.x/pixSize.z); % x
        elseif orientation == 3
            se_size(1) = line_width; % for x
            se_size(2) = line_width; % for y
            se_size(3) = round(se_size(1)*pixSize.x/pixSize.z); % for z
        end
        se = zeros(se_size(1)*2+1, se_size(2)*2+1, se_size(3)*2+1);
        [xMesh, yMesh, zMesh] = meshgrid(-se_size(1):se_size(1), -se_size(2):se_size(2), -se_size(3):se_size(3));
        ball = sqrt((xMesh/se_size(1)).^2 + (yMesh/se_size(2)).^2 + (zMesh/se_size(3)).^2);
        se(ball <= 1) = 1;

        minY = min([p1(1), p2(1)]);
        maxY = max([p1(1), p2(1)]);
        minX = min([p1(2), p2(2)]);
        maxX = max([p1(2), p2(2)]);
        minZ = min([p1(3), p2(3)]);
        maxZ = max([p1(3), p2(3)]);

        shiftY1 = se_size(2);
        shiftY2 = se_size(2);
        shiftX1 = se_size(1);
        shiftX2 = se_size(1);
        shiftZ1 = se_size(3);
        shiftZ2 = se_size(3);

        if minY - se_size(2) <= 0; shiftY1 = minY - 1; end
        if minX - se_size(1) <= 0; shiftX1 = minX - 1; end
        if minZ - se_size(3) <= 0; shiftZ1 = minZ - 1; end
        if maxY + se_size(2) > height; shiftY2 = height - maxY; end
        if maxX + se_size(1) > width; shiftX2 = width - maxX; end
        if maxZ + se_size(3) > thick; shiftZ2 = thick - maxZ; end

        p1shift = p1 - [minY-shiftY1-1; minX-shiftX1-1; minZ-shiftZ1-1];

        options.x = [minX-shiftX1, maxX+shiftX2];
        options.y = [minY-shiftY1, maxY+shiftY2];
        options.z = [minZ-shiftZ1, maxZ+shiftZ2];
        options.id = id;
        if isPyramidalDataset; options.magFactor = 1; end   % full-res window (coords are full-res)

        % do backup
        obj.mibModel.backup('selection', 1, options);

        currSelection = squeeze(cell2mat(obj.mibModel.getData3D('selection', [], orient, [], options)));
        selareaCrop = zeros(size(currSelection), 'uint8');

        nPnts = max(abs(dv)) + 1;
        linSpacing = linspace(0, 1, nPnts);
        for i = 1:nPnts
            selareaCrop(round(p1shift(1)+linSpacing(i)*dv(1)), round(p1shift(2)+linSpacing(i)*dv(2)), round(p1shift(3)+linSpacing(i)*dv(3))) = 1;
        end
        if isempty(find(se_size == 0, 1))    % dilate to make line thicker
            selareaCrop = imdilate(selareaCrop, se);
        end
        obj.trackerYXZ = [obj.trackerYXZ, [h; w; z]];
        % combine selections
        obj.mibModel.setData3D(bitor(currSelection, selareaCrop), 'selection', [], orient, [], options);
        notify(obj.mibModel, 'ShowImage');
        output = 'return';
        return;
    end
else
    obj.mibModel.backup('selection', 0);
    yCrop = yxzCoordinate(1);
    xCrop = yxzCoordinate(2);
    z = yxzCoordinate(3);
    options.blockModeSwitch = 1;
    options.id = id;
    if isPyramidalDataset; options.magFactor = 1; end
    if any(strcmp(modifier, 'control'))    % defines first point for the tracer
        obj.trackerYXZ = [yCrop; xCrop; z];
        currentSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], options));
        selarea = zeros(size(currentSelection), 'uint8');
        selarea(ceil(yx(1)*magFactor), ceil(yx(2)*magFactor)) = 1;
    else    % start tracing
        if isnan(obj.trackerYXZ(1))
            dlgOpt.MsgBoxOnly = true;
            dlgOpt.Icon = 'puffin_warning';
            dlgOpt.WindowStyle = 'modal';
            header = 'Please use Ctrl+Mouse click to define the starting point!';
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Missing the starting point', dlgOpt);
            return;
        end
        startPoint = obj.trackerYXZ(:,end);
        [axesX, axesY] = obj.mibModel.getAxesLimits();
        pointY = startPoint(1) - max([0, floor(axesY(1))]);
        pointX = startPoint(2) - max([0, floor(axesX(1))]);
        if pointY < 1 || pointX < 1 || pointX > axesX(2) || pointY > axesY(2)
            dlgOpt.MsgBoxOnly = true;
            dlgOpt.WindowStyle = 'modal';
            header = 'Please shift the window to see both the starting and the ending points!';
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong view!', dlgOpt);
            return;
        end
        currentSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], [], options));
        if segmHandles.membraneStraightLine.Value   % connect points using a straight line
            pnts(1,:) = [pointX, pointY];
            pnts(2,:) = [ceil(yx(2)*magFactor), ceil(yx(1)*magFactor)];
            selarea = zeros(size(currentSelection), 'uint8');
            selarea = utils.connectPoints(selarea, pnts);
            obj.trackerYXZ = [obj.trackerYXZ, [yCrop; xCrop; z]];
        else            % connect points using accurate fast marching function
            colorId = obj.mibModel.I{id}.selectedColorChannel;
            if colorId == 0
                if obj.mibModel.I{id}.image.colors > 1
                    dlgOpt.MsgBoxOnly = true;
                    header = 'Please select the color channel in the Selection panel!';
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong color channel!', dlgOpt);
                    return;
                else
                    colorId = 1;
                end
            end
            traceOptions.p1 = [pointY; pointX];
            traceOptions.p2 = [min([ceil(yx(1)*magFactor), size(currentSelection, 1)]); ...
                min([ceil(yx(2)*magFactor), size(currentSelection, 2)])];
            traceOptions.scaleFactor = segmHandles.membraneScale.Value;
            traceOptions.segmTrackBlackChk = segmHandles.membraneBlackSignal.Value;
            traceOptions.colorId = colorId;
            currImage = cell2mat(obj.mibModel.getData2D('image', [], [], [], options));

            [selarea, status] = utils.traceCurve(currImage, traceOptions);
            if status == 1; obj.trackerYXZ = [obj.trackerYXZ, [yCrop; xCrop; z]]; end
        end
    end
    if line_width > 0
        selarea = imdilate(selarea, strel('disk', line_width-1, 0));
    end
    obj.mibModel.setData2D(bitor(currentSelection, selarea), 'selection', [], [], [], options);
end

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfMembraneClickTrackers = obj.mibModel.preferences.Users.Tiers.numberOfMembraneClickTrackers + 1;
notify(obj.mibModel, 'UpdateUserScore');

notify(obj.mibModel, 'ShowImage');

end
