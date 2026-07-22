function fitView_Callback(obj)
% FITVIEW_CALLBACK - Reset the pair-view zoom to fit everything rendered.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.fitView_Callback()
%
% Clears the wheel-zoom state (:func:`scrollWheel_Callback`) and restores
% tight limits around whatever the pair view currently shows — the composited
% pair, the flicker stack or the two-click side-by-side. Wired to
% ``fitViewBtn`` and the ``F`` key.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.fitView_Callback: triggered\n');
end
obj.pairZoom = [];
if isempty(obj.view) || ~isfield(obj.view.handles, 'pairAxes'); return; end
pairAxes = obj.view.handles.pairAxes;
if isempty(findobj(pairAxes, 'Type', 'image')); return; end
axis(pairAxes, 'image');   % tight limits around all rendered images
end
