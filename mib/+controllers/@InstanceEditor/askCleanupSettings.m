function accepted = askCleanupSettings(obj, applyNow)
% ASKCLEANUPSETTINGS - Ask for the three Cleanup thresholds.
%
% Syntax:
%   .. code-block:: matlab
%
%       if ~obj.askCleanupSettings(true); return; end
%
% Cleanup is the one operation of the editor that is configured rather than
% simply pressed, and the one that is used least often - a proofreading session
% is a few hundred merges and splits and perhaps one cleanup at the end. Three
% permanent spinners for it cost more room in the window than they earn, so the
% thresholds are asked for on the way in instead.
%
% The answer is written back into ``obj.BatchOpt`` and into
% ``MibModel.sessionSettings.instanceEditor``, so the dialog reopens on the last
% values for the rest of the session and a re-opened editor starts from them too
% (the constructor seeds itself from the same place). They are deliberately not
% written to the preferences file: a threshold that suits one model is rarely
% the right opening offer for the next dataset.
%
% Input Arguments:
%   - **applyNow** - logical, whether accepting also runs the cleanup. Only the
%     wording changes: ``true`` for the *Cleanup* button, which acts on the whole
%     model as soon as the dialog is accepted, ``false`` for *Cleanup options*,
%     which only stores the answer
%
% Output Arguments:
%   - **accepted** - logical, false when the user cancelled, so the caller can
%     abandon the operation rather than run it on the old thresholds
%
% See also: controllers.InstanceEditor.runOperation, utils.instances.cleanup,
% utils.dlgs.stitchInstancesSettingsDlg

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.InstanceEditor.askCleanupSettings(%d): triggered\n', applyNow);
end

if applyNow
    note = sprintf(['Filters for the whole model, applied as soon as this is accepted.\n' ...
        'Object numbers are left as they are - use Compact to renumber.']);
    dlgParams.OkBtnText = 'Cleanup';
else
    note = sprintf(['Filters used by Cleanup, kept for the rest of the session.\n' ...
        'Nothing is changed in the model now.']);
    dlgParams.OkBtnText = 'Save';
end

prompts = {...
    sprintf('Min object size (voxels):\n  delete objects smaller than this; 0 = keep all'), ...
    sprintf(['Min object depth (slices):\n  delete objects seen on this many slices or fewer;\n' ...
             '  0 = keep all, 1 = drop single-slice objects. Catches the wide\n' ...
             '  false detection that a voxel count cannot see']), ...
    sprintf(['Absorb fragments (voxels):\n  give objects of this size or smaller to the object around them\n' ...
             '  instead of deleting them; 0 = off. This is what fills the holes\n' ...
             '  that stray predictor pixels punch into otherwise solid objects'])};

defAns = {...
    struct('Spinner', true, 'Value', obj.BatchOpt.cleanupMinObjectVoxels{1}, ...
        'Limits', obj.BatchOpt.cleanupMinObjectVoxels{2}, 'Step', 1, 'Round', true), ...
    struct('Spinner', true, 'Value', obj.BatchOpt.cleanupMinObjectSlices{1}, ...
        'Limits', obj.BatchOpt.cleanupMinObjectSlices{2}, 'Step', 1, 'Round', true), ...
    struct('Spinner', true, 'Value', obj.BatchOpt.cleanupAbsorbFragmentVoxels{1}, ...
        'Limits', obj.BatchOpt.cleanupAbsorbFragmentVoxels{2}, 'Step', 1, 'Round', true)};

dlgParams.WindowWidth = 620;
dlgParams.WindowHeight = 300;
dlgParams.HeaderLines = 2;
dlgParams.LabelPosition = 'left';
dlgParams.mibPath = obj.mibModel.mibPath;

answer = utils.dlgs.inputUniversalDlg(obj.view.gui, note, prompts, defAns, ...
    'Cleanup options', dlgParams);
accepted = ~isempty(answer);
if ~accepted; return; end

obj.BatchOpt.cleanupMinObjectVoxels{1} = answer{1};
obj.BatchOpt.cleanupMinObjectSlices{1} = answer{2};
obj.BatchOpt.cleanupAbsorbFragmentVoxels{1} = answer{3};

for name = {'cleanupMinObjectVoxels', 'cleanupMinObjectSlices', 'cleanupAbsorbFragmentVoxels'}
    obj.mibModel.sessionSettings.instanceEditor.(name{1}) = obj.BatchOpt.(name{1}){1};
end
end
