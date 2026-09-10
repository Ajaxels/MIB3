function findBestMinibatchSize(obj)
% FINDBESTMINIBATCHSIZE - measure which mini-batch size gives the best throughput on this GPU.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.findBestMinibatchSize()
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none) - the measured table is shown to the user, who chooses whether to apply the
%   recommended value to ``BatchOpt.T_MiniBatchSize``
%
% Trains the configured network on **synthetic patches** for a few iterations at each
% candidate mini-batch size and reports patches per second. The project images are never read
% and nothing is ever written to the project; the 2D Instance workflow does read a sample of
% the label maps, to match the object count of the synthetic patches to the real ones (see
% :func:`iSampleInstancesPerPatch`).
%
% **Why throughput and not a memory reading.** MATLAB's ``gpuDevice().AvailableMemory``
% saturates: in a calibration sweep on a 12 GB card it read 10.91 GB used both in the last
% healthy configuration and in every oversubscribed one, so it cannot tell them apart. Under
% the Windows WDDM driver an oversized batch does not raise an error either - the driver
% pages GPU memory to host RAM and the run silently continues many times slower. Throughput
% is what actually changes, and comparing two sizes of the same network on the same card
% needs no calibrated threshold at all:
%
% - below the limit, a larger mini-batch processes patches **faster** (fixed per-iteration
%   overhead is spread over more patches);
% - above it, throughput **collapses** as the driver starts paging.
%
% So the best size is simply where patches per second peaks.
%
% **Iterations are timed individually**, through the trainer's own OutputFcn, and the median
% is taken after discarding the first two. Timing the call as a whole does not work: network
% setup costs around 10 seconds against per-iteration costs of a fraction of a second, so the
% measurement is all overhead. Subtracting two runs of different lengths does not work
% either - the overhead varies by more than the signal, which made short runs come out
% *slower* than long ones when this was tried.
%
% **The result is a mild upper bound.** The probe runs the network alone; a real run also
% holds the validation set and the augmentation buffers. Reading and augmenting a patch was
% measured at 0.085 s against a 3.70 s iteration, so on this workflow that margin is around
% 9% and the timing below matches a recorded run to 1%. If the recommended value is the
% largest one tested, the true optimum may be higher still.
%
% For 2D Instance the probe deliberately measures with ``FreezeSubNetwork`` set to
% ``'none'``, the most memory-hungry case, because the two-phase schedule ends up there and
% a size chosen against the cheaper frozen phase would fail once the backbone is unfrozen.
%
% **How many instances a synthetic patch carries is measured, not assumed.** SOLOv2's cost is
% driven by the ground-truth instance count: the loss assigns every instance across the FPN
% levels and the target is an ``[h w K]`` logical stack. This used to generate a fixed 5
% objects per patch, and on a mitochondria project whose patches actually hold a median of 31
% the probe came out **2.1x too fast** (17.4 epochs/hour predicted against 8.3 recorded) while
% modelling a mask tensor six times smaller than the real one - 11.8 MB per iteration against
% 74 MB. Understating the memory is the worse half of that, because it lets the probe
% recommend a size that then pages in the real run. :func:`iSampleInstancesPerPatch` therefore
% reads a sample of the project's own label maps first. Only the label maps are read, never
% the images, and a project that is not preprocessed yet falls back to the old constant.
%
% Measured against that same recorded run - Resnet50, 768x768, mini-batch 4, whose real
% iteration took 3.700 s:
%
% ===========================  =============  ===========
% objects per synthetic patch  sec/iteration  epochs/hour
% ===========================  =============  ===========
% 5 (the old constant)         1.618          19.0
% 31 (measured from labels)    **3.732**      **8.2**
% real run                     3.700          8.3
% ===========================  =============  ===========
%
% A 2D U-net at 256x256 on a 12 GB card, repeated twice and agreeing to 0.1%:
%
% ====  =============  ==============
% size  sec/iteration  patches/second
% ====  =============  ==============
% 1     0.0254         39.40
% 2     0.0353         56.72
% 4     0.0539         74.16
% 8     0.1001         **79.95**
% 16    0.2346         68.21
% 32    0.5983         53.48
% ====  =============  ==============
%
% The decline past the peak here is ordinary diminishing returns. Running out of memory
% looks entirely different: with Resnet50 at 768x768 on the same card, an iteration went
% from around 2 s at mini-batch 4 to 63 s at mini-batch 8.

