function saveStarDistNetwork(obj, networkFilename, net, config, inputPatchSize)
% SAVESTARDISTNETWORK - Write a StarDist network file with the usual DeepMIB variables and StarDistConfig.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.saveStarDistNetwork(networkFilename, net, config, inputPatchSize)
%
% Writes the ``.mibDeep`` file of a StarDist network of the 2D Instance workflow. Used by
% :func:`startTrainingStarDist` after training and by :func:`createStarDistFromPretrained` for
% a pretrained model used without training, so both files are read the same way by
% :func:`startPredictionInstances` (which recognises a StarDist network by ``StarDistConfig``),
% :func:`selectNetwork`, Check network and continued training.
%
% Variables of the file (``-v7.3``):
%
% - ``net`` - the StarDist ``dlnetwork`` (deepmib.stardist.createNetwork);
% - ``StarDistConfig`` - ``config``, the deepmib.stardist.defaultConfig struct of the network,
%   including ``probThresh``, ``nmsThresh`` and ``pretrainedModel``;
% - ``StarDistOpt`` - the current ``obj.StarDistOpt``;
% - ``TrainingOptStruct``, ``AugOpt2DStruct``, ``AugOpt3DStruct``, ``InputLayerOpt``,
%   ``ActivationLayerOpt``, ``SegmentationLayerOpt``, ``DynamicMaskOpt``,
%   ``OverlapInstancesOpt``, ``BatchOpt`` - the current DeepMIB settings, as in the networks of
%   the other workflows;
% - ``classNames`` = ``{'object'}``, ``classColors`` - the first model material colour;
% - ``inputPatchSize``, ``outputPatchSize`` = ``[patchSize./grid, 1, 1 + nRays]``;
% - ``mibVersion``.
%
% Input Arguments:
%   - **networkFilename** - [char] full name of the ``.mibDeep`` file; overwritten when it exists
%   - **net** - [dlnetwork] StarDist network
%   - **config** - [struct] StarDist configuration of the network (deepmib.stardist.defaultConfig)
%   - **inputPatchSize** - [numeric] ``[height width depth colors]`` stored as ``inputPatchSize``
%
% Output Arguments:
%   (none); errors of ``save`` are passed to the caller

StarDistConfig = config;
StarDistOpt = obj.StarDistOpt;
TrainingOptStruct = obj.TrainingOpt;
AugOpt2DStruct = obj.AugOpt2D;
AugOpt3DStruct = obj.AugOpt3D;
InputLayerOpt = obj.InputLayerOpt;
ActivationLayerOpt = obj.ActivationLayerOpt;
SegmentationLayerOpt = obj.SegmentationLayerOpt;
DynamicMaskOpt = obj.DynamicMaskOpt;
OverlapInstancesOpt = obj.OverlapInstancesOpt;
classNames = {'object'};
classColors = obj.modelMaterialColors(1, :);
outputPatchSize = [config.patchSize ./ config.grid, 1, 1 + config.nRays];
BatchOpt = obj.BatchOpt;
mibVersion.mibVersion = obj.mibController.mibVersion;
mibVersion.mibVersionNumeric = obj.mibController.mibVersionNumeric;
save(networkFilename, 'net', 'StarDistConfig', 'StarDistOpt', 'TrainingOptStruct', ...
    'AugOpt2DStruct', 'AugOpt3DStruct', 'InputLayerOpt', 'ActivationLayerOpt', 'SegmentationLayerOpt', ...
    'DynamicMaskOpt', 'OverlapInstancesOpt', 'classNames', 'classColors', 'inputPatchSize', ...
    'outputPatchSize', 'BatchOpt', 'mibVersion', '-mat', '-v7.3');
end
