function evaluateSegmentationInstances(obj)
% EVALUATESEGMENTATIONINSTANCES - evaluate 2D Instance predictions by matching objects with the ground truth.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.evaluateSegmentationInstances()
%
% Called by evaluateSegmentation for the ``'2D Instance'`` workflow (SOLOv2 and StarDist).
% The semantic evaluation (``evaluateSemanticSegmentation``) cannot be used for instances:
% ``pixelLabelDatastore`` reads only uint8 label images, and it would treat every object id
% as a separate class.
%
% **Files.** The predictions are the ``*.model`` files of
% ``ResultingImagesDir\PredictionImages\ResultsModels`` written by startPredictionInstances
% (one unique index per object, per slice). The ground truth is read from
% ``OriginalPredictionImagesDir\Labels`` with the extension of "Model extension"
% (``BatchOpt.ModelFilenameExtension``): MIB ``.model`` files (deepmib.storeLoadModel) or
% label images (``imread``, all pages of a multi-page TIF), each object with its own index
% and background 0 - the same convention as the training labels
% (processImagesForInstanceSegmentation). The files are paired in alphabetical order, as in
% the semantic evaluation; the pairing is listed in the per-image table. A single ground-truth
% ``.model`` file is also accepted when its slices are the ground truth of the prediction files
% in that order (the "Single MIB model file" layout). Predictions and ground truth must have
% the same height, width and number of slices; z-stacks are evaluated slice by slice, because
% the predicted indices are per slice. When ``Labels`` has no file with the selected extension
% but has files with another extension of ``BatchOpt.ModelFilenameExtension{2}``, the message
% names that extension: "Model extension" is restored from the loaded network file, so it can
% differ from the labels of the prediction directory.
%
% **Matching.** For every slice deepmib.stardist.matchInstances matches predicted and true
% objects one-to-one at each IoU threshold (a pair matches when its IoU is at least the
% threshold), as ``stardist.matching.matching``. With ``TP`` matched pairs, ``FP = nPred - TP``
% and ``FN = nTrue - TP``:
%
%   - ``Precision = TP / (TP + FP)``, ``Recall = TP / (TP + FN)``
%   - ``F1 = 2 TP / (2 TP + FP + FN)``
%   - ``Accuracy = TP / (TP + FP + FN)`` (StarDist's accuracy, also used by its threshold tuning)
%   - ``MeanMatchedIoU`` - mean IoU of the matched pairs
%   - ``MeanTrueIoU`` - sum of the matched IoUs divided by the number of true objects
%   - ``PanopticQuality = MeanMatchedIoU * F1``
%
% A ratio with a zero denominator is 0, as StarDist's ``_safe_divide``. The dataset metrics sum
% ``TP``, ``nTrue``, ``nPred`` and the matched IoUs over all slices before the ratios are taken
% (``matching_dataset`` with ``by_image=False``), so images with many objects weigh more.
%
% The thresholds are typed as a MATLAB expression, e.g. ``0.1:0.1:0.9`` (default) or
% ``0.5 0.7``, and kept in ``preferences.Deep.Metrics.InstanceIoUThresholds``. The overlap
% matrix of a slice is dense (true x predicted objects), which is fine up to a few thousand
% objects per slice.
%
% **Results**: a figure with F1, precision, recall and panoptic quality against the IoU
% threshold, a summary dialog, and optional export to the MATLAB workspace (variable
% ``instanceMetrics``), a MAT file, an Excel file or CSV files in ``ResultsModels``
% (``EvaluationInstances*``). The exported struct has ``.Info`` (network, directories,
% thresholds), ``.DataSetMetrics`` (one row per threshold) and ``.ImageMetrics`` (one row per
% slice and threshold, with the paired filenames and the slice number). Cancel during the
% matching returns without results.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.evaluateSegmentationInstances: triggered\n');
end

truthDir = fullfile(obj.BatchOpt.OriginalPredictionImagesDir, 'Labels');
truthExtension = obj.BatchOpt.ModelFilenameExtension{1};
truthList = dir(fullfile(truthDir, lower(['*.' truthExtension])));
predictionDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
predictionList = dir(fullfile(predictionDir, '*.model'));

if isempty(truthList) || isempty(predictionList)
    messageParts = {};
    if isempty(truthList)
        messageParts{end+1} = sprintf('No ground truth labels (*.%s) in\n%s', lower(truthExtension), truthDir);
        % labels saved with another extension are the usual cause (the extension is restored
        % from the loaded network file), so name the one that is there
        otherExtensions = setdiff(obj.BatchOpt.ModelFilenameExtension{2}, {truthExtension}, 'stable');
        for extensionId = 1:numel(otherExtensions)
            numFiles = numel(dir(fullfile(truthDir, lower(['*.' otherExtensions{extensionId}]))));
            if numFiles > 0
                messageParts{end} = sprintf(['%s\n\nThe folder has %d *.%s file(s): set "Model extension" to %s ' ...
                    'on the Directories and Preprocessing tab'], messageParts{end}, numFiles, ...
                    lower(otherExtensions{extensionId}), otherExtensions{extensionId});
                break;
            end
        end
    end
    if isempty(predictionList)
        messageParts{end+1} = sprintf(['No predicted models (*.model) in\n%s\n\nRun the prediction first, or check ' ...
            '"Directory with resulting images" on the Directories and Preprocessing tab'], predictionDir);
    end
    localMessage(obj, 'Missing files', strjoin(messageParts, sprintf('\n\n')));
    return;
end
singleTruthFile = isscalar(truthList) && numel(predictionList) > 1 && strcmpi(truthExtension, 'MODEL');
if numel(truthList) ~= numel(predictionList) && ~singleTruthFile
    localMessage(obj, 'Wrong number of files', sprintf(['The number of ground truth files (%d) differs from the number of ' ...
        'predicted models (%d).\n\nGround truth: %s\nPredictions: %s'], numel(truthList), numel(predictionList), truthDir, predictionDir));
    return;
end

%% Settings
if ~isfield(obj.mibModel.preferences.Deep.Metrics, 'InstanceIoUThresholds')
    % preferences of a session started before this field existed; default of generatePreferences
    obj.mibModel.preferences.Deep.Metrics.InstanceIoUThresholds = '0.1:0.1:0.9';
end
dlgOptions.Header = sprintf(['Each predicted object is matched with at most one ground-truth object;\n' ...
    'a pair counts as a match when its IoU is at least the threshold']);
dlgOptions.HeaderLines = 2;
dlgOptions.WindowStyle = 'normal';
dlgOptions.WindowWidth = 500;
dlgOptions.LabelPosition = 'left';
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', {'IoU thresholds (e.g. 0.1:0.1:0.9 or 0.5 0.7):'}, ...
    {obj.mibModel.preferences.Deep.Metrics.InstanceIoUThresholds}, 'Instance evaluation settings', dlgOptions);
