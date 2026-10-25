function setStarDistSettings(obj)
% SETSTARDISTSETTINGS - Update settings of the StarDist architecture and optionally check how well the rays reconstruct the training labels.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.setStarDistSettings()
%
% Opened by the settings button next to "Starting weights" when the 2D Instance workflow uses
% the StarDist architecture (see :func:`setStartingWeightsSettings`). The values are stored in
% ``obj.StarDistOpt`` and used by :func:`startTrainingStarDist`:
%
% - ``.NRays``, ``.Grid`` - design of a network trained from random weights; a pretrained
%   model or a continued network keeps its own values;
% - ``.NormalizePercentiles`` - the intensity normalisation (StarDist uses ``[1 99.8]``; the
%   pretrained models expect it);
% - ``.OptimizeThresholds`` - tune the probability and NMS thresholds on the validation images
%   after training;
% - ``.RayCheckFiles`` - number of label files used by the ray reconstruction check.
%
% **Ray reconstruction check** (StarDist's own sanity check, ``relabel_image_stardist`` in
% its ``1_data`` example). For a sample of the preprocessed training label files
% (``TrainLabels/*.mat``, evenly spaced over the list), every object is replaced by the
% star-convex polygon its centroid would predict with perfect distances: the ray distances are
% computed for the whole label image (deepmib.stardist.computeTargets, or ``stardistMex``
% directly when it exists), read at the integer centroid of each object (``floor`` of the
% 0-based centroid, as StarDist's ``astype(int)``), and drawn with
% deepmib.stardist.polygonsToLabel, later objects on top. The score is StarDist's
% ``matching_dataset(..., thresh=0).mean_true_score``: the IoU summed over the best one-to-one
% assignment (deepmib.stardist.matchInstances at threshold 0) and divided by the number of
% objects, over all sampled files. It is reported for 8 to 128 rays. A score that stays low
% even with many rays means the objects are not star-convex; StarDist cannot represent them.
% The check is cancelable and changes no setting.
%
% **Pretrained network without training.** The last checkbox runs
% :func:`createStarDistFromPretrained` after OK (after the ray check when both are ticked):
% ``2D_versatile_fluo`` is written as a ``.mibDeep`` / ``.mibCfg`` pair that the Predict tab
% uses directly, with the normalisation percentiles set in this dialog. The same is offered
% when StarDist is picked in the Architecture dropdown (see :func:`selectArchitecture`).
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.setStarDistSettings: triggered\n');
end

gridItems = {'1', '2', '4'};
gridIndex = find(strcmp(gridItems, num2str(obj.StarDistOpt.Grid)), 1);
if isempty(gridIndex); gridIndex = 2; end

prompts = {'Number of rays per object [32]'; ...
    sprintf('Grid: the network predicts every n-th pixel;\n2 is faster and sees larger objects,\n1 suits very small objects [2]'); ...
    sprintf('Lower percentile of the intensity normalisation [1]'); ...
    sprintf('Upper percentile of the intensity normalisation [99.8]'); ...
    sprintf('Tune the detection thresholds\non the validation images after training'); ...
    sprintf('Test whether my objects suit StarDist\n(runs after OK, on the training labels)'); ...
    sprintf('Number of training label files to test'); ...
    sprintf('Create a network file from the pretrained\nmodel, for prediction without training\n(runs after OK)')};
defAns = {struct('Spinner', true, 'Value', obj.StarDistOpt.NRays, 'Limits', [3 256], 'Step', 1, 'Round', true); ...
    [gridItems, {gridIndex}]; ...
    struct('Spinner', true, 'Value', obj.StarDistOpt.NormalizePercentiles(1), 'Limits', [0 50], 'Step', 0.1, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.StarDistOpt.NormalizePercentiles(2), 'Limits', [50 100], 'Step', 0.1, 'Round', false); ...
    logical(obj.StarDistOpt.OptimizeThresholds); ...
    false; ...
    struct('Spinner', true, 'Value', obj.StarDistOpt.RayCheckFiles, 'Limits', [1 Inf], 'Step', 1, 'Round', true); ...
    false};

dlgOptions.WindowWidth = 600;
dlgOptions.WindowHeight = 460;
dlgOptions.Title = 'StarDist settings';
dlgOptions.HeaderLines = 3;
dlgOptions.LabelPosition = 'left';
header = sprintf(['The number of rays and the grid apply to a network trained from random weights;\n' ...
    'a pretrained StarDist model or a continued network keeps its own (32 rays, grid 2 for ' ...
    '2D_versatile_fluo).']);
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, 'StarDist settings', dlgOptions);
if isempty(answer); return; end

if answer{3} >= answer{4}
    msgOpt.MsgBoxOnly = true;
    msgOpt.Icon = 'puffin_warning';
    utils.dlgs.inputUniversalDlg(obj.view.gui, sprintf(['The lower percentile (%g) must be smaller than the upper one (%g).\n\n' ...
        'The settings were not changed.'], answer{3}, answer{4}), {}, {}, 'Wrong configuration', msgOpt);
    return;
end

obj.StarDistOpt.NRays = answer{1};
obj.StarDistOpt.Grid = str2double(answer{2});
obj.StarDistOpt.NormalizePercentiles = [answer{3}, answer{4}];
obj.StarDistOpt.OptimizeThresholds = logical(answer{5});
obj.StarDistOpt.RayCheckFiles = answer{7};

if answer{6}
    localRayReconstructionCheck(obj);
end
if answer{8}
    obj.createStarDistFromPretrained();
end
end

% -------------------------------------------------------------------------------------
function localRayReconstructionCheck(obj)
% StarDist relabel_image_stardist + matching_dataset(thresh=0).mean_true_score
labelsDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainLabels');
fileList = dir(fullfile(labelsDir, '*.mat'));
msgOpt.MsgBoxOnly = true;
if isempty(fileList)
    msgOpt.Icon = 'puffin_warning';
    msgOpt.HeaderLines = 1;
    msgOpt.WindowHeight = 200;
    utils.dlgs.inputUniversalDlg(obj.view.gui, 'Files are missing!', {}, {sprintf(['Preprocessed label files (*.mat) are missing in\n\n%s\n\n' ...
        'Preprocess the labels for training first'], labelsDir)}, 'Ray reconstruction check', msgOpt);
    return;
end
fileIds = unique(round(linspace(1, numel(fileList), min(numel(fileList), obj.StarDistOpt.RayCheckFiles))));
rayCounts = [8 16 32 64 128];
useMex = exist('stardistMex', 'file') == 3;

progressDlg = uiprogressdlg(obj.view.gui, 'Message', 'Reconstructing the training labels...', ...
    'Title', 'Ray reconstruction check', 'Cancelable', 'on');
cleanupDlg = onCleanup(@() delete(progressDlg));
sumIoU = zeros(1, numel(rayCounts));
nObjects = 0;
for fileNo = 1:numel(fileIds)
    data = load(fullfile(labelsDir, fileList(fileIds(fileNo)).name), 'instanceLabelMap');
    labelMap = data.instanceLabelMap;
    stats = regionprops(labelMap, 'Centroid');
    centroids = reshape([stats.Centroid], 2, [])';
    centroids = centroids(~isnan(centroids(:, 1)), :);
    points = floor([centroids(:, 2), centroids(:, 1)] - 1);     % 0-based [row col]
    linearIndex = points(:, 1) + 1 + points(:, 2) * size(labelMap, 1);
    for rayNo = 1:numel(rayCounts)
        if progressDlg.CancelRequested; return; end
        progressDlg.Value = ((fileNo - 1) * numel(rayCounts) + rayNo - 1) / (numel(fileIds) * numel(rayCounts));
        if useMex
            dist = stardistMex('starDist', uint32(labelMap), rayCounts(rayNo), 1, 1);
        else
            targets = deepmib.stardist.computeTargets(labelMap, struct('nRays', rayCounts(rayNo), 'grid', [1 1]));
            dist = targets(:, :, 2:end);
        end
        dist = reshape(dist, [], rayCounts(rayNo));
        reconstructed = deepmib.stardist.polygonsToLabel(points, double(dist(linearIndex, :)), ...
            (1:numel(linearIndex))', size(labelMap));
        matchStats = deepmib.stardist.matchInstances(labelMap, reconstructed, 0);
        sumIoU(rayNo) = sumIoU(rayNo) + matchStats.sumMatchedIoU;
        if rayNo == 1; nObjects = nObjects + matchStats.nTrue; end
    end
end
meanIoU = sumIoU / max(nObjects, 1);

lines = arrayfun(@(rays, score) sprintf('%5d rays:  %.3f', rays, score), rayCounts, meanIoU, 'UniformOutput', false);
current = find(rayCounts == obj.StarDistOpt.NRays, 1);
if ~isempty(current); lines{current} = [lines{current} '   <- current setting']; end
msgOpt.HeaderLines = 2;
msgOpt.WindowWidth = 560;
msgOpt.WindowHeight = 460;
msgOpt.Icon = 'puffin_measure';
utils.dlgs.inputUniversalDlg(obj.view.gui, ...
    sprintf('How well StarDist can represent your objects\n(%d objects tested in %d of %d training label files)', ...
    nObjects, numel(fileIds), numel(fileList)), {''}, ...
    {sprintf(['Shape match, 1 = perfect:\n\n%s\n\n' ...
    'Each object of your labels was replaced by the outline that StarDist would draw for it ' ...
    'if the network were perfectly trained, and compared with the original shape. ' ...
    'The value is the best StarDist can reach on these objects.\n\n' ...
    '- Close to 1: the objects suit StarDist.\n' ...
    '- Use a number of rays after which the value hardly improves.\n' ...
    '- Low even with 128 rays: the objects are too irregular for StarDist ' ...
    '(for example bent, branched or hollow); use SOLOv2 instead.'], strjoin(lines, newline))}, ...
    'Is StarDist suitable?', msgOpt);
end
