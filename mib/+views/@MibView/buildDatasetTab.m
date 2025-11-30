function buildDatasetTab(obj)
% function buildDatasetTab(obj)
% build the Dataset tab group (obj.handles.toolbar.dataset)
% and add it to obj.handles.toolbar.global 

arguments (Input)
    obj views.MibView
end

obj.handles.toolbar.dataset = matlab.ui.internal.toolstrip.Tab("Dataset");
obj.handles.toolbar.dataset.Tag = 'toolbarDataset';

%% ============= Make "Calibration" section =============
section = obj.handles.toolbar.dataset.addSection("Align");

% --------- Alignment ---------
column = section.addColumn();
obj.handles.dataset.alignment = matlab.ui.internal.toolstrip.Button('Alignment',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'alignment_24px')));
obj.handles.dataset.alignment.Description = 'Start the alignment tool';
obj.handles.dataset.alignment.ButtonPushedFcn = @(varargin)disp('Start the alignment tool pressed');
column.add(obj.handles.dataset.alignment);

%% ============= Make "Dataset tools" section =============
section = obj.handles.toolbar.dataset.addSection("Dataset tools");
% -------- Crop --------
column = section.addColumn();
obj.handles.dataset.crop = matlab.ui.internal.toolstrip.Button('Crop',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'crop_24px')));
obj.handles.dataset.crop.Description = 'Crop the dataset';
obj.handles.dataset.crop.ButtonPushedFcn = @(varargin)disp('Crop the dataset pressed');
column.add(obj.handles.dataset.crop);
% -------- Resize --------
column = section.addColumn();
obj.handles.dataset.resize = matlab.ui.internal.toolstrip.Button('Resize',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'resize_24px')));
obj.handles.dataset.resize.Description = 'Resize the dataset';
obj.handles.dataset.resize.ButtonPushedFcn = @(varargin)disp('Resize the dataset pressed');
column.add(obj.handles.dataset.resize);

% -------- Transform --------
column = section.addColumn();
obj.handles.dataset.transform =  matlab.ui.internal.toolstrip.DropDownButton('Transform', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'transform_24px')));
obj.handles.dataset.transform.Description = "Transform the dataset";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % ADD FRAME
obj.handles.dataset.addframe = matlab.ui.internal.toolstrip.ListItemWithPopup('Add frame...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'add_frame_24px')));
popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Add Frame -> Update with new width/height
obj.handles.dataset.addframeWidth =  matlab.ui.internal.toolstrip.ListItem('Update with new width/height', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'add_frame_width_24px')));
obj.handles.dataset.addframeWidth.ItemPushedFcn = @(varargin)disp('Update with new width/height pressed');
popupList2.add(obj.handles.dataset.addframeWidth);
% % Add Frame -> Update with new dX/dY
obj.handles.dataset.addframedX =  matlab.ui.internal.toolstrip.ListItem('Update with new dX/dY', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'add_frame_dX_24px')));
obj.handles.dataset.addframedX.ItemPushedFcn = @(varargin)disp('Update with new dX/dY pressed');
popupList2.add(obj.handles.dataset.addframedX);
obj.handles.dataset.addframe.Popup = popupList2;
popupList.add(obj.handles.dataset.addframe);

% % FLIP
obj.handles.dataset.flip = matlab.ui.internal.toolstrip.ListItemWithPopup('Flip...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'flip_24px')));
popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Flip horizontally
obj.handles.dataset.flipH =  matlab.ui.internal.toolstrip.ListItem('Flip horizontally', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'flipH_24px')));
obj.handles.dataset.flipH.ItemPushedFcn = @(varargin)disp('Flip dataset horizontally pressed');
popupList2.add(obj.handles.dataset.flipH);
% % Flip vertically
obj.handles.dataset.flipV =  matlab.ui.internal.toolstrip.ListItem('Flip vertically', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'flipV_24px')));
obj.handles.dataset.flipV.ItemPushedFcn = @(varargin)disp('Flip dataset vertically pressed');
popupList2.add(obj.handles.dataset.flipV);
% % Flip Z
obj.handles.dataset.flipZ =  matlab.ui.internal.toolstrip.ListItem('Flip Z', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'flipZ_24px')));
obj.handles.dataset.flipZ.ItemPushedFcn = @(varargin)disp('Flip Z pressed');
popupList2.add(obj.handles.dataset.flipZ);
% % Flip T
obj.handles.dataset.flipT =  matlab.ui.internal.toolstrip.ListItem('Flip T', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'flipT_24px')));
obj.handles.dataset.flipT.ItemPushedFcn = @(varargin)disp('Flip T pressed');
popupList2.add(obj.handles.dataset.flipT);

