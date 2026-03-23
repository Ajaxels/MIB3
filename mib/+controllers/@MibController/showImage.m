function showImage(obj, resizeToMagnification, setOfDatasetsIndex, sImgIn)
% function showImage(obj, resizeToMagnification, setOfDatasetsIndex, sImgIn)
% showImage - Display image in the main image axes
%
% Main visualization function that renders the RGB image with all layers
% (image, model, mask, selection, annotations) to the image axes panel
%
% Syntax:
%   obj.showImage()
%   obj.showImage(resizeToMagnification)
%   obj.showImage(resizeToMagnification, sImgIn)
%
% Parameters:
%   resizeToMagnification: [@em optional, logical] display mode:
%           true - resize to current magnification [@b default]          
%           false - return in original 100% resolution
%   setOfDatasetsIndex: [@em optional, numerical] id of the set use for show image, when empty use the current one
%   sImgIn: [@em optional] custom 2D RGB image to display (height, width, colors)
%           When provided with resizeToMagnification=0, shows in same scale/position as current dataset
%           When provided with resizeToMagnification=1, shows in full resolution
%
%| 
% @b Examples:
% @code 
% // standard call to redraw image in the image view panel
% notify(obj.mibModel, 'ShowImage');
% @endcode
%
% @code 
% // custom call to resizeToMagnification and redraw image in the image view panel
% Options.resizeToMagnification = true;
% eventdata = core.ToggleEventData(Options);
% notify(obj, 'ShowImage', eventdata);
% @endcode
%
% @code 
% // direct call from controllers.MibController class
% obj.showImage();
% @endcode
%
%

%% Parse input parameters
if nargin < 4; sImgIn = []; end
if nargin < 3; setOfDatasetsIndex = []; end
if nargin < 2; resizeToMagnification = true; end

% get the currently selected set
if isempty(setOfDatasetsIndex)
    selectedSet = obj.mibModel.Sets.selectedSet;
else
    selectedSet = setOfDatasetsIndex;
end
datasetId = obj.mibModel.Sets.selectedDataset(selectedSet)+(obj.mibModel.Sets.datasetsInSet*(selectedSet-1));
dataset = obj.mibModel.I{datasetId};
imViewAxes = obj.cImageDoc{selectedSet}.handles.imViewAxes;

%% Generate RGB image to display
rgbOptions.blockModeSwitch = true;
rgbOptions.roiId = -1;
rgbOptions.resizeToMagnification = resizeToMagnification;

if isempty(sImgIn)
    % Generate RGB from dataset
    [obj.mibModel.Ishown, obj.mibModel.Iraw] = obj.mibModel.getRGBimage(rgbOptions, datasetId);
else
    % Use provided custom image
    obj.mibModel.Ishown = obj.mibModel.getRGBimage(rgbOptions, datasetId, sImgIn);
end

%% Calculate aspect ratio coefficient based on orientation
if dataset.orientation == 3 % xy
    coef_z = dataset.image.pixSize.x / (dataset.image.pixSize.y);
elseif dataset.orientation == 1 % zx
    coef_z = dataset.image.pixSize.z / dataset.image.pixSize.x;
elseif dataset.orientation == 2 % zy
    coef_z = dataset.image.pixSize.z / dataset.image.pixSize.y;
end

%% Update image in axes
if isempty(obj.cImageDoc{selectedSet}.imageHandle.CData)
    % Create new image object with stretched XData
    imgHeight = size(obj.mibModel.Ishown, 1);
    imgWidth = size(obj.mibModel.Ishown, 2);

    obj.cImageDoc{selectedSet}.imageHandle = ...
        image(obj.mibModel.Ishown, ...
              'XData', [1 imgWidth * coef_z], ...
              'YData', [1 imgHeight], ...
              'parent', imViewAxes);
    
    % Configure image object
    obj.cImageDoc{selectedSet}.imageHandle.HitTest = 'off';
else
    % Update existing image
    imgHeight = size(obj.mibModel.Ishown, 1);
    imgWidth = size(obj.mibModel.Ishown, 2);
    
    obj.cImageDoc{selectedSet}.imageHandle.CData = [];
    obj.cImageDoc{selectedSet}.imageHandle.CData = obj.mibModel.Ishown;
    obj.cImageDoc{selectedSet}.imageHandle.XData = [1 imgWidth * coef_z];
    obj.cImageDoc{selectedSet}.imageHandle.YData = [1 imgHeight];
    
    % Remove old measurements and ROI overlays
    lineObj = findobj(imViewAxes, 'tag', 'measurements', '-or', 'tag', 'roi');
    if ~isempty(lineObj); delete(lineObj); end
end


%% Configure axes properties
% moved to controllers.MibActiveDataset.update_fromModel
% imViewAxes.Box = 'on';
% imViewAxes.XTick = [];
% imViewAxes.YTick = [];
% imViewAxes.Interruptible = 'off';
% imViewAxes.BusyAction = 'queue';
% imViewAxes.HandleVisibility = 'callback';

