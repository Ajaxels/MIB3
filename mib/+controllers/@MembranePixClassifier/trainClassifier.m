function trainClassifier(obj)
% TRAINCLASSIFIER - Extract membrane features and train the random forest classifier.
%
% Based on skript_trainClassifier_for_membraneDetection.m by Verena Kaynig.
% Trains on all slices that contain both object and background labels,
% then predicts those same slices and stores the result in the Selection layer.

arguments (Input)
    obj controllers.MembranePixClassifier
end

if isempty(obj.view)
    parentFigure = obj.mibModel.mibGUI;
else
    parentFigure = obj.view.gui;
    obj.view.handles.logList.Items = {''};
    obj.view.handles.logList.Value = '';
end
obj.updateLoglist('======= Starting training... =======');

if ~isempty(obj.view)
    obj.mibModel.backup('selection', 1);
end

id = obj.mibModel.getActiveId();
contextSize       = obj.BatchOpt.ContextSize{1};
membraneThickness = obj.BatchOpt.MembraneThickness{1};
votesThreshold    = obj.BatchOpt.VotesThreshold{1};

materialNames = obj.mibModel.I{id}.labels.materialNames;
posModel = find(strcmp(materialNames, obj.BatchOpt.ObjectMaterial{1}));
negModel = find(strcmp(materialNames, obj.BatchOpt.BackgroundMaterial{1}));

if isempty(posModel) || isempty(negModel)
    utils.dlgs.showErrorDialog(parentFigure, ...
        'Object or Background material was not found in the model!', 'Missing material');
    return;
end

% block mode: need full image for feature extraction, crop result afterwards
blockModeSwitch = obj.mibModel.I{id}.blockModeSwitch;
if blockModeSwitch
    dataset   = obj.mibModel.I{id};
    yMinShown = max(ceil(dataset.axesY(1)), 1);
    yMaxShown = min(ceil(dataset.axesY(2)), dataset.image.height);
    xMinShown = max(ceil(dataset.axesX(1)), 1);
    xMaxShown = min(ceil(dataset.axesX(2)), dataset.image.width);
end

tempDir = obj.dirOut;
if exist(tempDir, 'dir') == 0; mkdir(tempDir); end

t1 = tic;
getDataOptions.blockModeSwitch = 0;   % always fetch full slices for feature extraction
labelsData = cell2mat(obj.mibModel.getData3D('labels', [], 3, [], getDataOptions));
fmPos = [];
fmNeg = [];
slicesForTraining = zeros(size(labelsData, 3), 1);

for sliceNo = 1:size(labelsData, 3)
    if ~any(labelsData(:,:,sliceNo) == posModel, 'all') && ...
            ~any(labelsData(:,:,sliceNo) == negModel, 'all')
        continue;
    end
    slicesForTraining(sliceNo) = 1;
    featuresFilename = fullfile(tempDir, sprintf('slice_%06i.fm', sliceNo));

    if ~exist(featuresFilename, 'file')
        obj.updateLoglist(sprintf('Extracting membrane features for slice: %d...', sliceNo));
        imageSlice = cell2mat(obj.mibModel.getData2D('image', sliceNo, [], [], getDataOptions));
        fm = membraneFeatures(imageSlice, contextSize, membraneThickness, contextSize, obj.mibModel.cpuParallelLimitMax);
        fm(isnan(fm)) = 0;
        save(featuresFilename, 'fm', '-mat', '-v7.3');
    else
        load(featuresFilename, 'fm', '-mat');
    end

    obj.updateLoglist(sprintf('Adding features from slice: %d...', sliceNo));
    posPos = find(labelsData(:,:,sliceNo) == posModel);
    posNeg = find(labelsData(:,:,sliceNo) == negModel);

    fm = reshape(fm, size(fm,1)*size(fm,2), size(fm,3));
    fmPos = [fmPos; fm(posPos,:)]; %#ok<AGROW>
    fmNeg = [fmNeg; fm(posNeg,:)]; %#ok<AGROW>
end
clear fm posPos posNeg labelsData;

obj.updateLoglist('======= Training the classifier... =======');
labelVector = [zeros(size(fmNeg,1),1); ones(size(fmPos,1),1)];
featureMatrix = double([fmNeg; fmPos]);
rfOptions.sampsize = [obj.maxNumberOfSamplesPerClass, obj.maxNumberOfSamplesPerClass];
obj.forest = classRF_train(featureMatrix, labelVector, 300, 5, rfOptions);

% predict training slices and write to Selection layer
for sliceNo = find(slicesForTraining == 1)'
    featuresFilename = fullfile(tempDir, sprintf('slice_%06i.fm', sliceNo));
    obj.updateLoglist(sprintf('Predicting slice: %d...', sliceNo));
    load(featuresFilename, 'fm', '-mat');

    if blockModeSwitch
        fm = fm(yMinShown:yMaxShown, xMinShown:xMaxShown, :);
    end
    imageSize = [size(fm,1), size(fm,2)];
    fm = reshape(fm, imageSize(1)*imageSize(2), size(fm,3));

    [~, votes] = classRF_predict(double(fm), obj.forest);
    votes = reshape(votes(:,2), imageSize);
    votes = double(votes) / max(votes(:));

    if obj.BatchOpt.ExportVotes
        if ~exist('votesOut', 'var')
            votesOut = zeros([imageSize(1), imageSize(2), 1, numel(find(slicesForTraining==1))]);
            voteIndex = 1;
        end
        votesOut(:,:,1,voteIndex) = votes;
        voteIndex = voteIndex + 1;
    end

    if obj.BatchOpt.SkelClosed
        skelImg = uint8(bwmorph(skeletonize(votes >= votesThreshold), 'dilate', 1));
    else
        skelImg = uint8(votes > votesThreshold);
    end
    obj.mibModel.setData2D(skelImg, 'selection', sliceNo);
end

if obj.BatchOpt.ExportVotes && exist('votesOut', 'var')
    obj.updateLoglist('======= Exporting votes to matlab =======');
    assignin('base', 'mibVotes', votesOut);
    obj.updateLoglist('Done! variable -> mibVotes(1:height, 1:width, 1, 1:slices)');
end
obj.updateLoglist('======= Training finished! =======');
obj.updateLoglist(sprintf('Elapsed time is %f seconds.', toc(t1)));
notify(obj.mibModel, 'ShowImage');

end