% Iterations run per candidate; the first two are discarded as warm-up. Fast networks are
% measured again with more of them: on a 256x256 U-net, where an iteration costs under
% 0.1 s, 6 iterations gave readings that varied by up to 17% between repeats and put the
% peak in the wrong place, while 20 brought the spread to 1-6% and produced a clean curve.
% Slow networks do not need the second pass and would pay dearly for it - one iteration of
% Resnet50 at 768x768 costs around 2 s.
probeIterationsInitial = 8;
probeIterationsRefined = 24;
shortIterationSeconds = 0.15;
% how many candidates to try at most; the actual values are built by doubling from the
% start size the user picks in the dialog below
candidateSizes = zeros(1, 7);
% stop climbing once throughput has fallen this far below the best seen; whether the drop
% is a memory collapse or just diminishing returns does not matter, the peak is already behind
collapseFraction = 0.7;

if isempty(obj.BatchOpt.OriginalTrainingImagesDir)
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'Select the directory with training images first.', 'No project');
    return;
end

inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize); %#ok<ST2NM>
if numel(inputPatchSize) ~= 4
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'The input patch size must be given as [height width depth colors].', 'Wrong patch size');
    return;
end

% 2D Patch-wise classifies a whole patch instead of labelling its pixels, so its training
% data is an image paired with a single categorical rather than with a label image, and the
% network has T_NumberOfClasses-1 outputs. The synthetic datastores below produce neither.
if strcmp(obj.BatchOpt.Workflow{1}, '2D Patch-wise')
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf(['Measuring the mini-batch size is not available for the 2D Patch-wise workflow.\n\n' ...
        'Set it by hand: start from the value that works and double it while the training\n' ...
        '"Time/epoch" in the progress window keeps improving.']), ...
        'Not available for this workflow');
    return;
end

dlgOpt.Icon = 'puffin_question';
dlgOpt.WindowWidth = 490;
dlgOpt.WindowHeight = 340;

isInstanceWorkflow = strcmp(obj.BatchOpt.Workflow{1}, '2D Instance');

header = 'Identify the best size for Mini Batch';
dlgOpt.HeaderLines = 1;
textStr = sprintf([ ...
    'Train the current network on synthetic patches of [%s] for a few iterations at each ' ...
    'mini-batch size, and report how many patches per second each one achieves.\n\n' ...
    'The best size is the one where throughput peaks: below the limit of the card a larger ' ...
    'batch is faster, above it the driver starts paging GPU memory to system RAM and ' ...
    'throughput collapses.\n\n' ...
    'Testing starts at the size below and doubles it until throughput drops. Raise it to ' ...
    'skip sizes you know are too small - on a large card the small ones are slow to ' ...
    'measure and can never win.\n\n' ...
    'Start testing from this mini-batch size:'], obj.BatchOpt.T_InputPatchSize);

answer = utils.dlgs.inputUniversalDlg(obj.view.gui, header, ...
    {textStr}, ...
    {struct('Spinner', true, 'Value', 1, 'Limits', [1 1024], 'Step', 1, 'Round', true)}, ...
    'Find best mini-batch size', dlgOpt);

if isempty(answer); return; end
startSize = answer{1};

% double from the requested start until the cap; the collapse test below stops the climb
% long before the last entry on any real card
candidateSizes = startSize * 2.^(0:numel(candidateSizes)-1);
candidateSizes = candidateSizes(candidateSizes <= 1024);

% Assigned to obj.wb rather than kept local: createNetwork's helpers write progress into
% obj.wb directly whenever BatchOpt.showWaitbar is set (generateDeepLabV3Network line 271,
% generateUnet2DwithEncoder likewise). Every function that uses obj.wb deletes it on the way
% out and leaves the property holding a deleted handle, so a caller that keeps its own local
% dialog makes those helpers fail with MATLAB:class:InvalidHandle.
obj.wb = uiprogressdlg(obj.view.gui, 'Message', 'Building the network...', ...
    'Title', 'Find best mini-batch size', 'Cancelable', 'on');

