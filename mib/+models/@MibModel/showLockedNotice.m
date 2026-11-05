function unlocked = showLockedNotice(obj, id, layer, batchMode)
% SHOWLOCKEDNOTICE - explain that a change of a locked layer was refused, and offer to unlock it.
%
% Syntax:
%   .. code-block:: matlab
%
%      unlocked = obj.showLockedNotice(id, layer)
%      unlocked = obj.showLockedNotice(id, layer, batchMode)
%
% The single place the "locked" dialog is built. Called by the early guards
% of the editing operations (``moveLayers``, ``undo``, the material list,
% ``editInstanceObjects``, ``createModel``), by the voxel-size and
% bounding-box writes into a BigData image store, and by
% ``controllers.MibController`` when ``core.MibDataset`` fires
% ``LockedWriteRefused`` - the path every other labels write takes, because
% ``core.MibBigDataLabels.setData63`` refuses silently.
%
% The dialog (``utils.dlgs.inputQuestDlg``) has the buttons **Unlock** and
% **Keep locked** (default) and a "Do not show again" checkbox. *Unlock*
% calls ``setLockedState(id, layer, false)``. For ``'labels'`` the refused
% change is not repeated, the user repeats it; for ``'image'`` the callers
% (``controllers.MibRibbon.updateVoxelSizes``, ``controllers.BoundingBox``)
% carry on to their "Update zarr3 file?" question when this returns
% ``true``. The checkbox is kept per layer in
% ``obj.sessionSettings.DoNotShowDialogs.LockedImage`` /
% ``.LockedLabels``, so it lasts until MIB is closed - unlike
% ``preferences.DoNotShowDialogs``, which is saved. While it is set, a
% refused change is refused without a word; the padlock on the buffer
% button and the lock button of the Segmentation panel still show the state.
%
% Standard datasets: their labels lock is the disabled selection (see
% ``core.MibDataset.getLockedState``), so the text says that the
% segmentation layers are switched off and *Unlock* enables the selection
% (``setLockedState`` allocates the layers). The checkbox for it is kept
% apart, in ``sessionSettings.DoNotShowDialogs.SelectionDisabled``. Callers
% for this case are the segmentation entry points that used to return
% silently on ``enableSelection == 0``: a mouse press with a segmentation
% tool (``controllers.MibImageDocument.gui_WindowButtonDownFcn``), the a/s/r
% and f/z/x keys (``controllers.MibController.gui_WindowKeyPressFcn``),
% ``moveLayers``, and the material-list guards, which see ``'locked'``.
%
% Throttling: a brush stroke over locked labels refuses a write on every
% mouse-move, and ``uiwait`` inside the dialog keeps processing those
% callbacks. The dialog is therefore never opened while one is already open
% (``sessionSettings.LockedNotice.isOpen``), nor within 1 s after the last one
% closed (``.closedAt``, a ``tic`` value), which swallows the motion events
% queued behind it.
%
% Input Arguments:
%   - **id** - [numeric] index of the dataset in ``obj.I``; ``[]`` for the
%     active dataset
%   - **layer** - [char] ``'image'`` or ``'labels'``
%   - **batchMode** *(optional)* - [logical] ``true`` when called from a batch
%     run: no question is asked, the refusal is reported through
%     ``ShowErrorDialog`` and the protocol is stopped (``StopProtocol``).
%     Default: ``false``
%
% Output Arguments:
%   - **unlocked** - [logical] ``true`` when the user pressed *Unlock* and the
%     layer is now unlocked; ``false`` otherwise, including every case where no
%     dialog was shown
%
% Usage:
%   .. code-block:: matlab
%
%      if obj.I{id}.labels.lockedState
%          obj.showLockedNotice(id, 'labels');
%          return;
%      end
%

arguments
    obj models.MibModel
    id {mustBeNumeric}
    layer {mustBeMember(layer, {'image', 'labels'})}
    batchMode (1,1) logical = false
end

unlocked = false;
if isempty(id); id = obj.getActiveId(); end

switch layer
    case 'image'
        settingName = 'LockedImage';
        dlgTitle = 'Locked image';
        question = sprintf(['The image of this dataset is locked, so the change is not ' ...
            'written into the image file; it is used in this session only.\n\n' ...
            'Unlock the image to write the change into the file.']);
    case 'labels'
        if strcmp(obj.I{id}.datasetType, 'Standard')
            settingName = 'SelectionDisabled';
            dlgTitle = 'Selection disabled';
            question = sprintf(['The selection of this dataset is disabled, so its labels, mask and ' ...
                'selection layers are switched off and nothing can be segmented.\n\n' ...
                'Unlock to enable the selection and segment this dataset.']);
        else
            settingName = 'LockedLabels';
            dlgTitle = 'Locked labels';
            question = sprintf(['The labels of this dataset are locked, so the change was not made. ' ...
                'The selection and the mask stay editable.\n\n' ...
                'Unlock the labels and repeat the change to modify the materials.']);
        end
end

if batchMode
    errorOptions.winTitle = dlgTitle;
    errorOptions.err = question;
    notify(obj, 'ShowErrorDialog', core.ToggleEventData(errorOptions));
    notify(obj, 'StopProtocol');
    return;
end

if ~isfield(obj.sessionSettings, 'DoNotShowDialogs') || ~isstruct(obj.sessionSettings.DoNotShowDialogs)
    obj.sessionSettings.DoNotShowDialogs = struct();
end
if isfield(obj.sessionSettings.DoNotShowDialogs, settingName) && obj.sessionSettings.DoNotShowDialogs.(settingName)
    return;
end

if ~isfield(obj.sessionSettings, 'LockedNotice')
    obj.sessionSettings.LockedNotice = struct('isOpen', false, 'closedAt', []);
end
if obj.sessionSettings.LockedNotice.isOpen || ...
        (~isempty(obj.sessionSettings.LockedNotice.closedAt) && toc(obj.sessionSettings.LockedNotice.closedAt) < 1)
    return;
end

obj.sessionSettings.LockedNotice.isOpen = true;
cleanupNotice = onCleanup(@() localMarkClosed(obj));

dlgOptions = struct();
dlgOptions.Icon = 'puffin_warning';
dlgOptions.WindowWidth = 480;
dlgOptions.WindowHeight = 210;
dlgOptions.DoNotShowAgain = true;
dlgOptions.mibPath = obj.mibPath;
dlgOptions.HelpUrl = 'https://mib.helsinki.fi/help/main3/getting-started/dataset-types/index.html';
[answer, dontShowAgain] = utils.dlgs.inputQuestDlg(obj.getProgressBarParent(), question, dlgTitle, ...
    'Unlock', 'Keep locked', 'Keep locked', dlgOptions);
obj.sessionSettings.DoNotShowDialogs.(settingName) = dontShowAgain;

if strcmp(answer, 'Unlock')
    unlocked = obj.setLockedState(id, layer, false);
end

end

function localMarkClosed(obj)
% the dialog is closed, also on an error inside it
if isvalid(obj)
    obj.sessionSettings.LockedNotice.isOpen = false;
    obj.sessionSettings.LockedNotice.closedAt = tic;
end
end
