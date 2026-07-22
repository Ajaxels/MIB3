function method = morphAnisotropicMethod(obj, batchModeSwitch, batchMethod, opName)
% MORPHANISOTROPICMETHOD - Decide how to run a large anisotropic 3D strel operation.
%
% Syntax:
%   .. code-block:: matlab
%
%       method = utils.morphAnisotropicMethod(obj, batchModeSwitch, batchMethod, opName)
%
% For an anisotropic voxel-space element (XY radius ~= Z radius) the fast
% distance-transform path would produce an isotropic sphere rather than the
% intended ellipsoid. This helper decides which engine to use for large
% anisotropic 3D dilation/erosion:
%
%   - ``'accurate'`` — keep the (slow) ellipsoidal ``imdilate``/``imerode``
%   - ``'fast'``     — use the isotropic ``bwdist`` path (treats the element as a
%     sphere; acceptable only for slight anisotropy)
%   - ``'cancel'``   — the user aborted the operation
%
% In batch mode (``batchModeSwitch == 1``) the ``BatchOpt.AnisotropicMethod``
% value is honoured with no dialog. Interactively a warning dialog is shown.
%
% Input Arguments:
%   - **obj** — the ``models.MibModel`` instance (for the parent figure)
%   - **batchModeSwitch** — logical/double; 1 = headless batch mode (no dialog)
%   - **batchMethod** — char, the ``BatchOpt.AnisotropicMethod{1}`` value used in batch mode
%   - **opName** — char, ``'dilation'`` or ``'erosion'`` for message wording
%
% Output Arguments:
%   - **method** — char, ``'accurate'``, ``'fast'`` or ``'cancel'``
%

% Updates
%

% Batch mode: obey BatchOpt, never prompt
if batchModeSwitch
    if contains(lower(batchMethod), 'fast')
        method = 'fast';
    else
        method = 'accurate';
    end
    return;
end

dlgOptions.Icon = 'puffin_warning';
dlgOptions.WindowHeight = 250;
msg = sprintf(['This 3D %s can be slow for large brush sizes because the slices\n' ...
    'are thicker than the pixels (the voxels are not cubic).\n\n' ...
    'Use the accurate method, or a faster method that gives an almost\n' ...
    'identical result when this difference is small?\n\n' ...
    'Tip: for accurate results, applying several smaller steps usually works ' ...
    'better than a single large one.'], opName);

answer = utils.dlgs.inputQuestDlg(obj.getProgressBarParent(), msg, ...
    sprintf('Confirm 3D %s', opName), ...
    'Use accurate (slow)', 'Use bwdist (fast)', 'Cancel', ...
    'Use accurate (slow)', dlgOptions);

switch answer
    case 'Use bwdist (fast)'
        method = 'fast';
    case 'Use accurate (slow)'
        method = 'accurate';
    otherwise
        method = 'cancel';
end
end
