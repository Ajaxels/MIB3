function suspendCheckpointSaving(action)
% SUSPENDCHECKPOINTSAVING - move the checkpoint folder aside while a stopped run spins down.
%
% Syntax:
%   .. code-block:: matlab
%
%      deepmib.suspendCheckpointSaving(action)
%
% Input Arguments:
%   - **action** — [char] ``'suspend'`` to move the checkpoint folder out of the way,
%     ``'restore'`` to move it back, or ``'restoreOrphaned'`` to move back a folder left
%     behind by a run that never reached its restore step (Ctrl+C, crash, MATLAB restart)
%
% Notes:
%   ``trainSOLOV2`` (the ``2D Instance`` workflow) trains via
%   ``images.dltrain.internal.dltrain``. Its ``SerialTrainer``/``ParallelTrainer`` honour a
%   stop request by ending the inner per-epoch iteration loop only — the outer
%   ``for epoch = 1:MaxEpochs`` loop still runs to completion. Each of those idle epochs
%   fires an ``EpochEnd`` event and, when a ``CheckpointPath`` is configured, that event
%   saves the whole network to disk again. Stopping a long run early therefore blocked
%   MATLAB for hours while it rewrote hundreds of megabytes per idle epoch.
%
%   ``images.dltrain.internal.CheckpointSaver`` wraps its save in a ``try/catch`` that only
%   issues a "Checkpoint failed to save." warning, so making the checkpoint folder
%   temporarily unreachable turns every one of those saves into an instant no-op. The
%   folder is renamed rather than deleted, so checkpoints written before the stop survive.
%
%   The rename is driven from the training ``OutputFcn``, which runs on the same thread as
%   the checkpoint save, so no save can be in flight while the folder is moved. The pair of
%   paths is held in a persistent variable rather than in ``mibDeepTrainingProgressStruct``
%   so that ``'restore'`` still works when that global is reset mid-run (for example by a
%   second press of the stop button, see deepmib.stopTrainingCallback).
%
% See also:
%   deepmib.customTrainingProgressDisplay, deepmib.stopTrainingWithoutPlots,
%   controllers.MibDeep/startTrainingInstances

global mibDeepTrainingProgressStruct

persistent originalCheckpointPath    % '' when nothing is currently suspended
persistent suspendedCheckpointPath
persistent previousWarningState      % warning state to put back when restoring

if isempty(originalCheckpointPath); originalCheckpointPath = ''; end

switch action
    case 'suspend'
        if ~isempty(originalCheckpointPath); return; end     % already suspended
        % checkpoint saving is off for this run, nothing can be written anyway
        if ~isfield(mibDeepTrainingProgressStruct, 'CheckpointPath') || isempty(mibDeepTrainingProgressStruct.CheckpointPath)
            return;
        end
        checkpointPath = mibDeepTrainingProgressStruct.CheckpointPath;
        if ~isfolder(checkpointPath); return; end

        candidatePath = [checkpointPath '_stopping'];
        % a failed move only means the run keeps the old slow behaviour, so it is logged to
        % the command window rather than raised to the user in the middle of training
        if movefile(checkpointPath, candidatePath, 'f')
            originalCheckpointPath = checkpointPath;
            suspendedCheckpointPath = candidatePath;
            % Every idle epoch now hits the failing save in
            % images.dltrain.internal.CheckpointSaver, which issues an unconditional
            % "Checkpoint failed to save." - once per remaining epoch, so thousands of
            % lines of noise. That warning carries no identifier, so it cannot be switched
            % off individually and warnings have to go off wholesale for the spin-down.
            % Nothing but the idle loop runs during that window
            previousWarningState = warning('off', 'all');
        else
            fprintf('DeepMIB: could not suspend checkpoint saving in "%s", stopping may take a while\n', checkpointPath);
        end
    case 'restore'
        if isempty(originalCheckpointPath); return; end
        checkpointPath = originalCheckpointPath;
        candidatePath = suspendedCheckpointPath;
        originalCheckpointPath = '';
        suspendedCheckpointPath = '';
        iRestoreWarningState(previousWarningState);
        previousWarningState = [];
        iMoveFolderBack(candidatePath, checkpointPath);
    case 'restoreOrphaned'
        % Ctrl+C, a crash or a MATLAB restart can leave the renamed folder behind, because
        % the 'restore' call at the end of the run never happened and the persistent state
        % above is gone. Called at the start of every instance-training run so a stranded
        % folder heals itself instead of hiding the previous checkpoints for good.
        if ~isfield(mibDeepTrainingProgressStruct, 'CheckpointPath') || isempty(mibDeepTrainingProgressStruct.CheckpointPath)
            return;
        end
        checkpointPath = mibDeepTrainingProgressStruct.CheckpointPath;
        candidatePath = [checkpointPath '_stopping'];
        if ~isfolder(candidatePath); return; end
        fprintf('DeepMIB: recovering checkpoints left in "%s" by an interrupted run\n', candidatePath);
        iMoveFolderBack(candidatePath, checkpointPath);
        originalCheckpointPath = '';
        suspendedCheckpointPath = '';
        % a run killed during the spin-down left warnings switched off; a Ctrl+C also
        % skips this, so warnings stay off until the next training run starts
        iRestoreWarningState(previousWarningState);
        previousWarningState = [];
    otherwise
        error('deepmib:suspendCheckpointSaving:unknownAction', ...
            'Unknown action "%s", expected "suspend", "restore" or "restoreOrphaned"', action);
end

end

% -------------------------------------------------------------------------------------
function iRestoreWarningState(previousWarningState)
% put the warning configuration back the way it was before the spin-down

if isempty(previousWarningState); return; end
warning(previousWarningState);

end

% -------------------------------------------------------------------------------------
function iMoveFolderBack(candidatePath, checkpointPath)
% move the renamed folder back under its original name
%
% Housekeeping only: a failure here must never stop the caller from training, so problems
% are reported to the command window rather than thrown.

if ~isfolder(candidatePath); return; end

try
    if ~isfolder(checkpointPath)
        movefile(candidatePath, checkpointPath, 'f');
        return;
    end

    % the trainer never recreates the folder itself, but a later MIB action might have; in
    % that case move the preserved checkpoints back file by file. The folder can also be
    % empty - when no checkpoint had been written yet at the moment of the stop - and
    % movefile errors on a wildcard that matches nothing, so check the real contents first
    % ('.' and '..' are excluded, they are always listed by dir)
    folderContents = dir(candidatePath);
    folderContents = folderContents(~ismember({folderContents.name}, {'.', '..'}));
    if ~isempty(folderContents)
        movefile(fullfile(candidatePath, '*'), checkpointPath, 'f');
    end
    rmdir(candidatePath, 's');
catch err
    fprintf('DeepMIB: could not move "%s" back to "%s": %s\n', ...
        candidatePath, checkpointPath, err.message);
end

end
