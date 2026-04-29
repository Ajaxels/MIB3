function gui_WindowKeyReleaseFcn(obj, ~, ~)
% GUI_WINDOWKEYRELEASEFCN - Callback for key release in MIB.
%
% Syntax:
%   function gui_WindowKeyReleaseFcn(obj, ~, ~)
%
% Restores the brush radius enlarged by the Ctrl-key eraser mode and
% resets obj.view.ctrlPressed to 0.  Registered as WindowKeyReleaseFcn on
% every ImageViewDocument UIFigure (see MibImageDocument.setupCallbacks).
%
% Input Arguments:
%   (event arguments ignored)
%
% Output Arguments:
%   (none)
%
% Usage:
%   @code % registered automatically in MibImageDocument.setupCallbacks:
%   obj.UIFigure.WindowKeyReleaseFcn = @(h,d)obj.mibController.gui_WindowKeyReleaseFcn(h,d); @endcode
%

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
