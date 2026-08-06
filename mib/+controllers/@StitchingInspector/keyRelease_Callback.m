function keyRelease_Callback(obj, evnt)
% KEYRELEASE_CALLBACK - Dismiss the Shift ROI-box state on Shift release.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.keyRelease_Callback(evnt)
%
% Releasing ``Shift`` hides the hover ROI box and restores the arrow pointer.
%
% Input Arguments:
%   - **evnt** - KeyData from ``WindowKeyReleaseFcn``
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.keyRelease_Callback: triggered\n');
end
if strcmp(evnt.Key, 'shift')
    obj.shiftDown = false;
    if ~isempty(obj.view) && isvalid(obj.view.gui)
        obj.view.gui.Pointer = 'arrow';
    end
    obj.pairViewMotion();   % hides the box
end
end
