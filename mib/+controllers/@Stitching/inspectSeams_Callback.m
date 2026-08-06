function inspectSeams_Callback(obj)
% INSPECTSEAMS_CALLBACK - Open (or focus) the seam inspector.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.inspectSeams_Callback()
%
% Launches :class:`controllers.StitchingInspector` on the current
% edges/positions for worst-first manual QC (see
% ``development/stitching/plan_inspector.md``). The inspector mutates this
% controller's edge/position state in place; its ``SeamsUpdated`` event
% refreshes this window's widgets so both stay in sync.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.inspectSeams_Callback: triggered\n');
end

% Already open - bring to front.
if ~isempty(obj.inspector) && isvalid(obj.inspector) && ...
        ~isempty(obj.inspector.view) && isvalid(obj.inspector.view.gui)
    figure(obj.inspector.view.gui);
    return;
end

if isempty(obj.edges) || isempty(obj.positions)
    warnOptions.MsgBoxOnly  = true;
    warnOptions.Icon        = 'puffin_warning';
    warnOptions.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        sprintf('The inspector reviews seams at the SOLVED placement.\nRun Measure overlaps and Optimize positions first.'), ...
        {}, {}, 'Seam inspector', warnOptions);
    return;
end

obj.inspector = controllers.StitchingInspector(obj.mibModel, obj);
obj.inspectorListeners{1} = addlistener(obj.inspector, 'SeamsUpdated', ...
    @(~, ~) obj.updateWidgets());
obj.inspectorListeners{2} = addlistener(obj.inspector, 'CloseEvent', ...
    @(~, ~) obj.onInspectorClosed());
end
