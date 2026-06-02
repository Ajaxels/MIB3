function updateLoglist(obj, addText)
% UPDATELOGLIST - Append a timestamped message to the log list.
%
% In headless batch mode (no view) prints to the MATLAB console instead.

arguments (Input)
    obj controllers.MembranePixClassifier
    addText (1,:) char
end

c = clock;
msg = sprintf('%d:%02i:%02i  %s', c(4), c(5), round(c(6)), addText);

if isempty(obj.view) || ~isvalid(obj.view.gui)
    fprintf('%s\n', msg);
    return;
end

h = obj.view.handles;
items = h.logList.Items;
if isscalar(items) && isempty(items{1})
    items = {};
end
items{end+1} = msg;
h.logList.Items = items;
h.logList.Value = items{end};
drawnow;

end
