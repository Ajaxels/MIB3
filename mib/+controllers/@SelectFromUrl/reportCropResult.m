function reportCropResult(obj, imageGroupPath, cropPlan, materialNames, compositionReport)
% REPORTCROPRESULT - Tell the user what was actually loaded, and what to watch for.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.reportCropResult(imageGroupPath, cropPlan, materialNames, compositionReport)
%
% Silent when there is nothing to say. A dialog appears only when the
% composition found something the result itself cannot show - overlap between
% classes, ``unknown`` voxels sitting in material 0, classes that turned out
% empty, or a crop that is a single material throughout. Each of those looks
% like a normal model on screen, which is exactly why they are worth a sentence.
%
% Input Arguments:
%   - **imageGroupPath** - [char] image group the region came from, for context
%   - **cropPlan** - [struct] from :meth:`planLabelCrop`
%   - **materialNames** - {1xN cell} composed materials
%   - **compositionReport** - [struct] from :meth:`composeLabelModel`

% The level is named because the pairing, not the user, chose it - and when the
% labels are coarser than the image that level is not the full resolution the
% user was browsing a moment ago.
levelNote = '';
if ~isempty(cropPlan.imageLevelName)
    levelNote = sprintf(' level %s', cropPlan.imageLevelName);
end
summaryLine = sprintf('Loaded %d x %d x %d voxels at %g nm from %s%s, with %d material(s).', ...
    cropPlan.shapeYXZ(2), cropPlan.shapeYXZ(1), cropPlan.shapeYXZ(3), ...
    cropPlan.voxelSizeUm(1) * 1000, imageGroupPath, levelNote, numel(materialNames));

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.SelectFromUrl.openLabelCrop: %s\n', summaryLine);
    for lineIndex = 1:numel(compositionReport.lines)
        fprintf('  %s\n', compositionReport.lines{lineIndex});
    end
end

obj.setStatus(summaryLine);

if isempty(compositionReport.lines); return; end

parentFigure = obj.guiFigure();
if isempty(parentFigure); return; end   % headless: the DeveloperMode log above is the report

dialogOptions = struct();
dialogOptions.MsgBoxOnly   = true;
dialogOptions.Icon         = 'puffin_info';
dialogOptions.WindowWidth  = 560;
dialogOptions.WindowHeight = 120 + 22 * numel(compositionReport.lines);
utils.dlgs.inputUniversalDlg(parentFigure, summaryLine, ...
    compositionReport.lines, compositionReport.lines, ...
    'Label crop loaded', dialogOptions);
end
