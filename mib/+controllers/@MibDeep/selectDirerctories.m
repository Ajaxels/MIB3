function selectDirerctories(obj, event)
% SELECTDIRERCTORIES - select directories containing images for training and prediction.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.selectDirerctories(event)
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.selectDirerctories(%s): triggered\n', event.Source.Tag);
end

    switch event.Source.Tag
        case 'SelectOriginalTrainingImagesDir'
            fieldName = 'OriginalTrainingImagesDir';
            title = 'Select directory with images and models for training';
        case 'SelectOriginalPredictionImagesDir'
            fieldName = 'OriginalPredictionImagesDir';
            title = 'Select directory with images for prediction';
        case 'SelectResultingImagesDir'
            fieldName = 'ResultingImagesDir';
            title = 'Select directory for results';
    end
    selpath = uigetdir(obj.BatchOpt.(fieldName), title);
    if selpath == 0; return; end
    
    % the two following commands are fix of sending the DeepMIB
    % window behind main MIB window
    drawnow;
    figure(obj.view.gui);
    obj.BatchOpt.(fieldName) = selpath;
    obj.view.Figure.(fieldName).Value = selpath;
end