% the trainers reseed the global stream; leave it as we found it so pressing this button
% cannot change the patches a subsequent training run draws
rngState = rng();
cleanupRng = onCleanup(@() rng(rngState));

% measured from the project's own label maps, see iSampleInstancesPerPatch; unused by the
% semantic workflows, whose cost does not depend on an object count
objectsPerPatch = 0;
if isInstanceWorkflow
    obj.wb.Message = 'Sampling the label maps...';
    objectsPerPatch = iSampleInstancesPerPatch(obj, inputPatchSize(1:2));
end

try
    if isInstanceWorkflow
        inputPatchSize = [inputPatchSize([1 2]) 3];
        switch obj.BatchOpt.T_EncoderNetwork{1}
            case 'Resnet50';  detectorName = 'resnet50-coco';
            otherwise;        detectorName = 'light-resnet18-coco';
        end
        probeNetwork = solov2(detectorName, {'object'}, 'InputSize', inputPatchSize);
        outputPatchSize = [];
    else
        [probeNetwork, outputPatchSize] = obj.createNetwork(1);   % previewSwitch, no class weights
        if isempty(probeNetwork)
            delete(obj.wb);
            return;     % createNetwork already explained why
        end
    end
catch err
    delete(obj.wb);
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Could not build the network');
    return;
end

results = [];       % [miniBatchSize, secondsPerIteration, patchesPerSecond]
failedAt = NaN;
bestThroughput = 0;

% One throwaway run before measuring anything. MATLAB's first use of the GPU in a session
% carries context creation and kernel compilation that no per-candidate warm-up can absorb,
% and it lands entirely on whichever candidate goes first: measured cold, mini-batch 1 came
% out at 21 patches/second against 41 once the session was warm.
obj.wb.Message = 'Warming up...';
try
    iTimeCandidate(obj, probeNetwork, inputPatchSize, outputPatchSize, ...
        candidateSizes(1), 3, isInstanceWorkflow, objectsPerPatch);
catch
    % if the start size does not even fit, the loop below reports it properly
end

for candidateIdx = 1:numel(candidateSizes)
    miniBatchSize = candidateSizes(candidateIdx);
    if obj.wb.CancelRequested; break; end
    obj.wb.Value = (candidateIdx-1)/numel(candidateSizes);
    obj.wb.Message = sprintf('Measuring mini-batch size %d...', miniBatchSize);

    try
        secondsPerIteration = iTimeCandidate(obj, probeNetwork, inputPatchSize, outputPatchSize, ...
            miniBatchSize, probeIterationsInitial, isInstanceWorkflow, objectsPerPatch);
        if ~isnan(secondsPerIteration) && secondsPerIteration < shortIterationSeconds
            % too fast to time reliably over so few iterations, measure again with more
            secondsPerIteration = iTimeCandidate(obj, probeNetwork, inputPatchSize, outputPatchSize, ...
                miniBatchSize, probeIterationsRefined, isInstanceWorkflow, objectsPerPatch);
        end
    catch err
        if contains(lower(err.message), 'memory') || contains(lower(err.identifier), 'oom') || ...
                contains(lower(err.identifier), 'pmaxsize')
            failedAt = miniBatchSize;
            break;      % out of memory, nothing larger can work either
        end
        delete(obj.wb);
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'The measurement failed');
        return;
    end

    if isnan(secondsPerIteration) || secondsPerIteration <= 0
        continue;   % the trainer reported no usable per-iteration timing for this candidate
    end
    patchesPerSecond = miniBatchSize / secondsPerIteration;
    results(end+1, :) = [miniBatchSize, secondsPerIteration, patchesPerSecond]; %#ok<AGROW>

    bestThroughput = max(bestThroughput, patchesPerSecond);
    if patchesPerSecond < collapseFraction * bestThroughput
        break;      % past the peak, larger sizes only page harder
    end
end

cancelled = obj.wb.CancelRequested;
delete(obj.wb);

