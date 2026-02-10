function imView_ScrollWheelFcn(obj, eventdata) 
% function imView_ScrollWheelFcn(obj, eventdata) 
% Control callbacks from mouse scroll wheel 
%
% This function takes care of the mouse wheel. Depending on a key modifier and
% @em handles.mouseWheelToolbarSw it can:
% @li Ctrl+mouse wheel, change size of the brush and some other tools. The
% value of the new size value is displayed next to the cursor during the mouse
% wheel rotation.
% @li when @em handles.mouseWheelToolbarSw is not pressed, the mouse wheel
% is used for zoom in/zoom out actions.
% @li when @em handles.mouseWheelToolbarSw is pressed, the mouse wheel is
% used to change slices of the shown 3D dataset.
%
% Parameters:
% eventdata: additional parameters

% Updates
% 
imViewFigure = obj.handles.imView{obj.mibModel.Sets.selectedSet}.imViewFigure;
modifier = imViewFigure.CurrentModifier;    % detect control to change size of the brush tool
if isprop(eventdata, 'Parameter')
    % call of the function using ToggleEventData from key shortcuts
    verticalScrollCount = eventdata.Parameter.VerticalScrollCount;
    verticalScrollAmount = eventdata.Parameter.VerticalScrollAmount;
    if strcmp(modifier, 'shift')
        modifier = {'shiftcontrol'};
    else
        modifier = {'control'};
    end
else
    % standard call using mouse scroll wheel
    verticalScrollCount = eventdata.VerticalScrollCount;
    verticalScrollAmount = eventdata.VerticalScrollAmount;
end


if ismember('control', modifier) % same as "strcmp(modifier, 'control') | strcmp(cell2mat(modifier), 'shiftcontrol') | strcmp(cell2mat(modifier), 'controlalt') | strcmp(cell2mat(modifier), 'shiftcontrolalt')"
    step = 1;   % step of the brush size change
    if ismember('shift', modifier)   % same as "strcmp(cell2mat(modifier), 'shiftcontrol') || strcmp(cell2mat(modifier), 'shiftcontrolalt')"
        step = 5;
    end

    % get handle of widget with size of brush or other tools
    switch obj.handles.panels.segmentation.handles.segmTool.Value
        case '3D ball'
            h1 = obj.handles.panels.segmentation.handles.brushRadius;
        case {'Brush'}
            if strcmp(cell2mat(modifier), 'controlalt') || strcmp(cell2mat(modifier), 'shiftcontrolalt')
                h1 = obj.handles.panels.segmentation.handles.clustersPar1;
            else
                h1 = obj.handles.panels.segmentation.handles.brushRadius;
            end
        case 'Membrane ClickTracker'
            h1 = obj.handles.panels.segmentation.handles.membraneWidth;
        case 'Spot'
            h1 = obj.handles.panels.segmentation.handles.brushRadius;
        case 'MagicWand/RegionGrowing'
            h1 = obj.handles.panels.segmentation.handles.magicRange1;
        otherwise
            return;
    end

    % get current value
    val = h1.Value;
    
    % modification to release increase of the brush radius for the eraser
    if obj.ctrlPressed > 0 && h1 == obj.handles.panels.segmentation.handles.brushRadius
        val = val - obj.ctrlPressed;
        obj.ctrlPressed = -1;
        h1.Value = val;
        obj.updateBrushCursor();
    end
    
    if verticalScrollCount < 0
        val = val + step;
    else
        val = val - step;
        if val < 1; val = 1; end
    end
    
    if val < 100
        text_str = num2str(val);
    else
        text_str = '99';
    end

    % % add cursor text
    % text = obj.handles.status.pixelLabel.Text;
    % colon = strfind(text,':');
    % text = str2double(text(strfind(text,'(')+1:colon(2)-1));
    colorText = 1;
    % if text < obj.mibModel.I{obj.mibModel.id}.meta('MaxInt')/2
    %     colorText = 2;
    % end

    valuePointer = zeros([16 16]);
    for i = 1:numel(text_str)
        col_start = i*8 - 7;
        col_end = i*8;
        valuePointer(:, col_start:col_end) = obj.brushSizeNumbers{text_str(i)} * colorText;
    end
    valuePointer(valuePointer==0) = NaN;
    valuePointer(1:5,3) = colorText;
    valuePointer(3,1:5) = colorText;

    obj.handles.imView{obj.mibModel.Sets.selectedSet}.imViewFigure.Pointer = 'custom';
    obj.handles.imView{obj.mibModel.Sets.selectedSet}.imViewFigure.PointerShapeCData = valuePointer;
    h1.Value = val;
    % calculate new offset for the brush cursor
    obj.updateBrushCursorOffset();
    % update the brush cursor for the new size
    obj.updateBrushCursor();
    return;
end

return;

% check whether the mouse cursor within the axes.
position = obj.mibView.handles.mibImageAxes.CurrentPoint;
axXLim = obj.mibView.handles.mibImageAxes.XLim;
axYLim = obj.mibView.handles.mibImageAxes.YLim;
x = round(position(1,1));
y = round(position(1,2));
if x<axXLim(1) || x>axXLim(2) || y<axYLim(1) || y>axYLim(2)
    return;
end

