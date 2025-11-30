function buildDatasetTab(obj, lazyInit)
% function buildDatasetTab(obj, lazyInit)
% build the Dataset tab group (obj.handles.toolbar.dataset)
% and add it to obj.handles.toolbar.global 
%
% Parameters:
% lazyInit: [@em optional default=false] logical, when true do only
% place maker initialization of the panel. The full rendering is upon the
% first call, using
% "controllers.MibController.globalTabGroup_SelectionCallback" function

arguments (Input)
    obj views.MibView
    lazyInit logical = false
end

%% Lazy initialization
if lazyInit
    % lazy initialization, the real initialization is in controllers.MibController.globalTabGroup_SelectionCallback
    % Make the tab
    obj.handles.toolbar.dataset = matlab.ui.internal.toolstrip.Tab("Dataset");
    obj.handles.toolbar.dataset.Tag = 'toolbarDataset';
    % Add tab to the tab group
    obj.handles.toolbar.global.add(obj.handles.toolbar.dataset);
    return
end

%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton

%% ============= Make "Calibration" section =============
section = obj.handles.toolbar.dataset.addSection("Align");

% --------- Alignment ---------
column = section.addColumn();
obj.handles.dataset.alignment = Button('Alignment',  Icon(fullfile(iconPath, 'alignment_24px.png')));
obj.handles.dataset.alignment.Description = 'Start the alignment tool';
obj.handles.dataset.alignment.ButtonPushedFcn = @(varargin)disp('Start the alignment tool pressed');
column.add(obj.handles.dataset.alignment);

%% ============= Make "Dataset tools" section =============
section = obj.handles.toolbar.dataset.addSection("Dataset tools");
% -------- Crop --------
column = section.addColumn();
obj.handles.dataset.crop = Button('Crop',  Icon(fullfile(iconPath, 'crop_24px.png')));
obj.handles.dataset.crop.Description = 'Crop the dataset';
obj.handles.dataset.crop.ButtonPushedFcn = @(varargin)disp('Crop the dataset pressed');
column.add(obj.handles.dataset.crop);
% -------- Resize --------
column = section.addColumn();
obj.handles.dataset.resize = Button('Resize',  Icon(fullfile(iconPath, 'resize_24px.png')));
obj.handles.dataset.resize.Description = 'Resize the dataset';
obj.handles.dataset.resize.ButtonPushedFcn = @(varargin)disp('Resize the dataset pressed');
column.add(obj.handles.dataset.resize);

% -------- Transform --------
column = section.addColumn();
obj.handles.dataset.transform =  DropDownButton('Transform', Icon(fullfile(iconPath, 'transform_24px.png')));
obj.handles.dataset.transform.Description = "Transform the dataset";

popupList = PopupList();
% % ADD FRAME
obj.handles.dataset.addframe = matlab.ui.internal.toolstrip.ListItemWithPopup('Add frame...', Icon(fullfile(iconPath, 'add_frame_24px.png')));
popupList2 = PopupList();
% % Add Frame -> Update with new width/height
obj.handles.dataset.addframeWidth =  ListItem('Update with new width/height', Icon(fullfile(iconPath, 'add_frame_width_24px.png')));
obj.handles.dataset.addframeWidth.ItemPushedFcn = @(varargin)disp('Update with new width/height pressed');
popupList2.add(obj.handles.dataset.addframeWidth);
% % Add Frame -> Update with new dX/dY
obj.handles.dataset.addframedX =  ListItem('Update with new dX/dY', Icon(fullfile(iconPath, 'add_frame_dX_24px.png')));
obj.handles.dataset.addframedX.ItemPushedFcn = @(varargin)disp('Update with new dX/dY pressed');
popupList2.add(obj.handles.dataset.addframedX);
obj.handles.dataset.addframe.Popup = popupList2;
popupList.add(obj.handles.dataset.addframe);

% % FLIP
obj.handles.dataset.flip = matlab.ui.internal.toolstrip.ListItemWithPopup('Flip...', Icon(fullfile(iconPath, 'flip_24px.png')));
popupList2 = PopupList();
% % Flip horizontally
obj.handles.dataset.flipH =  ListItem('Flip horizontally', Icon(fullfile(iconPath, 'flipH_24px.png')));
obj.handles.dataset.flipH.ItemPushedFcn = @(varargin)disp('Flip dataset horizontally pressed');
popupList2.add(obj.handles.dataset.flipH);
% % Flip vertically
obj.handles.dataset.flipV =  ListItem('Flip vertically', Icon(fullfile(iconPath, 'flipV_24px.png')));
obj.handles.dataset.flipV.ItemPushedFcn = @(varargin)disp('Flip dataset vertically pressed');
popupList2.add(obj.handles.dataset.flipV);
% % Flip Z
obj.handles.dataset.flipZ =  ListItem('Flip Z', Icon(fullfile(iconPath, 'flipZ_24px.png')));
obj.handles.dataset.flipZ.ItemPushedFcn = @(varargin)disp('Flip Z pressed');
popupList2.add(obj.handles.dataset.flipZ);
% % Flip T
obj.handles.dataset.flipT =  ListItem('Flip T', Icon(fullfile(iconPath, 'flipT_24px.png')));
obj.handles.dataset.flipT.ItemPushedFcn = @(varargin)disp('Flip T pressed');
popupList2.add(obj.handles.dataset.flipT);

