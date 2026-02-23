function gui_ScrollWheelFcn(obj, eventdata)
% function gui_ScrollWheelFcn(obj, eventdata)
% Callback for mouse scroll wheel
%
% Handles different scroll wheel operations:
% - Ctrl+Scroll: Change brush/tool size, display size on cursor
% - Ctrl+Shift+Scroll: Change size in larger steps (5 units)
% - Regular scroll: Zoom in/out or slice navigation (handled elsewhere)
%
% Parameters:
%   eventdata: event data structure with VerticalScrollCount/Amount
%
% Return values:
%   none
%
% Example usage:
%   % This callback is automatically triggered by scroll events
%   % User actions:
%   % - Ctrl+Scroll Up: Increase brush size by 1
%   % - Ctrl+Shift+Scroll Down: Decrease brush size by 5

imViewFigure = obj.gui.imViewFigure;
modifier = imViewFigure.CurrentModifier;

% Get scroll parameters
if isprop(eventdata, 'Parameter')
    % Call from key shortcuts using ToggleEventData
    verticalScrollCount = eventdata.Parameter.VerticalScrollCount;
    verticalScrollAmount = eventdata.Parameter.VerticalScrollAmount;
    if strcmp(modifier, 'shift')
        modifier = {'shiftcontrol'};
    else
        modifier = {'control'};
    end
else
    % Standard mouse scroll wheel call
    verticalScrollCount = eventdata.VerticalScrollCount;
    verticalScrollAmount = eventdata.VerticalScrollAmount;
end

% Ctrl+Scroll: change brush/tool size
if ismember('control', modifier)
    step = 1;
    if ismember('shift', modifier)
        step = 5;
    end

    % Get appropriate widget based on current segmentation tool
    switch obj.view.handles.panels.segmentation.handles.segmTool.Value
        case '3D ball'
            h1 = obj.view.handles.panels.segmentation.handles.brushRadius;
        case {'Brush'}
            if strcmp(cell2mat(modifier), 'controlalt') || strcmp(cell2mat(modifier), 'shiftcontrolalt')
                h1 = obj.view.handles.panels.segmentation.handles.clustersPar1;
            else
                h1 = obj.view.handles.panels.segmentation.handles.brushRadius;
            end
        case 'Membrane ClickTracker'
            h1 = obj.view.handles.panels.segmentation.handles.membraneWidth;
        case 'Spot'
            h1 = obj.view.handles.panels.segmentation.handles.brushRadius;
        case 'MagicWand/RegionGrowing'
            h1 = obj.view.handles.panels.segmentation.handles.magicRange1;
        otherwise
            return;
    end

    % Get current value
    val = h1.Value;

    % Handle eraser modification
    if obj.view.ctrlPressed > 0 && h1 == obj.view.handles.panels.segmentation.handles.brushRadius
        val = val - obj.view.ctrlPressed;
        obj.view.ctrlPressed = -1;
        h1.Value = val;
        obj.updateBrushCursor();
    end

    % Update value based on scroll direction
    if verticalScrollCount < 0
        val = val + step;
    else
        val = val - step;
        if val < 1; val = 1; end
    end

    % Prepare text for custom cursor (max 99)
    if val < 100
        text_str = num2str(val);
    else
        text_str = '99';
    end

    % Create custom cursor showing the size value
    colorText = 1;
    valuePointer = zeros([16 16]);
    for i = 1:numel(text_str)
        col_start = i*8 - 7;
        col_end = i*8;
        valuePointer(:, col_start:col_end) = obj.view.brushSizeNumbers{text_str(i)} * colorText;
    end
    valuePointer(valuePointer==0) = NaN;
    valuePointer(1:5,3) = colorText;
    valuePointer(3,1:5) = colorText;

    obj.gui.imViewFigure.Pointer = 'custom';
    obj.gui.imViewFigure.PointerShapeCData = valuePointer;

    % Update widget value
    h1.Value = val;

    % Update brush cursor for new size
    obj.updateBrushCursorOffset();
    obj.updateBrushCursor();
    return;
end

% % check whether the mouse cursor within the axes.
% position = obj.mibView.handles.mibImageAxes.CurrentPoint;
% axXLim = obj.mibView.handles.mibImageAxes.XLim;
% axYLim = obj.mibView.handles.mibImageAxes.YLim;
% x = round(position(1,1));
% y = round(position(1,2));
% if x<axXLim(1) || x>axXLim(2) || y<axYLim(1) || y>axYLim(2)
%     return;
% end

if obj.mibModel.preferences.System.MouseWheel(1) == 's'  & ...  % scroll
        ismember('alt', modifier) & obj.mibModel.preferences.System.AltWithScrollWheel               %#ok<OR2,AND2> % change time point with Alt

    % if strcmp(cell2mat(modifier), 'shiftalt')
    %     shift = obj.mibView.handles.mibChangeTimeSlider.UserData.sliderShiftStep;
    % else
    %     shift = 1;
    % end
    % new_index = obj.mibModel.I{obj.mibModel.id}.slices{5}(1) - verticalScrollCount*shift;
    % if new_index < 1;  new_index = 1; end
    % if new_index > obj.mibModel.I{obj.mibModel.id}.time; new_index = obj.mibModel.I{obj.mibModel.id}.time; end
    % obj.mibView.handles.mibChangeTimeSlider.Value = new_index;     % update slider value
    % obj.mibChangeTimeSlider_Callback();
