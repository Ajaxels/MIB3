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
    [Ishown, Iraw] = obj.mibModel.getRGBimage(rgbOptions);
    %[obj.mibView.Ishown, obj.mibView.Iraw] = obj.mibModel.getRGBimage(rgbOptions);
else
    % Use provided custom image
    %obj.mibView.Ishown = obj.mibModel.getRGBimage(rgbOptions, sImgIn);
end

image(Ishown, 'parent', obj.view.handles.imView{obj.mibModel.Sets.selectedSet}.handles.imViewAxes);

return;


%% Calculate aspect ratio coefficient based on orientation
if obj.mibModel.mibDataset.orientation == 4 % xy
    coef_z = obj.mibModel.mibDataset.pixSize.x / obj.mibModel.mibDataset.pixSize.y;
elseif obj.mibModel.mibDataset.orientation == 1 % zx
    coef_z = obj.mibModel.mibDataset.pixSize.z / obj.mibModel.mibDataset.pixSize.x;
elseif obj.mibModel.mibDataset.orientation == 2 % zy
    coef_z = obj.mibModel.mibDataset.pixSize.z / obj.mibModel.mibDataset.pixSize.y;
end

%% Update image in axes
if isempty(obj.mibView.imh.CData)
    % Create new image object
    obj.mibView.imh = image(obj.mibView.Ishown, 'parent', obj.mibView.handles.mibImageAxes);
else
    % Update existing image
    obj.mibView.imh.CData = [];
    obj.mibView.imh.CData = obj.mibView.Ishown;

    % Remove old measurements and ROI overlays
    lineObj = findobj(obj.mibView.handles.mibImageAxes, 'tag', 'measurements', '-or', 'tag', 'roi');
    if ~isempty(lineObj)
        delete(lineObj);
    end
end

% Configure image object
obj.mibView.imh.HitTest = 'off';

%% Configure axes properties
obj.mibView.handles.mibImageAxes.Box = 'on';
obj.mibView.handles.mibImageAxes.XTick = [];
obj.mibView.handles.mibImageAxes.YTick = [];
obj.mibView.handles.mibImageAxes.Interruptible = 'off';
obj.mibView.handles.mibImageAxes.BusyAction = 'queue';
obj.mibView.handles.mibImageAxes.HandleVisibility = 'callback';

%% Set axes limits and zoom
if exist('sImgIn', 'var') && resizeToMagnification == 1
    % Custom image provided - fit to screen
    obj.mibView.handles.mibImageAxes.DataAspectRatioMode = 'manual';
    obj.mibView.handles.mibImageAxes.PlotBoxAspectRatioMode = 'manual';
    obj.mibView.handles.mibImageAxes.DataAspectRatio = [1 coef_z 1];

    imPanPos = obj.mibView.handles.mibViewPanel.Position;
    obj.mibView.handles.mibImageAxes.PlotBoxAspectRatio = [imPanPos(3)/imPanPos(4) 1 1];
    obj.mibView.handles.mibImageAxes.YLim = [1 size(obj.mibView.Ishown, 1)];
    obj.mibView.handles.mibImageAxes.XLim = [1 size(obj.mibView.Ishown, 2)];
else
    % Standard dataset display
    magFactor = obj.mibModel.getMagFactor();
    [axesX, axesY] = obj.mibModel.getAxesLimits();

    if resizeToMagnification == 1
        % Resize to fit screen
        obj.mibView.handles.mibImageAxes.DataAspectRatioMode = 'manual';
        obj.mibView.handles.mibImageAxes.PlotBoxAspectRatioMode = 'manual';
        obj.mibView.handles.mibImageAxes.DataAspectRatio = [1 coef_z 1];

        imPanPos = obj.mibView.handles.mibViewPanel.Position;
        obj.mibView.handles.mibImageAxes.PlotBoxAspectRatio = [imPanPos(3)/imPanPos(4) 1 1];
        obj.mibView.handles.mibZoomEdit.String = sprintf('%d %%', round(1/magFactor*100));
        obj.mibView.handles.mibImageAxes.YLim = [axesY(1)/magFactor axesY(2)/magFactor];
        obj.mibView.handles.mibImageAxes.XLim = [axesX(1)/magFactor axesX(2)/magFactor];
    else
        % Keep current zoom and pan settings
        obj.mibView.handles.mibImageAxes.Units = 'pixels';
        obj.mibView.handles.mibZoomEdit.String = sprintf('%d %%', round(1/magFactor*100));

        % Calculate X limits
        xl(1) = min([axesX(1)/magFactor 0]);
        if axesX(2) > size(obj.mibView.Ishown, 2) * magFactor
            if axesX(1) < 0
                xl(2) = axesX(2)/magFactor;
            else
                xl(2) = axesX(2)/magFactor - axesX(1)/magFactor;
            end
        else
            xl(2) = size(obj.mibView.Ishown, 2);
        end

        % Calculate Y limits
        yl(1) = min([axesY(1)/magFactor 0]);
        if axesY(2) > size(obj.mibView.Ishown, 1) * magFactor
            if axesY(1) < 0
                yl(2) = axesY(2)/magFactor;
            else
                yl(2) = axesY(2)/magFactor - axesY(1)/magFactor;
            end
        else
            yl(2) = size(obj.mibView.Ishown, 1);
        end

        obj.mibView.handles.mibImageAxes.YLim = yl;
        obj.mibView.handles.mibImageAxes.XLim = [xl(1) xl(2)];
    end

    %% Display center spot marker if enabled
    if obj.mibView.centerSpotHandle.enable
        if isempty(obj.mibView.centerSpotHandle.handle) || ...
           isvalid(obj.mibView.centerSpotHandle.handle) == 0
            % Create center spot marker
            obj.mibView.centerSpotHandle.handle = drawpoint(...
                'Position', [mean(obj.mibView.handles.mibImageAxes.XLim) ...
                            mean(obj.mibView.handles.mibImageAxes.YLim)], ...
                'Deletable', false, ...
                'parent', obj.mibView.handles.mibImageAxes, ...
                'Color', 'y');
        end
        % Update position
        obj.mibView.centerSpotHandle.handle.Position = ...
            [mean(obj.mibView.handles.mibImageAxes.XLim) ...
             mean(obj.mibView.handles.mibImageAxes.YLim)];
    end

    %% Add ROIs overlay
    if obj.mibView.handles.mibRoiShowCheck.Value
        obj.mibModel.mibDataset.hROI.addROIsToPlot(obj, 'shown');
    end

    %% Add measurements/annotations overlay
    if obj.mibModel.mibShowAnnotationsCheck
        obj.mibView.handles.mibShowAnnotationsCheck.Value = 1;
        obj.mibModel.mibDataset.hMeasure.addMeasurementsToPlot(...
            obj.mibModel, 'shown', obj.mibView.handles.mibImageAxes);
    end

    %% Update display
    if ~verLessThan('matlab', '9.7')
        drawnow nocallbacks limitrate;
    end
end

%% Update cursor size
obj.mibView.updateCursor();

end
