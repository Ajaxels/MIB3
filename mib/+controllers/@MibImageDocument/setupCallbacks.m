function setupCallbacks(obj)
% SETUPCALLBACKS - Setup all callbacks for this image document.
%
% Syntax:
%   function setupCallbacks(obj)
%
% Configures callbacks for:
% - Slice and frame navigation buttons and sliders
% - Mouse movement tracking
% - Mouse scroll wheel interactions
% - Window resize events
%
% Input Arguments:
%   none
%
% Output Arguments:
%   none
%

%% Context menu to the sliders

% Change of slice numbers
obj.handles.sliceNumberSliderContext = uicontextmenu(obj.UIFigure);
obj.handles.sliceNumberSliderContextDefault = uimenu(obj.handles.sliceNumberSliderContext, ...
    'Text', 'Default', 'Tag', 'sliceNumberSliderContextDefault');
obj.handles.sliceNumberSliderContextSetStep = uimenu(obj.handles.sliceNumberSliderContext, ...
    'Text', 'Set step...', 'Tag', 'sliceNumberSliderContextSetStep');
% Add context menu to buttons
obj.handles.sliceNumberSlider.ContextMenu = obj.handles.sliceNumberSliderContext;
% Add callbacks
obj.handles.sliceNumberSliderContextDefault.MenuSelectedFcn = @obj.sliceNumberSlider_ContextMenu;
obj.handles.sliceNumberSliderContextSetStep.MenuSelectedFcn = @obj.sliceNumberSlider_ContextMenu;

% Change of frame numbers
obj.handles.frameNumberSliderContext = uicontextmenu(obj.UIFigure);
obj.handles.frameNumberSliderContextDefault = uimenu(obj.handles.frameNumberSliderContext, ...
    'Text', 'Default', 'Tag', 'frameNumberSliderContextDefault');
obj.handles.frameNumberSliderContextSetStep = uimenu(obj.handles.frameNumberSliderContext, ...
    'Text', 'Set step...', 'Tag', 'frameNumberSliderContextSetStep');
% Add context menu to buttons
obj.handles.frameNumberSlider.ContextMenu = obj.handles.frameNumberSliderContext;
% Add callbacks
obj.handles.frameNumberSliderContextDefault.MenuSelectedFcn = @obj.sliceNumberSlider_ContextMenu;
obj.handles.frameNumberSliderContextSetStep.MenuSelectedFcn = @obj.sliceNumberSlider_ContextMenu;


%% Navigation callbacks
obj.handles.lastSlice.ButtonPushedFcn = @obj.gui_Callbacks;
obj.handles.prevSlice.ButtonPushedFcn = @obj.gui_Callbacks;
obj.handles.sliceNumberSlider.ValueChangingFcn = @obj.gui_Callbacks;
obj.handles.nextSlice.ButtonPushedFcn = @obj.gui_Callbacks;
obj.handles.firstSlice.ButtonPushedFcn = @obj.gui_Callbacks;
obj.handles.sliceNumber.ValueChangedFcn = @obj.gui_Callbacks;
obj.handles.frameNumber.ValueChangedFcn = @obj.gui_Callbacks;
obj.handles.firstFrame.ButtonPushedFcn = @obj.gui_Callbacks;
obj.handles.prevFrame.ButtonPushedFcn = @obj.gui_Callbacks;
obj.handles.frameNumberSlider.ValueChangingFcn = @obj.gui_Callbacks;
obj.handles.nextFrame.ButtonPushedFcn = @obj.gui_Callbacks;
obj.handles.lastFrame.ButtonPushedFcn = @obj.gui_Callbacks;

%% Mouse and key callbacks
obj.UIFigure.WindowButtonMotionFcn = @(~, ~)obj.gui_WinMouseMotionFcn();
obj.UIFigure.WindowScrollWheelFcn = @(~, eventdata)obj.gui_ScrollWheelFcn(eventdata);
obj.UIFigure.SizeChangedFcn = @(~, ~)obj.gui_SizeChangedFcn();
obj.UIFigure.WindowKeyPressFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);
obj.UIFigure.WindowKeyReleaseFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyReleaseFcn(hWidget, hData);
obj.UIFigure.WindowButtonDownFcn = @(~, ~)obj.gui_WindowButtonDownFcn();

%% Model listeners
% Update (or clear on dataset change) the quick-measurement text label.
% Both events are needed: UpdateDatasetAxes covers zoom/pan/resize;
% ShowImage covers buffer/dataset switches that don't fire UpdateDatasetAxes.
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateDatasetAxes', @(~,~) obj.updateMeasureText());
obj.listeners{end+1} = addlistener(obj.mibModel, 'ShowImage',         @(~,~) obj.updateMeasureText());
obj.listeners{end+1} = addlistener(obj.mibModel, 'SliceChanged',      @(~,~) obj.listener_sliceChanged());
obj.listeners{end+1} = addlistener(obj.mibModel, 'FrameChanged',      @(~,~) obj.listener_frameChanged());
obj.listeners{end+1} = addlistener(obj.mibModel, 'disableSegmentation', 'PostSet', @(~,~) obj.updateBrushCursor());

% obj.figureDoc.CanCloseFcn
end
