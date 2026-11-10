function roiDuplicate(obj)
% ROIDUPLICATE - Duplicate an existing ROI into a new ROI.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.roiDuplicate()
%
% The ROI selected in the ROI list is copied with all its fields (type,
% vertices, orientation, bounding box) and appended to the end of
% ``hROI.Data`` under a new label.  If "All" is selected in the ROI list a
% dialog prompts the user to choose the source ROI, the same way as
% :meth:`controllers.MibRoi.roiModify`.
%
% The new label is the first free integer starting from the new number of
% ROIs, so it never collides with an existing label (labels are used by
% :meth:`core.RoiRegion.findIndexByLabel` to address ROIs).  After
% duplicating a single selected ROI the copy is selected in the ROI list,
% so it can be moved straight away with the Modify button; when the source
% was picked from "All", "All" stays selected.  ROI display is switched on.
%
% Input Arguments:
%   - **obj** - controllers.MibRoi - the ROI panel controller
%
%   Return values: none
%
% Usage:
%   Example 1::
%
%     // called from gui_Callbacks when roiDuplicate is triggered
%     obj.roiDuplicate();
%

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRoi.roiDuplicate: pressed\n');
end

dataset = obj.mibModel.I{obj.mibModel.id};
hROI    = dataset.hROI;

if hROI.getNumberOfROI(0) < 1; return; end

% --- Determine which ROI to duplicate ---
[numberOfROI, indices] = hROI.getNumberOfROI(0);
roiIdx = dataset.selectedROI;   % 0 = All, >0 = list position
allSelected = roiIdx == 0;

% collect existing labels: used for the selection dialog and for a unique new label
labels = cell(1, numel(indices));
for i = 1:numel(indices)
    lbl = hROI.Data(indices(i)).label;
    if iscell(lbl); lbl = lbl{1}; end
    labels{i} = lbl;
end

if allSelected
    dlgOpts.mibPath = obj.mibModel.mibPath;
    dlgOpts.Icon    = 'puffin_question';
    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
        {'Select ROI to duplicate:'}, ...
        {[labels, 1]}, ...
        'Duplicate ROI', dlgOpts);
    if isempty(answer); return; end
    roiIdx = hROI.findIndexByLabel(answer{1});
    if isempty(roiIdx); return; end
else
    roiIdx = indices(roiIdx);
end

% --- Generate a unique label for the copy ---
newIndex = numberOfROI + 1;
labelNumber = newIndex;
labelStr = sprintf('%d', labelNumber);
while ismember(labelStr, labels)
    labelNumber = labelNumber + 1;
    labelStr = sprintf('%d', labelNumber);
end

% --- Store the copy ---
newData = hROI.Data(roiIdx);
newData.label = cellstr(labelStr);
hROI.storeROI(newData, newIndex);

% keep "All" when duplicating from it, otherwise select the copy
% (it is appended, so it is the last entry)
obj.refreshROIList([]);
if allSelected
    obj.handles.roiList.Value = 'All';
    dataset.selectedROI = 0;
else
    obj.handles.roiList.Value = labelStr;
    dataset.selectedROI = newIndex;
end

% ensure the "Show ROI" checkbox is on
obj.handles.roiShowROI.Value = true;
obj.mibController.cQuickAccessBar.handles.roiMode.Value = true;
dataset.roiShow = true;

notify(obj.mibModel, 'ShowImage');
end
