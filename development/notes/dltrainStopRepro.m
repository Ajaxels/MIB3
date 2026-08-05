function dltrainStopRepro
% DLTRAINSTOPREPRO - minimal reproduction for the trainSOLOV2 / images.dltrain stop issue.
%
% A stop is requested from the OutputFcn at iteration 3 in both runs below. The only
% difference between them is MaxEpochs. If the stop request were honoured, both runs would
% return after roughly the same time and would write roughly the same number of checkpoint
% files. Instead both scale with MaxEpochs, because
% images.dltrain.internal.SerialTrainer/fit only leaves its inner per-iteration loop and
% keeps running the outer "for epoch = 1:MaxEpochs" loop to completion.
%
% Accompanies the bug report "mathworks_bugreport_dltrain_stop.md".
%
% Requires the Computer Vision Toolbox Model for SOLOv2 Instance Segmentation support package.
%
% Usage:
%   >> dltrainStopRepro
% Each run prints the time trainSOLOV2 took to return after the stop was requested, and the
% number of checkpoint files written into <tempdir>/dltrainStopRepro/checkpoints_<MaxEpochs>.

runOnce(5);
runOnce(20);

end

% -------------------------------------------------------------------------------------
function runOnce(maxEpochs)

    numObservations = 4;
    patchSize = [256 256 3];

    % a fileDatastore whose ReadFcn synthesises one observation in the {image, boxes,
    % labels, masks} form trainSOLOV2 expects; the files themselves are only placeholders
    dataFolder = fullfile(tempdir, 'dltrainStopRepro');
    if ~isfolder(dataFolder); mkdir(dataFolder); end
    placeholderFiles = cell(numObservations, 1);
    for fileId = 1:numObservations
        placeholderFiles{fileId} = fullfile(dataFolder, sprintf('observation%d.mat', fileId));
        if ~isfile(placeholderFiles{fileId})
            placeholderValue = fileId;
            save(placeholderFiles{fileId}, 'placeholderValue');
        end
    end
    trainingStore = fileDatastore(placeholderFiles, ...
        'ReadFcn', @(filename) iSyntheticObservation(patchSize));

    detector = solov2('light-resnet18-coco', {'object'}, 'InputSize', patchSize);

    % a clean checkpoint folder per run, so the file count is unambiguous
    checkpointFolder = fullfile(dataFolder, sprintf('checkpoints_%d', maxEpochs));
    if isfolder(checkpointFolder); rmdir(checkpointFolder, 's'); end
    mkdir(checkpointFolder);

    trainingOpt = trainingOptions('adam', ...
        'MaxEpochs', maxEpochs, ...
        'MiniBatchSize', 1, ...
        'InitialLearnRate', 1e-4, ...
        'CheckpointPath', checkpointFolder, ...
        'Plots', 'none', ...
        'Verbose', false, ...
        'OutputFcn', @iStopAtIterationThree);

    fprintf('\n--- MaxEpochs = %d ---\n', maxEpochs);
    stopWatch = tic;
    trainSOLOV2(trainingStore, detector, trainingOpt, 'FreezeSubNetwork', 'backbone');
    elapsedTime = toc(stopWatch);

    fprintf('trainSOLOV2 returned %.1f s after a stop requested at iteration 3\n', elapsedTime);
    fprintf('checkpoint files written: %d\n', numel(dir(fullfile(checkpointFolder, '*.mat'))));

end

% -------------------------------------------------------------------------------------
function observation = iSyntheticObservation(patchSize)
% one image with a single square object, in the layout trainSOLOV2 expects

    image = uint8(128 * ones(patchSize));
    masks = false(patchSize(1), patchSize(2));
    masks(64:191, 64:191) = true;
    boxes = [64 64 128 128];    % [x y width height]
    labels = categorical({'object'}, {'object'});

    observation = {image, boxes, labels, masks};

end

% -------------------------------------------------------------------------------------
function stopFlag = iStopAtIterationThree(trainingInfo)

    stopFlag = trainingInfo.Iteration >= 3;

end
