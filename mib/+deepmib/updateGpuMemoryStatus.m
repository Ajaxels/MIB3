function updateGpuMemoryStatus(iteration, elapsedSeconds)
% UPDATEGPUMEMORYSTATUS - Warn once when iterations slow down the way an overcommitted GPU does.
%
% Syntax:
%   .. code-block:: matlab
%
%      deepmib.updateGpuMemoryStatus(iteration, elapsedSeconds)
%
% Input Arguments:
%   - **iteration** - [numeric] current training iteration number
%   - **elapsedSeconds** - [numeric] wall-clock seconds since the run started
%
% Output Arguments:
%   (none) - sets ``mibDeepTrainingProgressStruct.gpuSpillWarned`` and prints a one-off message
%   to the command window when the card looks overcommitted. The ``- over limit`` marker on
%   the GPU name line is drawn by :func:`updateStopEstimate`, which composes that line.
%
% Called once per refresh from :func:`customTrainingProgressDisplay` and
% :func:`customTrainingProgressDisplayTrainNet`, before :func:`updateStopEstimate`. All state lives
% in the global ``mibDeepTrainingProgressStruct`` and is initialized where the progress window
% is built (``.gpuSlowdownCheck``, ``.gpuRateSamples``, ``.gpuBaselineRate``,
% ``.gpuPrevIteration``, ``.gpuPrevElapsed``, ``.gpuSpillWarned``), which also means each phase
% of the two-phase instance schedule measures its own baseline (a trainable phase is
% legitimately slower than a frozen one).
%
% **Why timing and not memory.** On Windows (WDDM) the driver does **not** fail when the working
% set exceeds VRAM - it pages GPU memory to system RAM (24 GB was allocated on a 12 GB
% RTX 3080 Ti with no error). So "mini-batch slightly too large" is not a crash, it is a silent
% slowdown. Memory readings cannot detect it: this function runs *between* iterations, after
% the activations have been freed, so ``AvailableMemory`` under-reported a deliberate 4.96 GB
% transient by 60%, and in the calibration sweep it read the same 10.91 GB used (91%) both in
% the last healthy configuration and in every spilled one. An earlier version showed that
% reading as "peak X/Y GB" after the device name; it was removed (2026-11) because it misled
% more than it helped. Iteration time does discriminate, by a wide margin:
%
% =============  ==============  ============
% ballast        sec/iteration   vs baseline
% =============  ==============  ============
% 8 GB           0.0088          0.8x
% 10 GB          0.2968          **27.7x**
% 14 GB          0.3064          **28.6x**
% =============  ==============  ============
%
% Healthy iterations spanned 0.0088 to 0.0107 s (a 1.2x spread) while spilling costs ~28x,
% so the trigger factor below sits in a very wide empty band.
%
% **Important limitation.** The comparison is against the run's *own* early iterations, so
% this catches a run that *becomes* overcommitted - growing fragmentation, another process
% taking the card, a dataset whose later images are larger. It does **not** catch a run that
% was overcommitted from iteration 1, because the baseline is then measured in the slow
% state and nothing stands out. Detecting that case needs an external reference: either the
% Windows ``\GPU Process Memory(pid_*)\Shared Usage`` counter, which measures paging to host
% RAM directly (0.07 GB idle against 9.90 GB while oversubscribed, readable in 0.24 ms
% through .NET), or a startup probe that times the same network at two mini-batch sizes and
% compares samples per second. Neither is implemented.

global mibDeepTrainingProgressStruct

% Nothing to do unless the window was built for a single-GPU run (a CPU, Multi-GPU or
% Parallel run has no single device whose paging would show up this way)
if ~isfield(mibDeepTrainingProgressStruct, 'gpuSlowdownCheck') || ~mibDeepTrainingProgressStruct.gpuSlowdownCheck
    return;
end
if mibDeepTrainingProgressStruct.gpuSpillWarned; return; end   % one warning per run is enough

% Calibrated constants, see the table above. warmupSamples is dropped because kernel
% compilation and cuDNN autotuning make the opening iterations outliers (0.506 s against a
% steady 0.031 s in the same sweep). Medians rather than means throughout, so the
% occasional refresh interval that happens to contain a validation pass cannot move either
% the baseline or the recent estimate.
warmupSamples = 3;
baselineSamples = 10;
recentSamples = 5;
spillSlowdownFactor = 4;

% iteration pace, sampled between consecutive refreshes rather than cumulatively, so a
% slowdown that starts late in the run is not diluted by everything before it
iterationsSinceLast = iteration - mibDeepTrainingProgressStruct.gpuPrevIteration;
secondsSinceLast = elapsedSeconds - mibDeepTrainingProgressStruct.gpuPrevElapsed;
if iterationsSinceLast <= 0 || secondsSinceLast <= 0; return; end

mibDeepTrainingProgressStruct.gpuPrevIteration = iteration;
mibDeepTrainingProgressStruct.gpuPrevElapsed = elapsedSeconds;
mibDeepTrainingProgressStruct.gpuRateSamples(end+1) = secondsSinceLast / iterationsSinceLast;

rateSamples = mibDeepTrainingProgressStruct.gpuRateSamples;
if isnan(mibDeepTrainingProgressStruct.gpuBaselineRate) && ...
        numel(rateSamples) >= warmupSamples + baselineSamples
    mibDeepTrainingProgressStruct.gpuBaselineRate = ...
        median(rateSamples(warmupSamples+1:warmupSamples+baselineSamples));
end

if ~isnan(mibDeepTrainingProgressStruct.gpuBaselineRate) && numel(rateSamples) >= recentSamples
    recentRate = median(rateSamples(end-recentSamples+1:end));
    if recentRate > spillSlowdownFactor * mibDeepTrainingProgressStruct.gpuBaselineRate
        mibDeepTrainingProgressStruct.gpuSpillWarned = true;
        fprintf(['DeepMIB: iterations have slowed from %.3g to %.3g sec each (%.0fx). That is the\n' ...
            'signature of the graphics driver paging GPU memory out to system RAM, which happens\n' ...
            'when the mini-batch or the input patch size is slightly too large for the card. On\n' ...
            'Windows this does not raise an error, so the run will finish - just many times slower\n' ...
            'than it needs to.\n' ...
            'Reduce "Mini-batch size" on the Train tab and start again to get the speed back.\n' ...
            '(A slow image datastore can look similar: if the disk or network holding the images\n' ...
            'is busy, look there instead.)\n'], ...
            mibDeepTrainingProgressStruct.gpuBaselineRate, recentRate, ...
            recentRate/mibDeepTrainingProgressStruct.gpuBaselineRate);
    end
end
end
