function selection_Callbacks(obj, hWidget, hData)
% SELECTION_CALLBACKS - callback on press of buttons in the Selection to Mask section of the Selection ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.selection_Callbacks(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** - handle to the pressed widget
%   - **hData** - handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.selection_Callbacks: Selection ribbon-> %s\n', mode);
end

switch mode
    % ----------- Selection to mask section -------------
    case 'Add, 2D'        % obj.handles.ribbonSelection.selectionToMask2DAdd 
        obj.mibModel.moveLayers('selection', 'mask', '2D, Slice', 'add'); 
    case 'Remove, 2D'     % obj.handles.ribbonSelection.selectionToMask2DRemove
        obj.mibModel.moveLayers('selection', 'mask', '2D, Slice', 'remove');    
    case 'Replace, 2D'    % obj.handles.ribbonSelection.selectionToMask2DReplace
        obj.mibModel.moveLayers('selection', 'mask', '2D, Slice', 'replace');    
    case 'Add, 3D'        % obj.handles.ribbonSelection.selectionToMask3DAdd 
        obj.mibModel.moveLayers('selection', 'mask', '2D, Slice', 'add');    
    case 'Remove, 3D'     % obj.handles.ribbonSelection.selectionToMask3DRemove
        obj.mibModel.moveLayers('selection', 'mask', '2D, Slice', 'remove');    
    case 'Replace, 3D'    % obj.handles.ribbonSelection.selectionToMask3DReplace
        obj.mibModel.moveLayers('selection', 'mask', '2D, Slice', 'replace');    
    case 'Add, 4D'        % obj.handles.ribbonSelection.selectionToMask4DAdd 
        obj.mibModel.moveLayers('selection', 'mask', '2D, Slice', 'add');    
    case 'Remove, 4D'     % obj.handles.ribbonSelection.selectionToMask4DRemove
        obj.mibModel.moveLayers('selection', 'mask', '2D, Slice', 'remove');    
    case 'Replace, 4D'    % obj.handles.ribbonSelection.selectionToMask4DReplace
        obj.mibModel.moveLayers('selection', 'mask', '2D, Slice', 'replace');    
    
    % ----------- Selection to buffer section -------------
    case 'Copy (Ctrl+C)'    % obj.handles.ribbonSelection.copy
        obj.selectionBuffer('copy');
    case 'Paste (Ctrl+V)'    % obj.handles.ribbonSelection.paste
        obj.selectionBuffer('paste');
    case 'Paste to all slices (Ctrl+Shift+V)'    % obj.handles.ribbonSelection.pasteAll
        obj.selectionBuffer('pasteall');
    case 'Clear'    % obj.handles.ribbonSelection.clear
        obj.selectionBuffer('clear');

    % ----------- Selection MorphOps -------------
    case 'Branch points'        % obj.handles.ribbonSelection.branch
        obj.mibModel.sessionSettings.morphOpsImages.Objects3D = false;
        obj.mibModel.sessionSettings.morphOpsImages.MorphOperation   = 'branchpoints';
        obj.mibController.startController('controllers.MorphOps');
    case 'Diagonal fill'     % obj.handles.ribbonSelection.diag
        obj.mibModel.sessionSettings.morphOpsImages.Objects3D = false;
        obj.mibModel.sessionSettings.morphOpsImages.MorphOperation   = 'diag';
        obj.mibController.startController('controllers.MorphOps');
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
    
        % ----------- Invert Selection -------------
    case 'Shown slice (2D)'        % obj.handles.ribbonSelection.invert2D
        obj.mibModel.invertMask('selection', '2D, Slice');
    case 'Current stack (3D)'        % obj.handles.ribbonSelection.invert3D
        obj.mibModel.invertMask('selection', '3D, Stack');
    case {'Complete volume (4D)', 'Invert'}        % obj.handles.ribbonSelection.invert4D or obj.handles.ribbonSelection.invert
        obj.mibModel.invertMask('selection', '4D, Dataset');

        % ----------- Other Selection Tools -------------
    case sprintf('Expand to\nmask border')        % obj.handles.ribbonSelection.expandToMask
        obj.mibModel.expandSelectionToMaskBorder();
    case {sprintf('Interpolate as\nshape'), sprintf('Interpolate as\nline')}        % obj.handles.ribbonSelection.interpolate
        obj.mibController.updateInterpolationMode();
    case sprintf('Replace\nselected areas')        % obj.handles.ribbonSelection.replaceImage
        obj.mibModel.replaceMaskedArea('selection');
    case sprintf('Smooth\nselection')        % obj.handles.ribbonSelection.smooth
        obj.mibModel.smoothImage('selection');
end

end
