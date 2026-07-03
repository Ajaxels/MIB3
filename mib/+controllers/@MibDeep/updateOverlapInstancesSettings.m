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
%   .DetectionThreshold - confidence threshold of segmentObjects [both overlap modes]
%   .MergeIoU - in-band intersection-over-union to merge detections ["IoU merge" mode]
%   .MergeIoA - in-band intersection-over-smaller-area to merge detections ["IoU merge" mode]

% lazy init to cover instances created before this property was introduced
if isempty(obj.OverlapInstancesOpt)
    obj.OverlapInstancesOpt = struct('DetectionThreshold', 0.5, 'MergeIoU', 0.5, 'MergeIoA', 0.8);
end

prompts = {...
    sprintf('Detection confidence threshold (0-1):\nminimal confidence score for a detected instance to be kept;\ndecrease to detect more (weaker) objects, increase to keep only confident detections\n[used by both overlap modes]'); ...
    sprintf('\nMerge IoU threshold (0-1):\nmerge detections of neighboring tiles when the intersection-over-union of their masks\nwithin the shared overlap band exceeds this value;\ndecrease when objects get split at tile seams, increase when distinct touching objects get merged\n[used by the "IoU merge" mode]'); ...
    sprintf('\nMerge IoA threshold (0-1):\nadditionally merge when the intersection over the smaller in-band mask area exceeds this value;\nthis catches a truncated fragment that is fully contained in the neighboring tile''s complete mask\n[used by the "IoU merge" mode]')};

defAns = {...
    struct('Spinner', true, 'Value', obj.OverlapInstancesOpt.DetectionThreshold, 'Limits', [0 1], 'Step', 0.05, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.OverlapInstancesOpt.MergeIoU, 'Limits', [0 1], 'Step', 0.05, 'Round', false); ...
    struct('Spinner', true, 'Value', obj.OverlapInstancesOpt.MergeIoA, 'Limits', [0 1], 'Step', 0.05, 'Round', false)};

dlgTitle = 'Instance stitching settings';
options.WindowStyle = 'normal';
options.WindowWidth = 650;
options.WindowHeight = 380;
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
if isempty(answer); return; end

obj.OverlapInstancesOpt.DetectionThreshold = answer{1};
obj.OverlapInstancesOpt.MergeIoU = answer{2};
obj.OverlapInstancesOpt.MergeIoA = answer{3};
end
