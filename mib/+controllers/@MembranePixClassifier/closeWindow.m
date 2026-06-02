function closeWindow(obj)
% CLOSEWINDOW - Close the dialog and clean up listeners.

arguments (Input)
    obj controllers.MembranePixClassifier
end

if isvalid(obj.view.gui); delete(obj.view.gui); end
for i = 1:numel(obj.listener); delete(obj.listener{i}); end
notify(obj, 'CloseEvent');

end
