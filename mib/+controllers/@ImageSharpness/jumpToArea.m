function jumpToArea(obj)
% JUMPTOAREA - Show the area of the first selected results row in the image view.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.jumpToArea()
%
% Centres the image view on the analysed area of ``obj.selectedRows(1)`` and
% goes to its slice and time point; the zoom is kept. The active dataset must
% be the one the row was measured on (compared by file name) and shown in
% the same orientation, otherwise a message names what to switch to; MIB
% datasets are not switched automatically, because the buffer that held the
% file may have been reused.
%
% The centre is the middle of ``row.position`` (``[x1 y1 x2 y2]`` in pixels
% of the shown orientation, see getRegions). The slice number counts along
% the axis perpendicular to the orientation: Z for XY, Y for ZX, X for ZY.
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ImageSharpness.jumpToArea: triggered\n');
end
if isempty(obj.selectedRows); return; end
row = obj.results(obj.selectedRows(1));

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};
[~, datasetName, extension] = fileparts(dataset.image.filename);
if ~strcmp([datasetName extension], row.datasetName)
    uialert(obj.view.gui, sprintf('The measurement was made on %s.\nSwitch to that dataset first.', row.datasetName), ...
        'Jump to area', 'Icon', 'info');
    return;
end
orientationNames = {'ZX', 'ZY', 'XY'};
if dataset.orientation ~= row.orientation
    uialert(obj.view.gui, sprintf('The measurement was made in the %s orientation.\nSwitch to that orientation first.', ...
        orientationNames{row.orientation}), 'Jump to area', 'Icon', 'info');
    return;
end
if isempty(row.position)
    uialert(obj.view.gui, 'The position of this area was not recorded.', 'Jump to area', 'Icon', 'info');
    return;
end

centreX = mean(row.position([1 3]));
centreY = mean(row.position([2 4]));
dataset.moveView(centreX, centreY);

if dataset.image.time > 1 && dataset.getCurrentTimePoint() ~= row.timePoint
    dataset.slices{5} = [row.timePoint, row.timePoint];
    notify(obj.mibModel, 'FrameChanged');
end
% number of slices along the axis perpendicular to the orientation
sliceDimension = [1 2 3];       % ZX: y, ZY: x, XY: z in dim_yxzct
numberOfSlices = dataset.image.dim_yxzct(sliceDimension(row.orientation));
if numberOfSlices > 1
    dataset.slices{row.orientation} = [row.sliceNumber, row.sliceNumber];
    notify(obj.mibModel, 'SliceChanged');
else
    notify(obj.mibModel, 'ShowImage');
end
end
