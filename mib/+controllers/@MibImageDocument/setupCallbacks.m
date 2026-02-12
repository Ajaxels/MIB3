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
% Note: UIFigure (imViewFigure) is identified inside ImageView.mlapp as
% parentFigure = ancestor(obj.handles.imViewAxes, 'figure')
obj.UIFigure.WindowButtonMotionFcn = @(~, ~)obj.gui_WinMouseMotionFcn();
obj.UIFigure.WindowScrollWheelFcn = @(~, eventdata)obj.gui_ScrollWheelFcn(eventdata);
obj.UIFigure.SizeChangedFcn = @(~, ~)obj.gui_SizeChangedFcn();

% obj.figureDoc.CanCloseFcn
end
