function loss = lossFunction(Y, T, config)
% LOSSFUNCTION - StarDist training loss: probability cross-entropy plus masked ray-distance error.
%
% Syntax:
%   .. code-block:: matlab
%
%      loss = deepmib.stardist.lossFunction(Y, T, config)
%      net = trainnet(datastore, net, @(Y, T) deepmib.stardist.lossFunction(Y, T, config), options)
%
% Reproduces the StarDist 0.9.2 loss with ``train_dist_loss = 'mae'``
% (``StarDistBase.prepare_for_training``, ``masked_loss_mae``):
%
% ``loss = w(1) * probLoss + w(2) * distLoss`` with ``w = config.trainLossWeights``, where
%
% - ``probLoss`` = mean over all pixels of the binary cross-entropy between the predicted
%   probability and the **soft** target (the normalised EDT, not a binary mask). As Keras
%   ``binary_crossentropy``, the prediction is clipped to ``[1e-7, 1-1e-7]`` and ``1e-7`` is
%   added inside both logarithms.
% - ``distLoss`` = mean over pixels of
%   ``mean_rays(mask .* |dTrue - dPred|) / (mean(mask) + 1e-7) + reg * mean_rays((1-mask) .* |dPred|)``
%   with ``mask`` = the probability target, ``mean(mask)`` taken over the whole mini-batch and
%   ``reg = config.trainBackgroundReg``. The first term weighs distance errors by how central
%   the pixel is in its object; the second pulls predicted distances towards 0 with the weight
%   ``1 - mask``: fully in the background, and a little near object edges and even inside
%   objects, since the soft mask is below 1 everywhere but at the object centre.
%
% Input Arguments:
%   - **Y** - [dlarray] network output ``[h w 1+nRays B]``: probability (after the sigmoid) in
%     channel 1, distances in channels ``2:end``
%   - **T** - [numeric or dlarray] targets of the same size, see deepmib.stardist.computeTargets
%   - **config** - [struct] configuration, see deepmib.stardist.defaultConfig; uses
%     ``.trainLossWeights`` and ``.trainBackgroundReg``
%
% Output Arguments:
%   - **loss** - [dlarray] scalar loss

epsilon = 1e-7;
weights = config.trainLossWeights;

probPred = Y(:, :, 1, :);
distPred = Y(:, :, 2:end, :);
probTrue = T(:, :, 1, :);
distTrue = T(:, :, 2:end, :);

probClipped = min(max(probPred, epsilon), 1 - epsilon);
crossEntropy = -(probTrue .* log(probClipped + epsilon) + (1 - probTrue) .* log(1 - probClipped + epsilon));
probLoss = mean(crossEntropy, 'all');

mask = probTrue;
maskedError = mean(mask .* abs(distTrue - distPred), 3);
backgroundPenalty = mean((1 - mask) .* abs(distPred), 3);
distLoss = mean(maskedError / (mean(mask, 'all') + epsilon) + config.trainBackgroundReg * backgroundPenalty, 'all');

loss = weights(1) * probLoss + weights(2) * distLoss;
end
