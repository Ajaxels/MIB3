function singleModelTrainingFileValueChanged(obj, event)
% SINGLEMODELTRAININGFILEVALUECHANGED - callback for press of SingleModelTrainingFile.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.singleModelTrainingFileValueChanged(event)
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.singleModelTrainingFileValueChanged: triggered\n');
end

    if nargin < 2; event.Source = obj.view.handles.SingleModelTrainingFile; end

    obj.updateBatchOptFromGUI(event);
    obj.view.handles.NumberOfClassesPreprocessing.Enable = 'on';
    if obj.BatchOpt.SingleModelTrainingFile
        
        obj.view.handles.ModelFilenameExtension.Enable = 'off';
        %obj.view.handles.MaskFilenameExtension.Enable = 'off';
        %obj.view.handles.NumberOfClassesPreprocessing.Enable = 'off';

        obj.view.handles.ModelFilenameExtension.Value = 'MODEL';
        obj.view.handles.MaskFilenameExtension.Value = 'MASK';
        event2.Source = obj.view.handles.ModelFilenameExtension;
        obj.updateBatchOptFromGUI(event2);
        event2.Source = obj.view.handles.MaskFilenameExtension;
        obj.updateBatchOptFromGUI(event2);
    else
        obj.view.handles.ModelFilenameExtension.Enable = 'on';
        obj.view.handles.MaskFilenameExtension.Enable = 'on';
    end
end

