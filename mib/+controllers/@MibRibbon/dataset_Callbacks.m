function dataset_Callbacks(obj, hWidget, hData)
% DATASET_CALLBACKS - callbacks on press of buttons in the Dataset ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.dataset_Callbacks(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** - handle to the pressed widget
%   - **hData** - handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.dataset_Callbacks: Dataset ribbon pressed -> %s\n', mode);
end

switch mode
    % --------------- Alignment section ---------------
    case 'Alignment'
        obj.mibController.startController('controllers.Alignment');
    case 'Stitching'
        obj.mibController.startController('controllers.Stitching');
    % --------------- Dataset tools section ---------------
    case 'Crop'              % obj.handles.ribbonDataset.crop
        obj.mibController.startController('controllers.CropDataset', obj.mibController);
    case 'Resize'           % obj.handles.ribbonDataset.resize
        obj.mibController.startController('controllers.ResampleDataset');
    % --------------- Transform ---------------
    case {'Update with new width/height', 'Update with new dX/dY', 'Flip horizontally', ...
            'Flip vertically', 'Flip Z', 'Flip T', 'Rotate 90 degrees', 'Rotate -90 degrees', ...
            'Transpose YX -> YZ', 'Transpose YX -> XZ', 'Transpose YX -> XY', ...
            'Transpose Z <-> T', 'Transpose Z <-> C'}

        % Normalize ' <-> ' → '<->' for BatchOpt compatibility
        mode = strrep(mode, ' <-> ', '<->');
        BatchOpt.Transform = {mode};
        obj.mibModel.transformDataset(BatchOpt);
    % --------------- Slices ---------------    
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
    % --------------- Calibration section ---------------
    case 'Scale bar'              % obj.handles.ribbonDataset.scalebar
        obj.mibController.scaleBarCalibration();
    case 'Bounding box'           % obj.handles.ribbonDataset.boundingbox
        obj.mibController.startController('controllers.BoundingBox');  % a new appdesigner version
    case 'Voxels'                % obj.handles.ribbonDataset.voxels
        obj.updateVoxelSizes();
    % --------------- Metadata section ---------------
    case 'Action log'              % obj.handles.ribbonDataset.log
        obj.mibController.startController('controllers.ActionLog');
    case 'Metadata'                 % obj.handles.ribbonDataset.info
        obj.mibController.startController('controllers.DatasetInfo');
end

end
