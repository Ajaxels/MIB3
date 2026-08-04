function restoreModelLayers(obj, snapshot)
% RESTOREMODELLAYERS - Put back label, selection and mask layers taken with copyModelLayers.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.restoreModelLayers(snapshot)
%
% Replaces the three segmentation layer objects with the copies held in
% ``snapshot``, restoring the model type along with the pixel data. The
% snapshot is copied again on the way in, so the same entry can be restored
% more than once (undo → redo → undo) without the history and the live
% dataset ending up sharing the same handle objects.
%
% Input Arguments:
%   - **snapshot** — structure produced by
%     :func:`core.MibDataset.copyModelLayers`
%
% **Example**
%
%   .. code-block:: matlab
%
%      snapshot = obj.mibModel.I{1}.copyModelLayers();
%      obj.mibModel.I{1}.restoreModelLayers(snapshot);
%
% See also :func:`core.MibDataset.copyModelLayers`

% Updates
%

obj.labels    = copy(snapshot.labels);
obj.selection = copy(snapshot.selection);
obj.mask      = copy(snapshot.mask);

obj.maskExist             = snapshot.maskExist;
obj.modelExist            = snapshot.modelExist;
obj.selectedMaterial      = snapshot.selectedMaterial;
obj.selectedAddToMaterial = snapshot.selectedAddToMaterial;
end
