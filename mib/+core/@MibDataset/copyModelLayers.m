function snapshot = copyModelLayers(obj)
% COPYMODELLAYERS - Take an independent copy of the label, selection and mask layers.
%
% Syntax:
%   .. code-block:: matlab
%
%       snapshot = obj.copyModelLayers()
%
% Returns deep copies of the three segmentation layer objects together with
% the flags that describe them. Unlike a pixel snapshot taken with
% :func:`core.MibDataset.getData3D`, this keeps the **layer objects
% themselves** — so the model type (63 / 255 / 65535 / 4294967295), the
% material names and colours and the selected material all travel with the
% snapshot.
%
% This is what makes the ``'modelLayers'`` undo entry immune to model-type
% changes: in a type-63 model the mask and selection live in bits 7-8 of
% ``obj.labels``, in the larger types they are standalone layers, and a pixel
% snapshot taken under one arrangement cannot be written back under the other.
%
% Only meaningful for ``'Standard'`` datasets — the Virtual and BigData label
% layers are backed by on-demand readers that must not be duplicated.
%
% Output Arguments:
%   - **snapshot** — structure with fields ``labels``, ``selection``, ``mask``
%     (independent copies of the layer objects), ``maskExist``,
%     ``modelExist``, ``selectedMaterial``, ``selectedAddToMaterial``
%
% **Example** — snapshot the layers, then restore them
%
%   .. code-block:: matlab
%
%      snapshot = obj.mibModel.I{1}.copyModelLayers();
%      % ... an operation that replaces obj.labels with a different model type
%      obj.mibModel.I{1}.restoreModelLayers(snapshot);
%
% See also :func:`core.MibDataset.restoreModelLayers`

% Updates
%

snapshot = struct( ...
    'labels',                copy(obj.labels), ...
    'selection',             copy(obj.selection), ...
    'mask',                  copy(obj.mask), ...
    'maskExist',             obj.maskExist, ...
    'modelExist',            obj.modelExist, ...
    'selectedMaterial',      obj.selectedMaterial, ...
    'selectedAddToMaterial', obj.selectedAddToMaterial);
end