elseif obj.mibModel.preferences.System.MouseWheel(1) == 'z'                 % 'zoom', zoom in/zoom out with the mouse wheel
    % % Power law allows for the inverse to work:
    % %      C^(x) * C^(-x) = 1
    % % Choose C to get "appropriate" zoom factor
    % C = 1.10;
    % %             ch = get(handles.im_browser, 'CurrentCharacter');
    % %             if ch == '`'    % change size of the brush
    % %                 brush = str2double(get(handles.segmSpotSizeEdit,'String'));
    % %                 brush = max([1 brush+verticalScrollCount]);
    % %                 set(handles.segmSpotSizeEdit,'String',num2str(brush));
    % %                 set(handles.im_browser, 'CurrentCharacter', '1');
    % %                 return;
    % %             end
    % 
    % curPt  = mean(obj.mibView.handles.mibImageAxes.CurrentPoint);
    % curPt = curPt(1:2);  % mouse coordinates
    % 
    % % modify curPt with shifts that come from handles.Img{handles.Id}.I.axesX/handles.Img{handles.Id}.I.axesY and magnification factor
    % magFactor = obj.mibModel.getMagFactor();
    % [axesX, axesY] = obj.mibModel.getAxesLimits();
    % curPt(1) = curPt(1)*magFactor + max([0 axesX(1)]);
    % curPt(2) = curPt(2)*magFactor + max([0 axesY(1)]);
    % xl = axesX;
    % yl = axesY;
    % % zoom will work only when the mouse is above the image
    % if curPt(1)<xl(1) || curPt(1)>xl(2); return; end
    % if curPt(2)<yl(1) || curPt(2)>yl(2); return; end
    % 
    % midX = mean(xl);
    % rngXhalf = diff(xl) / 2; % half-width of the shown image
    % midY = mean(yl);
    % rngYhalf = diff(yl) / 2; % half-height of the shown image
    % 
    % curPt2 = (curPt-[midX, midY]) ./ [rngXhalf, rngYhalf];  % image shift in %%
    % curPt  = [curPt; curPt];
    % curPt2 = [-(1+curPt2).*[rngXhalf, rngYhalf];...
    %     (1-curPt2).*[rngXhalf, rngYhalf]];           % new image half-sizes without zooming
    % 
    % r = C^(verticalScrollCount*verticalScrollAmount);
    % newLimSpan = r * curPt2;
    % 
    % % Determine new limits based on r
    % lims = curPt + newLimSpan;
    % 
    % % check out of image bounds conditions
    % if lims(1,1) < 0 && lims(2,1) < 0; return; end
    % if lims(1,2) < 0 && lims(2,2) < 0; return; end
    % if lims(1,1) > obj.mibModel.I{obj.mibModel.id}.width && lims(2,1) > obj.mibModel.I{obj.mibModel.id}.width; return; end
    % if lims(1,2) > obj.mibModel.I{obj.mibModel.id}.height && lims(2,2) > obj.mibModel.I{obj.mibModel.id}.height; return; end
    % 
    % obj.mibModel.setMagFactor(magFactor*r);    % update magFactor
    % obj.mibModel.setAxesLimits(lims(:,1)', lims(:,2)');    % update axes limits
    % obj.plotImage(0);
    % 
    % % notify listeners that the image axes were changed -> mibSnapshotController
    % motifyEvent.Name = 'updteAxesLimits_changed';
    % eventdata = ToggleEventData(motifyEvent);
    % notify(obj.mibModel, 'modelNotify', eventdata);
else    % slice change with the mouse wheel
    % update the slider step
    if ismember('shift', modifier)
        shift = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.sliderShiftStep;
    else
        shift = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.sliderStep;
    end
    
    %if ~obj.mibModel.preferences.System.AltWithScrollWheel && ismember('alt', modifier)
        %if obj.mibView.altPressed == 0
        %    obj.mibView.altPressed = obj.mibModel.I{obj.mibModel.id}.getCurrentSliceNumber();
        %end
    %end

    datasetId = obj.mibModel.id;
    orientation = obj.mibModel.I{datasetId}.orientation;
    new_index = obj.mibModel.I{datasetId}.slices{orientation}(1) - verticalScrollCount*shift;
    if new_index < 1;  new_index = 1; end
    if new_index > obj.mibModel.I{datasetId}.dim_yxzct(orientation)
        new_index = obj.mibModel.I{datasetId}.dim_yxzct(orientation); 
    end
    
    obj.handles.sliceNumberSlider.Value = new_index;     % update slider value
    obj.sliceNumberSlider_Callback();
end
end
