function switched = ensureDatasetMode(obj, datasetId, targetMode)
% ENSUREDATASETMODE - Put a dataset buffer into the mode the import needs.
%
% Syntax:
%   .. code-block:: matlab
%
%      switched = obj.ensureDatasetMode(datasetId, targetMode)
%
% A no-op when the buffer is already in that mode, which is the common case and
% worth keeping free: ``switchDatasetMode`` re-initialises the buffer with a
% placeholder, so calling it needlessly discards whatever is open.
%
% **The placeholder has to match the target mode**, and the two forms are not
% interchangeable - this is the whole reason the function exists rather than the
% call being inlined:
%
%   * ``'Standard'`` wants a **numeric matrix**, or ``[]`` to let
%     ``core.MibImage.initialize`` build its own 512x512 uint8 placeholder;
%   * ``'Virtual'`` / ``'BigData'`` want a **cell array of file paths**, because
%     those modes open a reader rather than hold pixels.
%
% Handing the cell form to Standard puts a cell in ``MibImage.data``, and the
% first thing ``initialize`` does with it is ``intmax(class(data))``, which
% raises "Class name must be a class that supports INTMAX" from four frames
% below the caller with nothing in the message about dataset modes.
%
% **The Datasets panel cache is written here**, on every success including the
% no-op, because this is the one place the mode is changed. Leaving it to the
% caller is what left the label-crop route showing "BigData" over a buffer that
% had been switched to Standard: the image branch of ``openBtn_Callback`` synced
% the cache and the crop branch never did.
%
% **The repaint is NOT notified here, and must not be.** ``DatasetsPanelUpdate``
% reaches ``MibActiveDataset.update_fromModel`` -> ``buffers_Callback`` ->
% ``ShowImage``, so it repaints the buffer - which at this point holds nothing
% but the mode-switch placeholder. For a Virtual/BigData target that is a path to
% ``default.h5`` with no reader attached, and the repaint dies inside
% ``MibVirtualImage.getDataVirt``. Each caller notifies once its own load has
% finished and the buffer is paintable.
%
% Input Arguments:
%   - **datasetId** - [numeric] buffer index
%   - **targetMode** - [char] ``'Standard'``, ``'Virtual'`` or ``'BigData'``
%
% Output Arguments:
%   - **switched** - [logical] true when the buffer is now in ``targetMode``;
%     false means the failure was already reported to the user

switched = true;

if ~strcmp(obj.mibModel.I{datasetId}.datasetType, targetMode)
    modeIndex = find(strcmp({'Standard', 'Virtual', 'BigData'}, targetMode), 1);
    if isempty(modeIndex)
        switched = false;
        obj.stopProgress();   % a modal bar would sit in front of the message
        utils.dlgs.showErrorDialog(obj.guiFigure(), ...
            sprintf('"%s" is not a dataset mode.', targetMode), 'Import from URL');
        return;
    end

    if modeIndex == 1
        % Empty: MibImage.initialize substitutes its own placeholder image. Whatever
        % is loaded next replaces it outright, so there is nothing to gain from
        % reading a file here.
        placeholder = [];
    else
        placeholder = {fullfile(obj.mibModel.mibPath, 'assets', 'images', 'default.h5')};
    end

    achievedMode = obj.mibModel.I{datasetId}.switchDatasetMode(modeIndex, ...
        obj.mibModel.preferences.System.EnableSelection, placeholder);

    if achievedMode ~= modeIndex
        switched = false;
        obj.stopProgress();   % a modal bar would sit in front of the message
        utils.dlgs.showErrorDialog(obj.guiFigure(), ...
            sprintf('Could not switch the dataset buffer to %s mode.', targetMode), ...
            'Import from URL');
        return;
    end
end

% ---- keep the Datasets panel's cache honest about the mode --------------
% The panel's type dropdown reads the Sets.datasetTypes cache rather than
% I{id}.datasetType, so switchDatasetMode above leaves the cache stale. Same
% pattern as Stitching.stitchBtn_Callback and CropDataset. The cache is indexed
% [set, buffer-within-set], NOT by the global dataset id.
%
% Read back from the dataset rather than from targetMode: switchDatasetMode is
% the authority on what the buffer actually became, and nothing between here and
% the load changes it (MibModel.loadImages never assigns datasetType; only
% MibDataset.initialize does).
%
% Writing the cache is inert - no listener reads it until something repaints -
% so it is safe here while the notify is not. See the header.
datasetsInSet = obj.mibModel.Sets.datasetsInSet;
targetSet     = floor((datasetId - 1) / datasetsInSet) + 1;
targetLocalId = mod(datasetId - 1, datasetsInSet) + 1;
obj.mibModel.Sets.datasetTypes{targetSet, targetLocalId} = ...
    obj.mibModel.I{datasetId}.datasetType;
end
