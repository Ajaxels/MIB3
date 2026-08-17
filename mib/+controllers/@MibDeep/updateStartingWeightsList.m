function updateStartingWeightsList(obj)
% UPDATESTARTINGWEIGHTSLIST - refresh the "Starting weights" dropdown for the current network design.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateStartingWeightsList()
%
% Where the initial weights of a network come from, and how much of the network is
% retrained, is a property of the **(workflow, architecture, encoder)** combination
% rather than a free choice. This method rebuilds ``BatchOpt.T_StartingWeights{2}``
% (the list of states that are actually possible for the current design), reconciles
% ``{1}`` when the previous value is no longer in the list, and enables the dropdown
% only where a genuine choice exists.
%
% Combinations that offer no choice still **display their single truthful value** in a
% disabled dropdown, rather than being blanked or hidden: a network that is silently
% ImageNet-pretrained (DeepLab v3+) or that trains with a frozen backbone (SOLOv2)
% should say so.
%
% Available states:
%   - ``'None (random)'`` - weights are initialized randomly
%   - ``'Pretrained'`` - the network starts from an already trained template. What that
%     template is depends on the design: DeepLab v3+ with a Resnet encoder downloads a
%     MIB-hosted template and asks whether to fetch the **Electron Microscopy**
%     (``_sbem``) or **Light microscopy/Pathology** (``_pathology``) variant, while the
%     U-net Resnet encoders come from ``mib.helsinki.fi/web-update/encoders``. The
%     template is cached in ``preferences.ExternalDirs.DeepMIBDir`` and reused silently
%     afterwards, so which variant is in use is **not** recorded in the config and
%     cannot be reported here.
%   - ``'ImageNet'`` - 2D Patch-wise classification networks initialized from the
%     MathWorks ImageNet-pretrained weights (requires the matching support package)
%   - ``'COCO, frozen then trainable'`` *(default)* - the two-phase schedule: train with the
%     backbone frozen, then unfreeze it and continue at a much lower rate. Phase 1 ends as
%     soon as the training loss goes flat, or at a cap, whichever comes first; the epochs it
%     does not use go to phase 2. Configured through ``obj.StartingWeightsOpt``
%     (see :func:`setStartingWeightsSettings`) and run by :func:`startTrainingInstances`
%   - ``'COCO, trainable backbone'`` - SOLOv2 from COCO weights, the whole
%     network keeps training (``trainSOLOV2(..., 'FreezeSubNetwork', 'none')``), so the
%     features adapt to microscopy data. **The initial learning rate must come down to
%     about 1e-4**: at the rates that suit a frozen backbone (1e-3 to 1e-2) the pretrained
%     backbone is destroyed within the first hundred iterations, the loss flatlines and
%     the network detects nothing. The reliable way to use it is to continue training an
%     already trained frozen network, which applies the current freeze setting to the
%     restored weights (see :func:`startTrainingInstances`)
%   - ``'COCO, frozen backbone'`` - SOLOv2 from COCO weights, the backbone stays at its
%     COCO values (``'FreezeSubNetwork', 'backbone'``); faster, tolerant of a high
%     learning rate and less prone to overfitting on very small datasets
%
% ``'ImageNet'`` is dropped from the list in the deployed (standalone) version, where
% the pretrained networks are not shipped - see :func:`createNetwork`.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%

randomWeights = 'None (random)';
pretrainedWeights = 'Pretrained';
imagenetWeights = 'ImageNet';

% by default a design offers no choice and starts from random weights
itemsList = {randomWeights};

switch obj.BatchOpt.Workflow{1}
    case {'2D Semantic', '2.5D Semantic'}
        switch obj.BatchOpt.Architecture{1}
            case {'DeepLab v3+', 'Z2C + DLv3', '3DC + DLv3 Resnet18'}
                % generateDeepLabV3Network downloads a MIB template (EM or LM variant)
                % for the Resnet encoders, and falls back to deeplabv3plusLayers on a
                % pretrained base network for xception / inceptionresnetv2
                itemsList = {pretrainedWeights};
            case {'U-net +Encoder', 'Z2C + U-net +Encoder'}
                % 'Classic' builds a plain unet, the Resnet encoders are downloaded
                % pretrained by generateUnet2DwithEncoder
                if strcmp(obj.BatchOpt.T_EncoderNetwork{1}, 'Classic')
                    itemsList = {randomWeights};
                else
                    itemsList = {pretrainedWeights};
                end
            otherwise   % SegNet, U-net, Z2C + U-net
                itemsList = {randomWeights};
        end
    case '3D Semantic'
        % no pretrained 3D networks are available
        itemsList = {randomWeights};
    case '2D Patch-wise'
        % the only workflow where the user picks; the pretrained classification
        % networks are not shipped with the standalone version
        if isdeployed
            itemsList = {randomWeights};
        else
            itemsList = {randomWeights, imagenetWeights};
        end
    case '2D Instance'
        % solov2() can only be built from a named COCO-pretrained detector, so random
        % initialization is not offered; the choice is what happens to the backbone.
        % The two-phase schedule is first, i.e. the default, because it measured best on
        % the mitochondria benchmark (validation mAP 0.76 against 0.00 for a backbone
        % unfrozen from the start at the rate that suits a frozen one)
        itemsList = {'COCO, frozen then trainable', 'COCO, frozen backbone', 'COCO, trainable backbone'};
end

obj.BatchOpt.T_StartingWeights{2} = itemsList;
% keep the current selection when it is still possible, otherwise fall back to the
% first item, exactly as Architecture is reconciled when the workflow changes
if ~ismember(obj.BatchOpt.T_StartingWeights{1}, itemsList)
    obj.BatchOpt.T_StartingWeights{1} = itemsList{1};
end

obj.view.handles.T_StartingWeights.Items = obj.BatchOpt.T_StartingWeights{2};
obj.view.handles.T_StartingWeights.Value = obj.BatchOpt.T_StartingWeights{1};
if numel(itemsList) > 1
    obj.view.handles.T_StartingWeights.Enable = 'on';
else
    obj.view.handles.T_StartingWeights.Enable = 'off';
end

% the settings button only configures the two-phase schedule, so it is meaningless for
% every other state
if strcmp(obj.BatchOpt.T_StartingWeights{1}, 'COCO, frozen then trainable')
    obj.view.handles.T_StartingWeightsSettings.Enable = 'on';
else
    obj.view.handles.T_StartingWeightsSettings.Enable = 'off';
end
end
