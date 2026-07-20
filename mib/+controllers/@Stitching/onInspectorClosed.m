function onInspectorClosed(obj)
% ONINSPECTORCLOSED - Release the seam-inspector handle and its listeners.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.onInspectorClosed()
%

for listenerIdx = 1:numel(obj.inspectorListeners)
    if ~isempty(obj.inspectorListeners{listenerIdx}) && isvalid(obj.inspectorListeners{listenerIdx})
        delete(obj.inspectorListeners{listenerIdx});
    end
end
obj.inspectorListeners = {};
obj.inspector = [];
if ~isempty(obj.view) && isvalid(obj.view.gui)
    obj.updateWidgets();
end
end
