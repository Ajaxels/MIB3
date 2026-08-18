function updateGpuMemoryStatus(iteration, elapsedSeconds)
% UPDATEGPUMEMORYSTATUS - Report GPU memory headroom and warn when the card is overcommitted.
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
%   (none) - the GPU name label in the training progress window is updated in place, and a
%   one-off message is printed to the command window when the card looks overcommitted
%
% Called once per refresh from :func:`customTrainingProgressDisplay` and
% :func:`customTrainingProgressDisplayTrainNet`. All state lives in the global
% ``mibDeepTrainingProgressStruct`` and is initialized where the progress window is built,
% which also means each phase of the two-phase instance schedule measures its own baseline
% (a trainable phase is legitimately slower than a frozen one).
%
% **What is reported, and what it is worth.** Two measurements taken on an RTX 3080 Ti
% (12 GB, WDDM) decide the design:
%
% 1. This function runs *between* iterations, where the forward/backward activations have
%    already been freed. Measured against a deliberate 4.96 GB transient, the reading taken
%    here was 1.96 GB - it under-reports the true peak by 60%. The figure shown is therefore
%    a **lower bound** on peak usage, useful for headroom but not a batch-size calculator.
%    Sampling mid-iteration is not possible: a MATLAB timer cannot preempt the main thread
%    while the trainer holds it.
%
% 2. On Windows (WDDM) the driver does **not** fail when the working set exceeds VRAM - it
%    pages GPU memory to system RAM. 24 GB was allocated on the 12 GB card with no error at
%    all. So "mini-batch slightly too large" is not a crash, it is a silent slowdown.
%
% **Why the warning uses timing and not memory.** In the calibration sweep, ``AvailableMemory``
% read 1.09 GB (used 10.91 GB, 91% of VRAM) both in the last healthy configuration and in
% every spilled one - identical on both sides of the cliff, so it cannot discriminate.
% Iteration time can, and by a wide margin:
%
% =============  ==============  ==============  ============
% ballast        used peak       sec/iteration   vs baseline
% =============  ==============  ==============  ============
% 8 GB           10.91 GB (91%)  0.0088          0.8x
% 10 GB          10.91 GB (91%)  0.2968          **27.7x**
% 14 GB          10.91 GB (91%)  0.3064          **28.6x**
% =============  ==============  ==============  ============
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
% compares samples per second. Neither is implemented yet - see
% development/deepmib/potential_improvements.md.

global mibDeepTrainingProgressStruct

% Nothing to do unless the window was built for a single-GPU run: gpuBaseLabel is only set
% in that case (a CPU, Multi-GPU or Parallel run has no single device to interrogate)
if ~isfield(mibDeepTrainingProgressStruct, 'gpuBaseLabel') || isempty(mibDeepTrainingProgressStruct.gpuBaseLabel)
    return;
end
if ~isfield(mibDeepTrainingProgressStruct, 'TrainingProgress') || ...
        ~isvalid(mibDeepTrainingProgressStruct.TrainingProgress)
    return;
end

% Calibrated constants, see the table above. warmupSamples is dropped because kernel
% compilation and cuDNN autotuning make the opening iterations outliers (0.506 s against a
% steady 0.031 s in the same sweep). Medians rather than means throughout, so the
% occasional refresh interval that happens to contain a validation pass cannot move either
% the baseline or the recent estimate.
warmupSamples = 3;
baselineSamples = 10;
recentSamples = 5;
spillSlowdownFactor = 4;
gigabyte = 2^30;

try
    availableMemory = gpuDevice().AvailableMemory;   % ~0.06 ms, measured
catch
    return;     % device busy or gone, skip this refresh rather than break the display
end

usedMemory = mibDeepTrainingProgressStruct.gpuTotalMemory - availableMemory;
mibDeepTrainingProgressStruct.gpuPeakUsed = max(mibDeepTrainingProgressStruct.gpuPeakUsed, usedMemory);

% ---- iteration pace, sampled between consecutive refreshes rather than cumulatively, so a
% slowdown that starts late in the run is not diluted by everything before it
iterationsSinceLast = iteration - mibDeepTrainingProgressStruct.gpuPrevIteration;
secondsSinceLast = elapsedSeconds - mibDeepTrainingProgressStruct.gpuPrevElapsed;
if iterationsSinceLast > 0 && secondsSinceLast > 0
    mibDeepTrainingProgressStruct.gpuPrevIteration = iteration;
    mibDeepTrainingProgressStruct.gpuPrevElapsed = elapsedSeconds;
    mibDeepTrainingProgressStruct.gpuRateSamples(end+1) = secondsSinceLast / iterationsSinceLast;

    rateSamples = mibDeepTrainingProgressStruct.gpuRateSamples;
    if isnan(mibDeepTrainingProgressStruct.gpuBaselineRate) && ...
            numel(rateSamples) >= warmupSamples + baselineSamples
        mibDeepTrainingProgressStruct.gpuBaselineRate = ...
            median(rateSamples(warmupSamples+1:warmupSamples+baselineSamples));
    end

    if ~isnan(mibDeepTrainingProgressStruct.gpuBaselineRate) && ...
            ~mibDeepTrainingProgressStruct.gpuSpillWarned && numel(rateSamples) >= recentSamples
        recentRate = median(rateSamples(end-recentSamples+1:end));
        if recentRate > spillSlowdownFactor * mibDeepTrainingProgressStruct.gpuBaselineRate
            mibDeepTrainingProgressStruct.gpuSpillWarned = true;
            fprintf(['DeepMIB: iterations have slowed from %.3g to %.3g sec each (%.0fx) while the GPU is\n' ...
                'holding %.1f of its %.1f GB. That combination is the signature of the graphics driver\n' ...
                'paging GPU memory out to system RAM, which happens when the mini-batch or the input\n' ...
                'patch size is slightly too large for the card. On Windows this does not raise an error,\n' ...
                'so the run will finish - just many times slower than it needs to.\n' ...
                'Reduce "Mini-batch size" on the Train tab and start again to get the speed back.\n' ...
                '(A slow image datastore can look similar; if the memory figure above is well below the\n' ...
                'card total, look at disk or network speed instead.)\n'], ...
                mibDeepTrainingProgressStruct.gpuBaselineRate, recentRate, ...
                recentRate/mibDeepTrainingProgressStruct.gpuBaselineRate, ...
                mibDeepTrainingProgressStruct.gpuPeakUsed/gigabyte, ...
                mibDeepTrainingProgressStruct.gpuTotalMemory/gigabyte);
        end
    end
end

% ---- label
labelText = sprintf('%s (peak %.1f/%.1f GB)', mibDeepTrainingProgressStruct.gpuBaseLabel, ...
    mibDeepTrainingProgressStruct.gpuPeakUsed/gigabyte, mibDeepTrainingProgressStruct.gpuTotalMemory/gigabyte);
if mibDeepTrainingProgressStruct.gpuSpillWarned
    labelText = [labelText ' - over limit'];
    mibDeepTrainingProgressStruct.TrainingProgress.FontColor = [0.75 0 0];
end
mibDeepTrainingProgressStruct.TrainingProgress.Text = labelText;
mibDeepTrainingProgressStruct.TrainingProgress.Tooltip = sprintf([ ...
    'Most GPU memory seen in use at any refresh, out of the card total.\n' ...
    'This is a lower bound: it is sampled between iterations, after the activations of the ' ...
    'forward and backward pass have been freed, so the true peak inside an iteration is higher.']);
end
