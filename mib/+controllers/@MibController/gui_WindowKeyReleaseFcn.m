function gui_WindowKeyReleaseFcn(obj, ~, ~)
% GUI_WINDOWKEYRELEASEFCN - Callback for key release in MIB.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.gui_WindowKeyReleaseFcn(src, evtData)
%
% Restores the brush radius enlarged by the Ctrl-key eraser mode and
% resets obj.view.ctrlPressed to 0.  Registered as WindowKeyReleaseFcn on
% every ImageViewDocument UIFigure (see MibImageDocument.setupCallbacks).
%
% Input Arguments:
%   - **src** — event source UIFigure (unused, indicated by ``~`` in the signature)
%   - **evtData** — key-release event data (unused, indicated by ``~`` in the signature)
%
% Output Arguments:
%   (none)
%
% **Example** — registered automatically in MibImageDocument.setupCallbacks:
%
%   .. code-block:: matlab
%
%      obj.UIFigure.WindowKeyReleaseFcn = @(h,d)obj.mibController.gui_WindowKeyReleaseFcn(h,d);
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
