function saveBigDataModel(obj, id)
% function saveBigDataModel(obj, id)
% Finalize a BigData model: materialize every pyramid level from the level map
% and persist the level-map side-file, so the on-disk model is fully consistent
% at all resolutions (correct for export and any external reader).
%
% During interactive segmentation a BigData model is only written at the level
% each edit was drawn (+ coarser); finer levels are reconstructed on demand
% (see ``core.MibBigDataLabels.getData63`` / ``materializeForRead``). This method
% performs the deferred work for every level at once.
%
% Parameters:
% id: [@em optional] index of the dataset; when omitted uses
% ``obj.getActiveId()``.
%
% Return values:
%
%
% @note no-op for non-BigData datasets or when no model exists.

% Updates
%

if nargin < 2; id = obj.getActiveId(); end

dataset = obj.I{id};
if ~strcmp(dataset.datasetType, 'BigData') || ...
        ~isa(dataset.labels, 'core.MibBigDataLabels') || ~dataset.modelExist
    return;
end

wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
    'Title', 'Save model', 'Message', 'Finalizing all resolution levels...', ...
    'Indeterminate', 'off');
drawnow;
cleanupWaitbar = onCleanup(@() delete(wb));

dataset.labels.materializeAll(@(progress) set(wb, 'Value', min(1, progress)));
dataset.labels.saveLevelMap();
end
