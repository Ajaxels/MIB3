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
% Input Arguments:
%   - **datasetId** - [numeric] buffer index
%   - **targetMode** - [char] ``'Standard'``, ``'Virtual'`` or ``'BigData'``
%
% Output Arguments:
%   - **switched** - [logical] true when the buffer is now in ``targetMode``;
%     false means the failure was already reported to the user

switched = true;
if strcmp(obj.mibModel.I{datasetId}.datasetType, targetMode); return; end

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
end
end
