function updatePreprocessingMode(obj)
% UPDATEPREPROCESSINGMODE - callback for change of selection in the Preprocess for dropdown.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updatePreprocessingMode()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.updatePreprocessingMode: triggered\n');
end

    obj.BatchOpt.PreprocessingMode{1} = obj.view.handles.PreprocessingMode.Value;
    % if strcmp(obj.view.handles.PreprocessingMode.Value, 'Preprocessing is not required') || strcmp(obj.view.handles.PreprocessingMode.Value, 'Split files for training/validation')
    %     obj.BatchOpt.MaskAway = false;
    %     obj.BatchOpt.SingleModelTrainingFile = false;
    % else
    %
    % end
    obj.updateWidgets();
end

