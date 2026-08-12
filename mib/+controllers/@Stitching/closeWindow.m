function closeWindow(obj)
% CLOSEWINDOW - Close the Stitching GUI and clean up listeners.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.closeWindow()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.closeWindow: triggered\n');
end
% Remember the dialog's parameters for the next time it is opened in this
% session; the constructor restores them, minus InputPath and OutputPath. Only
% from the GUI, because a batch protocol states its own parameters in full and
% has no business changing what the dialog opens with. Written on close rather
% than on every widget change: sessionSettings lives in RAM, so there is nothing
% an earlier write would survive that this one does not.
if ~isempty(obj.view)
    obj.mibModel.sessionSettings.stitching = obj.collectProjectSettings();
end

% Close the seam inspector first - it holds handles into this controller.
if ~isempty(obj.inspector) && isvalid(obj.inspector)
    obj.inspector.closeWindow();
end

% Delete interactive tile-placement ROI listeners (the ROIs go with the axes).
if ~isempty(obj.roiListeners)
    for roiListenerIdx = 1:numel(obj.roiListeners)
        if isvalid(obj.roiListeners{roiListenerIdx})
            delete(obj.roiListeners{roiListenerIdx});
        end
    end
    obj.roiListeners = {};
end

if ~isempty(obj.view) && isvalid(obj.view.gui)
    delete(obj.view.gui);
end
for listenerIdx = 1:numel(obj.listener)
    delete(obj.listener{listenerIdx});
end
notify(obj, 'CloseEvent');

end