if isempty(answer); return; end
iouThresholds = str2num(answer{1}); %#ok<ST2NM>
if isempty(iouThresholds) || ~isnumeric(iouThresholds) || any(iouThresholds <= 0 | iouThresholds > 1)
    localMessage(obj, 'Wrong thresholds', sprintf('IoU thresholds should be numbers above 0 and up to 1, for example\n0.1:0.1:0.9 or 0.5 0.7'));
    return;
end
iouThresholds = unique(iouThresholds(:)');
obj.mibModel.preferences.Deep.Metrics.InstanceIoUThresholds = answer{1};
numThresholds = numel(iouThresholds);

%% Matching
progressDlg = uiprogressdlg(obj.view.gui, 'Message', 'Matching objects...', ...
    'Title', 'Evaluate instance segmentation', 'Cancelable', 'on');
cleanupDlg = onCleanup(@() localDeleteDialog(progressDlg));

try
    if singleTruthFile
        truthVolume = deepmib.storeLoadModel(fullfile(truthList(1).folder, truthList(1).name));
        if size(truthVolume, 3) ~= numel(predictionList)
            delete(progressDlg);
            localMessage(obj, 'Wrong ground truth', sprintf(['The ground truth file %s has %d slice(s), while there are %d predicted ' ...
                'models.\n\nA single ground truth file must have one slice per predicted model'], ...
                truthList(1).name, size(truthVolume, 3), numel(predictionList)));
            return;
        end
    end

    % per slice: [nTrue, nPred] and per threshold TP and the sum of matched IoUs
    numSlicesTotal = 0;
    sliceInfo = cell(0, 3);     % prediction file, ground truth file, slice number
    sliceCounts = zeros(0, 2);
    sliceTP = zeros(0, numThresholds);
    sliceSumIoU = zeros(0, numThresholds);
    for fileId = 1:numel(predictionList)
        if progressDlg.CancelRequested; delete(progressDlg); localCancelled(obj); return; end
        progressDlg.Value = (fileId - 1) / numel(predictionList);
        progressDlg.Message = sprintf('Matching objects: %s (%d / %d)', predictionList(fileId).name, fileId, numel(predictionList));

        prediction = deepmib.storeLoadModel(fullfile(predictionList(fileId).folder, predictionList(fileId).name));
        if singleTruthFile
            truth = truthVolume(:, :, fileId);
            truthName = sprintf('%s (slice %d)', truthList(1).name, fileId);
        else
            truth = localReadLabels(fullfile(truthList(fileId).folder, truthList(fileId).name), truthExtension);
            truthName = truthList(fileId).name;
        end
        if size(prediction, 1) ~= size(truth, 1) || size(prediction, 2) ~= size(truth, 2) || size(prediction, 3) ~= size(truth, 3)
            delete(progressDlg);
            localMessage(obj, 'Size mismatch', sprintf(['The predicted model and its ground truth have different sizes:\n\n' ...
                '%s: %s\n%s: %s\n\nThe files are paired in alphabetical order'], ...
                predictionList(fileId).name, mat2str(size(prediction, 1:3)), truthName, mat2str(size(truth, 1:3))));
            return;
        end

        for sliceId = 1:size(prediction, 3)
            if progressDlg.CancelRequested; delete(progressDlg); localCancelled(obj); return; end
            stats = deepmib.stardist.matchInstances(truth(:, :, sliceId), prediction(:, :, sliceId), iouThresholds);
            numSlicesTotal = numSlicesTotal + 1;
            sliceInfo(numSlicesTotal, :) = {predictionList(fileId).name, truthName, sliceId};
            sliceCounts(numSlicesTotal, :) = [stats.nTrue, stats.nPred];
            sliceTP(numSlicesTotal, :) = stats.truePositives;
            sliceSumIoU(numSlicesTotal, :) = stats.sumMatchedIoU;
        end
    end
catch err
    delete(progressDlg);
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Instance evaluation error');
    return;
end
progressDlg.Value = 1;
progressDlg.Message = 'Calculating metrics...';

%% Metrics
dataSetMetrics = localMetricsTable(iouThresholds, sum(sliceTP, 1), sum(sliceSumIoU, 1), ...
    sum(sliceCounts(:, 1)), sum(sliceCounts(:, 2)));

imageMetrics = cell(numSlicesTotal, 1);
for rowId = 1:numSlicesTotal
    sliceTable = localMetricsTable(iouThresholds, sliceTP(rowId, :), sliceSumIoU(rowId, :), ...
        sliceCounts(rowId, 1), sliceCounts(rowId, 2));
    fileTable = table(repmat(sliceInfo(rowId, 1), [numThresholds 1]), repmat(sliceInfo(rowId, 2), [numThresholds 1]), ...
        repmat(sliceInfo{rowId, 3}, [numThresholds 1]), 'VariableNames', {'ModelFilename', 'GroundTruthFilename', 'Slice'});
    imageMetrics{rowId} = [fileTable, sliceTable];
end
imageMetrics = vertcat(imageMetrics{:});

instanceMetrics.Info.NetworkName = obj.BatchOpt.NetworkFilename;
instanceMetrics.Info.PredictionResultsDirectory = predictionDir;
instanceMetrics.Info.GroundTruthDirectory = truthDir;
instanceMetrics.Info.IoUThresholds = iouThresholds;
instanceMetrics.DataSetMetrics = dataSetMetrics;
instanceMetrics.ImageMetrics = imageMetrics;
delete(progressDlg);

%% Results
[~, netName] = fileparts(obj.BatchOpt.NetworkFilename);
localPlotMetrics(dataSetMetrics, netName, sum(sliceCounts(:, 1)), numSlicesTotal);

summaryText = sprintf('%d true and %d predicted objects in %d image(s)\n\n', ...
    sum(sliceCounts(:, 1)), sum(sliceCounts(:, 2)), numSlicesTotal);
for thresholdId = 1:numThresholds
    row = dataSetMetrics(thresholdId, :);
    summaryText = sprintf('%sIoU %.2f:  F1 %.3f,  precision %.3f,  recall %.3f,  PQ %.3f\n', summaryText, ...
        row.IoUThreshold, row.F1, row.Precision, row.Recall, row.PanopticQuality);
end
resultOptions.HeaderLines = numel(strfind(summaryText, newline)) + 1;
resultOptions.LabelPosition = 'left';
resultOptions.WindowStyle = 'normal';
resultOptions.WindowWidth = 560;
prompts = {'Export to Matlab'; 'Save as Matlab file'; 'Save as Excel file'; 'Save as CSV file'};
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, summaryText, prompts, {false; false; false; false}, ...
    'Instance evaluation results', resultOptions);
