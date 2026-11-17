function maxTimeReached = checkMaxTimeReached()
% CHECKMAXTIMEREACHED - Request a graceful stop of training once the MaxTime limit has passed.
%
% Syntax:
%   .. code-block:: matlab
%
%      maxTimeReached = deepmib.checkMaxTimeReached()
%
% Output Arguments:
%   - **maxTimeReached** - [logical] ``true`` when this call raised the stop request because
%     the time limit has passed
%
% Description:
%   ``trainingOptions`` has no time limit, so ``TrainingOpt.MaxTime`` (hours, fractional values
%   allowed; ``0`` disables the limit) is enforced from the training ``OutputFcn``. The training
%   start functions (``controllers.MibDeep.startTraining``, ``startTrainingInstances``,
%   ``startTrainingStarDist``) store in the global ``mibDeepTrainingProgressStruct``:
%
%     - ``.maxTimeSeconds`` - the limit in seconds, ``0`` or missing = no limit
%     - ``.maxTimeTimer`` - ``tic`` value taken right before the trainer is called
%
%   When the limit has passed, this function sets the global ``mibDeepStopTraining`` flag,
%   which is exactly what the "Stop training" button does. The calling ``OutputFcn`` then
%   returns ``true`` and the trainer finishes the run gracefully, returning the network of the
%   last iteration (or of the best validation loss, depending on ``OutputNetwork``).
%   Training therefore ends at whichever of ``MaxTime`` or ``MaxEpochs`` is reached first.
%   The check runs once per iteration, so the run can overshoot the limit by the duration of
%   one iteration (plus a validation pass, if one is due).
%
%   For the two-phase "COCO, frozen then trainable" SOLOv2 schedule the timer is started once,
%   before the frozen phase, so the limit covers both phases; a stop during the frozen phase
%   skips the trainable phase like a manual stop does.
%
%   The flag ``.maxTimeReached`` is set in ``mibDeepTrainingProgressStruct`` so the caller can
%   tell a time-limit stop from the other stop reasons. Cost per call is one ``toc``.
%
%   Called from deepmib.customTrainingProgressDisplay,
%   deepmib.customTrainingProgressDisplayTrainNet and deepmib.stopTrainingWithoutPlots.
%

global mibDeepStopTraining
global mibDeepTrainingProgressStruct

maxTimeReached = false;
if isempty(mibDeepTrainingProgressStruct) || ~isstruct(mibDeepTrainingProgressStruct) || ...
        ~isfield(mibDeepTrainingProgressStruct, 'maxTimeSeconds') || ...
        isempty(mibDeepTrainingProgressStruct.maxTimeSeconds) || ...
        mibDeepTrainingProgressStruct.maxTimeSeconds <= 0 || ...
        ~isfield(mibDeepTrainingProgressStruct, 'maxTimeTimer')
    return;
end
% already stopping for another reason, nothing to add
if ~isempty(mibDeepStopTraining) && mibDeepStopTraining; return; end

elapsedSeconds = toc(mibDeepTrainingProgressStruct.maxTimeTimer);
if elapsedSeconds >= mibDeepTrainingProgressStruct.maxTimeSeconds
    fprintf('DeepMIB: the maximal training time (MaxTime = %g h) has been reached after %.0f h %.0f min, stopping training\n', ...
        mibDeepTrainingProgressStruct.maxTimeSeconds/3600, floor(elapsedSeconds/3600), floor(mod(elapsedSeconds, 3600)/60));
    mibDeepTrainingProgressStruct.maxTimeReached = true;
    mibDeepStopTraining = true;
    maxTimeReached = true;
end
end
