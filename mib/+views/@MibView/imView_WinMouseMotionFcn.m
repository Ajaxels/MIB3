function imView_WinMouseMotionFcn(obj)
% function imView_WinMouseMotionFcn(obj)
% Returns coordinates and image intensities under the mouse cursor
%
% This function is called on every mouse movement over the figure window.
% It updates the cursor position display, tracks mouse movement distance,
% and manages the brush cursor visibility based on axes boundaries.
%
% Parameters:
% obj: handle to the MibView class instance
%
% Return values:
% none

% Prevent re-entrance to improve performance
% When mouse moves rapidly, this ensures previous callback completes before starting new one
persistent inCallback lastCallTime wasInside
currentTime = tic;

% Auto-reset if stuck for more than 100ms (handles debugging breakpoints and crashes)
if ~isempty(lastCallTime) && toc(lastCallTime) > 0.1
    inCallback = false;
end

% Exit immediately if already processing a mouse move
if ~isempty(inCallback) && inCallback; return; end
inCallback = true;
lastCallTime = currentTime;

try
    % get aliases
    selectedSet = obj.mibModel.Sets.selectedSet;
    imView = obj.handles.imView{selectedSet};
    imViewAxes = imView.handles.imViewAxes;

    % get mouse coordinates
    position = imViewAxes.CurrentPoint;
    xMouse = round(position(1, 1));
    yMouse = round(position(1, 2));

    % get axes limits
    axXLim = imViewAxes.XLim;
    axYLim = imViewAxes.YLim;

    % Check if mouse pointer is within the current axes boundaries
    isInsideAxes = xMouse > axXLim(1) && xMouse < axXLim(2) && yMouse > axYLim(1) && yMouse < axYLim(2);

    if isInsideAxes  % mouse pointer within the current axes
        % alias to the parent figure
        % the figure parent identified inside ImageView.mlapp as
        % parentFigure = ancestor(obj.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes, 'figure');
        imView.imViewFigure.Pointer = 'crosshair';

        sessionSettings = obj.mibModel.sessionSettings;
        % calculate mouse travel distance
        if sessionSettings.prevCursorCoordinate(1) > 0
            mouseDist = sqrt((sessionSettings.prevCursorCoordinate(1)-xMouse)^2 + (sessionSettings.prevCursorCoordinate(2)-yMouse)^2) * sessionSettings.metersPerPixel;
            obj.mibModel.preferences.Users.Tiers.mouseTravelDistance = obj.mibModel.preferences.Users.Tiers.mouseTravelDistance + mouseDist;
            obj.mibModel.preferences.Users.Tiers.collectedPoints = obj.mibModel.preferences.Users.Tiers.collectedPoints + mouseDist;
        end
        obj.mibModel.sessionSettings.prevCursorCoordinate = [xMouse, yMouse];     % store the previous coordinate of the cursor
        %fprintf('Mouse travel distance: %f meters\n', obj.mibModel.preferences.Users.Tiers.mouseTravelDistance);
        %fprintf('Collected points: %f\n', obj.mibModel.preferences.Users.Tiers.collectedPoints);
       
        % flag that the image inside the image frames
        isInsideImage =  xMouse > 0 && yMouse > 0 && xMouse<=size(obj.mibModel.Ishown,2) && yMouse<=size(obj.mibModel.Ishown,1);
        if isInsideImage
            dataset = obj.mibModel.I{obj.mibModel.id};
            orientation = dataset.orientation; % current orientation
            cImage = dataset.slices{4}; % selected color channels
            tImage = dataset.slices{5}(1); % current time point

            if dataset.datasetType(1) == 'V' % Virtual mode
                if dataset.magFactor < 1
                    [xImg, yImg] = ceil(obj.mibModel.convertMouseToDataCoordinates(xMouse, yMouse, 'blockmode'));
                else
                    xImg = ceil(xMouse);
                    yImg = ceil(yMouse);
                end
            end

            % recalculate mouse coordinates to coordinates of the dataset
            [xImage, yImage, sliceNo] = obj.mibModel.convertMouseToDataCoordinates(xMouse, yMouse, 'shown');
            xImage = ceil(xImage);
            yImage = ceil(yImage);

            % get image dimensions in the shown orientation
            getDimsOptions.blockModeSwitch = false;
            [imgHeight, imgWidth, imgDepth] = dataset.getDatasetDimensions('image', [], getDimsOptions);
            yImage = min([yImage, imgHeight]);
            xImage = min([xImage, imgWidth]);
            sliceNo = min([sliceNo, imgDepth]);
            
            colorValues = [];
            modelValues = NaN;
            if orientation == 3   % yx
                if dataset.datasetType(1) ~= 'V' % YX orientation; not virtual mode
                    colorValues = squeeze(dataset.image.data{1}(yImage, xImage, sliceNo, cImage, tImage));
                    if dataset.modelExist
                        modelValues = dataset.labels.data{1}(yImage, xImage, sliceNo, tImage);
                    end
                else    % virtual stacking mode, hdd-resident
                    colorValues = 0;
                    if ~isempty(obj.mibModel.Iraw)
                        colorValues = obj.mibModel.Iraw(yImg, xImg, :);
                    end
                end
            elseif orientation == 1 && dataset.datasetType(1) ~= 'V' % ZX orientation, not virtual mode 
                colorValues = squeeze(dataset.image.data{1}(sliceNo, yImage, xImage, cImage, tImage));
                if dataset.modelExist
                    modelValues = dataset.labels.data{1}(sliceNo, yImage, xImage, tImage);
                end
            elseif orientation == 2 && dataset.datasetType(1) ~= 'V' % ZY orientation, not virtual mode 
                colorValues = squeeze(dataset.image.data{1}(yImage, sliceNo, xImage, cImage, tImage));
                if dataset.modelExist
                    modelValues = dataset.labels.data{1}(yImage, sliceNo, xImage, tImage);
                end
            end

            if numel(colorValues) == 0
                obj.controller.cStatus.handles.pixelLabel.Text = sprintf('%d:%d', xImage, yImage);
            else
                % Pad colorValues with NaN to always have 4 values
                colorPadded = [double(colorValues); NaN(max(0, 4-numel(colorValues)), 1)];

                obj.controller.cStatus.handles.pixelLabel.Text = sprintf('%d:%d (%d:%d:%d:%d) / %d', xImage, yImage, ...
                    colorPadded(1), colorPadded(2), colorPadded(3), colorPadded(4), modelValues);
            end

        else
            obj.controller.cStatus.handles.pixelLabel.Text = sprintf('Pixel: %d:%d (RRRRR:GGGGG:BBBBB)', xMouse, yMouse);
        end

        % recalculate brush cursor positions
        % possible code to show brush cursor, requires obj.handles.cursor handle for the plot type object
        if obj.brushCursorShow; obj.updateBrushCursor([xMouse, yMouse], [], true); end

    else
        imView.imViewFigure.Pointer = 'arrow';
        obj.controller.cStatus.handles.pixelLabel.Text = 'Pixel: XXXXX:XXXXX (RRRRR:GGGGG:BBBBB)';
    end

    % Optimize: Only update cursor visibility when crossing axes boundary
    % This avoids unnecessary function calls when mouse stays outside axes
    if isempty(wasInside) || wasInside ~= isInsideAxes
        if ~isInsideAxes && obj.brushCursorShow
            % Hide brush cursor when leaving axes
            obj.updateBrushCursor([], [], false);
        end
        % Store current state for next comparison
        wasInside = isInsideAxes;
    end

catch err
    err
end

inCallback = false;
end