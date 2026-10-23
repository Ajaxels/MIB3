function bioformatsCallback(obj, event)
% BIOFORMATSCALLBACK - update available filename extensions upon press of the BioFormats.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.bioformatsCallback(event)
%
% checkbox
%
% Also called when the prediction extension changes: for 'ZARR' (OME-Zarr v2/v3
% stores, which are folders) the Index field is relabelled 'Level' because it then
% selects the pyramid level (1 = full resolution), and the Bio checkbox is
% unticked and disabled. 'ZARR' is offered for prediction only; the 'ZARR2'/'ZARR3'
% entries of the standard extension list are removed from both lists.
%
% Input Arguments:
%   - **event** - an event structure of appdesigner
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.bioformatsCallback(%s): triggered\n', event.Source.Tag);
end
    extensionFieldName = 'ImageFilenameExtension';
    bioformatsFileName = 'Bioformats';
    indexFieldName = 'BioformatsIndex';
    if strcmp(event.Source.Tag, 'BioformatsTraining')
        extensionFieldName = 'ImageFilenameExtensionTraining';
        bioformatsFileName = 'BioformatsTraining';
        indexFieldName = 'BioformatsTrainingIndex';
    end

    obj.view.handles.(indexFieldName).Enable = 'on';
    if obj.BatchOpt.(bioformatsFileName)    % bio formats checkbox ticked
        obj.BatchOpt.(extensionFieldName){2} = upper(obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'BioFormats', false)); %{'AM', 'PNG', 'TIF'};
    else
        % zarr stores are folders: prediction lists them as one 'ZARR' entry
        % (the reader detects v2/v3 per store), training does not support them
        extensionList = upper(obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', false)); %{'LEI', 'ZVI'};
        extensionList = extensionList(~ismember(extensionList, {'ZARR2', 'ZARR3'}));
        if strcmp(extensionFieldName, 'ImageFilenameExtension')
            extensionList = sort([extensionList, {'ZARR'}]);
        end
        obj.BatchOpt.(extensionFieldName){2} = extensionList;
        %                 if strcmp(indexFieldName, 'BioformatsTrainingIndex')
        %                     obj.view.handles.(indexFieldName).Enable = 'off';
        %                 end
    end
    if ~ismember(obj.BatchOpt.(extensionFieldName)(1), obj.BatchOpt.(extensionFieldName){2})
        obj.BatchOpt.(extensionFieldName)(1) = obj.BatchOpt.(extensionFieldName){2}(1);
    end

    obj.view.Figure.(extensionFieldName).Items = obj.BatchOpt.(extensionFieldName){2};
    obj.view.Figure.(extensionFieldName).Value = obj.BatchOpt.(extensionFieldName){1};

    % for zarr images the index selects the pyramid level, and Bio-Formats is not used
    if strcmp(extensionFieldName, 'ImageFilenameExtension')
        if strcmp(obj.BatchOpt.ImageFilenameExtension{1}, 'ZARR')
            obj.view.handles.IndexEditField_2Label.Text = 'Level';
            obj.BatchOpt.Bioformats = false;
            obj.view.handles.Bioformats.Value = false;
            obj.view.handles.Bioformats.Enable = 'off';
        else
            obj.view.handles.IndexEditField_2Label.Text = 'Index';
            obj.view.handles.Bioformats.Enable = 'on';
        end
    end
end

