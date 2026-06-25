function model_Callbacks(obj, hWidget, hData)
% MODEL_CALLBACKS - callbacks on press of buttons in the Model ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.model_Callbacks(hWidget, hData)
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
    fprintf('controllers.MibRibbon.model_Callbacks: Model ribbon -> %s\n', mode);
end

BatchOpt = struct();
switch mode
    % -------------- Convert model section --------------
    case {'63 materials', '255 materials', '65535 materials', '4294967295 materials'}
        BatchOpt.ModelType = {strrep(mode, ' materials', '')};
        obj.mibModel.convertModel([], BatchOpt);
    case '2D objects conn4'
        BatchOpt.ModelType = {'indexed objects 2D/4'};
        obj.mibModel.convertModel([], BatchOpt);
    case '2D objects conn8'
        BatchOpt.ModelType = {'indexed objects 2D/8'};
        obj.mibModel.convertModel([], BatchOpt);
    case '3D objects conn4'
        BatchOpt.ModelType = {'indexed objects 3D/6'};
        obj.mibModel.convertModel([], BatchOpt);
    case '3D objects conn8'
        BatchOpt.ModelType = {'indexed objects 3D/26'};
        obj.mibModel.convertModel([], BatchOpt);

    %% -------------- Model import section --------------
    case sprintf('New\nmodel')      % obj.handles.ribbonModel.new
        obj.mibModel.createModel();
    case sprintf('Load\nmodel')     % obj.handles.ribbonModel.load
        obj.mibModel.loadModel();
    case {'Import', 'Import model from MATLAB'}   % obj.handles.ribbonModel.import
        obj.mibModel.importDataset('model');
    case 'Import model from another MIB dataset'    % obj.handles.ribbonModel.importFromMIB
        obj.mibModel.importDatasetFromMib('model');
    
    %% -------------- Model export section --------------
    case {'Export', 'Export model to MATLAB'}    % obj.handles.ribbonModel.export or obj.handles.ribbonModel.exportToMatlab
        obj.mibModel.exportDataset('model');
    case 'Export model to Imaris as volume'      % obj.handles.ribbonModel.exportToImaris
        obj.mibModel.exportDatasetToImaris('model');
    case 'Export model to another MIB dataset'   % obj.handles.ribbonModel.exportToMIB
        obj.mibModel.exportDatasetToMib('model');
    case 'Export model to Zarr3'                  % obj.handles.ribbonModel.exportToZarr3
        parentFig = obj.mibModel.getProgressBarParent();
        id = obj.mibModel.getActiveId();
        ds = obj.mibModel.I{id};
        if ~ds.modelExist
            utils.dlgs.showErrorDialog(parentFig, 'There is no model to export.', 'Export model to Zarr3');
            return;
        end
        [imgPath, imgStem] = fileparts(ds.image.filename);
        if isempty(imgPath); imgPath = obj.mibModel.currentDirectory; end
        if isempty(imgStem); imgStem = 'dataset'; end
        [zFile, zDir] = uiputfile({'*.zarr3', 'OME-Zarr v3 (*.zarr3)'}, ...
            'Export model to Zarr3', fullfile(imgPath, ['Labels_' imgStem '.zarr3']));
        if isequal(zFile, 0); return; end
        datasetInfo = struct('Y', ds.image.height, 'X', ds.image.width, 'Z', ds.image.depth, ...
            'pixSize', ds.image.pixSize);
        zOpt = io.savers.Zarr3Saver.optionsDialog(parentFig, obj.mibModel.mibPath, true, datasetInfo);
        if isempty(zOpt); return; end   % cancelled the settings dialog
        wb = uiprogressdlg(parentFig, 'Title', 'Export model to Zarr3', ...
            'Message', 'Writing OME-Zarr v3 pyramid, please wait...', 'Indeterminate', 'on');
        try
            io.savers.Zarr3Saver.exportModel(obj.mibModel, id, fullfile(zDir, zFile), zOpt);
            delete(wb);
            uialert(parentFig, sprintf('Model exported to:\n%s', fullfile(zDir, zFile)), ...
                'Export model to Zarr3', 'Icon', 'success');
        catch ME
            if isvalid(wb); delete(wb); end
            utils.dlgs.showErrorDialog(parentFig, ME.message, 'Export model to Zarr3 failed');
        end
    case sprintf('Save\nmodel')                                  % obj.handles.ribbonModel.save — save using existing filename
        activeId = obj.mibModel.getActiveId();
        if strcmp(obj.mibModel.I{activeId}.datasetType, 'BigData')
            % BigData model lives on disk as a pyramid; pixel edits are written live.
            % Offer two ways to persist, since full finalization can be lengthy:
            %   Finalize & save — materialize every resolution level (consistent at all
            %                     zooms; needed for export / external readers). Slow on
            %                     a large slide.
            %   Save sidecar    — write only the small level-map side-file (fast). A
            %                     crash-safety checkpoint: the level map is the only
            %                     volatile state, so persisting it lets a reopen rebuild
            %                     the deferred finer levels correctly.
            questOpt = struct('WindowStyle', 'modal', 'mibPath', obj.mibModel.mibPath, ...
                'WindowHeight', 250, ...
                'HelpUrl', 'https://mib.helsinki.fi/help/main3/getting-started/dataset-types/index.html');
            answer = utils.dlgs.inputQuestDlg(obj.mibModel.getProgressBarParent(), ...
                sprintf(['How would you like to save the BigData model?\n\n' ...
                '• Finalize & save — materialize every resolution level so the model is ' ...
                'consistent at all zooms (needed for export and external readers). On a ' ...
                'large slide this can take a while.\n\n' ...
                '• Save sidecar — quickly write only the level-map file. Edits are already ' ...
                'on disk; this is a fast crash-safety checkpoint so a reopen restores the ' ...
                'model precisely without re-materializing.']), ...
                'Save model', 'Finalize & save', 'Save sidecar', 'Cancel', 'Save sidecar', questOpt);
            switch answer
                case 'Finalize & save'
                    obj.mibModel.saveBigDataModel(activeId, 'full');
                case 'Save sidecar'
                    obj.mibModel.saveBigDataModel(activeId, 'sidecar');
                otherwise   % 'Cancel' or dialog closed
                    return;
            end
            return;
        end
        if isempty(obj.mibModel.I{activeId}.labels.filename)
            obj.mibModel.saveLabels([]);   % no filename yet — show Save As dialog
        else
            % confirm before overwriting the existing model file
            [~, modelName, modelExt] = fileparts(obj.mibModel.I{activeId}.labels.filename);
            questOpt = struct('WindowStyle', 'modal', 'mibPath', obj.mibModel.mibPath);
            answer = utils.dlgs.inputQuestDlg(obj.mibModel.getProgressBarParent(), ...
                sprintf('Overwrite the existing model file?\n\n%s%s', modelName, modelExt), ...
                'Save model', 'Overwrite', 'Save as...', 'Cancel', 'Overwrite', questOpt);
            switch answer
                case 'Overwrite'
                    obj.mibModel.saveLabels();
                case 'Save as...'
                    obj.mibModel.saveLabels([]);   % prompt for a new filename
                otherwise   % 'Cancel' or dialog closed
                    return;
            end
        end
    case sprintf('Save\nmodel as...')            % obj.handles.ribbonModel.saveAs — save with dialog
        obj.mibModel.saveLabels([]);

    %% -------------- Materials section --------------
    case 'Rename material'      % obj.handles.ribbonModel.matRename
        obj.mibModel.materialsActions('Rename material');
    case 'Add material'      % obj.handles.ribbonModel.matAdd
        obj.mibModel.materialsActions('Add material');
    case 'Insert material'    % obj.handles.ribbonModel.matInsert
        obj.mibModel.materialsActions('Insert material');
    case 'Swap materials'      % obj.handles.ribbonModel.matSwap
        obj.mibModel.materialsActions('Swap materials');
    case 'Reorder materials'      % obj.handles.ribbonModel.matReorder
        obj.mibModel.materialsActions('Reorder materials');
    case 'Export material'    % obj.handles.ribbonModel.matExport
        obj.mibModel.materialsActions('Export material');
    case 'Save material to file'      % obj.handles.ribbonModel.matSave
        obj.mibModel.materialsActions('Save material to file');
    case 'Remove materials'      % obj.handles.ribbonModel.matRemove
        obj.mibModel.materialsActions('Remove material');
    
    %% -------------- Annotations section --------------
    case {sprintf('List of\nannotations'), 'List of annotations'}      % obj.handles.ribbonModel.annotations or obj.handles.ribbonModel.annotationsList
        obj.mibController.startController('controllers.Annotations');
    case 'Export to Imaris as Spots'    % obj.handles.ribbonModel.annotationsImaris

    case 'Remove all annotations'    % obj.handles.ribbonModel.annotationsRemove
        obj.mibModel.deleteAnnotations();
    
    %% -------------- Model rendering section --------------
    case {'Render', 'MIB rendering'}      % obj.handles.ribbonModel.render or obj.handles.ribbonModel.renderMIB
        menuEntry.Tag = 'materialsTableContextRenMIB';
        menuEntry.Text = 'Ribbon->Models->Rendering->MIB Rendering';
        obj.mibController.cSegmentation.materialsTable_ContextMenu(menuEntry);
    case 'MATLAB isosurface'      % obj.handles.ribbonModel.renderMatlab
        obj.mibController.cSegmentation.renderIsosurface();
    case 'MATLAB isosurface and export to Imaris'      % obj.handles.ribbonModel.renderMatlabImaris

    case 'MATLAB volume viewer'      % obj.handles.ribbonModel.renderMatlabVolView
        if isdeployed
            utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                'Rendering in the MATLAB VolumeViewer app is only available for the MATLAB version of MIB', ...
                'Not available');
            return;
        end
        activeId = obj.mibModel.getActiveId();
        if obj.mibModel.I{activeId}.showAllMaterials == 1
            materialIndex = NaN;
        else
            materialIndex = obj.mibModel.I{activeId}.getSelectedMaterialIndex();
        end
        img = cell2mat(obj.mibModel.getData3D('labels', [], 3, materialIndex));

        answer = utils.dlgs.inputQuestDlg(obj.mibModel.getProgressBarParent(), ...
            'Would you like to export the model as a volume for volume rendering or as materials together with the original dataset?', ...
            'Render model', 'As Volume', 'As materials', 'Cancel', 'As Volume');
        if strcmp(answer, 'Cancel'); return; end

        pixSize = obj.mibModel.I{activeId}.image.pixSize;
        if strcmp(answer, 'As Volume')
            tform = zeros(4);
            tform(1,1) = pixSize.x;
            tform(2,2) = pixSize.y;
            tform(3,3) = pixSize.z;
            tform(4,4) = 1;
            %#exclude volumeViewer
            volumeViewer(img, tform);
        else
            volume = cell2mat(obj.mibModel.getData3D('image', [], 3));
            if size(volume, 4) > 1
                utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
                    sprintf('Volume viewer is not compatible with multicolor images;\nplease keep only a single color channel displayed and try again!'), ...
                    'Not implemented');
                return;
            end
            %#exclude volumeViewer
            volumeViewer(squeeze(volume), img, 'ScaleFactors', [pixSize.x pixSize.y pixSize.z]);
        end

    case 'Fiji volume viewer'      % obj.handles.ribbonModel.renderFiji
        menuEntry.Tag = 'materialsTableContextRenFiji';
        menuEntry.Text = 'Ribbon->Models->Rendering->Fiji volume viewer';
        obj.mibController.cSegmentation.materialsTable_ContextMenu(menuEntry);
    case 'Imaris surface'      % obj.handles.ribbonModel.renderImaris
        id = obj.mibModel.getActiveId();
        if obj.mibModel.I{id}.showAllMaterials == 1
            options.materialIndex = 0;
        else
            options.materialIndex = obj.mibModel.I{id}.getSelectedMaterialIndex();
        end
        obj.mibModel.connImaris = io.imaris.renderModelImaris(obj.mibModel.I{id}, obj.mibModel.connImaris, options);

    %% -------------- Quantification section --------------
    case 'Quantify'
        obj.mibController.startController('controllers.Quantification');

end


end