if isempty(answer); return; end

if answer{1}
    assignin('base', 'instanceMetrics', instanceMetrics);
    fprintf('A variable "instanceMetrics" was created in Matlab\n');
end
try
    if answer{2}
        filename = fullfile(predictionDir, 'EvaluationInstances.mat');
        save(filename, 'instanceMetrics', '-v7.3');
        fprintf('Evaluation results were saved to:\n%s\n', filename);
    end
    if answer{3}
        filename = fullfile(predictionDir, 'EvaluationInstances.xlsx');
        if isfile(filename); delete(filename); end
        writecell({sprintf('Instance evaluation of %s', obj.BatchOpt.NetworkFilename)}, filename, 'Sheet', 'DataSetMetrics', 'Range', 'A1');
        writetable(dataSetMetrics, filename, 'Sheet', 'DataSetMetrics', 'Range', 'A3');
        writecell({'Prediction results directory:', predictionDir; 'Ground truth directory:', truthDir}, filename, 'Sheet', 'ImageMetrics', 'Range', 'A1');
        writetable(imageMetrics, filename, 'Sheet', 'ImageMetrics', 'Range', 'A4');
        fprintf('Evaluation results were saved to:\n%s\n', filename);
    end
    if answer{4}
        filename = fullfile(predictionDir, 'EvaluationInstancesDataSetMetrics.csv');
        writetable(dataSetMetrics, filename);
        writetable(imageMetrics, fullfile(predictionDir, 'EvaluationInstancesImageMetrics.csv'));
        fprintf('Evaluation results were saved to:\n%s\n%s\n', filename, fullfile(predictionDir, 'EvaluationInstancesImageMetrics.csv'));
    end
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Saving evaluation results', ...
        sprintf('The file may be open elsewhere\n\n%s', filename));
