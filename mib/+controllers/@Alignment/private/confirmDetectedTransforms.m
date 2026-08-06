function tf = confirmDetectedTransforms(parentFig, kind, payload, titleStr)
% CONFIRMDETECTEDTRANSFORMS - Preview freshly detected displacements and confirm.
%
% Syntax:
%   .. code-block:: matlab
%
%      tf = confirmDetectedTransforms(parentFig, kind, payload, titleStr)
%
% Plots the detected per-slice displacements (via
% :func:`plotAlignmentTransforms`) and asks the user whether to align the dataset
% using them - mirroring the standard drift-correction confirmation. The caller
% is responsible for skipping this in batch mode (no dialogs headless).
%
% Input Arguments:
%   - **parentFig** - parent window handle for the dialog.
%   - **kind** / **payload** - see :func:`plotAlignmentTransforms`
%     (``'shifts'`` + ``shiftX``/``shiftY``, or ``'tforms'`` + ``tforms``).
%   - **titleStr** - [char] preview-plot title (e.g. the landmark mode name).
%
% Output Arguments:
%   - **tf** - [logical] ``true`` when the user chose to apply, ``false`` to abort.

hFig = plotAlignmentTransforms(kind, payload, titleStr);
cleanupFig = onCleanup(@() closeIfValid(hFig));

opt.Icon        = 'puffin_question';
opt.WindowStyle = 'normal';   % keep the preview figure visible alongside the dialog
choice = utils.dlgs.inputQuestDlg(parentFig, ...
    'Align the dataset using these detected displacements?', 'Align dataset', ...
    'Apply current values', 'Quit alignment', 'Apply current values', opt);
tf = ~isempty(choice) && strcmp(choice, 'Apply current values');
end

% =============================================================================
function closeIfValid(hFig)
if ~isempty(hFig) && isvalid(hFig)
    delete(hFig);
end
end