if isempty(results)
    if ~cancelled
        utils.dlgs.showErrorDialog(obj.view.gui, ...
            sprintf('Even a mini-batch size of %d did not fit on this device.\nReduce the input patch size.', ...
            candidateSizes(1)), 'Nothing fits');
    end
    return;
end

[~, bestIdx] = max(results(:,3));
recommendedSize = results(bestIdx,1);

% Epochs per hour, so the table answers "how long will the run take" and not only "which
% size is fastest". An epoch is observations/miniBatchSize iterations - the same expression
% startTraining / startTrainingInstances use for maxNoIter - so it shrinks as the mini-batch
% grows and the two columns do not simply track each other. The rounding differs by
% workflow: trainNetwork drops the observations that do not fill the last mini-batch,
% images.dltrain (behind trainSOLOV2) runs them as one more iteration.
trainingObservations = iCountTrainingObservations(obj);
if isInstanceWorkflow
    roundIterations = @ceil;
else
    roundIterations = @floor;
end

reportLines = cell(size(results,1), 1);
for rowIdx = 1:size(results,1)
    marker = '';
    if rowIdx == bestIdx; marker = '   <-- best'; end
    if trainingObservations > 0
        iterationsPerEpoch = max(1, roundIterations(trainingObservations / results(rowIdx,1)));
        epochsPerHour = 3600 / (iterationsPerEpoch * results(rowIdx,2));
        reportLines{rowIdx} = sprintf('%6d %14.3f %16.2f %14.1f%s', ...
            results(rowIdx,1), results(rowIdx,2), results(rowIdx,3), epochsPerHour, marker);
    else
        reportLines{rowIdx} = sprintf('%6d %14.3f %16.2f %14s%s', ...
            results(rowIdx,1), results(rowIdx,2), results(rowIdx,3), '-', marker);
    end
end
if trainingObservations > 0
    reportHeader = sprintf('  size   sec/iteration   patches/second   epochs/hour');
else
    reportHeader = sprintf('  size   sec/iteration   patches/second   epochs/hour (no training patches found)');