obj.handles.dataset.flip.Popup = popupList2;
popupList.add(obj.handles.dataset.flip);

% % ROTATE
obj.handles.dataset.rotate = matlab.ui.internal.toolstrip.ListItemWithPopup('Rotate...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'flipT_24px')));
popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Rotate 90
obj.handles.dataset.rotPos90 =  matlab.ui.internal.toolstrip.ListItem('Rotate 90 degrees', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'rotate_pos_90_24px')));
obj.handles.dataset.rotPos90.ItemPushedFcn = @(varargin)disp('Rotate 90 degrees pressed');
popupList2.add(obj.handles.dataset.rotPos90);
% % Rotate -90
obj.handles.dataset.rotNeg90 =  matlab.ui.internal.toolstrip.ListItem('Rotate -90 degrees', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'rotate_neg_90_24px')));
obj.handles.dataset.rotNeg90.ItemPushedFcn = @(varargin)disp('Rotate -90 degrees pressed');
popupList2.add(obj.handles.dataset.rotNeg90);

obj.handles.dataset.rotate.Popup = popupList2;
popupList.add(obj.handles.dataset.rotate);

% % TRANSPOSE
obj.handles.dataset.transpose = matlab.ui.internal.toolstrip.ListItemWithPopup('Transpose...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'transpose_yx_yz_24px')));
popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Transpose YX -> YZ
obj.handles.dataset.transposeYX2YZ =  matlab.ui.internal.toolstrip.ListItem('Transpose YX -> YZ', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'transpose_yx_yz_24px')));
obj.handles.dataset.transposeYX2YZ.ItemPushedFcn = @(varargin)disp('Transpose YX -> YZ pressed');
popupList2.add(obj.handles.dataset.transposeYX2YZ);
% % Transpose YX -> XZ
obj.handles.dataset.transposeYX2XZ =  matlab.ui.internal.toolstrip.ListItem('Transpose YX -> XZ', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'transpose_yx_xz_24px')));
obj.handles.dataset.transposeYX2XZ.ItemPushedFcn = @(varargin)disp('Transpose YX -> YZ pressed');
popupList2.add(obj.handles.dataset.transposeYX2XZ);
% % Transpose YX -> XY
obj.handles.dataset.transposeYX2XY =  matlab.ui.internal.toolstrip.ListItem('Transpose YX -> XY', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'transpose_yx_xy_24px')));
obj.handles.dataset.transposeYX2XY.ItemPushedFcn = @(varargin)disp('Transpose YX -> XY pressed');
popupList2.add(obj.handles.dataset.transposeYX2XY);
% % Transpose Z <-> T
obj.handles.dataset.transposeZ2T =  matlab.ui.internal.toolstrip.ListItem('Transpose Z <-> T', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'transpose_z2t_24px')));
obj.handles.dataset.transposeZ2T.ItemPushedFcn = @(varargin)disp('Transpose Z -> T pressed');
popupList2.add(obj.handles.dataset.transposeZ2T);
% % Transpose Z <-> C
obj.handles.dataset.transposeZ2C =  matlab.ui.internal.toolstrip.ListItem('Transpose Z <-> C', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'transpose_z2c_24px')));
obj.handles.dataset.transposeZ2C.ItemPushedFcn = @(varargin)disp('Transpose Z -> T pressed');
popupList2.add(obj.handles.dataset.transposeZ2C);

obj.handles.dataset.transpose.Popup = popupList2;
popupList.add(obj.handles.dataset.transpose);

% add the popup list to the Transform button
obj.handles.dataset.transform.Popup = popupList;
column.add(obj.handles.dataset.transform);


