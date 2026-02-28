function setupCallbacks(obj)
% function setupCallbacks(obj)
% Setup all callbacks for this image document
%
% Configures callbacks for:
% - Slice and frame navigation buttons and sliders
% - Mouse movement tracking
% - Mouse scroll wheel interactions
% - Window resize events
%
% Parameters:
%   none
%
% Return values:
%   none

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

%% Mouse and window callbacks
% Note: UIFigure (imViewFigure) is identified inside ImageViewDocument.mlapp as
% parentFigure = ancestor(obj.handles.imViewAxes, 'figure')
obj.UIFigure.WindowButtonMotionFcn = @(~, ~)obj.gui_WinMouseMotionFcn();
obj.UIFigure.WindowScrollWheelFcn = @(~, eventdata)obj.gui_ScrollWheelFcn(eventdata);
obj.UIFigure.SizeChangedFcn = @(~, ~)obj.gui_SizeChangedFcn();
obj.UIFigure.WindowKeyPressFcn = @(~, ~)obj.gui_WindowKeyPressFcn();
obj.UIFigure.WindowButtonDownFcn = @(~, ~)obj.gui_WindowButtonDownFcn();

% obj.figureDoc.CanCloseFcn
end
