function updateStopEstimate(elapsedSeconds, iteration)
% UPDATESTOPESTIMATE - Update "Time to go", the progress gauge and the expected stop mode of the training progress window.
%
% Syntax:
%   .. code-block:: matlab
%
%      deepmib.updateStopEstimate(elapsedSeconds, iteration)
%      deepmib.updateStopEstimate(0, 0)     % at window creation: stop mode only
%
% Input Arguments:
%   - **elapsedSeconds** - [numeric] wall-clock seconds since the trainer started, as reported
%     in the progress struct (``TimeSinceStart`` or ``TimeElapsed`` converted to seconds)
%   - **iteration** - [numeric] current iteration number
%
% Output Arguments:
%   (none) - updates ``.TimeToGo``, ``.ProgressGauge`` and ``.TrainingProgress`` (the bold
%   device line) of the global ``mibDeepTrainingProgressStruct``
%
% Description:
%   Training ends at whichever of ``MaxEpochs`` or ``TrainingOpt.MaxTime`` comes first (the
%   time limit is enforced by :func:`checkMaxTimeReached`). Two estimates are made:
%
%     - **epochs**: the average time per iteration so far, multiplied by the iterations left to
%       ``mibDeepTrainingProgressStruct.maxIter``;
%     - **time**: ``maxTimeSeconds`` minus ``toc(maxTimeTimer)``, the same clock
%       :func:`checkMaxTimeReached` stops on, so the countdown matches the actual stop. It is
%       used only when ``maxTimeSeconds > 0``.
%
%   The smaller one wins and drives all three widgets:
%
%     - "Time to go" shows its remaining time;
%     - the gauge shows ``iteration/maxIter`` in the epochs mode and
%       ``toc(maxTimeTimer)/maxTimeSeconds`` in the time mode, so it reaches 100 at the
%       point where the run actually stops. Both are clamped to 100: ``maxIter`` is an
%       estimate (iterations per epoch x epochs), and a needle past the edge of the [0 100]
%       scale reads as a fault rather than an off-by-one in the estimate;
%     - the device line names the winner: ``<device> (stop: epochs)`` or
%       ``<device> (stop: time limit)``.
%
%   The mode is re-evaluated on every refresh, so the run switches from epochs to time (or
%   back) as the pace changes, for example when validation passes slow it down. Before the
%   pace is known (``iteration`` or ``elapsedSeconds`` is 0) only the device line is set, to
%   ``(stop: epochs)`` without a limit and ``(stop: epochs or time limit)`` with one.
%
%   ``.deviceLabel`` is the device name built at window creation, with the card memory
%   appended for a single-GPU run (``1. NVIDIA GeForce RTX 3080 Ti 12GB``). The
%   ``- over limit`` marker and red colour are added when :func:`updateGpuMemoryStatus` has
%   raised ``.gpuSpillWarned``, so call that first.
%
%   For the two-phase "COCO, frozen then trainable" SOLOv2 schedule each phase builds its own
%   window and ``maxIter`` covers that phase only, while the time limit covers both phases.
%   During the frozen phase the epochs mode therefore estimates the end of the frozen phase,
%   not of the run, while the time mode estimates the end of the run.
%
%   Called from :func:`customTrainingProgressDisplay` and
%   :func:`customTrainingProgressDisplayTrainNet`.

global mibDeepTrainingProgressStruct

timeLimitSeconds = 0;
if isfield(mibDeepTrainingProgressStruct, 'maxTimeSeconds') && ~isempty(mibDeepTrainingProgressStruct.maxTimeSeconds) && ...
        isfield(mibDeepTrainingProgressStruct, 'maxTimeTimer')
    timeLimitSeconds = mibDeepTrainingProgressStruct.maxTimeSeconds;
end

if iteration > 0 && elapsedSeconds > 0
    secondsToGo = elapsedSeconds / iteration * max(0, mibDeepTrainingProgressStruct.maxIter - iteration);
    progressPercent = iteration / mibDeepTrainingProgressStruct.maxIter * 100;
    stopModeText = 'epochs';
    if timeLimitSeconds > 0
        timeLimitElapsed = toc(mibDeepTrainingProgressStruct.maxTimeTimer);
        timeLimitSecondsToGo = max(0, timeLimitSeconds - timeLimitElapsed);
        if timeLimitSecondsToGo < secondsToGo
            secondsToGo = timeLimitSecondsToGo;
            progressPercent = timeLimitElapsed / timeLimitSeconds * 100;
            stopModeText = 'time limit';
        end
    end
    mibDeepTrainingProgressStruct.TimeToGo.Text = sprintf('Time to go: ~%.0f h %.0f min %.2d sec', ...
        floor(secondsToGo/3600), floor(mod(round(secondsToGo),3600)/60), mod(round(secondsToGo),60));
    mibDeepTrainingProgressStruct.ProgressGauge.Value = min(100, progressPercent);
elseif timeLimitSeconds > 0
    stopModeText = 'epochs or time limit';
else
    stopModeText = 'epochs';
end

labelText = sprintf('%s (stop: %s)', mibDeepTrainingProgressStruct.deviceLabel, stopModeText);
if isfield(mibDeepTrainingProgressStruct, 'gpuSpillWarned') && mibDeepTrainingProgressStruct.gpuSpillWarned
    labelText = [labelText ' - over limit'];
    mibDeepTrainingProgressStruct.TrainingProgress.FontColor = [0.75 0 0];
end
mibDeepTrainingProgressStruct.TrainingProgress.Text = labelText;
end