% -------- Slice --------
column = section.addColumn();
obj.handles.dataset.slice =  matlab.ui.internal.toolstrip.DropDownButton('Slices', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'slices_24px')));
obj.handles.dataset.slice.Description = "Operations with slices";
% % COPY SLICE
popupList = matlab.ui.internal.toolstrip.PopupList();
obj.handles.dataset.sliceCopy =  matlab.ui.internal.toolstrip.ListItem('Copy slice...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'slices_copy_24px')));
obj.handles.dataset.sliceCopy.ItemPushedFcn = @(varargin)disp('Copy slice pressed');
popupList.add(obj.handles.dataset.sliceCopy);
% % INSERT EMPTY SLICE
obj.handles.dataset.sliceInsert =  matlab.ui.internal.toolstrip.ListItem('Insert empty slice(s)...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'slices_insert_24px')));
obj.handles.dataset.sliceInsert.ItemPushedFcn = @(varargin)disp('Insert empty slice pressed');
popupList.add(obj.handles.dataset.sliceInsert);
% % INTERVAL SLICING
obj.handles.dataset.sliceInterval =  matlab.ui.internal.toolstrip.ListItem('Interval slicing...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'slices_interval_24px')));
obj.handles.dataset.sliceInterval.ItemPushedFcn = @(varargin)disp('Interval slicing pressed');
popupList.add(obj.handles.dataset.sliceInterval);
% % SWAP SLICES
obj.handles.dataset.sliceSwap =  matlab.ui.internal.toolstrip.ListItem('Swap slices...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'slices_swap_24px')));
obj.handles.dataset.sliceSwap.ItemPushedFcn = @(varargin)disp('Swap slices pressed');
popupList.add(obj.handles.dataset.sliceSwap);
% % SEPARATOR
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);
% % DELETE SLICES
obj.handles.dataset.sliceDelete =  matlab.ui.internal.toolstrip.ListItem('Delete slice(s)...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'slices_delete_24px')));
obj.handles.dataset.sliceDelete.ItemPushedFcn = @(varargin)disp('Delete slice pressed');
popupList.add(obj.handles.dataset.sliceDelete);
% % DELETE FRAMES
obj.handles.dataset.sliceFrameDelete =  matlab.ui.internal.toolstrip.ListItem('Delete frame(s)...', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'slices_frame_delete_24px')));
obj.handles.dataset.sliceFrameDelete.ItemPushedFcn = @(varargin)disp('Delete frame pressed');
popupList.add(obj.handles.dataset.sliceFrameDelete);

obj.handles.dataset.slice.Popup = popupList;
column.add(obj.handles.dataset.slice);

%% ============= Make "Calibration" section =============
section = obj.handles.toolbar.dataset.addSection("Calibration");

% --------- Scale bar ---------
column = section.addColumn();
obj.handles.dataset.scalebar = matlab.ui.internal.toolstrip.Button('Scale bar',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'scale_24px')));
obj.handles.dataset.scalebar.Description = 'Dataset calibration using scale bar';
obj.handles.dataset.scalebar.ButtonPushedFcn = @(varargin)disp('Dataset calibration using scale bar pressed');
column.add(obj.handles.dataset.scalebar);
% --------- Bounding box --------- 
column = section.addColumn();
obj.handles.dataset.boundingbox = matlab.ui.internal.toolstrip.Button('Bounding box',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'bounding_box_24px')));
obj.handles.dataset.boundingbox.Description = 'Dataset calibration using bounding box';
obj.handles.dataset.boundingbox.ButtonPushedFcn = @(varargin)disp('Bounding box pressed');
column.add(obj.handles.dataset.boundingbox);
% --------- Voxels --------- 
column = section.addColumn();
obj.handles.dataset.voxels = matlab.ui.internal.toolstrip.Button('Voxels',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'voxels_24px')));
obj.handles.dataset.voxels.Description = 'Dataset calibration using voxel size';
obj.handles.dataset.voxels.ButtonPushedFcn = @(varargin)disp('Voxels pressed');
column.add(obj.handles.dataset.voxels);

%% ============= Make "Metadata" section =============
section = obj.handles.toolbar.dataset.addSection("Metadata");
% --------- Log button bar ---------
column = section.addColumn();
obj.handles.dataset.log = matlab.ui.internal.toolstrip.Button('Action log',  matlab.ui.internal.toolstrip.Icon.PROPERTIES_24);
obj.handles.dataset.log.Description = 'See the log of operations done with the dataset';
obj.handles.dataset.log.ButtonPushedFcn = @(varargin)disp('See the log of operations done with the dataset pressed');
column.add(obj.handles.dataset.log);

% --------- Info button bar ---------
column = section.addColumn();
obj.handles.dataset.info = matlab.ui.internal.toolstrip.Button('Metadata',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'about_24px')));
obj.handles.dataset.info.Description = 'Dataset related metadata';
obj.handles.dataset.info.ButtonPushedFcn = @(varargin)disp('Dataset related metadata pressed');
column.add(obj.handles.dataset.info);

obj.handles.toolbar.global.add(obj.handles.toolbar.dataset);

end