end
end

% -------------------------------------------------------------------------------------
function labels = localReadLabels(filename, extension)
% instance label image: a MIB model, or all pages of an image file
if strcmpi(extension, 'MODEL')
    labels = deepmib.storeLoadModel(filename);
    return;
end
info = imfinfo(filename);
labels = imread(filename, 1);
if numel(info) > 1
    labels(:, :, numel(info)) = 0;
    for pageId = 2:numel(info)
        labels(:, :, pageId) = imread(filename, pageId);
    end
end
end

function metrics = localMetricsTable(iouThresholds, tp, sumIoU, nTrue, nPred)
% one row per threshold; ratios with a zero denominator are 0 (StarDist _safe_divide)
tp = tp(:);
sumIoU = sumIoU(:);
fp = nPred - tp;
fn = nTrue - tp;
safeDivide = @(numerator, denominator) (denominator > 0) .* numerator ./ max(denominator, eps);
meanMatchedIoU = safeDivide(sumIoU, tp);
f1 = safeDivide(2 * tp, 2 * tp + fp + fn);
numRows = numel(iouThresholds);
metrics = table(iouThresholds(:), repmat(nTrue, [numRows 1]), repmat(nPred, [numRows 1]), tp, fp, fn, ...
    safeDivide(tp, tp + fp), safeDivide(tp, tp + fn), f1, safeDivide(tp, tp + fp + fn), ...
    meanMatchedIoU, safeDivide(sumIoU, repmat(nTrue, [numRows 1])), meanMatchedIoU .* f1, ...
    'VariableNames', {'IoUThreshold', 'NumTrue', 'NumPredicted', 'TP', 'FP', 'FN', 'Precision', 'Recall', ...
    'F1', 'Accuracy', 'MeanMatchedIoU', 'MeanTrueIoU', 'PanopticQuality'});
