function removeROI(obj)
% REMOVEROI - Remove selected ROI(s) from the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.removeROI()
%
% When 'All' is selected in the ROI list, removes every ROI after
% user confirmation.  Otherwise removes only the selected ROI.
% The ROI list is refreshed and the image is repainted.
%
% Input Arguments:
%   - **obj** — controllers.MibRoi — the ROI panel controller
%
%   Return values: none
%
% Usage:
%   Example 1::
%
%     // called from gui_Callbacks when roiRemove button is pressed
%     obj.removeROI();
%

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRoi.removeROI: pressed\n');
end

dataset = obj.mibModel.I{obj.mibModel.id};
hROI    = dataset.hROI;

selectedItem = obj.handles.roiList.Value;
if isempty(selectedItem); return; end

if strcmp(selectedItem, 'All')
    % confirm deletion of all ROIs
    answer = utils.dlgs.inputQuestDlg(obj.mibController.view.gui, ...
        sprintf('!!! Warning !!!\nYou are going to delete all ROIs.\nAre you sure?'), ...
        'Delete ROIs!', 'Delete', 'Cancel', 'Cancel');
    if ~strcmp(answer, 'Delete'); return; end
    hROI.removeROI(0);
else
    % find the index corresponding to the selected label
    index = hROI.findIndexByLabel(selectedItem);
    if isempty(index); return; end

    answer = utils.dlgs.inputQuestDlg(obj.mibController.view.gui, ...
        sprintf('You are going to delete\nROI region with label "%s".\nAre you sure?', selectedItem), ...
        'Delete ROI!', 'Delete', 'Cancel', 'Cancel');
    if ~strcmp(answer, 'Delete'); return; end
    hROI.removeROI(index);
end

obj.refreshROIList('All');

% hide ROI overlay if no ROIs remain
if hROI.getNumberOfROI(0) == 0
    obj.handles.roiShowROI.Value = false;
end

notify(obj.mibModel, 'ShowImage');
end