obj.handles.dataset.flip.Popup = popupList2;
popupList.add(obj.handles.dataset.flip);

% % ROTATE
obj.handles.dataset.rotate = matlab.ui.internal.toolstrip.ListItemWithPopup('Rotate...', Icon(fullfile(iconPath, 'rotate_24px.png')));
popupList2 = PopupList();
% % Rotate 90
obj.handles.dataset.rotPos90 =  ListItem('Rotate 90 degrees', Icon(fullfile(iconPath, 'rotate_pos_90_24px.png')));
obj.handles.dataset.rotPos90.ItemPushedFcn = @(varargin)disp('Rotate 90 degrees pressed');
popupList2.add(obj.handles.dataset.rotPos90);
% % Rotate -90
obj.handles.dataset.rotNeg90 =  ListItem('Rotate -90 degrees', Icon(fullfile(iconPath, 'rotate_neg_90_24px.png')));
obj.handles.dataset.rotNeg90.ItemPushedFcn = @(varargin)disp('Rotate -90 degrees pressed');
popupList2.add(obj.handles.dataset.rotNeg90);

obj.handles.dataset.rotate.Popup = popupList2;
popupList.add(obj.handles.dataset.rotate);

% % TRANSPOSE
obj.handles.dataset.transpose = matlab.ui.internal.toolstrip.ListItemWithPopup('Transpose...', Icon(fullfile(iconPath, 'transpose_yx_yz_24px.png')));
popupList2 = PopupList();
% % Transpose YX -> YZ
obj.handles.dataset.transposeYX2YZ =  ListItem('Transpose YX -> YZ', Icon(fullfile(iconPath, 'transpose_yx_yz_24px.png')));
obj.handles.dataset.transposeYX2YZ.ItemPushedFcn = @(varargin)disp('Transpose YX -> YZ pressed');
popupList2.add(obj.handles.dataset.transposeYX2YZ);
% % Transpose YX -> XZ
obj.handles.dataset.transposeYX2XZ =  ListItem('Transpose YX -> XZ', Icon(fullfile(iconPath, 'transpose_yx_xz_24px.png')));
obj.handles.dataset.transposeYX2XZ.ItemPushedFcn = @(varargin)disp('Transpose YX -> YZ pressed');
popupList2.add(obj.handles.dataset.transposeYX2XZ);
% % Transpose YX -> XY
obj.handles.dataset.transposeYX2XY =  ListItem('Transpose YX -> XY', Icon(fullfile(iconPath, 'transpose_yx_xy_24px.png')));
obj.handles.dataset.transposeYX2XY.ItemPushedFcn = @(varargin)disp('Transpose YX -> XY pressed');
popupList2.add(obj.handles.dataset.transposeYX2XY);
% % Transpose Z <-> T
obj.handles.dataset.transposeZ2T =  ListItem('Transpose Z <-> T', Icon(fullfile(iconPath, 'transpose_z2t_24px.png')));
obj.handles.dataset.transposeZ2T.ItemPushedFcn = @(varargin)disp('Transpose Z -> T pressed');
popupList2.add(obj.handles.dataset.transposeZ2T);
% % Transpose Z <-> C
obj.handles.dataset.transposeZ2C =  ListItem('Transpose Z <-> C', Icon(fullfile(iconPath, 'transpose_z2c_24px.png')));
obj.handles.dataset.transposeZ2C.ItemPushedFcn = @(varargin)disp('Transpose Z -> T pressed');
popupList2.add(obj.handles.dataset.transposeZ2C);

obj.handles.dataset.transpose.Popup = popupList2;
popupList.add(obj.handles.dataset.transpose);

% add the popup list to the Transform button
obj.handles.dataset.transform.Popup = popupList;
column.add(obj.handles.dataset.transform);


