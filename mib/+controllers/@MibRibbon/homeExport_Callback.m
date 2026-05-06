function homeExport_Callback(obj, hWidget, hData)
% HOMEEXPORT_CALLBACK - callback on press of buttons in the Export section of the Home ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.homeExport_Callback(hWidget, hData)
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
    fprintf('controllers.MibRibbon.homeExport_Callback: Export panel button pressed -> %s\n', mode);
end

switch mode
    case 'Save as'     % obj.handles.ribbonHome.saveFileAs — save image with dialog
        obj.mibModel.saveImage('image');
    case {'Export', 'Export to MATLAB'}     % obj.handles.ribbonHome.export & obj.handles.ribbonHome.exportToMatlab
        obj.mibModel.exportDataset('image');
    case 'Export to Imaris'     % obj.handles.ribbonHome.exportToImaris
        obj.mibModel.exportDatasetToImaris('image');
    case 'Snapshot'     % obj.handles.ribbonHome.snapshot
        obj.mibController.startController('controllers.Snapshot');
    case 'Movie'     % obj.handles.ribbonHome.movie
    case {'Render', 'MIB Rendering'}     % obj.handles.ribbonHome.render &  obj.handles.ribbonHome.renderMIB
        obj.mibController.startController('controllers.VolRenApp');
    case 'MATLAB Volume Viewer'     % obj.handles.ribbonHome.renderMatlab
        id = obj.mibModel.getActiveId();
        dataset = obj.mibModel.I{id};
        img = cell2mat(obj.mibModel.getData3D('image', [], 3));
        if size(img, 4) > 1
            utils.dlgs.showErrorDialog(obj.view.gui, sprintf('Volume viewer is not compatible with multicolor images;\nplease keep only a single color channel displayed and try again!'), 'Not implemented');
            return;
        end
        
        answer = 'Only volume';
        if dataset.modelExist
            answer = utils.dlgs.inputQuestDlg(obj.view.gui, sprintf('Would you like to have the model exported together with the volume?'), ...
                'Include model', 'Volume+labels', 'Only volume', 'Cancel', 'Only volume');
            if strcmp(answer, 'Cancel'); return; end
        end
        pixSize = dataset.image.pixSize;
        if strcmp(answer, 'Only volume')
            volumeViewer(squeeze(img), 'VolumeType', 'Volume', 'ScaleFactors', [pixSize.x pixSize.y pixSize.z]);
        else
            labels = cell2mat(obj.mibModel.getData3D('labels'));
            volumeViewer(squeeze(img), labels, 'ScaleFactors', [pixSize.x pixSize.y pixSize.z]);
        end

    case '3D viewer in Fiji'     % obj.handles.ribbonHome.renderFiji
        img = cell2mat(obj.mibModel.getData3D('image', [], 3));
        id = obj.mibModel.getActiveId();
        utils.renderVolumeWithFiji(img, obj.mibModel.I{id}.image.pixSize, obj.mibModel.mibGUI);
end
end
