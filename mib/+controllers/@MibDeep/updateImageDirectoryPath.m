function updateImageDirectoryPath(obj, event)
    % function updateImageDirectoryPath(obj, event)
    % update directories with images for training, prediction and
    % results
    fieldName = event.Source.Tag;
    value = obj.view.Figure.(fieldName).Value;
    if isfolder(value) == 0; obj.view.Figure.(fieldName).Value = obj.BatchOpt.(fieldName); return; end
    obj.BatchOpt.(fieldName) = value;
end

