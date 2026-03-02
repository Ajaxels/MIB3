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
        obj.gui.imViewFigure.Pointer = 'crosshair';
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

        % Check if inside image boundaries
        obj.isInsideImage = xMouse > 0 && yMouse > 0 && ...
            xMouse <= size(obj.mibModel.Ishown, 2) && ...
            yMouse <= size(obj.mibModel.Ishown, 1);

        if obj.isInsideImage
            obj.syncActiveSet();  % lightweight: keep mibModel.id/selectedSet in sync for split-panel mode
            dataset = obj.mibModel.I{obj.mibModel.id};
            orientation = dataset.orientation;
            cImage = dataset.slices{4};
            tImage = dataset.slices{5}(1);

            % Handle Virtual mode
            if dataset.datasetType(1) == 'V'
                if dataset.magFactor < 1
                    [xImg, yImg] = ceil(obj.mibModel.convertMouseToDataCoordinates(xMouse, yMouse, 'blockmode'));
                else
                    xImg = ceil(xMouse);
                    yImg = ceil(yMouse);
                end
            end

            % Convert mouse coordinates to dataset coordinates
            [xImage, yImage, sliceNo] = obj.mibModel.convertMouseToDataCoordinates(xMouse, yMouse, 'shown');
            xImage = ceil(xImage);
            yImage = ceil(yImage);

            % Get image dimensions in the current orientation
            getDimsOptions.blockModeSwitch = false;
            [imgHeight, imgWidth, imgDepth] = dataset.getDatasetDimensions('image', [], getDimsOptions);

            yImage = min([yImage, imgHeight]);
            xImage = min([xImage, imgWidth]);
            sliceNo = min([sliceNo, imgDepth]);

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
                        colorValues = obj.mibModel.Iraw(yImg, xImg, :);
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
            if numel(colorValues) == 0
                obj.mibController.cStatus.handles.pixelLabel.Text = sprintf('%d:%d', xImage, yImage);
            else
                % Pad colorValues with NaN to always show 4 channels
                colorPadded = [double(colorValues); NaN(max(0, 4-numel(colorValues)), 1)];
                obj.mibController.cStatus.handles.pixelLabel.Text = sprintf('%d:%d (%d:%d:%d:%d) / %d', ...
                    xImage, yImage, colorPadded(1), colorPadded(2), colorPadded(3), colorPadded(4), modelValues);
            end

            % Update brush cursor position
            if obj.view.brushCursorShow
                obj.updateBrushCursor([xMouse, yMouse]);
            end
        else
            obj.mibController.cStatus.handles.pixelLabel.Text = sprintf('Pixel: %d:%d (RRRRR:GGGGG:BBBBB)', xMouse, yMouse);
        end
    else
        obj.gui.imViewFigure.Pointer = 'arrow';
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