% -------- Slice --------
column = section.addColumn();
obj.handles.dataset.slice =  DropDownButton('Slices', Icon(fullfile(iconPath, 'slices_24px.png')));
obj.handles.dataset.slice.Description = "Operations with slices";
% % COPY SLICE
popupList = PopupList();
obj.handles.dataset.sliceCopy =  ListItem('Copy slice...', Icon(fullfile(iconPath, 'slices_copy_24px.png')));
obj.handles.dataset.sliceCopy.ItemPushedFcn = @(varargin)disp('Copy slice pressed');
popupList.add(obj.handles.dataset.sliceCopy);
% % INSERT EMPTY SLICE
obj.handles.dataset.sliceInsert =  ListItem('Insert empty slice(s)...', Icon(fullfile(iconPath, 'slices_insert_24px.png')));
obj.handles.dataset.sliceInsert.ItemPushedFcn = @(varargin)disp('Insert empty slice pressed');
popupList.add(obj.handles.dataset.sliceInsert);
% % INTERVAL SLICING
obj.handles.dataset.sliceInterval =  ListItem('Interval slicing...', Icon(fullfile(iconPath, 'slices_interval_24px.png')));
obj.handles.dataset.sliceInterval.ItemPushedFcn = @(varargin)disp('Interval slicing pressed');
popupList.add(obj.handles.dataset.sliceInterval);
% % SWAP SLICES
obj.handles.dataset.sliceSwap =  ListItem('Swap slices...', Icon(fullfile(iconPath, 'slices_swap_24px.png')));
obj.handles.dataset.sliceSwap.ItemPushedFcn = @(varargin)disp('Swap slices pressed');
popupList.add(obj.handles.dataset.sliceSwap);
% % SEPARATOR
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);
% % DELETE SLICES
obj.handles.dataset.sliceDelete =  ListItem('Delete slice(s)...', Icon(fullfile(iconPath, 'slices_delete_24px.png')));
obj.handles.dataset.sliceDelete.ItemPushedFcn = @(varargin)disp('Delete slice pressed');
popupList.add(obj.handles.dataset.sliceDelete);
% % DELETE FRAMES
obj.handles.dataset.sliceFrameDelete =  ListItem('Delete frame(s)...', Icon(fullfile(iconPath, 'slices_frame_delete_24px.png')));
obj.handles.dataset.sliceFrameDelete.ItemPushedFcn = @(varargin)disp('Delete frame pressed');
popupList.add(obj.handles.dataset.sliceFrameDelete);

obj.handles.dataset.slice.Popup = popupList;
column.add(obj.handles.dataset.slice);

%% ============= Make "Calibration" section =============
section = obj.handles.toolbar.dataset.addSection("Calibration");

% --------- Scale bar ---------
column = section.addColumn();
obj.handles.dataset.scalebar = Button('Scale bar',  Icon(fullfile(iconPath, 'scale_24px.png')));
obj.handles.dataset.scalebar.Description = 'Dataset calibration using scale bar';
obj.handles.dataset.scalebar.ButtonPushedFcn = @(varargin)disp('Dataset calibration using scale bar pressed');
column.add(obj.handles.dataset.scalebar);
% --------- Bounding box --------- 
column = section.addColumn();
obj.handles.dataset.boundingbox = Button('Bounding box',  Icon(fullfile(iconPath, 'bounding_box_24px.png')));
obj.handles.dataset.boundingbox.Description = 'Dataset calibration using bounding box';
obj.handles.dataset.boundingbox.ButtonPushedFcn = @(varargin)disp('Bounding box pressed');
column.add(obj.handles.dataset.boundingbox);
% --------- Voxels --------- 
column = section.addColumn();
obj.handles.dataset.voxels = Button('Voxels',  Icon(fullfile(iconPath, 'voxels_24px.png')));
obj.handles.dataset.voxels.Description = 'Dataset calibration using voxel size';
obj.handles.dataset.voxels.ButtonPushedFcn = @(varargin)disp('Voxels pressed');
column.add(obj.handles.dataset.voxels);

%% ============= Make "Metadata" section =============
section = obj.handles.toolbar.dataset.addSection("Metadata");
% --------- Log button bar ---------
column = section.addColumn();
obj.handles.dataset.log = Button('Action log',  Icon.PROPERTIES_24);
obj.handles.dataset.log.Description = 'See the log of operations done with the dataset';
obj.handles.dataset.log.ButtonPushedFcn = @(varargin)disp('See the log of operations done with the dataset pressed');
column.add(obj.handles.dataset.log);

% --------- Info button bar ---------
column = section.addColumn();
obj.handles.dataset.info = Button('Metadata',  Icon(fullfile(iconPath, 'about_24px.png')));
obj.handles.dataset.info.Description = 'Dataset related metadata';
obj.handles.dataset.info.ButtonPushedFcn = @(varargin)disp('Dataset related metadata pressed');
column.add(obj.handles.dataset.info);

end