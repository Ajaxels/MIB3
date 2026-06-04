function predictDataset(obj, sliceNumber)
% PREDICTDATASET - Predict membrane probability using the trained classifier.
%
% Loads a .forest classifier from disk, extracts membrane features for
% each requested slice, and writes the thresholded result to the Selection
% layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.predictDataset()           % predict entire stack
%       obj.predictDataset(sliceNo)    % predict one slice
%
% Input Arguments:
%   - **sliceNumber** — *(optional)* slice index to predict; omit to predict all slices

arguments (Input)
    obj         controllers.MembranePixClassifier
    sliceNumber (1,1) double = NaN
end

if isempty(obj.view)
    parentFigure = obj.mibModel.mibGUI;
else
    parentFigure = obj.view.gui;
    obj.view.handles.logList.Items = {''};
    obj.view.handles.logList.Value = '';
end

id = obj.mibModel.getActiveId();
if isnan(sliceNumber)
    startSlice  = 1;
    finishSlice = obj.mibModel.I{id}.image.depth;
    totalSlices = finishSlice;
else
    startSlice  = sliceNumber;
    finishSlice = sliceNumber;
    totalSlices = 1;
end

obj.updateLoglist('======= Starting prediction... =======');

if ~isempty(obj.view)
    obj.mibModel.backup('selection', 1);
end

contextSize       = obj.BatchOpt.ContextSize{1};
membraneThickness = obj.BatchOpt.MembraneThickness{1};
votesThreshold    = obj.BatchOpt.VotesThreshold{1};

% block mode: crop feature maps to the shown viewport after extraction
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
inFile = obj.classFilename;
obj.updateLoglist('Loading classifier...');
obj.updateLoglist(inFile);
if exist(inFile, 'file') == 0
    utils.dlgs.showErrorDialog(parentFigure, ...
        sprintf('!!! Error !!!\n\nThe classifier file was not found!\nTry to train the classifer and save it to a file'), ...
        'Missing the classifier');
    obj.updateLoglist('The classifier was not found!');
    return;
end
loadedData = load(inFile, '-mat');
obj.forest = loadedData.forest;
obj.updateLoglist('Classifier loaded!');

getDataOptions.blockModeSwitch = 0;
for sliceNo = startSlice:finishSlice
    featuresFilename = fullfile(tempDir, sprintf('slice_%06i.fm', sliceNo));

    if ~exist(featuresFilename, 'file')
        obj.updateLoglist(sprintf('Extracting membrane features for slice: %d...', sliceNo));
        imageSlice = cell2mat(obj.mibModel.getData2D('image', sliceNo, [], [], getDataOptions));
        fm = membraneFeatures(imageSlice, contextSize, membraneThickness, contextSize, obj.mibModel.preferences.System.cpuParallelLimit);
        fm(isnan(fm)) = 0;
        save(featuresFilename, 'fm', '-mat', '-v7.3');
    else
        load(featuresFilename, 'fm', '-mat');
    end

    obj.updateLoglist(sprintf('Predicting slice: %d...', sliceNo));
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
            votesOut = zeros([imageSize(1), imageSize(2), 1, totalSlices]);
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
obj.updateLoglist('======= Prediction finished! =======');
obj.updateLoglist(sprintf('Elapsed time is %f seconds.', toc(t1)));
notify(obj.mibModel, 'ShowImage');

end
