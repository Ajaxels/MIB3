function gui_WinMouseMotionFcn(obj)
% function gui_WinMouseMotionFcn(obj)
% Callback for mouse movement over the figure window
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
% Parameters:
%   none
%
% Return values:
%   none

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

            % coef_z for anisotropic voxel stretching
            switch orientation
                case 3;  coef_z = dataset.image.pixSize.x / dataset.image.pixSize.y;
                case 1;  coef_z = dataset.image.pixSize.z / dataset.image.pixSize.x;
                otherwise; coef_z = dataset.image.pixSize.z / dataset.image.pixSize.y;
            end

            % Handle Virtual mode
            if dataset.datasetType(1) == 'V'
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
                if magFactor >= 1 && axesX(1) <= 1
                    xStatus = ceil(xMouse * magFactor / coef_z);
                    yStatus = ceil(yMouse * magFactor);
                else
                    xStatus = ceil(xMouse * magFactor / coef_z + max([0 floor(axesX(1))]));
                    yStatus = ceil(yMouse * magFactor           + max([0 floor(axesY(1))]));
                end
            else
                % Convert mouse coordinates to dataset coordinates (shown mode, inline)
                if magFactor >= 1 && axesX(1) <= 1
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
                if dataset.datasetType(1) ~= 'V'
                    colorValues = squeeze(dataset.image.data{1}(yImage, xImage, sliceNo, cImage, tImage));
                    if dataset.modelExist
                        modelValues = dataset.labels.data{1}(yImage, xImage, sliceNo, tImage);
                    end
                else  % Virtual stacking mode
                    colorValues = 0;
                    if ~isempty(obj.mibModel.Iraw)
                        % Iraw is [viewportH, viewportW, allChannels].
                        % Index only the selected channels and squeeze to a
                        % column vector so the downstream concatenation works.
                        colorValues = squeeze(obj.mibModel.Iraw(yImage, xImage, cImage));
                    end
                end
            elseif orientation == 1 && dataset.datasetType(1) ~= 'V'  % ZX orientation
                colorValues = squeeze(dataset.image.data{1}(sliceNo, yImage, xImage, cImage, tImage));
                if dataset.modelExist
                    modelValues = dataset.labels.data{1}(sliceNo, yImage, xImage, tImage);
                end
            elseif orientation == 2 && dataset.datasetType(1) ~= 'V'  % ZY orientation
                colorValues = squeeze(dataset.image.data{1}(yImage, sliceNo, xImage, cImage, tImage));
                if dataset.modelExist
                    modelValues = dataset.labels.data{1}(yImage, sliceNo, xImage, tImage);
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

            % Update brush cursor position
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
