function fitView_Callback(obj)
% FITVIEW_CALLBACK - Reset the pair-view zoom to fit everything rendered.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.fitView_Callback()
%
% Clears the wheel-zoom state (:func:`scrollWheel_Callback`) and restores
% tight limits around whatever the pair view currently shows - the composited
% pair, the flicker stack or the two-click side-by-side - then widens the
% short side to the axes' shape so the fit fills the reserved area
% (:meth:`StitchingInspector.pairAxesFillLimits`). Wired to ``fitViewBtn``
% and the ``F`` key; it is also the way to re-fill the view after the window
% has been resized.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.fitView_Callback: triggered\n');
end
obj.pairZoom = [];
if ~obj.hasWidget('pairAxes'); return; end
pairAxes = obj.view.handles.pairAxes;
if isempty(findobj(pairAxes, 'Type', 'image')); return; end
axis(pairAxes, 'image');   % tight limits around all rendered images
% ...then widen the short side so the fit uses the whole reserved cell rather
% than a letterboxed column (see StitchingInspector.pairAxesFillLimits).
[xLim, yLim] = obj.pairAxesFillLimits();
if ~isempty(xLim)
    pairAxes.XLim = xLim;
    pairAxes.YLim = yLim;
end
end