end
reportText = sprintf('%s\n%s\n%s', reportHeader, ...
    repmat('-', 1, numel(reportHeader)), strjoin(reportLines', newline));
% also to the command window, where a monospace font actually lines the columns up
fprintf('DeepMIB: mini-batch throughput on synthetic %s patches\n%s\n', ...
    obj.BatchOpt.T_InputPatchSize, reportText);

trailer = '';
if ~isnan(failedAt)
    trailer = sprintf('\n\nMini-batch %d ran out of memory, so nothing larger was tried.', failedAt);
elseif recommendedSize == results(end,1) && results(end,1) == candidateSizes(end)
    trailer = sprintf('\n\nThroughput was still climbing at %d, the largest size tested.', recommendedSize);
end
if cancelled
    trailer = [trailer sprintf('\n\nMeasurement was cancelled, so larger sizes were not tried.')];
end

applyOpt.Icon = 'puffin_info';
applyOpt.WindowStyle = 'normal';
applyOpt.WindowWidth = 620;
applyOpt.WindowHeight = 300 + 20*size(results,1) + 20*isInstanceWorkflow;   % one line per measured candidate
if trainingObservations > 0
    epochsNote = sprintf(['\n\nepochs/hour assumes %d training patches per epoch (%d images x %d patches each). ' ...
        'At the recommended size, the %d epochs currently configured would take about %s.'], ...
        trainingObservations, round(trainingObservations/obj.BatchOpt.T_PatchesPerImage{1}), ...
        obj.BatchOpt.T_PatchesPerImage{1}, obj.TrainingOpt.MaxEpochs, ...
        iFormatDuration(obj.TrainingOpt.MaxEpochs * ...
        max(1, floor(trainingObservations/recommendedSize)) * results(bestIdx,2)));
else
    epochsNote = sprintf(['\n\nepochs/hour could not be estimated: no training patches were found. ' ...
        'Preprocess or split the project first.']);
end

% the instance count is the dominant cost term for SOLOv2, so say which one was used rather
% than leaving the reader to assume the synthetic patches resemble their data
instancesNote = '';
if isInstanceWorkflow
    instancesNote = sprintf(['\n\nSynthetic patches carry %d instances each, the median measured ' ...
        'in this project''s label maps.'], objectsPerPatch);
end

applyHeader = sprintf(['Measured on synthetic %s patches.\n\n%s\n\n' ...
    'Recommended mini-batch size: %d\n' ...
    '(an upper bound - a real run also holds the validation set and augmentation buffers)%s%s%s\n\n' ...
    'Apply this value?'], obj.BatchOpt.T_InputPatchSize, reportText, recommendedSize, ...
    instancesNote, epochsNote, trailer);
answer = utils.dlgs.inputQuestDlg(obj.view.gui, applyHeader, 'Measurement finished', ...
    sprintf('Use %d', recommendedSize), 'Keep current', sprintf('Use %d', recommendedSize), applyOpt);
if ~strcmp(answer, sprintf('Use %d', recommendedSize)); return; end

obj.BatchOpt.T_MiniBatchSize{1} = recommendedSize;
if isfield(obj.view.handles, 'T_MiniBatchSize')
    obj.view.handles.T_MiniBatchSize.Value = recommendedSize;
end
fprintf('DeepMIB: mini-batch size set to %d (%.2f patches/sec on synthetic %s patches)\n', ...
    recommendedSize, results(bestIdx,3), obj.BatchOpt.T_InputPatchSize);
end

% -------------------------------------------------------------------------------------
function secondsPerIteration = iTimeCandidate(obj, probeNetwork, inputPatchSize, outputPatchSize, ...
    miniBatchSize, numIterations, isInstanceWorkflow, objectsPerPatch)
% train on synthetic patches and return the median time of one iteration
%
% One epoch over exactly miniBatchSize*numIterations observations, so the iteration count is
% what the caller asked for. Checkpoints, plots and validation are all off, and the learning
% rate is negligible - the weights are irrelevant here, only the cost of producing them.
%
% The per-iteration times come from the trainer's own OutputFcn rather than from wrapping the
% call in tic/toc, because network setup costs seconds while an iteration costs a fraction of
% one. warmupIterations are dropped: the opening iterations carry kernel compilation and
% cuDNN autotuning, which ran 16x slower than the steady state when measured.

warmupIterations = 2;
iterationSeconds = nan(1, numIterations + 2);
recordedCount = 0;
previousElapsed = 0;

numObservations = miniBatchSize * numIterations;
trainingOptions_ = trainingOptions('adam', ...
    'MaxEpochs', 1, ...
    'MiniBatchSize', miniBatchSize, ...
    'InitialLearnRate', 1e-8, ...
    'Shuffle', 'never', ...
    'Plots', 'none', ...
    'Verbose', false, ...
    'ResetInputNormalization', false, ...
    'ExecutionEnvironment', 'auto', ...
    'OutputFcn', @recordIteration);

if isInstanceWorkflow
    probeDatastore = iSyntheticInstanceDatastore(inputPatchSize, numObservations, objectsPerPatch);
    trainSOLOV2(probeDatastore, probeNetwork, trainingOptions_, 'FreezeSubNetwork', 'none');
else
    % trainNetwork cannot consume a dlnetwork, and from R2026a the network builders return
    % one (unet, unet3d), so the engine follows what createNetwork actually produced rather
    % than obj.TrainEngine alone
    useTrainnet = isa(probeNetwork, 'dlnetwork') || strcmp(obj.TrainEngine, 'trainnet');
    probeDatastore = iSyntheticSemanticDatastore(obj, inputPatchSize, outputPatchSize, ...
        numObservations, probeNetwork, useTrainnet);
    if useTrainnet
        if isa(probeNetwork, 'dlnetwork')
            probeDlnetwork = probeNetwork;
        else
            % trainnet takes no output layer, unlike the layer graph trainNetwork wants
            probeDlnetwork = dlnetwork(removeLayers(probeNetwork, probeNetwork.Layers(end).Name));
        end
        trainnet(probeDatastore, probeDlnetwork, 'crossentropy', trainingOptions_);
    else
        trainNetwork(probeDatastore, probeNetwork, trainingOptions_);
    end
end

usableSamples = iterationSeconds(warmupIterations+1:recordedCount);
usableSamples = usableSamples(~isnan(usableSamples) & usableSamples > 0);
if isempty(usableSamples)
    secondsPerIteration = NaN;
else
    secondsPerIteration = median(usableSamples);
end

    function stopState = recordIteration(progressInfo)
        % nested so it can write into iterationSeconds without a global or a handle class
        stopState = false;
        if ~isfield(progressInfo, 'Iteration') || isempty(progressInfo.Iteration) || ...
                progressInfo.Iteration == 0
            return;
        end
        if isfield(progressInfo, 'TimeSinceStart')
            currentElapsed = progressInfo.TimeSinceStart;        % trainNetwork, seconds
        elseif isfield(progressInfo, 'TimeElapsed')
            currentElapsed = progressInfo.TimeElapsed;           % trainnet / trainSOLOV2
            if isduration(currentElapsed); currentElapsed = seconds(currentElapsed); end
        else
            return;
        end
        recordedCount = recordedCount + 1;
        if recordedCount <= numel(iterationSeconds)
            iterationSeconds(recordedCount) = currentElapsed - previousElapsed;
        end
        previousElapsed = currentElapsed;
    end
end

% -------------------------------------------------------------------------------------
function objectsPerPatch = iSampleInstancesPerPatch(obj, patchSize)
% median number of ground-truth instances a patch of this project actually contains
%
% Windows are placed the way deepmib.readInstancePatch places them - object-seeded 90% of
% the time, uniform-random otherwise - because a uniform sample would land in background far
% more often than training does and would report too few objects.
%
% Only the ``instanceLabelMap`` variable of each ``*.mat`` is loaded; the images are never
% touched, which keeps this at roughly 15 ms per file. Deliberately independent of
% deepmib.readInstancePatch despite duplicating its window placement: that function
% short-circuits on the ``mibDeepTrainingProgressStruct`` globals, so a stale
% ``spinDownActive`` left by an earlier stopped run would silently hand back placeholder
% observations and a stale ``emergencyBrake`` would throw - neither is acceptable in a
% measurement tool that runs when no training is in progress.

filesToSample = 12;
windowsPerFile = 3;
objectFraction = 0.9;       % same object-seeded/uniform mix as deepmib.readInstancePatch
minObjectArea = 4;          % same threshold, drops slivers left at the window edge
% what this function assumed unconditionally before it measured anything; also the answer
% for a project whose labels have not been preprocessed yet
fallbackCount = 5;

objectsPerPatch = fallbackCount;
try
    labelDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainLabels');
    fileList = dir(fullfile(labelDir, '*.mat'));
    if isempty(fileList); return; end
    if numel(fileList) > filesToSample
        fileList = fileList(round(linspace(1, numel(fileList), filesToSample)));
    end

    counts = nan(numel(fileList) * windowsPerFile, 1);
    countIdx = 0;
    for fileIdx = 1:numel(fileList)
        data = load(fullfile(fileList(fileIdx).folder, fileList(fileIdx).name), 'instanceLabelMap');
        if ~isfield(data, 'instanceLabelMap') || isempty(data.instanceLabelMap); continue; end
        labelMap = data.instanceLabelMap;
        [height, width] = size(labelMap);
        % a patch larger than the image is padded during training, so the whole image is
        % the window in that case
        patchHeight = min(patchSize(1), height);
        patchWidth = min(patchSize(2), width);
        objectList = unique(labelMap(labelMap > 0));

        for windowIdx = 1:windowsPerFile
            if ~isempty(objectList) && rand <= objectFraction
                objectId = objectList(randi(numel(objectList)));
                [rowsOfObject, colsOfObject] = find(labelMap == objectId);
                anchorIdx = randi(numel(rowsOfObject));
                % same jitter as the training reader: the object lands anywhere in the patch
                topRow  = rowsOfObject(anchorIdx) - randi(patchHeight) + 1;
                leftCol = colsOfObject(anchorIdx) - randi(patchWidth) + 1;
            else
                topRow  = randi(height - patchHeight + 1);
                leftCol = randi(width - patchWidth + 1);
            end
            topRow  = min(max(topRow, 1), height - patchHeight + 1);
            leftCol = min(max(leftCol, 1), width - patchWidth + 1);

            window = labelMap(topRow:topRow+patchHeight-1, leftCol:leftCol+patchWidth-1);
            presentLabels = double(window(window > 0));
            countIdx = countIdx + 1;
            if isempty(presentLabels)
                counts(countIdx) = 0;
            else
                areaPerLabel = accumarray(presentLabels(:), 1);
                counts(countIdx) = sum(areaPerLabel >= minObjectArea);
            end
        end
    end

    counts = counts(~isnan(counts));
    if ~isempty(counts)
        % at least 1: a patch with no object still costs the loss something, and 0 would
        % build a degenerate [h w 0] mask stack that trainSOLOV2 cannot consume
        objectsPerPatch = max(1, round(median(counts)));
    end
catch
    % a half-prepared project must never stop the measurement
    objectsPerPatch = fallbackCount;
end
end

% -------------------------------------------------------------------------------------
function probeDatastore = iSyntheticInstanceDatastore(inputPatchSize, numObservations, objectsPerPatch)
% random images with square objects, in the 4-column layout trainSOLOV2 wants
% (image, boxes, labels, masks), matching what deepmib.readInstancePatch produces
%
% objectsPerPatch comes from the project's own label maps (see iSampleInstancesPerPatch)
% because it, not the patch size, is what drives SOLOv2's cost and its target tensor size

objectSide = max(16, round(min(inputPatchSize(1:2))/8));
images = cell(numObservations,1); boxes = cell(numObservations,1);
labels = cell(numObservations,1); masks = cell(numObservations,1);
for observationIdx = 1:numObservations
    images{observationIdx} = randi([0 255], inputPatchSize, 'uint8');
    patchBoxes = zeros(objectsPerPatch, 4);
    patchMasks = false([inputPatchSize(1:2) objectsPerPatch]);
    for objectIdx = 1:objectsPerPatch
        left = randi([1 max(1, inputPatchSize(2)-objectSide-1)]);
        top  = randi([1 max(1, inputPatchSize(1)-objectSide-1)]);
        patchBoxes(objectIdx,:) = [left top objectSide objectSide];
        patchMasks(top:top+objectSide, left:left+objectSide, objectIdx) = true;
    end
    boxes{observationIdx} = patchBoxes;
    masks{observationIdx} = patchMasks;
    labels{observationIdx} = repmat(categorical("object"), objectsPerPatch, 1);
end
probeDatastore = combine(arrayDatastore(images, 'OutputType', 'same'), ...
    arrayDatastore(boxes, 'OutputType', 'same'), ...
    arrayDatastore(labels, 'OutputType', 'same'), ...
    arrayDatastore(masks, 'OutputType', 'same'));
end

% -------------------------------------------------------------------------------------
function probeDatastore = iSyntheticSemanticDatastore(obj, inputPatchSize, outputPatchSize, ...
    numObservations, probeNetwork, useOneHot)
% random image patches paired with random labels of the size the network outputs
%
% trainnet takes one-hot numeric targets, which sidesteps having to match the categorical
% class names of the output layer; trainNetwork needs the categoricals, so those are taken
% from the output layer itself when it declares them. The caller decides which, because it
% also depends on whether createNetwork returned a dlnetwork or a layer graph.
%
% **outputPatchSize cannot be read positionally.** createNetwork fills it differently per
% architecture: ``[h w 1 numClasses]`` for U-net, ``[h w d colours]`` for SegNet,
% ``[h w colours]`` for DeepLab v3+, ``[h w 1]`` for 2.5D U-net +Encoder. Only the leading
% spatial entries are common to all of them, so the class count comes from
% BatchOpt.T_NumberOfClasses, which is what createNetwork passes to the builders in the
% first place.
%
% Which dimensions are spatial follows the same rule createNetwork uses: 3D Semantic and the
% "3DC" 2.5D architectures convolve in 3D, while the "Z2C" ones feed the depth slices in as
% colour channels and are 2D networks.

is3D = strcmp(obj.BatchOpt.Workflow{1}, '3D Semantic');
usesDepthAsColour = false;
if strcmp(obj.BatchOpt.Workflow{1}, '2.5D Semantic')
    is3D = strncmp(obj.BatchOpt.Architecture{1}, '3DC', 3);
    usesDepthAsColour = ~is3D;
end

if is3D
    imageSize = inputPatchSize([1 2 3 4]);
    labelSize = outputPatchSize(1:3);
elseif usesDepthAsColour
    imageSize = inputPatchSize([1 2 3]);     % depth carries the colour channels
    labelSize = outputPatchSize(1:2);
else
    imageSize = inputPatchSize([1 2 4]);
    labelSize = outputPatchSize(1:2);
end
numClasses = obj.BatchOpt.T_NumberOfClasses{1};

images = cell(numObservations,1);
targets = cell(numObservations,1);
if ~useOneHot
    classNames = arrayfun(@(k) sprintf('Class%d', k), 1:numClasses, 'UniformOutput', false);
    outputLayer = probeNetwork.Layers(end);
    if isprop(outputLayer, 'Classes') && ~isempty(outputLayer.Classes) && ...
            ~(ischar(outputLayer.Classes) && strcmp(outputLayer.Classes, 'auto'))
        classNames = cellstr(string(outputLayer.Classes));
    end
end

for observationIdx = 1:numObservations
    images{observationIdx} = rand(imageSize, 'single');
    labelIndices = randi(numClasses, labelSize);
    if useOneHot
        % the class dimension is the last one, whether the patch is 2D or 3D, so index it
        % generically rather than with a fixed (:,:,k)
        oneHot = zeros([labelSize numClasses], 'single');
        classStride = prod(labelSize);
        for classIdx = 1:numClasses
            oneHot((classIdx-1)*classStride + (1:classStride)) = single(labelIndices(:) == classIdx);
        end
        targets{observationIdx} = oneHot;
    else
        targets{observationIdx} = categorical(labelIndices, 1:numClasses, classNames);
    end
end
probeDatastore = combine(arrayDatastore(images, 'OutputType', 'same'), ...
    arrayDatastore(targets, 'OutputType', 'same'));
end

% -------------------------------------------------------------------------------------
function trainingObservations = iCountTrainingObservations(obj)
% how many patches one epoch draws, for the epochs/hour column
%
% Counting files rather than building a datastore, so pressing the button stays cheap. The
% directories follow the same rule startTraining uses: the originals unless preprocessing
% wrote its own copies. Returns 0 when nothing is found, which the caller reports instead of
% showing a meaningless number.

trainingObservations = 0;
try
    if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
        trainingDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainLabels');
        fileExtension = '.mat';
    elseif strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Preprocessing is not required') || ...
            strcmp(obj.BatchOpt.PreprocessingMode{1}, 'Split files for training/validation')
        trainingDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainImages');
        fileExtension = lower(['.' obj.BatchOpt.ImageFilenameExtensionTraining{1}]);
    else
        trainingDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'TrainImages');
        fileExtension = '.mibImg';
    end
    if ~isfolder(trainingDir); return; end
    noImages = numel(dir(fullfile(trainingDir, ['*' fileExtension])));
    trainingObservations = noImages * obj.BatchOpt.T_PatchesPerImage{1};
catch
    trainingObservations = 0;   % a partially configured project, just omit the column
end
end

% -------------------------------------------------------------------------------------
function durationText = iFormatDuration(totalSeconds)
% seconds as a short human-readable span, e.g. "3 days 4 h" or "18 min"

if totalSeconds >= 86400
    noDays = floor(totalSeconds/86400);
    dayWord = 'days'; if noDays == 1; dayWord = 'day'; end
    durationText = sprintf('%.0f %s %.0f h', noDays, dayWord, mod(totalSeconds,86400)/3600);
elseif totalSeconds >= 3600
    durationText = sprintf('%.0f h %.0f min', floor(totalSeconds/3600), mod(totalSeconds,3600)/60);
else
    durationText = sprintf('%.0f min', max(1, round(totalSeconds/60)));
end
end
