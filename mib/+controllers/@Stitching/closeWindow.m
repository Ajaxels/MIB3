function closeWindow(obj)
% CLOSEWINDOW - Close the Stitching GUI and clean up listeners.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.closeWindow()
%

if ~isempty(obj.view) && isvalid(obj.view.gui)
    delete(obj.view.gui);
end
for listenerIdx = 1:numel(obj.listener)
    delete(obj.listener{listenerIdx});
end
notify(obj, 'CloseEvent');

end
