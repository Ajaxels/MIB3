function gui_WindowKeyReleaseFcn(obj, ~, ~)
% function gui_WindowKeyReleaseFcn(obj, ~, ~)
% Callback for key release in MIB
%
% Restores the brush radius enlarged by the Ctrl-key eraser mode and
% resets obj.view.ctrlPressed to 0.  Registered as WindowKeyReleaseFcn on
% every ImageViewDocument UIFigure (see MibImageDocument.setupCallbacks).
%
% Parameters:
%   (event arguments ignored)
%
% Return values:
%   (none)
%

%|
% @b Examples:
% @code % registered automatically in MibImageDocument.setupCallbacks:
% obj.UIFigure.WindowKeyReleaseFcn = @(h,d)obj.mibController.gui_WindowKeyReleaseFcn(h,d); @endcode

% Updates
%

% Clear stored modifier state so stale values don't affect subsequent button clicks
obj.currentModifier = {};

if obj.view.ctrlPressed ~= 0
    radius = obj.cSegmentation.handles.brushRadius.Value;
    obj.cSegmentation.handles.brushRadius.Value = radius - max([0, obj.view.ctrlPressed]);
    obj.cImageDoc{obj.mibModel.Sets.selectedSet}.updateBrushCursor([], ':', true);
end
obj.view.ctrlPressed = 0;

end
