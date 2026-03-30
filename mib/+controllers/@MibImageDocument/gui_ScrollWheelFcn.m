function gui_ScrollWheelFcn(obj, eventdata)
% function gui_ScrollWheelFcn(obj, eventdata)
% Callback for mouse scroll wheel
%
% Dispatches scroll events to one of three behaviors based on active
% modifier keys and the MouseWheel mode preference:
%
%   Ctrl + Scroll         - Adjust brush/tool size by 1 unit
%   Ctrl + Shift + Scroll - Adjust brush/tool size by 5 units
%   Alt + Scroll          - Navigate time frames (scroll mode + AltWithScrollWheel pref)
%   Scroll (zoom mode)    - Zoom in/out centred on cursor position (power law, C=1.10)
%   Scroll (scroll mode)  - Navigate Z-slices
%
% When adjusting brush size, the cursor is temporarily replaced with a
% numeric size indicator (capped at display value 99). Brush size is
% clamped to a minimum of 1.
%
% Can be triggered by both the standard figure ScrollWheelFcn event and
% programmatically via key shortcut callbacks using a ToggleEventData
% object whose .Parameter struct contains VerticalScrollCount and
% VerticalScrollAmount.
%
% Inputs:
%   obj       - View controller; holds handles to GUI, mibModel, and
%               segmentation panel widgets
%   eventdata - matlab.ui.eventdata.ScrollData  (normal scroll), OR
%               core.ToggleEventData with .Parameter.VerticalScrollCount /
%               .VerticalScrollAmount  (key shortcut call)
%
% Example usage:
%   % This callback is automatically triggered by scroll events
%   % User actions:
%   % - Ctrl+Scroll Up: Increase brush size by 1
%   % - Ctrl+Shift+Scroll Down: Decrease brush size by 5

imViewFigure = obj.UIFigure;
% Use obj.mibController.currentModifier rather than UIFigure.CurrentModifier.
% UIFigure.CurrentModifier can become stale after a blocking Python (pyrun)
% call — the Shift key-release event is queued but never delivered while
% MATLAB is blocked, so the figure property stays {'shift'} even after the
% user has released the key.  currentModifier is reset explicitly after each
% SAM segmentation call, so it always reflects the true keyboard state.
%modifier = imViewFigure.CurrentModifier;
modifier = obj.mibController.currentModifier;

% Get scroll parameters
if isprop(eventdata, 'Parameters')
    % Call from key shortcuts using ToggleEventData
    verticalScrollCount = eventdata.Parameters.VerticalScrollCount;
    verticalScrollAmount = eventdata.Parameters.VerticalScrollAmount;
    if strcmp(modifier, 'shift')
        modifier = {'shift', 'control'};
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
    text_str = num2str(min(val, 99));

    % Create custom cursor showing the size value
    valuePointer = zeros([16 16]);
    for i = 1:numel(text_str)
        col_start = i*8 - 7;
        col_end = i*8;
        valuePointer(:, col_start:col_end) = obj.view.brushSizeNumbers{text_str(i)};
    end
    valuePointer(valuePointer==0) = NaN;
    valuePointer(1:5,3) = 1;
    valuePointer(3,1:5) = 1;

    obj.UIFigure.Pointer = 'custom';
    obj.UIFigure.PointerShapeCData = valuePointer;

    % Update widget value
    h1.Value = val;

    % Update brush cursor for new size
    obj.updateBrushCursorOffset();
    obj.updateBrushCursor();
    return;
end

% % check whether the mouse cursor within the axes.
if ~obj.isInsideAxes; return; end

% get alias to the dataset
% Split-panel guard: sync model to this document's set if needed
if obj.mibModel.Sets.selectedSet ~= obj.setOfDatasetsIndex
    setName = obj.mibModel.Sets.names{obj.setOfDatasetsIndex};
    obj.mibController.view.handles.panels.activeDataset.handles.sets.Value = setName;
    obj.mibController.cActiveDataset.setsOps_Callbacks([], [], 'sets');
end
dataset = obj.mibModel.I{obj.mibModel.id};

if obj.mibModel.preferences.System.MouseWheel(1) == 's'  && ...  % scroll
        ismember('alt', modifier) && obj.mibModel.preferences.System.AltWithScrollWheel 
    %% change frame number with holding Alt
    % Note! it depends on settings in Preferences->User interface->Hold Alt with scroll wheel
    
    if ismember('shift', modifier)
        shift = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.sliderTShiftStep;
    else
        shift = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.sliderTStep;
    end
    
    new_index = dataset.slices{5}(1) - verticalScrollCount*shift;
    new_index = max(1, min(new_index, dataset.image.time));
    
    obj.handles.frameNumberSlider.Value = new_index;     % update slider value
    obj.frameNumberSlider_Callback();
elseif obj.mibModel.preferences.System.MouseWheel(1) == 'z'                 % 'zoom', zoom in/zoom out with the mouse wheel
    % Power law allows for the inverse to work:
    %      C^(x) * C^(-x) = 1
    % Choose C to get "appropriate" zoom factor
    C = 1.10;
    % Get mouse coordinates
    curPt = obj.handles.imViewAxes.CurrentPoint;
    curPt = curPt(1, 1:2);  % mouse coordinates
    
    % Convert cursor from physical (XData) space to data-pixel coordinates.
    % Uses the same logic as convertMouseToDataCoordinates('shown').
    magFactor = obj.mibModel.getMagFactor();
    [axesX, axesY] = obj.mibModel.getAxesLimits();
    [curPt(1), curPt(2)] = obj.mibModel.convertMouseToDataCoordinates(curPt(1), curPt(2), 'shown');
    xl = axesX;
    yl = axesY;

    % Image dimensions in the displayed axis coordinate system
    % (X→depth for orientation 1/2; Y→height or width depending on orientation)
    getDimsOpts.blockModeSwitch = false;
    [imgAxesH, imgAxesW] = dataset.getDatasetDimensions('image', [], getDimsOpts);

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
    if lims(1,1) > imgAxesW && lims(2,1) > imgAxesW; return; end
    if lims(1,2) > imgAxesH && lims(2,2) > imgAxesH; return; end
    
    obj.mibModel.setMagFactor(magFactor*r);    % update magFactor
    obj.mibModel.setAxesLimits(lims(:,1)', lims(:,2)');    % update axes limits
    obj.brushCursorOffset = []; % clear brush offset
    obj.mibController.showImage();
    
    % % notify listeners that the image axes were changed -> mibSnapshotController
    % motifyEvent.Name = 'UpdateDatasetAxes';
    % eventdata = ToggleEventData(motifyEvent);
    % notify(obj.mibModel, 'modelNotify', eventdata);
else    % slice change with the mouse wheel
    % update the slider step
    if ismember('shift', modifier)
        shift = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.sliderZShiftStep;
    else
        shift = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.sliderZStep;
    end
    
    %if ~obj.mibModel.preferences.System.AltWithScrollWheel && ismember('alt', modifier)
        %if obj.mibView.altPressed == 0
        %    obj.mibView.altPressed = obj.mibModel.I{obj.mibModel.id}.getCurrentSliceNumber();
        %end
    %end

    orientation = dataset.orientation;
    new_index = dataset.slices{orientation}(1) - verticalScrollCount*shift;
    if new_index < 1;  new_index = 1; end
    if new_index > dataset.dim_yxzct(orientation)
        new_index = dataset.dim_yxzct(orientation); 
    end
    
    obj.handles.sliceNumberSlider.Value = new_index;     % update slider value
    obj.sliceNumberSlider_Callback();
end
end