%% Set axes limits and zoom
if ~isempty(sImgIn) && resizeToMagnification == 1
    % Custom image provided - fit to screen
    imViewAxes.DataAspectRatioMode = 'manual';
    imViewAxes.PlotBoxAspectRatioMode = 'manual';
    imViewAxes.DataAspectRatio = [1 coef_z 1];

    imPanPos = obj.cImageDoc{selectedSet}.handles.mainGridLayout.OuterPosition;
    imPanPos(3) = imPanPos(3) - obj.cImageDoc{selectedSet}.handles.mainGridLayout.RowHeight{2};
    imPanPos(4) = imPanPos(4) - obj.cImageDoc{selectedSet}.handles.mainGridLayout.ColumnWidth{1};
    imViewAxes.PlotBoxAspectRatio = [imPanPos(3)/imPanPos(4) 1 1];
    imViewAxes.YLim = [1 size(obj.mibModel.Ishown, 1)];
    imViewAxes.XLim = [1 size(obj.mibModel.Ishown, 2)];
else
    % Standard dataset display
    magFactor = dataset.magFactor;
    [axesX, axesY] = dataset.getAxesLimits();

    % Keep axes in stretch-to-fill mode (auto aspect ratio)
    imViewAxes.DataAspectRatioMode = 'auto';
    imViewAxes.PlotBoxAspectRatioMode = 'auto';

    if ~resizeToMagnification 
        % Full-resolution mode: axesX/axesY are in data-pixel coords.
        % XLim must be in physical (XData) coords: multiply X by coef_z.
        % Y has no aspect-ratio correction.
        imViewAxes.YLim = [axesY(1)/magFactor axesY(2)/magFactor];
        imViewAxes.XLim = [axesX(1)*coef_z/magFactor axesX(2)*coef_z/magFactor];
    else
        % Standard mode: XData = [1, imgWidth*coef_z], so XLim must be in
        % the same physical space: axesX (data pixels) * coef_z / magFactor.
        % Y is unscaled (YData = [1, imgHeight], coef_z applies to X only).

        % Calculate X limits
        xl(1) = min([axesX(1)*coef_z/magFactor, 0]);
        if axesX(2) > size(obj.mibModel.Ishown, 2) * magFactor
            if axesX(1) < 0
                xl(2) = axesX(2)*coef_z/magFactor;
            else
                xl(2) = (axesX(2) - axesX(1))*coef_z/magFactor;
            end
        else
            xl(2) = size(obj.mibModel.Ishown, 2) * coef_z;
        end

        % Calculate Y limits (no coef_z for Y axis)
        yl(1) = min([axesY(1)/magFactor 0]);
        if axesY(2) > size(obj.mibModel.Ishown, 1) * magFactor
            if axesY(1) < 0
                yl(2) = axesY(2)/magFactor;
            else
                yl(2) = axesY(2)/magFactor - axesY(1)/magFactor;
            end
        else
            yl(2) = size(obj.mibModel.Ishown, 1);
        end

        imViewAxes.YLim = yl;
        imViewAxes.XLim = xl;
    end
    
    % update the zoom value only when image of the currently selected set is updated
    if obj.mibModel.id == datasetId
        obj.view.handles.status.zoom.Value = sprintf('%d %%', round(1/magFactor*100));
    end

    %% Display center spot marker if enabled
    if obj.view.handles.qab.target.Value
        axesHandle = imViewAxes;
        centerX = mean(axesHandle.XLim);
        centerY = mean(axesHandle.YLim);
        
        if isempty(obj.cImageDoc{selectedSet}.centralMarker) || ...
                ~isvalid(obj.cImageDoc{selectedSet}.centralMarker)
            % create marker
            obj.cQuickAccessBar.createCentralMarker(centerX, centerY);
        else
            % Update position
            obj.cImageDoc{selectedSet}.centralMarker.XData = centerX;
            obj.cImageDoc{selectedSet}.centralMarker.YData = centerY;
        end
    else
        % Delete old marker if it exists to prevent stacking
        if isprop(obj.cImageDoc{selectedSet}, 'centralMarker') && ...
                ~isempty(obj.cImageDoc{selectedSet}.centralMarker) && ...
                isvalid(obj.cImageDoc{selectedSet}.centralMarker)
            delete(obj.cImageDoc{selectedSet}.centralMarker);
        end
    end
    
    %% Add ROIs overlay
    if obj.cQuickAccessBar.handles.roiMode.Value
        ds = dataset;
        if ds.hROI.getNumberOfROI(ds.orientation) > 0
            showLabel = obj.cRoi.handles.roiShowLabel.Value;
            convertFcn = @(x,y) obj.mibModel.convertDataToMouseCoordinates(x, y, 'shown');
            ds.hROI.addROIsToPlot(imViewAxes, ...
                'shown', ds.orientation, convertFcn, ds.selectedROI, showLabel);
        end
    end

    % %% Add measurements/annotations overlay
    % if obj.mibModel.mibShowAnnotationsCheck
    %     obj.mibView.handles.mibShowAnnotationsCheck.Value = 1;
    %     dataset.hMeasure.addMeasurementsToPlot(...
    %         obj.mibModel, 'shown', imViewAxes);
    % end

    %% Update display
    %if ~verLessThan('matlab', '9.7')
    %    drawnow nocallbacks limitrate;
    %end
end

%% Update cursor size
obj.cImageDoc{selectedSet}.updateBrushCursor();

%% Reposition drawing ROI if interactive ROI addition is in progress
if obj.cRoi.drawingROI.active
    obj.cRoi.repositionDrawingROI();
end

end
