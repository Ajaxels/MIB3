function listners_Callbacks(obj, src, evtData)
% LISTENERS_CALLBACKS - Generic callback on getting listeners events
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listners_Callbacks(src, evtData)
%
% Input Arguments:
%   - **obj** — handle to the ``Graphcut`` controller
%   - **evnt** — event data; ``evnt.EventName`` is inspected for dispatch


switch evtData.EventName
    case {'ShowMask'}
        if obj.mibController.cSelection.handles.showMask.Value == 1 && ...
            obj.mibModel.showMask == 1
            return;
        end
        obj.mibController.cSelection.handles.showMask.Value = true;
        obj.mibModel.showMask = obj.handles.showMask.Value;
        notify(obj.mibModel, 'ShowImage');
end

end