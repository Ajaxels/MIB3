function selectionTools_Callbacks(obj, hWidget, hData)
% SELECTIONTOOLS_CALLBACKS - callback on press of buttons in the Tools section of the Selection ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.selectionTools_Callbacks(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.selectionTools_Callbacks: Selection ribbon-> Tools section pressed -> %s\n', mode);
end

switch mode
    case 'Branch points'        % obj.handles.ribbonSelection.branch
        obj.mibModel.sessionSettings.morphOpsImages.Objects3D = false;
        obj.mibModel.sessionSettings.morphOpsImages.MorphOperation   = 'branchpoints';
        obj.mibController.startController('controllers.MorphOps');
    case 'Diagonal fill'     % obj.handles.ribbonSelection.diag
        obj.mibModel.sessionSettings.morphOpsImages.Objects3D = false;
        obj.mibModel.sessionSettings.morphOpsImages.MorphOperation   = 'diag';
        obj.mibController.startController('controllers.MorphOps');
    case 'Replace, 2D'    % obj.handles.ribbonSelection.selectionToMask2DReplace
    case 'Endpoints'        % obj.handles.ribbonSelection.endpoints
        obj.mibModel.sessionSettings.morphOpsImages.Objects3D = false;
        obj.mibModel.sessionSettings.morphOpsImages.MorphOperation   = 'endpoints';
        obj.mibController.startController('controllers.MorphOps');
    case 'Skeleton'     % obj.handles.ribbonSelection.skeleton
        obj.mibModel.sessionSettings.morphOpsImages.Objects3D = false;
        obj.mibModel.sessionSettings.morphOpsImages.MorphOperation   = 'skel';
        obj.mibController.startController('controllers.MorphOps');
    case 'Spur'    % obj.handles.ribbonSelection.spur
        obj.mibModel.sessionSettings.morphOpsImages.Objects3D = false;
        obj.mibModel.sessionSettings.morphOpsImages.MorphOperation   = 'spur';
        obj.mibController.startController('controllers.MorphOps');
    case 'Thin'        % obj.handles.ribbonSelection.thin
        obj.mibModel.sessionSettings.morphOpsImages.Objects3D = false;
        obj.mibModel.sessionSettings.morphOpsImages.MorphOperation   = 'thin';
        obj.mibController.startController('controllers.MorphOps');
    case 'Ultimate erosion'     % obj.handles.ribbonSelection.ultErosion
        obj.mibModel.sessionSettings.morphOpsImages.Objects3D = false;
        obj.mibModel.sessionSettings.morphOpsImages.MorphOperation   = 'bwulterode';
        obj.mibController.startController('controllers.MorphOps');

    case 'Shown slice (2D)'        % obj.handles.ribbonSelection.invert2D
    case 'Current stack (3D)'        % obj.handles.ribbonSelection.invert3D
    case {'Complete volume (4D)', 'Invert'}        % obj.handles.ribbonSelection.invert4D or obj.handles.ribbonSelection.invert

    case sprintf('Expand to\nmask border')        % obj.handles.ribbonSelection.expandToMask
    case {sprintf('Interpolate as\nshape'), sprintf('Interpolate as\nline')}        % obj.handles.ribbonSelection.interpolate
        obj.mibController.updateInterpolationMode();
    case sprintf('Replace\nselected areas')        % obj.handles.ribbonSelection.replaceImage
    case sprintf('Smooth\nselection')        % obj.handles.ribbonSelection.smooth

end

end
