function datasetTools_Callback(obj, hWidget, hData)
% DATASETTOOLS_CALLBACK - callback on press of buttons in the Dataset tools section of the Dataset ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.datasetTools_Callback(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.datasetTools_Callback: Dataset tools section pressed -> %s\n', mode);
end

switch mode
    case 'Alignment'
        obj.mibController.startController('controllers.Alignment');
    case 'Crop'              % obj.handles.ribbonDataset.crop
        obj.mibController.startController('controllers.CropDataset', obj.mibController);
    case 'Resize'           % obj.handles.ribbonDataset.resize
        obj.mibController.startController('controllers.ResampleDataset');
    case {'Update with new width/height', 'Update with new dX/dY', 'Flip horizontally', ...
            'Flip vertically', 'Flip Z', 'Flip T', 'Rotate 90 degrees', 'Rotate -90 degrees', ...
            'Transpose YX -> YZ', 'Transpose YX -> XZ', 'Transpose YX -> XY', ...
            'Transpose Z <-> T', 'Transpose Z <-> C'}
        
        % Normalize ' <-> ' → '<->' for BatchOpt compatibility
        mode = strrep(mode, ' <-> ', '<->');
        BatchOpt.Transform = {mode};
        obj.mibModel.transformDataset(BatchOpt);
        
    case 'Copy slice...'              % obj.handles.ribbonDataset.sliceCopy
        obj.mibController.datasetSlices('copySlice');
    case 'Insert empty slice(s)...'                 % obj.handles.ribbonDataset.sliceInsert
        obj.mibController.datasetSlices('insertSlice');
    case 'Interval slicing...'              % obj.handles.ribbonDataset.sliceInterval
        obj.mibController.datasetSlices('reslice');
    case 'Swap slices...'                 % obj.handles.ribbonDataset.sliceSwap
        obj.mibController.datasetSlices('swapSlice');
    case 'Delete slice(s)...'              % obj.handles.ribbonDataset.sliceDelete
        obj.mibController.datasetSlices('deleteSlice');
    case 'Delete frame(s)...'                 % obj.handles.ribbonDataset.sliceFrameDelete
        obj.mibController.datasetSlices('deleteFrame');
end

end
