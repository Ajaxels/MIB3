function gui_SizeChangedFcn(obj)
% function gui_SizeChangedFcn(obj)
% Callback when figure size changes
%
% Updates all dataset axes and redraws the image when the
% figure window is resized. Uses persistent variables to
% prevent callback re-entrance.
%
% Parameters:
%   none
%
% Return values:
%   none

persistent inCallback lastCallTime
currentTime = tic();

% Auto-reset if stuck for more than 200ms
if ~isempty(lastCallTime) && toc(lastCallTime) > 0.2
    inCallback = false;
end

% Exit if already processing
if ~isempty(inCallback) && inCallback; return; end
inCallback = true;
lastCallTime = currentTime;

% Update axes for all datasets
% get global id of the first dataset of the current document
globalFirstIndex = 1 + ((obj.documentIndex-1) * obj.mibModel.Sets.datasetsInSet);
for i = globalFirstIndex:globalFirstIndex+obj.mibModel.Sets.datasetsInSet-1
    Options.mode = 'resize';
    Options.index = i;
    eventdata = core.ToggleEventData(Options);
    notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
end

% Trigger image redraw
notify(obj.mibModel, 'ShowImage');

% % Update brush cursor for all document sets
% for setId = 1:numel(obj.view.handles.imView)
%     if isa(obj.view.handles.imView{setId}, 'controllers.MibImageDocument')
%         obj.view.handles.imView{setId}.updateBrushCursor([], [], false);
%     end
% end

obj.updateBrushCursor([], [], false);

inCallback = false;
end
