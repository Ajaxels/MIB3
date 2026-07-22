function getSearchWindow_Callback(obj)
% GETSEARCHWINDOW_CALLBACK - Populate the manual subarea fields from the current selection bounding box.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.getSearchWindow_Callback()
%
% Reads the selection layer of the current slice; if the layer contains any
% non-zero pixels, copies the bounding box of the first connected region into
% ``minX/minY/maxX/maxY`` widgets and the matching ``BatchOpt`` fields.

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Alignment.getSearchWindow_Callback: triggered\n');
end
selection = cell2mat(obj.mibModel.getData2D('selection'));
stats = regionprops(selection, 'BoundingBox');
if isempty(stats)
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        'No selection layer present in the current slice', {''}, ...
        {'Use the Brush or Selection tool to mark the desired search area, then retry.'}, ...
        'Search window', dlgOpt);
    return;
end

bb = stats(1).BoundingBox;
h = obj.view.handles;
h.minX.Value = ceil(bb(1));
h.minY.Value = ceil(bb(2));
h.maxX.Value = ceil(bb(1)) + bb(3) - 1;
h.maxY.Value = ceil(bb(2)) + bb(4) - 1;
obj.subwindowEdit_Callback();
obj.updateBatchOptFromGUI(h.minX);
obj.updateBatchOptFromGUI(h.minY);
obj.updateBatchOptFromGUI(h.maxX);
obj.updateBatchOptFromGUI(h.maxY);

end
