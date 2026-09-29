function homeImport_Callback(obj, hWidget, hData)
% HOMEIMPORT_CALLBACK - callback on press of the import buttons in the Home ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.homeImport_Callback(hWidget, hData)
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
    fprintf('controllers.MibRibbon.homeImport_Callback: Load dataset pressed -> %s\n', mode);
end

switch mode
    case 'Load'
        newPath = uigetdir(obj.mibModel.currentDirectory, 'Choose directory');
        if newPath == 0; return; end
        obj.mibModel.currentDirectory = newPath;
        obj.handles.currentDirectory.Value = newPath;
        obj.mibController.cDirContents.updateFileList_Callback();
        
    case {'Import', 'MATLAB'}  % obj.handles.ribbonHome.import &  obj.handles.ribbonHome.importFromMatlab
        obj.mibModel.importDataset('image');
    case 'System Clipboard'    % obj.handles.ribbonHome.importFromClipboard
        utils.ensureJavaLibraries({'imageselection'});  % link ImageSelection.java on the first use
        try     % fails without Java on macOS/Linux
            img = imclipboard('paste');
        catch err
            utils.dlgs.showErrorDialog(obj.view.gui, err, 'Clipboard import');
            return;
        end
        if isempty(img)
            utils.dlgs.showErrorDialog(obj.view.gui, 'Image is missing in the clipboard!', 'Clipboard import');
            return;
        end
        % convert to MIB3 [y,x,z,c,t] dimensions
        img = permute(img, [1,2,4,3]);
        imageFilename = fullfile(obj.mibModel.currentDirectory, 'import_clipboard.jpg');
        imageMeta = core.MibImage.initializeImgInfo('Filename', imageFilename);
        id = obj.mibModel.getActiveId();
        obj.mibModel.I{id}.initialize(img, imageMeta, 'Standard', 'imageOnly', obj.mibModel.preferences.System.EnableSelection);

        % --- notify controllers ---
        notify(obj.mibModel, 'NewDataset');
        notify(obj.mibModel, 'ShowImage');

    case 'Imaris'              % obj.handles.ribbonHome.importFromImaris
        [imageData, imarisInfo, viewPort, lutColors, obj.mibModel.connImaris] = io.imaris.getImarisDataset(obj.mibModel.connImaris);
        if isnan(imageData(1)); return; end

        % getImarisDataset returns [h,w,c,z,t]; convert to MIB3 [h,w,z,c,t]
        imageData = permute(imageData, [1,2,4,3,5]);

        % Build metadata dictionary from Imaris containers.Map
        [imgDesc, actionLog] = core.MibImage.splitImageDescription(imarisInfo('ImageDescription'));
        imageMeta = core.MibImage.initializeImgInfo( ...
            'Filename',         fullfile(obj.mibModel.currentDirectory, 'imaris_import.tif'), ...
            'ColorType',        imarisInfo('ColorType'), ...
            'ImageDescription', imgDesc, ...
            'ActionLog',        actionLog, ...
            'viewPort',         viewPort, ...
            'lutColors',        lutColors);

        id = obj.mibModel.getActiveId();
        obj.mibModel.I{id}.initialize(imageData, imageMeta, 'Standard', 'imageOnly', obj.mibModel.preferences.System.EnableSelection);
        obj.mibModel.I{id}.useLUT = true;

        notify(obj.mibModel, 'NewDataset');
        notify(obj.mibModel, 'ShowImage');
        
    case 'Omero'               % obj.handles.ribbonHome.importFromOmero
        utils.dlgs.showErrorDialog(obj.view.gui, 'Not implemented yet!', 'OMERO import');
        return;

    case 'URL / Zarr'                 % obj.handles.ribbonHome.importFromURL
        % Handles both an OME-Zarr container (browsed and opened as a
        % BigData/Virtual/Standard dataset) and an ordinary image URL, which
        % keeps the original imread behaviour - see
        % controllers.SelectFromUrl.openPlainImageUrl.
        obj.mibController.startController('controllers.SelectFromUrl');
end

end
