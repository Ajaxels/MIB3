function updateImageDirectoryPath(obj, event)
% UPDATEIMAGEDIRECTORYPATH - update directories with images for training, prediction and.
%
% Syntax:
%   function updateImageDirectoryPath(obj, event)
%
% results
    fieldName = event.Source.Tag;
    value = obj.view.Figure.(fieldName).Value;
    if isfolder(value) == 0; obj.view.Figure.(fieldName).Value = obj.BatchOpt.(fieldName); return; end
    obj.BatchOpt.(fieldName) = value;
end

