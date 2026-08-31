function closeWindow(obj)
% CLOSEWINDOW - Close the Instance editor and give back everything it took over.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.closeWindow()
%
% Pick mode is switched off **first**. It replaces the image figure's
% ``WindowButtonDownFcn`` with a callback into this controller and sets
% ``mibModel.disableSegmentation``; closing the window without undoing that
% leaves the main application unable to segment, with a mouse handler pointing
% at a deleted object and no clue on screen as to why.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.InstanceEditor.closeWindow: triggered\n');
end

obj.setPickMode(false);

if ~isempty(obj.datasetListener) && isvalid(obj.datasetListener)
    delete(obj.datasetListener);
end
for i = 1:numel(obj.listener)
    if isvalid(obj.listener{i}); delete(obj.listener{i}); end
end

if ~isempty(obj.view) && isvalid(obj.view.gui)
    delete(obj.view.gui);
end

notify(obj, 'CloseEvent');
end
