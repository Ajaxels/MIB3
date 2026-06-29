function gui_WinMouseMotionFcn(obj)
% GUI_WINMOUSEMOTIONFCN - Callback for mouse movement over the figure window.
%
% Syntax:
%   function gui_WinMouseMotionFcn(obj)
%
% This function is called on every mouse movement. It:
% - Updates cursor position display in the status bar
% - Tracks mouse movement distance for user statistics
% - Retrieves and displays pixel values under cursor
% - Manages brush cursor visibility based on axes boundaries
%
% Uses persistent variables to prevent callback re-entrance
% and improve performance during rapid mouse movements.
%
% Input Arguments:
%   none
%
% Output Arguments:
%   none
%

persistent inCallback lastCallTime %obj.wasInsideAxes
currentTime = tic();

% Auto-reset if stuck for more than 100ms (handles debugging breakpoints)
if ~isempty(lastCallTime) && toc(lastCallTime) > 0.1
    inCallback = false;
end

% Exit if already processing
if ~isempty(inCallback) && inCallback; return; end
inCallback = true;
lastCallTime = currentTime;

try
    % Get handles
    imViewAxes = obj.handles.imViewAxes;

    % Get mouse coordinates
    position = imViewAxes.CurrentPoint;
    xMouse = round(position(1, 1));
    yMouse = round(position(1, 2));

    % Get axes limits
    axXLim = imViewAxes.XLim;
    axYLim = imViewAxes.YLim;

    % Check if mouse is within axes boundaries
    obj.isInsideAxes = xMouse > axXLim(1) && xMouse < axXLim(2) && ...
        yMouse > axYLim(1) && yMouse < axYLim(2);

    % Only one document can hold the cursor at a time. This figure is the one
    % currently receiving motion events, so clear any stale isInsideAxes flags on
    % the other documents — otherwise in split view both flags stay true and the
    % zoom / keyboard-navigation handlers act on the wrong document.
    cImageDocs = obj.mibController.cImageDoc;
    if numel(cImageDocs) > 1
        for iOtherDoc = 1:numel(cImageDocs)
            if cImageDocs{iOtherDoc} ~= obj
                cImageDocs{iOtherDoc}.isInsideAxes = false;
            end
        end
    end

    % Rubber band + fill preview during custom Polyline Stage 1 placement
    cRoiCtrl = obj.mibController.cRoi;
    if ~isempty(cRoiCtrl) && cRoiCtrl.drawingROI.placementMode && ...
            ~isempty(cRoiCtrl.drawingROI.placementVertices)
        placementVerts = cRoiCtrl.drawingROI.placementVertices;
        cursorX = position(1,1);
        cursorY = position(1,2);
        nVerts = size(placementVerts, 1);

        % Convert last and first confirmed vertices to axes coords
        lastVert  = placementVerts(end, :);
        firstVert = placementVerts(1,   :);
        [lastAxX,  lastAxY]  = obj.mibModel.convertDataToMouseCoordinates(lastVert(1),  lastVert(2),  'shown');
        [firstAxX, firstAxY] = obj.mibModel.convertDataToMouseCoordinates(firstVert(1), firstVert(2), 'shown');

        % Rubber band: last → cursor → first (one segment when only 1 vertex)
        if nVerts == 1
            rbX = [lastAxX; cursorX];
            rbY = [lastAxY; cursorY];
        else
            rbX = [lastAxX; cursorX; firstAxX];
            rbY = [lastAxY; cursorY; firstAxY];
        end
        lineH = cRoiCtrl.drawingROI.rubberBandLine;
        if isempty(lineH) || ~isvalid(lineH)
            lineH = line(imViewAxes, rbX, rbY, ...
                'Color', [0 0.447 0.741], 'LineWidth', 1, 'LineStyle', '--', ...
                'Tag', 'polylinePlacement', 'HitTest', 'off', 'PickableParts', 'none');
            cRoiCtrl.drawingROI.rubberBandLine = lineH;
        else
            lineH.XData = rbX;
            lineH.YData = rbY;
        end

        % Semi-transparent fill: all confirmed vertices + cursor (needs ≥ 3 total)
        if nVerts >= 2
            [allAxX, allAxY] = obj.mibModel.convertDataToMouseCoordinates( ...
                placementVerts(:,1), placementVerts(:,2), 'shown');
            patchX = [allAxX(:); cursorX];
            patchY = [allAxY(:); cursorY];
            patchH = cRoiCtrl.drawingROI.previewPatch;
            if isempty(patchH) || ~isvalid(patchH)
                patchH = patch(imViewAxes, patchX, patchY, [0 0.447 0.741], ...
                    'EdgeColor', 'none', ...
                    'Tag', 'polylinePlacement', 'HitTest', 'off', 'PickableParts', 'none');
                patchH.FaceAlpha = 0.15;
                cRoiCtrl.drawingROI.previewPatch = patchH;
            else
                patchH.XData = patchX;
                patchH.YData = patchY;
            end
        end
    end

    if obj.isInsideAxes
        obj.UIFigure.Pointer = 'crosshair';
        sessionSettings = obj.mibModel.sessionSettings;

        % Calculate mouse travel distance
        if sessionSettings.prevCursorCoordinate(1) > 0
            mouseDist = sqrt((sessionSettings.prevCursorCoordinate(1)-xMouse)^2 + ...
                (sessionSettings.prevCursorCoordinate(2)-yMouse)^2) * ...
                sessionSettings.metersPerPixel;
            obj.mibModel.preferences.Users.Tiers.mouseTravelDistance = ...
                obj.mibModel.preferences.Users.Tiers.mouseTravelDistance + mouseDist;
            obj.mibModel.preferences.Users.Tiers.collectedPoints = ...
                obj.mibModel.preferences.Users.Tiers.collectedPoints + mouseDist;
        end
        obj.mibModel.sessionSettings.prevCursorCoordinate = [xMouse, yMouse];

        % Check if inside image boundaries.
        % xMouse/yMouse are in XData/YData (physical) coordinates where the X axis
        % is stretched by coef_z. Use imageHandle.XData(2)/YData(2) as boundaries
        % since those already incorporate the coef_z scaling set in showImage.
        if ~isempty(obj.imageHandle) && isvalid(obj.imageHandle)
            obj.isInsideImage = xMouse > 0 && yMouse > 0 && ...
                xMouse <= obj.imageHandle.XData(2) && ...
                yMouse <= obj.imageHandle.YData(2);
        else
            obj.isInsideImage = false;
        end

        if obj.isInsideImage
            % Use a local id for pixel readout — never write to mibModel.id
            % here.  Writing mibModel.id on every mouse move corrupts the
            % active-dataset state for panning, keyboard shortcuts, and any
            % MibModel method that reads obj.id as a default.
            localId = obj.mibModel.Sets.selectedDataset(obj.setOfDatasetsIndex) + ...
                (obj.setOfDatasetsIndex - 1) * obj.mibModel.Sets.datasetsInSet;
            dataset = obj.mibModel.I{localId};
            orientation = dataset.orientation;
            cImage = dataset.slices{4};
            tImage = dataset.slices{5}(1);

            % Local copies for coordinate conversion (avoid MibModel
            % wrappers that read obj.id)
            magFactor = dataset.magFactor;
            axesX = dataset.axesX;
            axesY = dataset.axesY;
            if numel(axesX) < 2 || isnan(axesX(1)); axesX = [1, dataset.dim_yxzct(2)]; end
            if numel(axesY) < 2 || isnan(axesY(1)); axesY = [1, dataset.dim_yxzct(1)]; end

            % coef_z for anisotropic voxel stretching
            switch orientation
                case 3;  coef_z = dataset.image.pixSize.x / dataset.image.pixSize.y;
                case 1;  coef_z = dataset.image.pixSize.z / dataset.image.pixSize.x;
                otherwise; coef_z = dataset.image.pixSize.z / dataset.image.pixSize.y;
            end

            % Handle Virtual / BigData mode (on-demand readers; pixel readout
            % comes from the rendered Iraw, never from dataset.image.data which
            % is empty for these types)
            if any(dataset.datasetType(1) == ['V' 'B'])
                % Iraw is the raw image displayed on screen.
                % When zoomed in (magFactor < 1): Iraw is a full-res crop of the
                % dataset — use 'blockmode' to get position within that crop.
                % When zoomed out (magFactor >= 1): Iraw is at screen resolution —
                % axes coordinates index directly into it.
                if magFactor < 1
                    % blockmode conversion (inline)
                    xImage = ceil(xMouse * magFactor);
                    yImage = ceil(yMouse * magFactor);
                else
                    xImage = xMouse;
                    yImage = yMouse;
                end

                % Clamp Iraw indices to actual rendered image size
                if ~isempty(obj.mibModel.Iraw)
                    xImage = max(1, min(xImage, size(obj.mibModel.Iraw, 2)));
                    yImage = max(1, min(yImage, size(obj.mibModel.Iraw, 1)));
                end

                % Dataset-absolute coordinates for the status bar (shown mode, inline)
                if magFactor >= 1 && axesX(1) <= 1 && axesY(1) <= 1
                    xStatus = ceil(xMouse * magFactor / coef_z);
                    yStatus = ceil(yMouse * magFactor);
                else
                    xStatus = ceil(xMouse * magFactor / coef_z + max([0 floor(axesX(1))]));
                    yStatus = ceil(yMouse * magFactor           + max([0 floor(axesY(1))]));
                end
            else
                % Convert mouse coordinates to dataset coordinates (shown mode, inline)
                if magFactor >= 1 && axesX(1) <= 1 && axesY(1) <= 1
                    xImage = ceil(xMouse * magFactor / coef_z);
                    yImage = ceil(yMouse * magFactor);
                else
                    xImage = ceil(xMouse * magFactor / coef_z + max([0 floor(axesX(1))]));
                    yImage = ceil(yMouse * magFactor           + max([0 floor(axesY(1))]));
                end
                sliceNo = dataset.getCurrentSliceNumber();

                % Get image dimensions in the current orientation
                getDimsOptions.blockModeSwitch = false;
                [imgHeight, imgWidth, imgDepth] = dataset.getDatasetDimensions('image', [], getDimsOptions);

                yImage = min([yImage, imgHeight]);
                xImage = min([xImage, imgWidth]);
                sliceNo = min([sliceNo, imgDepth]);

                xStatus = xImage;
                yStatus = yImage;
            end

            colorValues = [];
            modelValues = NaN;

            % Get pixel values based on orientation
            if orientation == 3  % YX orientation
                if ~any(dataset.datasetType(1) == ['V' 'B'])
                    colorValues = squeeze(dataset.image.data(yImage, xImage, sliceNo, cImage, tImage));
                    if dataset.modelExist
                        modelValues = dataset.labels.data(yImage, xImage, sliceNo, tImage);
                    end
                else  % Virtual / BigData stacking mode
                    colorValues = 0;
                    if ~isempty(obj.mibModel.Iraw)
                        % Iraw is [viewportH, viewportW, allChannels].
                        % Index only the selected channels and squeeze to a
                        % column vector so the downstream concatenation works.
                        colorValues = squeeze(obj.mibModel.Iraw(yImage, xImage, cImage));
                    end
                    % IrawModel is the rendered model material-index raster,
                    % aligned with Iraw (same viewport grid). The model store is
                    % read on demand so we reuse the already-rendered overlay
                    % rather than hitting the disk on every mouse move.
                    if dataset.modelExist && ~isempty(obj.mibModel.IrawModel)
                        mYImage = max(1, min(yImage, size(obj.mibModel.IrawModel, 1)));
                        mXImage = max(1, min(xImage, size(obj.mibModel.IrawModel, 2)));
                        modelValues = obj.mibModel.IrawModel(mYImage, mXImage);
                    end
                end
            elseif orientation == 1 && ~any(dataset.datasetType(1) == ['V' 'B'])  % ZX orientation
                colorValues = squeeze(dataset.image.data(sliceNo, yImage, xImage, cImage, tImage));
                if dataset.modelExist
                    modelValues = dataset.labels.data(sliceNo, yImage, xImage, tImage);
                end
            elseif orientation == 2 && ~any(dataset.datasetType(1) == ['V' 'B'])  % ZY orientation
                colorValues = squeeze(dataset.image.data(yImage, sliceNo, xImage, cImage, tImage));
                if dataset.modelExist
                    modelValues = dataset.labels.data(yImage, sliceNo, xImage, tImage);
                end
            end

            % Update status label with pixel coordinates and values
            % xStatus/yStatus are dataset-absolute; xImage/yImage index into Iraw
            if numel(colorValues) == 0
                obj.mibController.cStatus.handles.pixelLabel.Text = sprintf('%d:%d', xStatus, yStatus);
            else
                % Pad colorValues with NaN to always show 4 channels
                colorPadded = [double(colorValues); NaN(max(0, 4-numel(colorValues)), 1)];
                obj.mibController.cStatus.handles.pixelLabel.Text = sprintf('%d:%d (%d:%d:%d:%d) / %d', ...
                    xStatus, yStatus, colorPadded(1), colorPadded(2), colorPadded(3), colorPadded(4), modelValues);
            end

            % Update brush cursor position.
            % Magnification staleness is detected inside updateBrushCursor
            % (via brushCursorMagFactor), so no explicit resetOffset needed here.
            if obj.view.brushCursorShow
                obj.updateBrushCursor([xMouse, yMouse]);
            end
        else
            obj.mibController.cStatus.handles.pixelLabel.Text = sprintf('Pixel: %d:%d (RRRRR:GGGGG:BBBBB)', xMouse, yMouse);
        end
    else
        obj.UIFigure.Pointer = 'arrow';
        obj.mibController.cStatus.handles.pixelLabel.Text = 'Pixel: XXXXX:XXXXX (RRRRR:GGGGG:BBBBB)';
    end

    % Optimize: only update cursor visibility when crossing axes/image boundary
    if isempty(obj.wasInsideAxes) || obj.wasInsideAxes ~= obj.isInsideImage || obj.wasInsideAxes ~= obj.isInsideAxes
        if (~obj.isInsideImage || ~obj.isInsideAxes) && obj.view.brushCursorShow
            %obj.updateBrushCursor([], [], false);
            obj.updateBrushCursor();
        end
        obj.wasInsideAxes = obj.isInsideImage;
    end
    % % Optimize: only update cursor visibility when crossing axes boundary
    % if isempty(obj.wasInsideAxes) || obj.wasInsideAxes ~= obj.isInsideAxes
    %     if ~obj.isInsideAxes && obj.view.brushCursorShow
    %         obj.updateBrushCursor([], [], false);
    %     end
    %     obj.wasInsideAxes = obj.isInsideAxes;
    % end

catch err
    disp(err);
end

inCallback = false;
end
