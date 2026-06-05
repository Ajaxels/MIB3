function datasetSlices(obj, parameter)
% DATASETSLICES - Dispatcher for Menu -> Dataset -> Slice operations.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.datasetSlices(parameter)
%
% Routes slice-related menu actions to the corresponding ``MibModel``
% methods.  Checks for virtual-stacking mode and returns early with a
% warning when applicable.
%
% Input Arguments:
%   - **parameter** — string identifying the requested action:
%
%     - ``'copySlice'`` — copy a slice from one position to another
%     - ``'swapSlice'`` — swap two or more slices
%     - ``'insertSlice'`` — insert empty slice(s)
%     - ``'deleteSlice'`` — delete a depth (z) slice
%     - ``'deleteFrame'`` — delete a time-frame
%     - ``'reslice'`` — stride-reslice the dataset
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.datasetSlices('deleteSlice');
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.datasetSlices('reslice');
%

% Updates
%

activeId = obj.mibModel.getActiveId();
if strcmp(obj.mibModel.I{activeId}.datasetType, 'Virtual')
    warnOpt.MsgBoxOnly  = true;
    warnOpt.Icon        = 'puffin_warning';
    warnOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '!!! Warning !!!', {''}, ...
        {sprintf('Slice actions are not yet available in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again.')}, ...
        'Not implemented', warnOpt);
    return;
end

switch parameter
    case 'copySlice'
        obj.mibModel.copySwapSlice([], [], 'replace');
    case 'swapSlice'
        obj.mibModel.copySwapSlice([], [], 'swap');
    case 'insertSlice'
        obj.mibModel.insertEmptySlice();
    case 'deleteSlice'
        obj.mibModel.deleteSlice(3);   % orient 3 = depth (z) in MIB3
    case 'deleteFrame'
        obj.mibModel.deleteSlice(5);   % orient 5 = time
    case 'reslice'
        obj.mibModel.resliceDataset();
end
end
