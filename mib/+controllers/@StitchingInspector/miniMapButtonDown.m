function miniMapButtonDown(obj)
% MINIMAPBUTTONDOWN - Mini-map click: jump the review to the nearest seam.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.miniMapButtonDown()
%
% Wired on ``miniMapAxes`` itself (not per tile patch - see
% :func:`renderMiniMap`), so the click point comes straight from
% ``miniMapAxes.CurrentPoint``, exactly like :func:`scrollWheel_Callback` and
% :func:`pairViewButtonDown` already read the pair-view axes. This sidesteps
% any doubt about what a PATCH's ``ButtonDownFcn`` hit event actually carries
% (unlike the image objects the pair view uses) and about which patch - of
% possibly several overlapping ones - would receive it.
%
% The nearest seam to that point (:meth:`edgeAtMiniMapPoint`) is selected
% directly; nothing here falls back to "the clicked tile's worst seam".
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.miniMapButtonDown: triggered\n');
end
if ~obj.dataValid() || ~obj.hasWidget('miniMapAxes'); return; end

mapAxes = obj.view.handles.miniMapAxes;
point = mapAxes.CurrentPoint(1, 1:2);

k = obj.edgeAtMiniMapPoint(point);
if ~isempty(k)
    obj.selectSeam(k);
end
end
