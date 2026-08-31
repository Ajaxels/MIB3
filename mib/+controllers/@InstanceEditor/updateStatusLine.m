function updateStatusLine(obj)
% UPDATESTATUSLINE - Report the object count and the state of the index cache.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateStatusLine()
%
% The stale state has to be visible. Every operation reads bounding boxes out of
% the cached index, so if the model has been changed by something else - a brush
% stroke, an undo, another tool - the boxes describe a model that is gone, and
% an edit made against them would write the wrong voxels. The operations refuse
% to run in that state; the status line is what explains why.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

% Updates
%

if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
label = obj.view.handles.indexStatusLabel;

if ~obj.modelIsEditable()
    label.Text = 'No instance model in the active dataset';
    label.FontColor = [0.5 0.5 0.5];
    return;
end

dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
index = dataset.instanceIndex;

if isempty(index) || ~isstruct(index)
    label.Text = 'Objects not indexed yet - press Rebuild';
    label.FontColor = [0.6 0.4 0.0];
    return;
end
if ~obj.indexIsUsable()
    label.Text = 'Index is out of date - press Rebuild';
    label.FontColor = [0.7 0.0 0.0];
    return;
end

if obj.view.handles.Mode3D.Value
    label.Text = sprintf('%d objects, highest index %d', index.numObjects, index.maxIndex);
    label.FontColor = [0.0 0.5 0.0];
    return;
end

% 2D mode: the list describes one slice, and which slice that is has to be
% visible. With the automatic refresh off it can be a slice the user has already
% moved away from, and an operation would then act on objects of the shown slice
% rather than on the ones on the list.
shownSlice = dataset.getCurrentSliceNumber();
if ~isempty(obj.tableSlice) && obj.tableSlice ~= shownSlice
    label.Text = sprintf('List shows slice %d, image is on slice %d - press "Update list"', ...
        obj.tableSlice, shownSlice);
    label.FontColor = [0.6 0.4 0.0];
else
    stats = obj.currentSliceStats();
    label.Text = sprintf('Slice %d: %d objects; %d in the whole model', ...
        shownSlice, numel(stats.objectIds), index.numObjects);
    label.FontColor = [0.0 0.5 0.0];
end
end
