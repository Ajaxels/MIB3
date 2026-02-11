function imView_SizeChangedFcn(obj)
% function imView_SizeChangedFcn(obj)
% callback on size change of the Image View panel

persistent inCallback lastCallTime
currentTime = tic;

% Auto-reset if stuck for more than 100ms (handles debugging breakpoints and crashes)
if ~isempty(lastCallTime) && toc(lastCallTime) > 0.2
    inCallback = false;
end
% Exit immediately if already processing a mouse move
if ~isempty(inCallback) && inCallback; return; end
inCallback = true;
lastCallTime = currentTime;

for i = 1:numel(obj.mibModel.I)
    Options.mode = 'resize';
    Options.index = i;
    eventdata = core.ToggleEventData(Options);
    notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
end
notify(obj.mibModel, 'DatasetsPanelUpdate');
obj.updateBrushCursor([], [], false);

inCallback = false;
end