function updateOverlapInstancesSettings(obj)
% UPDATEOVERLAPINSTANCESSETTINGS - update settings for stitching of instances across tiles.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateOverlapInstancesSettings()
%
% Settings for prediction in the 2D Instance workflow; the stitching mode itself is
% selected with the "Overlap mode" dropdown (BatchOpt.P_OverlapInstancesMode) and the
% values below are stored in obj.OverlapInstancesOpt:
%
%   - `.DetectionThreshold` - confidence threshold of segmentObjects [both overlap modes]
%   - `.MergeIoU` - in-band intersection-over-union to merge detections ["IoU merge" mode]
%   - `.MergeIoA` - in-band intersection-over-smaller-area to merge detections ["IoU merge" mode]
%   - `.MinSplitArea` - min area, px, of a component kept when a stitched label is split into
%     one index per connected object [both overlap modes]
%
% With the StarDist architecture the button opens the StarDist prediction settings instead,
% stored in obj.StarDistOpt and used by startPredictionInstances:
%
%   - `.PredictThresholds` - ``'From the network'`` uses the probability and NMS thresholds
%     stored in the network file (tuned on the validation images after training, see
%     startTrainingStarDist); ``'Custom'`` uses `.ProbThresh` and `.NmsThresh`. The header shows
%     the thresholds of the network selected in the Predict tab when its file exists.
%   - `.PredictTileSize` - core size of the prediction tiles, see deepmib.stardist.predictMaps;
%     the overlap needed for seamless maps is added automatically, so larger tiles only trade
%     memory for speed.

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.updateOverlapInstancesSettings: triggered\n');
end

% StarDist tiles its probability and distance maps, not the instances, so it has nothing to
% stitch; the same button opens its prediction settings instead
if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance') && strcmp(obj.BatchOpt.Architecture{1}, 'StarDist')
    localStarDistPredictionSettings(obj);
    return;
end

% lazy init to cover instances created before this property was introduced
if isempty(obj.OverlapInstancesOpt)
    obj.OverlapInstancesOpt = struct('DetectionThreshold', 0.5, 'MergeIoU', 0.5, 'MergeIoA', 0.8, 'MinSplitArea', 100);
end
if ~isfield(obj.OverlapInstancesOpt, 'MinSplitArea')     % settings saved before this field existed
    obj.OverlapInstancesOpt.MinSplitArea = 100;
end

prompts = {...
    sprintf('Detection confidence threshold (0-1):\nminimal confidence score for a detected instance to be kept;\ndecrease to detect more (weaker) objects, increase to keep only confident detections\n[used by both overlap modes]'); ...
    sprintf('\nMerge IoU threshold (0-1):\nmerge detections of neighboring tiles when the intersection-over-union of their masks\nwithin the shared overlap band exceeds this value;\ndecrease when objects get split at tile seams, increase when distinct touching objects get merged\n[used by the "IoU merge" mode]'); ...
    sprintf('\nMerge IoA threshold (0-1):\nadditionally merge when the intersection over the smaller in-band mask area exceeds this value;\nthis catches a truncated fragment that is fully contained in the neighboring tile''s complete mask,\nand is applied only to fragments that really are cut by a tile edge\n[used by the "IoU merge" mode]'); ...
    sprintf('\nMinimal object area, pixels:\nafter stitching, each index is split into its separate objects so that two isolated objects\nnever share one index; components smaller than this are discarded as speckle;\nset to 0 to keep every component\n[used by both overlap modes]')};

defAns = {...
    struct('Spinner', true, 'Value', obj.OverlapInstancesOpt.DetectionThreshold, 'Limits', [0 1], 'Step', 0.05, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.OverlapInstancesOpt.MergeIoU, 'Limits', [0 1], 'Step', 0.05, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.OverlapInstancesOpt.MergeIoA, 'Limits', [0 1], 'Step', 0.05, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.OverlapInstancesOpt.MinSplitArea, 'Limits', [0 Inf], 'Step', 10, 'Round', true)};

dlgTitle = 'Instance stitching settings';
options.WindowStyle = 'normal';
options.WindowWidth = 650;
options.WindowHeight = 500;
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
if isempty(answer); return; end

obj.OverlapInstancesOpt.DetectionThreshold = answer{1};
obj.OverlapInstancesOpt.MergeIoU = answer{2};
obj.OverlapInstancesOpt.MergeIoA = answer{3};
obj.OverlapInstancesOpt.MinSplitArea = answer{4};
end

% -------------------------------------------------------------------------------------
function localStarDistPredictionSettings(obj)
% thresholds and tile size of StarDist prediction, stored in obj.StarDistOpt
networkInfo = 'no StarDist network is selected';
if isfile(obj.BatchOpt.NetworkFilename)
    try
        saved = load(obj.BatchOpt.NetworkFilename, '-mat', 'StarDistConfig');
        if isfield(saved, 'StarDistConfig')
            networkInfo = sprintf('the selected network has probability %.3f, overlap %.2f', ...
                saved.StarDistConfig.probThresh, saved.StarDistConfig.nmsThresh);
        else
            networkInfo = 'the selected network is not a StarDist network';
        end
    catch
        % an unreadable file is reported when Predict is pressed
    end
end

thresholdItems = {'From the network', 'Custom'};
thresholdIndex = find(strcmp(thresholdItems, obj.StarDistOpt.PredictThresholds), 1);
if isempty(thresholdIndex); thresholdIndex = 1; end
prompts = {sprintf('Detection thresholds:\n"From the network" uses the values tuned after training'); ...
    sprintf('Custom probability threshold (0-1):\nlower to detect more (weaker) objects'); ...
    sprintf('Custom overlap threshold (0-1):\nlower to suppress more overlapping detections'); ...
    sprintf('Tile size, pixels:\nlarger tiles are faster but need more GPU memory')};
defAns = {[thresholdItems, {thresholdIndex}]; ...
    struct('Spinner', true, 'Value', obj.StarDistOpt.ProbThresh, 'Limits', [0 1], 'Step', 0.01, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.StarDistOpt.NmsThresh, 'Limits', [0 1], 'Step', 0.05, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.StarDistOpt.PredictTileSize, 'Limits', [64 16384], 'Step', 128, 'Round', true)};
options.WindowStyle = 'normal';
options.WindowWidth = 560;
options.HeaderLines = 1;
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, sprintf('Thresholds: %s', networkInfo), ...
    prompts, defAns, 'StarDist prediction settings', options);
if isempty(answer); return; end
obj.StarDistOpt.PredictThresholds = answer{1};
obj.StarDistOpt.ProbThresh = answer{2};
obj.StarDistOpt.NmsThresh = answer{3};
obj.StarDistOpt.PredictTileSize = answer{4};
end
