function mask_Callbacks(obj, hWidget, hData)
% MASK_CALLBACKS - callback on press of buttons in the Mask ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.mask_Callbacks(hWidget, hData)
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
    fprintf('controllers.MibRibbon.mask_Callbacks: Mask ribbon-> %s\n', mode);
end

switch mode
    % -------------- Mask to Selection section --------------
    case 'Add, 2D'      % obj.handles.ribbonMask.maskToSelection2DAdd
        obj.mibModel.moveLayers('mask', 'selection', '2D, Slice', 'add');    
    case 'Remove, 2D'   % obj.handles.ribbonMask.maskToSelection2DRemove
        obj.mibModel.moveLayers('mask', 'selection', '2D, Slice', 'remove');    
    case 'Replace, 2D'  % obj.handles.ribbonMask.maskToSelection2DReplace
        obj.mibModel.moveLayers('mask', 'selection', '2D, Slice', 'replace');    
    case 'Add, 3D'      % obj.handles.ribbonMask.maskToSelection3DAdd
        obj.mibModel.moveLayers('mask', 'selection', '3D, Stack', 'add');    
    case 'Remove, 3D'   % obj.handles.ribbonMask.maskToSelection3DRemove
        obj.mibModel.moveLayers('mask', 'selection', '3D, Stack', 'remove');    
    case 'Replace, 3D'  % obj.handles.ribbonMask.maskToSelection3DReplace
        obj.mibModel.moveLayers('mask', 'selection', '3D, Stack', 'replace');    
    case 'Add, 4D'      % obj.handles.ribbonMask.maskToSelection4DAdd
        obj.mibModel.moveLayers('mask', 'selection', '4D, Dataset', 'add');    
    case 'Remove, 4D'   % obj.handles.ribbonMask.maskToSelection4DRemove
        obj.mibModel.moveLayers('mask', 'selection', '4D, Dataset', 'remove');    
    case 'Replace, 4D'  % obj.handles.ribbonMask.maskToSelection4DReplace
        obj.mibModel.moveLayers('mask', 'selection', '4D, Dataset', 'replace');   

        % -------------- Import Mask section --------------
    case sprintf('Clear\nmask')      % obj.handles.ribbonMask.clear
        obj.mibModel.clearMask('4D, Dataset');
    case sprintf('Load\nmask')   % obj.handles.ribbonMask.load
        obj.mibModel.loadMask();
    case {'Import', 'Import mask from MATLAB'}  % obj.handles.ribbonMask.import or obj.handles.ribbonMask.importFromMatlab
        obj.mibModel.importDataset('mask');
    case 'Import mask from another MIB dataset'      % obj.handles.ribbonMask.importFromMIB
        obj.mibModel.importDatasetFromMib('mask');  

        % -------------- Export Mask section --------------
    case {'Export', 'Export mask to MATLAB'}        % obj.handles.ribbonMask.export or obj.handles.ribbonMask.exportToMatlab
        obj.mibModel.exportDataset('mask');
    case 'Export mask to Imaris'                     % obj.handles.ribbonMask.exportToImaris
        obj.mibModel.exportDatasetToImaris('mask');
    case 'Export mask to another MIB dataset'       % obj.handles.ribbonMask.exportToMIB
        obj.mibModel.exportDatasetToMib('mask');
    case sprintf('Save\nmask')                      % obj.handles.ribbonMask.saveMask
        obj.mibModel.saveMask([]);

        % -------------- Mask tools section --------------
    case 'Shown slice (2D)'       % obj.handles.ribbonMask.invert2D
        obj.mibModel.invertMask('mask', '2D, Slice');
    case 'Current stack (3D)'                     % obj.handles.ribbonMask.invert3D
        obj.mibModel.invertMask('mask', '3D, Stack');
    case {'Complete volume (4D)', 'Invert'}                    % obj.handles.ribbonMask.invert4D
        obj.mibModel.invertMask('mask', '4D, Dataset');
    case sprintf('Replace\nmasked areas')                     % obj.handles.ribbonMask.replaceImage
        obj.mibModel.replaceMaskedArea('mask');
    case sprintf('Smooth\nmask')                    % obj.handles.ribbonMask.smooth
        obj.mibModel.smoothImage('mask');
    case 'Quantify'                    % obj.handles.ribbonMask.quantify
        id = obj.mibModel.getActiveId();
        selMaterial = obj.mibModel.I{id}.selectedMaterial;
        obj.mibModel.I{id}.selectedMaterial = 1;
        obj.mibController.startController('controllers.Quantification');
        obj.mibModel.I{id}.selectedMaterial = selMaterial;

end
notify(obj.mibModel, 'ShowImage');

end
