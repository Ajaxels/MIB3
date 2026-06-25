function saveBigDataModel(obj, id, mode)
% function saveBigDataModel(obj, id, mode)
% Persist a BigData model. Two modes:
%
%   'full'    : materialize every pyramid level from the level map AND write the
%               level-map side-file, so the on-disk model is fully consistent at
%               all resolutions (correct for export and any external reader). Can
%               be slow on a large slide.
%   'sidecar' : write ONLY the level-map side-file (fast). Pixel edits are already
%               on disk (each edit is written live at its working level + coarser);
%               the only volatile state is the in-memory level map. Persisting it
%               is a cheap crash-safety checkpoint: after a crash a reopen can then
%               reconstruct the deferred finer levels correctly instead of showing
%               stale data. No materialization is performed.
%
% During interactive segmentation a BigData model is only written at the level
% each edit was drawn (+ coarser); finer levels are reconstructed on demand
% (see ``core.MibBigDataLabels.getData63`` / ``materializeForRead``). 'full'
% performs that deferred work for every level at once.
%
% Parameters:
% id: [@em optional] index of the dataset; when omitted uses ``obj.getActiveId()``.
% mode: [@em optional] ``'full'`` (default) or ``'sidecar'``.
%
% Return values:
%
%
% @note no-op for non-BigData datasets or when no model exists.

% Updates
%

if nargin < 3 || isempty(mode); mode = 'full'; end
if nargin < 2 || isempty(id); id = obj.getActiveId(); end

dataset = obj.I{id};
if ~strcmp(dataset.datasetType, 'BigData') || ...
        ~isa(dataset.labels, 'core.MibBigDataLabels') || ~dataset.modelExist
    return;
end

if strcmp(mode, 'sidecar')
    % fast path: persist only the level map (no materialization)
    wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0.5, ...
        'Title', 'Save model', 'Message', 'Writing the level-map side-file...', ...
        'Indeterminate', 'on');
    cleanupWaitbar = onCleanup(@() delete(wb));
    dataset.labels.saveLevelMap();
    clear cleanupWaitbar;   % triggers waitbar deletion
    return;
end

wb = uiprogressdlg(obj.getProgressBarParent(), 'Value', 0, ...
    'Title', 'Save model', 'Message', 'Finalizing all resolution levels...', ...
    'Indeterminate', 'off');
drawnow;
cleanupWaitbar = onCleanup(@() delete(wb));

dataset.labels.materializeAll(@(progress) set(wb, 'Value', min(1, progress)));
dataset.labels.saveLevelMap();
clear cleanupWaitbar;   % triggers waitbar deletion
end
