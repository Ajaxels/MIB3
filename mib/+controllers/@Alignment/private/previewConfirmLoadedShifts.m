function tf = previewConfirmLoadedShifts(obj, parameters, parentFig)
% PREVIEWCONFIRMLOADEDSHIFTS - Preview pre-loaded alignment coefficients and
% confirm before the dataset is aligned (called from continueBtn_Callback when
% loadShiftsCheck has loaded a .coefXY file).
%
% Syntax:
%   .. code-block:: matlab
%
%      tf = previewConfirmLoadedShifts(obj, parameters, parentFig)
%
% Classifies the loaded coefficients held in ``obj.shiftsX`` (drift shifts,
% feature-based v2 struct, or legacy tform matrices), plots them (via
% :func:`plotAlignmentTransforms`), and asks the user to confirm. When the
% coefficient type does not match the currently selected algorithm
% (``parameters.method``) an error dialog explains the mismatch and the run is
% aborted - applying, e.g., v2 transforms as a drift correction would fail or
% silently recompute.
%
% Output Arguments:
%   - **tf** - [logical] ``true`` to proceed with the alignment, ``false`` to abort.

tf = false;

% --- Classify the loaded coefficients + the algorithm(s) that consume that type.
% A coefficient TYPE maps to several algorithms (e.g. numeric shifts drive drift,
% template matching AND single-landmark), so the compatibility set is per type.
if isnumeric(obj.shiftsX)
    kindLabel = 'drift / translation shifts';
    compatAlg = {'Drift correction', 'Template matching', 'Single landmark point'};
    nFrames   = numel(obj.shiftsX);
    plotKind  = 'shifts';
    payload   = struct('shiftX', obj.shiftsX, 'shiftY', obj.shiftsY);
elseif isstruct(obj.shiftsX) && isfield(obj.shiftsX, 'cumulativeTforms')
    kindLabel = 'feature-based (v2) transforms';
    compatAlg = {'Automatic feature-based v2'};
    nFrames   = numel(obj.shiftsX.cumulativeTforms);
    plotKind  = 'tforms';
    payload   = struct('tforms', {obj.shiftsX.cumulativeTforms});
elseif iscell(obj.shiftsX)
    kindLabel = 'feature-based / landmark transforms';
    compatAlg = {'Automatic feature-based', 'Landmarks, multi points', ...
                 'Color channels, multi points'};
    nFrames   = numel(obj.shiftsX);
    plotKind  = 'tforms';
    payload   = struct('tforms', {obj.shiftsX});
else
    kindLabel = 'alignment coefficients';
    compatAlg = {};
    nFrames   = 0;
    plotKind  = 'unknown';
    payload   = struct();
end

% --- Abort on algorithm mismatch ---------------------------------------------
if ~isempty(compatAlg) && ~ismember(parameters.method, compatAlg)
    utils.dlgs.showErrorDialog(parentFig, sprintf( ...
        ['The loaded coefficients are %s, produced by "%s", but the selected ' ...
         'algorithm is "%s".\n\nSelect "%s" (or load coefficients that match the ' ...
         'current algorithm) and try again.'], ...
        kindLabel, strjoin(compatAlg, '" / "'), parameters.method, compatAlg{1}), ...
        'Alignment coefficients mismatch');
    return;
end

% --- File label for the plot / message ---------------------------------------
fileLabel = 'loaded file';
if ~isempty(obj.view) && isvalid(obj.view) && isfield(obj.view.handles, 'loadShiftsXYpath')
    [~, stem, ext] = fileparts(obj.view.handles.loadShiftsXYpath.Value);
    if ~isempty(stem); fileLabel = [stem ext]; end
end

% --- Preview plot + confirm --------------------------------------------------
hFig = plotAlignmentTransforms(plotKind, payload, ...
    sprintf('%s - %s (%d frames)', [upper(kindLabel(1)) kindLabel(2:end)], fileLabel, nFrames));
cleanupFig = onCleanup(@() closeIfValid(hFig));

opt.Icon        = 'puffin_question';
opt.WindowStyle = 'normal';   % keep the preview figure visible alongside the dialog
msg = sprintf('%s for %d frames loaded from "%s".\n\nAlign the dataset using these coefficients?', ...
    [upper(kindLabel(1)) kindLabel(2:end)], nFrames, fileLabel);
choice = utils.dlgs.inputQuestDlg(parentFig, msg, 'Confirm loaded coefficients', ...
    'Align', 'Cancel', 'Align', opt);
tf = strcmp(choice, 'Align');
end

% =============================================================================
function closeIfValid(hFig)
if ~isempty(hFig) && isvalid(hFig)
    delete(hFig);
end
end
