function toggleAugmentations(obj)
% TOGGLEAUGMENTATIONS - callback for press of the T_augmentation checkbox.
%
% Syntax:
%   function toggleAugmentations(obj)
%
    if obj.view.handles.T_augmentation.Value == 1
        obj.view.handles.Augmentation2DSettings.Enable = 'on';
        obj.view.handles.Augmentation3DSettings.Enable = 'on';
        obj.view.handles.T_AugmentationPreview.Enable = 'on';
        obj.view.handles.T_AugmentationPreviewSettings.Enable = 'on';
    else
        obj.view.handles.Augmentation2DSettings.Enable = 'off';
        obj.view.handles.Augmentation3DSettings.Enable = 'off';
        obj.view.handles.T_AugmentationPreview.Enable = 'off';
        obj.view.handles.T_AugmentationPreviewSettings.Enable = 'off';
    end
    obj.BatchOpt.T_augmentation = logical(obj.view.handles.T_augmentation.Value);
end

