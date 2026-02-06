function showImage(obj, resizeToMagnification, sImgIn)
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

%I = cell2mat(obj.mibModel.I{obj.mibModel.id}.getData2D());
%image(I, 'parent', obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes);

%% Parse input parameters
if nargin < 3; sImgIn = []; end
if nargin < 2; resizeToMagnification = true; end

%% Generate RGB image to display
rgbOptions.blockModeSwitch = true;
rgbOptions.roiId = -1;
rgbOptions.resizeToMagnification = resizeToMagnification;

if isempty(sImgIn)
    % Generate RGB from dataset
    [obj.mibModel.Ishown, obj.mibModel.Iraw] = obj.mibModel.getRGBimage(rgbOptions);
else
    % Use provided custom image
    obj.mibModel.Ishown = obj.mibModel.getRGBimage(rgbOptions, sImgIn);
end

%% Calculate aspect ratio coefficient based on orientation
if obj.mibModel.I{obj.mibModel.id}.orientation == 3 % xy
    coef_z = obj.mibModel.I{obj.mibModel.id}.pixSize.x / (obj.mibModel.I{obj.mibModel.id}.pixSize.y);
elseif obj.mibModel.I{obj.mibModel.id}.orientation == 1 % zx
    coef_z = obj.mibModel.I{obj.mibModel.id}.pixSize.z / obj.mibModel.I{obj.mibModel.id}.pixSize.x;
elseif obj.mibModel.I{obj.mibModel.id}.orientation == 2 % zy
    coef_z = obj.mibModel.I{obj.mibModel.id}.pixSize.z / obj.mibModel.I{obj.mibModel.id}.pixSize.y;
end

%% Update image in axes
if isempty(obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.imageHandle.CData)
    % Create new image object with stretched XData
    imgHeight = size(obj.mibModel.Ishown, 1);
    imgWidth = size(obj.mibModel.Ishown, 2);

    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.imageHandle = ...
        image(obj.mibModel.Ishown, ...
              'XData', [1 imgWidth * coef_z], ...
              'YData', [1 imgHeight], ...
              'parent', obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes);
    
    % Configure image object
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.imageHandle.HitTest = 'off';
else
    % Update existing image
    imgHeight = size(obj.mibModel.Ishown, 1);
    imgWidth = size(obj.mibModel.Ishown, 2);
    
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.imageHandle.CData = [];
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.imageHandle.CData = obj.mibModel.Ishown;
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.imageHandle.XData = [1 imgWidth * coef_z];
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.imageHandle.YData = [1 imgHeight];
    
    % Remove old measurements and ROI overlays
    lineObj = findobj(obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes, 'tag', 'measurements', '-or', 'tag', 'roi');
    if ~isempty(lineObj); delete(lineObj); end
end


%% Configure axes properties
% moved to controllers.MibActiveDataset.update_fromModel
% obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.Box = 'on';
% obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.XTick = [];
% obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.YTick = [];
% obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.Interruptible = 'off';
% obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.BusyAction = 'queue';
% obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.HandleVisibility = 'callback';

%% Set axes limits and zoom
if ~isempty(sImgIn) && resizeToMagnification == 1
    % Custom image provided - fit to screen
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.DataAspectRatioMode = 'manual';
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.PlotBoxAspectRatioMode = 'manual';
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.DataAspectRatio = [1 coef_z 1];

    imPanPos = obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.mainGridLayout.OuterPosition;
    imPanPos(3) = imPanPos(3) - obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.mainGridLayout.RowHeight{2};
    imPanPos(4) = imPanPos(4) - obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.mainGridLayout.ColumnWidth{1};
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.PlotBoxAspectRatio = [imPanPos(3)/imPanPos(4) 1 1];
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.YLim = [1 size(obj.mibModel.Ishown, 1)];
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.XLim = [1 size(obj.mibModel.Ishown, 2)];
else
    % Standard dataset display
    magFactor = obj.mibModel.I{obj.mibModel.id}.magFactor;
    [axesX, axesY] = obj.mibModel.I{obj.mibModel.id}.getAxesLimits();

    % Keep axes in stretch-to-fill mode (auto aspect ratio)
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.DataAspectRatioMode = 'auto';
    obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.PlotBoxAspectRatioMode = 'auto';

    if resizeToMagnification == 1
        % Resize to fit screen - limits already scaled by coef_z in listenerUpdateDatasetAxes
        obj.view.handles.status.zoom.Value = sprintf('%d %%', round(1/magFactor*100));
        obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.YLim = [axesY(1)/magFactor axesY(2)/magFactor];
        obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.XLim = [axesX(1)/magFactor axesX(2)/magFactor];
    else
        % Keep current zoom and pan settings - limits already scaled
        obj.view.handles.status.zoom.Value = sprintf('%d %%', round(1/magFactor*100));

        % Calculate X limits
        xl(1) = min([axesX(1)/magFactor 0]);
        if axesX(2) > size(obj.mibModel.Ishown, 2) * magFactor
            if axesX(1) < 0
                xl(2) = axesX(2)/magFactor;
            else
                xl(2) = axesX(2)/magFactor - axesX(1)/magFactor;
            end
        else
            xl(2) = size(obj.mibModel.Ishown, 2) * coef_z;  % CHANGED: multiply by coef_z
        end

        % Calculate Y limits
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

        obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.YLim = yl;
        obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes.XLim = xl;
    end

    %% Display center spot marker if enabled
    if obj.view.handles.qab.target.Value
        axesHandle = obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes;
        centerX = mean(axesHandle.XLim);
        centerY = mean(axesHandle.YLim);
        
        if isempty(obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.centralMarker) || ...
                ~isvalid(obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.centralMarker)
            % create marker
            obj.cQuickAccessBar.createCentralMarker(centerX, centerY);
        else
            % Update position
            obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.centralMarker.XData = centerX;
            obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.centralMarker.YData = centerY;
        end
    else
        % Delete old marker if it exists to prevent stacking
        if isprop(obj.view.handles.imView{obj.mibModel.Sets.selectedSet}, 'centralMarker') && ...
                ~isempty(obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.centralMarker) && ...
                isvalid(obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.centralMarker)
            delete(obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.centralMarker);
        end
    end
    
    % %% Add ROIs overlay
    % if obj.mibView.handles.mibRoiShowCheck.Value
    %     obj.mibModel.I{obj.mibModel.id}.hROI.addROIsToPlot(obj, 'shown');
    % end

    % %% Add measurements/annotations overlay
    % if obj.mibModel.mibShowAnnotationsCheck
    %     obj.mibView.handles.mibShowAnnotationsCheck.Value = 1;
    %     obj.mibModel.I{obj.mibModel.id}.hMeasure.addMeasurementsToPlot(...
    %         obj.mibModel, 'shown', obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes);
    % end

    %% Update display
    %if ~verLessThan('matlab', '9.7')
    %    drawnow nocallbacks limitrate;
    %end
end

%% Update cursor size
obj.view.updateBrushCursor();

end
