function widgetHandles = addRibbonDataset(obj, lazyInit)
% ADDRIBBONDATASET - build the Datasets tab group (obj.handles.ribbon.dataset).
%
% Syntax:
%   function widgetHandles = addRibbonDataset(obj, lazyInit)
%
% and add it to obj.handles.ribbon.global
%
% Input Arguments:
%   - **lazyInit** — [*optional* default=false] logical, when true do only
%     place maker initialization of the panel. The full rendering is upon the
%     first call, using
%     "controllers.MibController.globalTabGroup_SelectionCallback" function
%

arguments (Input)
    obj views.MibView
    lazyInit logical = false
end

%% Lazy initialization
if lazyInit
    % lazy initialization, the real initialization is in controllers.MibController.globalTabGroup_SelectionCallback
    % Make the tab
    obj.handles.ribbon.dataset = matlab.ui.internal.toolstrip.Tab("Dataset");
    obj.handles.ribbon.dataset.Tag = 'toolbarDataset';
    % Add tab to the tab group
    obj.handles.ribbon.global.add(obj.handles.ribbon.dataset);
    widgetHandles = [];
    return
end

%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.PopupListHeader
import matlab.ui.internal.toolstrip.PopupListSeparator
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton

%% ============= Make "Calibration" section =============
section = obj.handles.ribbon.dataset.addSection("Align");

% --------- Alignment ---------
column = section.addColumn();
widgetHandles.alignment = Button('Alignment',  Icon(fullfile(iconPath, 'alignment_24px.png')));
widgetHandles.alignment.Description = 'Start the alignment tool';
column.add(widgetHandles.alignment);

%% ============= Make "Dataset tools" section =============
section = obj.handles.ribbon.dataset.addSection("Dataset tools");
% -------- Crop --------
column = section.addColumn();
widgetHandles.crop = Button('Crop',  Icon(fullfile(iconPath, 'crop_24px.png')));
widgetHandles.crop.Description = 'Crop the dataset';
column.add(widgetHandles.crop);
% -------- Resize --------
column = section.addColumn();
widgetHandles.resize = Button('Resize',  Icon(fullfile(iconPath, 'resize_24px.png')));
widgetHandles.resize.Description = 'Resize the dataset';
column.add(widgetHandles.resize);

% -------- Transform --------
column = section.addColumn();
widgetHandles.transform =  DropDownButton('Transform', Icon(fullfile(iconPath, 'transform_24px.png')));
widgetHandles.transform.Description = "Transform the dataset";

popupList = PopupList();
header1 = PopupListHeader('Transform orientation');
popupList.add(header1);
% % ADD FRAME
widgetHandles.addframe = matlab.ui.internal.toolstrip.ListItemWithPopup('Add frame...', Icon(fullfile(iconPath, 'add_frame_24px.png')));
popupList2 = PopupList();
% % Add Frame -> Update with new width/height
widgetHandles.addframeWidth =  ListItem('Update with new width/height', Icon(fullfile(iconPath, 'add_frame_width_24px.png')));
popupList2.add(widgetHandles.addframeWidth);
% % Add Frame -> Update with new dX/dY
widgetHandles.addframedX =  ListItem('Update with new dX/dY', Icon(fullfile(iconPath, 'add_frame_dX_24px.png')));
popupList2.add(widgetHandles.addframedX);
widgetHandles.addframe.Popup = popupList2;
popupList.add(widgetHandles.addframe);

% % FLIP
widgetHandles.flip = matlab.ui.internal.toolstrip.ListItemWithPopup('Flip...', Icon(fullfile(iconPath, 'flip_24px.png')));
popupList2 = PopupList();
% % Flip horizontally
widgetHandles.flipH =  ListItem('Flip horizontally', Icon(fullfile(iconPath, 'flipH_24px.png')));
popupList2.add(widgetHandles.flipH);
% % Flip vertically
widgetHandles.flipV =  ListItem('Flip vertically', Icon(fullfile(iconPath, 'flipV_24px.png')));
popupList2.add(widgetHandles.flipV);
% % Flip Z
widgetHandles.flipZ =  ListItem('Flip Z', Icon(fullfile(iconPath, 'flipZ_24px.png')));
popupList2.add(widgetHandles.flipZ);
% % Flip T
widgetHandles.flipT =  ListItem('Flip T', Icon(fullfile(iconPath, 'flipT_24px.png')));
popupList2.add(widgetHandles.flipT);

widgetHandles.flip.Popup = popupList2;
popupList.add(widgetHandles.flip);

% % ROTATE
widgetHandles.rotate = matlab.ui.internal.toolstrip.ListItemWithPopup('Rotate...', Icon(fullfile(iconPath, 'rotate_24px.png')));
popupList2 = PopupList();
% % Rotate 90
widgetHandles.rotPos90 =  ListItem('Rotate 90 degrees', Icon(fullfile(iconPath, 'rotate_pos_90_24px.png')));
popupList2.add(widgetHandles.rotPos90);
% % Rotate -90
widgetHandles.rotNeg90 =  ListItem('Rotate -90 degrees', Icon(fullfile(iconPath, 'rotate_neg_90_24px.png')));
popupList2.add(widgetHandles.rotNeg90);

widgetHandles.rotate.Popup = popupList2;
popupList.add(widgetHandles.rotate);