if strcmp(obj.mibView.handles.mouseWheelToolbarSw.State,'on') & ...
        (strcmp(modifier, 'alt') | strcmp(cell2mat(modifier), 'shiftalt')) & obj.mibModel.preferences.System.AltWithScrollWheel               %#ok<OR2,AND2> % change time point with Alt

    if strcmp(cell2mat(modifier), 'shiftalt')
        shift = obj.mibView.handles.mibChangeTimeSlider.UserData.sliderShiftStep;
    else
        shift = 1;
    end
    new_index = obj.mibModel.I{obj.mibModel.id}.slices{5}(1) - verticalScrollCount*shift;
    if new_index < 1;  new_index = 1; end
    if new_index > obj.mibModel.I{obj.mibModel.id}.time; new_index = obj.mibModel.I{obj.mibModel.id}.time; end
    obj.mibView.handles.mibChangeTimeSlider.Value = new_index;     % update slider value
    obj.mibChangeTimeSlider_Callback();
elseif strcmp(obj.mibView.handles.mouseWheelToolbarSw.State,'off')                % zoom in/zoom out with the mouse wheel
    % Power law allows for the inverse to work:
    %      C^(x) * C^(-x) = 1
    % Choose C to get "appropriate" zoom factor
    C = 1.10;
    %             ch = get(handles.im_browser, 'CurrentCharacter');
    %             if ch == '`'    % change size of the brush
    %                 brush = str2double(get(handles.segmSpotSizeEdit,'String'));
    %                 brush = max([1 brush+verticalScrollCount]);
    %                 set(handles.segmSpotSizeEdit,'String',num2str(brush));
    %                 set(handles.im_browser, 'CurrentCharacter', '1');
    %                 return;
    %             end
    
    curPt  = mean(obj.mibView.handles.mibImageAxes.CurrentPoint);
    curPt = curPt(1:2);  % mouse coordinates
    
    % modify curPt with shifts that come from handles.Img{handles.Id}.I.axesX/handles.Img{handles.Id}.I.axesY and magnification factor
    magFactor = obj.mibModel.getMagFactor();
    [axesX, axesY] = obj.mibModel.getAxesLimits();
    curPt(1) = curPt(1)*magFactor + max([0 axesX(1)]);
    curPt(2) = curPt(2)*magFactor + max([0 axesY(1)]);
    xl = axesX;
    yl = axesY;
    % zoom will work only when the mouse is above the image
    if curPt(1)<xl(1) || curPt(1)>xl(2); return; end
    if curPt(2)<yl(1) || curPt(2)>yl(2); return; end
    
    midX = mean(xl);
    rngXhalf = diff(xl) / 2; % half-width of the shown image
    midY = mean(yl);
    rngYhalf = diff(yl) / 2; % half-height of the shown image
    
    curPt2 = (curPt-[midX, midY]) ./ [rngXhalf, rngYhalf];  % image shift in %%
    curPt  = [curPt; curPt];
    curPt2 = [-(1+curPt2).*[rngXhalf, rngYhalf];...
               (1-curPt2).*[rngXhalf, rngYhalf]];           % new image half-sizes without zooming
    
    r = C^(verticalScrollCount*verticalScrollAmount);
    newLimSpan = r * curPt2;
    
    % Determine new limits based on r
    lims = curPt + newLimSpan;
    
    % check out of image bounds conditions
    if lims(1,1) < 0 && lims(2,1) < 0; return; end
    if lims(1,2) < 0 && lims(2,2) < 0; return; end
    if lims(1,1) > obj.mibModel.I{obj.mibModel.id}.width && lims(2,1) > obj.mibModel.I{obj.mibModel.id}.width; return; end
    if lims(1,2) > obj.mibModel.I{obj.mibModel.id}.height && lims(2,2) > obj.mibModel.I{obj.mibModel.id}.height; return; end
    
    obj.mibModel.setMagFactor(magFactor*r);    % update magFactor
    obj.mibModel.setAxesLimits(lims(:,1)', lims(:,2)');    % update axes limits
    obj.plotImage(0);
    
    % notify listeners that the image axes were changed -> mibSnapshotController
    motifyEvent.Name = 'updteAxesLimits_changed';
    eventdata = ToggleEventData(motifyEvent);
    notify(obj.mibModel, 'modelNotify', eventdata);
else    % slice change with the mouse wheel
    if ismember('shift', modifier)
        shift = obj.mibView.handles.mibChangeLayerSlider.UserData.sliderShiftStep;
    else
        shift = 1;
    end
    if ~obj.mibModel.preferences.System.AltWithScrollWheel && ismember('alt', modifier)
        if obj.mibView.altPressed == 0
            obj.mibView.altPressed = obj.mibModel.I{obj.mibModel.id}.getCurrentSliceNumber();
        end
    end

    new_index = obj.mibModel.I{obj.mibModel.id}.slices{obj.mibModel.I{obj.mibModel.id}.orientation}(1) - verticalScrollCount*shift;
    if new_index < 1;  new_index = 1; end
    if new_index > obj.mibModel.I{obj.mibModel.id}.dim_yxczt(obj.mibModel.I{obj.mibModel.id}.orientation); new_index = obj.mibModel.I{obj.mibModel.id}.dim_yxczt(obj.mibModel.I{obj.mibModel.id}.orientation); end
    
    obj.mibView.handles.mibChangeLayerSlider.Value = new_index;     % update slider value
    obj.mibChangeLayerSlider_Callback();
end
end