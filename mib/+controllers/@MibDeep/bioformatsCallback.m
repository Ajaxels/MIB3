function bioformatsCallback(obj, event)
    % function bioformatsCallback(obj, event)
    % update available filename extensions upon press of the BioFormats
    % checkbox
    %
    % Parameters:
    % event: an event structure of appdesigner

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
        obj.BatchOpt.(extensionFieldName){2} = upper(obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', false)); %{'LEI', 'ZVI'};
    else
        obj.BatchOpt.(extensionFieldName){2} = upper(obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'BioFormats', false)); %{'AM', 'PNG', 'TIF'};
        %                 if strcmp(indexFieldName, 'BioformatsTrainingIndex')
        %                     obj.view.handles.(indexFieldName).Enable = 'off';
        %                 end
    end
    if ~ismember(obj.BatchOpt.(extensionFieldName)(1), obj.BatchOpt.(extensionFieldName){2})
        obj.BatchOpt.(extensionFieldName)(1) = obj.BatchOpt.(extensionFieldName){2}(1);
    end

    obj.view.Figure.(extensionFieldName).Items = obj.BatchOpt.(extensionFieldName){2};
    obj.view.Figure.(extensionFieldName).Value = obj.BatchOpt.(extensionFieldName){1};
end