% % TRANSPOSE
widgetHandles.transpose = matlab.ui.internal.toolstrip.ListItemWithPopup('Transpose...', Icon(fullfile(iconPath, 'transpose_yx_yz_24px.png')));
popupList2 = PopupList();
% % Transpose YX -> YZ
widgetHandles.transposeYX2YZ =  ListItem('Transpose YX -> YZ', Icon(fullfile(iconPath, 'transpose_yx_yz_24px.png')));
popupList2.add(widgetHandles.transposeYX2YZ);
% % Transpose YX -> XZ
widgetHandles.transposeYX2XZ =  ListItem('Transpose YX -> XZ', Icon(fullfile(iconPath, 'transpose_yx_xz_24px.png')));
popupList2.add(widgetHandles.transposeYX2XZ);
% % Transpose YX -> XY
widgetHandles.transposeYX2XY =  ListItem('Transpose YX -> XY', Icon(fullfile(iconPath, 'transpose_yx_xy_24px.png')));
popupList2.add(widgetHandles.transposeYX2XY);
% % Transpose Z <-> T
widgetHandles.transposeZ2T =  ListItem('Transpose Z <-> T', Icon(fullfile(iconPath, 'transpose_z2t_24px.png')));
popupList2.add(widgetHandles.transposeZ2T);
% % Transpose Z <-> C
widgetHandles.transposeZ2C =  ListItem('Transpose Z <-> C', Icon(fullfile(iconPath, 'transpose_z2c_24px.png')));
popupList2.add(widgetHandles.transposeZ2C);

widgetHandles.transpose.Popup = popupList2;
popupList.add(widgetHandles.transpose);

% add the popup list to the Transform button
widgetHandles.transform.Popup = popupList;
column.add(widgetHandles.transform);


% -------- Slice --------
column = section.addColumn();
widgetHandles.slice =  DropDownButton('Slices', Icon(fullfile(iconPath, 'slices_24px.png')));
widgetHandles.slice.Description = "Operations with slices";
% % COPY SLICE
popupList = PopupList();
header1 = PopupListHeader('Operations with slices/frames');
popupList.add(header1);
widgetHandles.sliceCopy =  ListItem('Copy slice...', Icon(fullfile(iconPath, 'slices_copy_24px.png')));
popupList.add(widgetHandles.sliceCopy);
% % INSERT EMPTY SLICE
widgetHandles.sliceInsert =  ListItem('Insert empty slice(s)...', Icon(fullfile(iconPath, 'slices_insert_24px.png')));
popupList.add(widgetHandles.sliceInsert);
% % INTERVAL SLICING
widgetHandles.sliceInterval =  ListItem('Interval slicing...', Icon(fullfile(iconPath, 'slices_interval_24px.png')));
popupList.add(widgetHandles.sliceInterval);
% % SWAP SLICES
widgetHandles.sliceSwap =  ListItem('Swap slices...', Icon(fullfile(iconPath, 'slices_swap_24px.png')));
popupList.add(widgetHandles.sliceSwap);
% % SEPARATOR
separator = PopupListSeparator();
popupList.add(separator);
% % DELETE SLICES
widgetHandles.sliceDelete =  ListItem('Delete slice(s)...', Icon(fullfile(iconPath, 'slices_delete_24px.png')));
popupList.add(widgetHandles.sliceDelete);
% % DELETE FRAMES
widgetHandles.sliceFrameDelete =  ListItem('Delete frame(s)...', Icon(fullfile(iconPath, 'slices_frame_delete_24px.png')));
popupList.add(widgetHandles.sliceFrameDelete);

widgetHandles.slice.Popup = popupList;
column.add(widgetHandles.slice);

%% ============= Make "Calibration" section =============
section = obj.handles.ribbon.dataset.addSection("Calibration");

% --------- Scale bar ---------
column = section.addColumn();
widgetHandles.scalebar = Button('Scale bar',  Icon(fullfile(iconPath, 'scale_24px.png')));
widgetHandles.scalebar.Description = 'Dataset calibration using scale bar';
column.add(widgetHandles.scalebar);
% --------- Bounding box --------- 
column = section.addColumn();
widgetHandles.boundingbox = Button('Bounding box',  Icon(fullfile(iconPath, 'bounding_box_24px.png')));
widgetHandles.boundingbox.Description = 'Dataset calibration using bounding box';
column.add(widgetHandles.boundingbox);
% --------- Voxels --------- 
column = section.addColumn();
widgetHandles.voxels = Button('Voxels',  Icon(fullfile(iconPath, 'voxels_24px.png')));
widgetHandles.voxels.Description = 'Dataset calibration using voxel size';
column.add(widgetHandles.voxels);

%% ============= Make "Metadata" section =============
section = obj.handles.ribbon.dataset.addSection("Metadata");
% --------- Log button bar ---------
column = section.addColumn();
widgetHandles.log = Button('Action log',  Icon.PROPERTIES_24);
widgetHandles.log.Description = 'See the log of operations done with the dataset';
column.add(widgetHandles.log);

% --------- Info button bar ---------
column = section.addColumn();
widgetHandles.info = Button('Metadata',  Icon(fullfile(iconPath, 'about_24px.png')));
widgetHandles.info.Description = 'Dataset related metadata';
column.add(widgetHandles.info);

obj.handles.ribbonDataset = widgetHandles;

end
