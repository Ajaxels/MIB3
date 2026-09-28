function updateImageDirectoryPath(obj, event)
% UPDATEIMAGEDIRECTORYPATH - update directories with images for training, prediction and.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateImageDirectoryPath(event)
%
% results

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.updateImageDirectoryPath(%s): triggered\n', event.Source.Tag);
end

    fieldName = event.Source.Tag;
    value = obj.view.Figure.(fieldName).Value;
    if isfolder(value) == 0; obj.view.Figure.(fieldName).Value = obj.BatchOpt.(fieldName); return; end
    obj.BatchOpt.(fieldName) = value;
end

