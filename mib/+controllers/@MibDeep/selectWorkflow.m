function selectWorkflow(obj, event)
% SELECTWORKFLOW - select deep learning workflow to perform.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.selectWorkflow(event)
%
    if nargin < 2; event.Source = obj.view.handles.Workflow; end
    obj.updateBatchOptFromGUI(event);

    obj.view.handles.MaskAway.Enable = 'on';
    obj.view.handles.MaskFilenameExtension.Enable = 'on';

    switch obj.BatchOpt.Workflow{1}
        case '2D Semantic'
            obj.BatchOpt.Architecture{2} = obj.availableArchitectures(obj.BatchOpt.Workflow{1});
        case '2.5D Semantic'
            obj.BatchOpt.Architecture{2} = obj.availableArchitectures(obj.BatchOpt.Workflow{1});
        case '3D Semantic'
            obj.BatchOpt.Architecture{2} = obj.availableArchitectures(obj.BatchOpt.Workflow{1});
        case '2D Patch-wise'
            obj.BatchOpt.Architecture{2} = obj.availableArchitectures(obj.BatchOpt.Workflow{1});
            obj.view.handles.MaskAway.Enable = 'off';
            obj.view.handles.MaskFilenameExtension.Enable = 'off';
        case '2D Instance'
            obj.BatchOpt.Architecture{2} = obj.availableArchitectures(obj.BatchOpt.Workflow{1});
    end
    obj.view.handles.Architecture.Items = obj.BatchOpt.Architecture{2};
    obj.selectArchitecture();
end