end

function localPlotMetrics(dataSetMetrics, netName, numTrue, numImages)
% F1, precision, recall and panoptic quality against the IoU threshold
seriesNames = {'F1', 'Precision', 'Recall', 'PanopticQuality'};
seriesLabels = {'F1', 'Precision', 'Recall', 'Panoptic quality'};
seriesColors = [0.165 0.471 0.839; 0.922 0.408 0.204; 0.106 0.686 0.478; 0.929 0.631 0];
seriesMarkers = {'o', 's', '^', 'd'};
hFig = figure('Name', sprintf('Instance evaluation: %s', netName), 'NumberTitle', 'off');
hAxes = axes(hFig);
hold(hAxes, 'on');
for seriesId = 1:numel(seriesNames)
    plot(hAxes, dataSetMetrics.IoUThreshold, dataSetMetrics.(seriesNames{seriesId}), ['-' seriesMarkers{seriesId}], ...
        'Color', seriesColors(seriesId, :), 'MarkerFaceColor', seriesColors(seriesId, :), ...
        'LineWidth', 1.5, 'MarkerSize', 6, 'DisplayName', seriesLabels{seriesId});
end
hold(hAxes, 'off');
hAxes.YLim = [0 1];
hAxes.XLim = [max(0, min(dataSetMetrics.IoUThreshold) - 0.05), min(1, max(dataSetMetrics.IoUThreshold) + 0.05)];
hAxes.Box = 'off';
grid(hAxes, 'on');
hAxes.GridAlpha = 0.15;
xlabel(hAxes, 'IoU threshold');
ylabel(hAxes, 'Score');
title(hAxes, {strrep(netName, '_', '\_'), sprintf('%d ground-truth objects in %d image(s)', numTrue, numImages)}, 'FontWeight', 'normal');
legend(hAxes, 'Location', 'southwest', 'Box', 'off');
end

function localCancelled(obj)
localMessage(obj, 'Evaluation cancelled', 'The evaluation was cancelled; no results were calculated or saved');
end

function localMessage(obj, title, text)
% message box: the title as a one-line header, the text in the body. The height is computed from
% the wrapped lines of the text, because the automatic estimate of inputUniversalDlg counts the
% line breaks of plain text twice and makes the window far too tall
msgOpt.MsgBoxOnly = true;
msgOpt.Icon = 'puffin_warning';
msgOpt.HeaderLines = 1;
msgOpt.WindowWidth = 520;
charsPerLine = floor((msgOpt.WindowWidth - 140) / 7);
textLines = strsplit(text, newline);
wrappedLines = sum(max(1, ceil(cellfun(@numel, textLines) / charsPerLine)));
msgOpt.WindowHeight = min(800, 130 + 20 * wrappedLines);
utils.dlgs.inputUniversalDlg(obj.view.gui, title, {''}, {text}, title, msgOpt);
end

function localDeleteDialog(dialogHandle)
if ~isempty(dialogHandle) && isvalid(dialogHandle); delete(dialogHandle); end
end
