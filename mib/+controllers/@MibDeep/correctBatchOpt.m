function res = correctBatchOpt(obj, res)
    % function res = correctBatchOpt(obj, res)
    % correct loaded BatchOpt structure if it is not compatible
    % with the current version of DeepMIB
    %
    % Parameters:
    % res: BatchOpt structure loaded from a file

    % update res.BatchOpt to be compatible with DeepMIB v2.83
    if ~isfield(res.BatchOpt, 'Workflow')
        %obj.BatchOpt.Architecture = {};
        switch res.BatchOpt.Architecture{1}
            case {'2D U-net', '2D SegNet', '2D DLv3 Resnet18', '2D DeepLabV3 Resnet18', '2D DeepLabV3 Resnet50'}
                res.BatchOpt.Workflow = {'2D Semantic'};
                res.BatchOpt.Architecture{1} = res.BatchOpt.Architecture{1}(4:end);
                res.BatchOpt.Architecture{2} = obj.availableArchitectures('2D Semantic');
            case {'3D U-net', '3D U-net Anisotropic'}
                res.BatchOpt.Workflow = {'3D Semantic'};
                res.BatchOpt.Architecture{1} = res.BatchOpt.Architecture{1}(4:end);
                res.BatchOpt.Architecture{2} = obj.availableArchitectures('3D Semantic');
            case {'2D Patch-wise Resnet18', '2D Patch-wise Resnet50'}
                res.BatchOpt.Workflow = {'2D Patch-wise'};
                res.BatchOpt.Architecture{1} = res.BatchOpt.Architecture{1}(15:end);
                res.BatchOpt.Architecture{2} = obj.availableArchitectures('2D Patch-wise');
        end
        res.BatchOpt.Workflow{2} = obj.BatchOpt.Workflow{2}; % {'2D U-net', '2D SegNet', '2D DLv3 Resnet18', '3D U-net', '3D U-net Anisotropic', '2D Patch-wise Resnet18', '2D Patch-wise Resnet50'}
    end

    % correct Architecture names
    if obj.mibController.mibVersionNumeric > 2.9020
        % replace DeepLabV3 to DeepLabV3+ from MIB v2.9020
        switch res.BatchOpt.Architecture{1}
            case {'Segnet', 'Unet'}

            case {'DLv3 Resnet18', 'DeepLabV3 Resnet18'}
                res.BatchOpt.Architecture{1} = 'DeepLab v3+';
                res.BatchOpt.Architecture{2} = obj.availableArchitectures('2D Semantic');
                res.BatchOpt.T_EncoderNetwork{1} = 'Resnet18';
                res.BatchOpt.T_EncoderNetwork{2} = {'Resnet18', 'Resnet50', 'Xception', 'InceptionResnetv2'};
            case {'DLv3 Resnet50', 'DeepLabV3 Resnet50'}
                res.BatchOpt.Architecture{1} = 'DeepLab v3+';
                res.BatchOpt.Architecture{2} = obj.availableArchitectures('2D Semantic');
                res.BatchOpt.T_EncoderNetwork{1} = 'Resnet50';
                res.BatchOpt.T_EncoderNetwork{2} = {'Resnet18', 'Resnet50', 'Xception', 'InceptionResnetv2'};
            case {'DLv3 Xception', 'DeepLabV3 Xception'}
                res.BatchOpt.Architecture{1} = 'DeepLab v3+';
                res.BatchOpt.Architecture{2} = obj.availableArchitectures('2D Semantic');
                res.BatchOpt.T_EncoderNetwork{1} = 'Xception';
                res.BatchOpt.T_EncoderNetwork{2} = {'Resnet18', 'Resnet50', 'Xception', 'InceptionResnetv2'};
            case {'DLv3 Inception-ResNet-v2', 'DeepLabV3 Inception-ResNet-v2'}
                res.BatchOpt.Architecture{1} = 'DeepLab v3+';
                res.BatchOpt.Architecture{2} = obj.availableArchitectures('2D Semantic');
                res.BatchOpt.T_EncoderNetwork{1} = 'InceptionResnetv2';
                res.BatchOpt.T_EncoderNetwork{2} = {'Resnet18', 'Resnet50', 'Xception', 'InceptionResnetv2'};
            case {'Z2C + DLv3 Resnet18', 'Z2C + DLv3 Resnet50'}
                res.BatchOpt.T_EncoderNetwork{1} = res.BatchOpt.Architecture{1}(end-7:end);
                res.BatchOpt.T_EncoderNetwork{2} = {'Resnet18', 'Resnet50'};
                res.BatchOpt.Architecture{1} = 'Z2C + DLv3';
                res.BatchOpt.Architecture{2} = obj.availableArchitectures('2.5D Semantic');
        end
    elseif obj.mibController.mibVersionNumeric >= 2.85
        % replace DeepLabV3 to DLv3 from MIB v2.85
        res.BatchOpt.Architecture{1} = strrep(res.BatchOpt.Architecture{1}, 'DeepLabV3', 'DLv3');
    end

    switch res.BatchOpt.Architecture{1}
        case {'3DC+DLv3 Resnet18', '3DUnet+DLv3 Resnet18'}
            mgsOpt.MsgBoxOnly = true;
            header = sprintf('This architecture (%s) is not available in the current version of MIB', res.BatchOpt.Architecture{1}');
            mgsOpt.Icon = 'puffin_error';
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong architecture!', mgsOpt);
            return;
        end

    if ~isfield(res.AugOpt2DStruct, 'RandScale') || ~isstruct(res.AugOpt2DStruct.RandScale)
        res.AugOpt2DStruct = mibDeepConvertOldAugmentationSettingsToNew(res.AugOpt2DStruct, '2D');
    end
    if ~isfield(res.AugOpt3DStruct, 'RandScale') || ~isstruct(res.AugOpt3DStruct.RandScale)
        res.AugOpt3DStruct = mibDeepConvertOldAugmentationSettingsToNew(res.AugOpt3DStruct, '3D');
    end
end

