function updatePlots(obj, rowIndex)
% UPDATEPLOTS - Show one results row in the plot tabs, drawing only the visible tab.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updatePlots(rowIndex)   % show this row
%      obj.updatePlots()           % draw the visible tab for the current row, if not drawn yet
%      obj.updatePlots([])         % clear the plots
%
% Tabs and their plots, drawn by :func:`controllers.ImageSharpness.drawResultPlot`:
% ``imageAxes`` - ``'image'``, ``spectrumAxes`` - ``'spectrum'``,
% ``profileAxes`` - ``'profile'``, ``directionAxes`` - ``'directions'``.
%
% Only the tab that is visible is drawn; the others are drawn when they are
% selected (``plotTabGroup.SelectionChangedFcn`` calls ``updatePlots()``
% without arguments). Drawing a uiaxes costs 0.1-0.25 s, mostly in
% ``cla(..., 'reset')``, which re-creates the axes interactions, and in
% ``legend``; redrawing all four tabs on every row change took about 0.7 s.
% ``obj.drawnAxes`` lists the axes already drawn for ``obj.plotRowIndex``.
%
% Input Arguments:
%   - **rowIndex** *(optional)* - [numeric] index into ``obj.results``;
%     ``[]`` clears all plots; omitted keeps the current row
%

% Updates
%

handles = obj.view.handles;
allAxes = {handles.imageAxes, handles.spectrumAxes, handles.profileAxes, handles.directionAxes};

if nargin > 1
    obj.plotRowIndex = rowIndex;
    obj.drawnAxes = {};
    if isempty(rowIndex) || rowIndex < 1 || rowIndex > numel(obj.results)
        obj.plotRowIndex = [];
        for axesId = 1:numel(allAxes); cla(allAxes{axesId}, 'reset'); end
        return;
    end
end
if isempty(obj.plotRowIndex); return; end

selectedTab = handles.plotTabGroup.SelectedTab;
visibleAxes = allAxes(cellfun(@(axesHandle) isequal(ancestor(axesHandle, 'uitab'), selectedTab), allAxes));
if isempty(visibleAxes); return; end
visibleAxes = visibleAxes{1};
if any(cellfun(@(axesHandle) isequal(axesHandle, visibleAxes), obj.drawnAxes)); return; end

row = obj.results(obj.plotRowIndex);
cla(visibleAxes, 'reset');
plotNames = {'image', 'spectrum', 'profile', 'directions'};
plotName = plotNames{cellfun(@(axesHandle) isequal(axesHandle, visibleAxes), allAxes)};
controllers.ImageSharpness.drawResultPlot(visibleAxes, row, plotName);
obj.drawnAxes{end+1} = visibleAxes;
end
