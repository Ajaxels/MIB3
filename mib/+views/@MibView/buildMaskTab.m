function buildMaskTab(obj)
% function buildMaskTab(obj)
% build the Mask tab group (obj.handles.toolbar.mask)
% and add it to obj.handles.toolbar.global 
arguments (Input)
    obj views.MibView
end

%% Make the tab
obj.handles.toolbar.mask = matlab.ui.internal.toolstrip.Tab("Mask");
obj.handles.toolbar.mask.Tag = 'toolbarMask';

%% ============= Make "Mask Convert" section =============
section = obj.handles.toolbar.mask.addSection("Convert");
% ------------- Mask->Selection -------------
column = section.addColumn();

obj.handles.mask.maskToSelection =  matlab.ui.internal.toolstrip.DropDownButton('Mask->Selection', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_convert_24px.png')));
obj.handles.mask.maskToSelection.Description = "Convert Mask to Selection";
popupList = matlab.ui.internal.toolstrip.PopupList();
% % Mask->Selection -> Shown slice (2D)
obj.handles.mask.maskToSelection2D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Shown slice (2D)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/dataset2d_24px.png')));

popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Mask to Selection -> Shown slice (2D) -> Add
obj.handles.mask.maskToSelection2DAdd =  matlab.ui.internal.toolstrip.ListItem('Add', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/add_24px.png')));
obj.handles.mask.maskToSelection2DAdd.ItemPushedFcn = @(varargin)disp('Mask to Selection 2D Add pressed');
popupList2.add(obj.handles.mask.maskToSelection2DAdd);
% % Mask to Selection -> Shown slice (2D) -> Remove
obj.handles.mask.maskToSelection2DRemove =  matlab.ui.internal.toolstrip.ListItem('Remove', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/remove_24px.png')));
obj.handles.mask.maskToSelection2DRemove.ItemPushedFcn = @(varargin)disp('Mask to Selection 2D Remove pressed');
popupList2.add(obj.handles.mask.maskToSelection2DRemove);
% % Mask to Selection -> Shown slice (2D) -> Replace
obj.handles.mask.maskToSelection2DReplace =  matlab.ui.internal.toolstrip.ListItem('Replace', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/replace_24px.png')));
obj.handles.mask.maskToSelection2DReplace.ItemPushedFcn = @(varargin)disp('Mask to Selection 2D Replace pressed');
popupList2.add(obj.handles.mask.maskToSelection2DReplace);
obj.handles.mask.maskToSelection2D.Popup = popupList2;

popupList.add(obj.handles.mask.maskToSelection2D);

% ------------- Mask->Selection -> Current stack (3D) -------------
obj.handles.mask.maskToSelection3D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Current stack (3D)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/dataset3d_24px.png')));

popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Mask to Selection -> Current stack (3D) -> Add
obj.handles.mask.maskToSelection3DAdd =  matlab.ui.internal.toolstrip.ListItem('Add', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/add_24px.png')));
obj.handles.mask.maskToSelection3DAdd.ItemPushedFcn = @(varargin)disp('Mask to Selection 3D Add pressed');
popupList2.add(obj.handles.mask.maskToSelection3DAdd);
% % Mask to Selection -> Current stack (3D) -> Remove
obj.handles.mask.maskToSelection3DRemove =  matlab.ui.internal.toolstrip.ListItem('Remove', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/remove_24px.png')));
obj.handles.mask.maskToSelection3DRemove.ItemPushedFcn = @(varargin)disp('Mask to Selection 3D Remove pressed');
popupList2.add(obj.handles.mask.maskToSelection3DRemove);
% % Mask to Selection -> Current stack (3D) -> Replace
obj.handles.mask.maskToSelection3DReplace =  matlab.ui.internal.toolstrip.ListItem('Replace', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/replace_24px.png')));
obj.handles.mask.maskToSelection3DReplace.ItemPushedFcn = @(varargin)disp('Mask to Selection 3D Replace pressed');
popupList2.add(obj.handles.mask.maskToSelection3DReplace);
obj.handles.mask.maskToSelection3D.Popup = popupList2;

popupList.add(obj.handles.mask.maskToSelection3D);

% ------------- Mask->Selection -> Complete volume (4D) -------------
obj.handles.mask.maskToSelection4D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Complete volume (4D)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/dataset4d_24px.png')));

popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Mask to Selection -> Complete volume (4D) -> Add
obj.handles.mask.maskToSelection4DAdd =  matlab.ui.internal.toolstrip.ListItem('Add', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/add_24px.png')));
obj.handles.mask.maskToSelection4DAdd.ItemPushedFcn = @(varargin)disp('Mask to Selection 4D Add pressed');
popupList2.add(obj.handles.mask.maskToSelection4DAdd);
% % Mask to Selection -> Complete volume (4D) -> Remove
obj.handles.mask.maskToSelection4DRemove =  matlab.ui.internal.toolstrip.ListItem('Remove', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/remove_24px.png')));
obj.handles.mask.maskToSelection4DRemove.ItemPushedFcn = @(varargin)disp('Mask to Selection 4D Remove pressed');
popupList2.add(obj.handles.mask.maskToSelection4DRemove);
% % Mask to Selection -> Complete volume (4D) -> Replace
obj.handles.mask.maskToSelection4DReplace =  matlab.ui.internal.toolstrip.ListItem('Replace', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/replace_24px.png')));
obj.handles.mask.maskToSelection4DReplace.ItemPushedFcn = @(varargin)disp('Mask to Selection 4D Replace pressed');
popupList2.add(obj.handles.mask.maskToSelection4DReplace);
obj.handles.mask.maskToSelection4D.Popup = popupList2;

popupList.add(obj.handles.mask.maskToSelection4D);

obj.handles.mask.maskToSelection.Popup = popupList;
column.add(obj.handles.mask.maskToSelection);

%% ============= Make "Mask Input" section =============
section = obj.handles.toolbar.mask.addSection("Input");
% ------------- Clear mask -------------
column = section.addColumn();
obj.handles.mask.clear = matlab.ui.internal.toolstrip.Button(sprintf('Clear\nmask'),  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_clear_24px.png')));
obj.handles.mask.clear.Description = 'Clear the mask layer';
obj.handles.mask.clear.ButtonPushedFcn = @(varargin)disp('Clear mask pressed');
column.add(obj.handles.mask.clear);
% ------------- Load mask -------------
column = section.addColumn();
obj.handles.mask.load = matlab.ui.internal.toolstrip.Button(sprintf('Load\nmask'),  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_load_24px.png')));
obj.handles.mask.load.Description = 'Load mask from a file';
obj.handles.mask.load.ButtonPushedFcn = @(varargin)disp('Load mask pressed');
column.add(obj.handles.mask.load);
% ------------- Import mask -------------
column = section.addColumn();
obj.handles.mask.import =  matlab.ui.internal.toolstrip.SplitButton('Import', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_import_24px.png')));
obj.handles.mask.import.Description = 'Import mask';
obj.handles.mask.import.ButtonPushedFcn = @(varargin)disp('Import mask pressed');

popupList = matlab.ui.internal.toolstrip.PopupList();
obj.handles.mask.importFromMatlab =  matlab.ui.internal.toolstrip.ListItem( 'Import mask from MATLAB',  matlab.ui.internal.toolstrip.Icon.MATLAB_24); 
obj.handles.mask.importFromMatlab.ItemPushedFcn = @(varargin)disp('Import mask from MATLAB pressed');
popupList.add(obj.handles.mask.importFromMatlab);
obj.handles.mask.importFromMIB =  matlab.ui.internal.toolstrip.ListItem( 'Import mask from another MIB dataset',  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mib_icon_24px.png'))); 
obj.handles.mask.importFromMIB.ItemPushedFcn = @(varargin)disp('Import mask from another MIB dataset pressed');
popupList.add(obj.handles.mask.importFromMIB);
obj.handles.mask.import.Popup = popupList;
column.add(obj.handles.mask.import);

%% ============= Make "Mask Export" section =============
section = obj.handles.toolbar.mask.addSection("Export");
% ------------- Export to MATLAB -------------
column = section.addColumn();
obj.handles.mask.export =  matlab.ui.internal.toolstrip.SplitButton('Export', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_export_24px.png')));
obj.handles.mask.export.Description = 'Export mask';
obj.handles.mask.export.ButtonPushedFcn = @(varargin)disp('Export mask pressed');

popupList = matlab.ui.internal.toolstrip.PopupList();
obj.handles.mask.exportToMatlab =  matlab.ui.internal.toolstrip.ListItem( 'Export mask to MATLAB', matlab.ui.internal.toolstrip.Icon.MATLAB_24); 
obj.handles.mask.exportToMatlab.ItemPushedFcn = @(varargin)disp('Export mask to MATLAB pressed');
popupList.add(obj.handles.mask.exportToMatlab);
obj.handles.mask.exportToMIB =  matlab.ui.internal.toolstrip.ListItem( 'Export mask to another MIB dataset',  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mib_icon_24px.png'))); 
obj.handles.mask.exportToMIB.ItemPushedFcn = @(varargin)disp('Export mask to another MIB dataset pressed');
popupList.add(obj.handles.mask.exportToMIB);

obj.handles.mask.export.Popup = popupList;
column.add(obj.handles.mask.export);

% ------------- Save mask -------------
column = section.addColumn();
obj.handles.mask.save = matlab.ui.internal.toolstrip.Button(sprintf('Save\nmask'), matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_save_24px.png')));
obj.handles.mask.save.Description = 'Save the mask layer';
obj.handles.mask.save.ButtonPushedFcn = @(varargin)disp('Save the mask layer pressed');
column.add(obj.handles.mask.save);

%% ============= Make "Mask Tools" section =============
section = obj.handles.toolbar.mask.addSection("Tools");
%% -------- INVERT --------
column = section.addColumn();
obj.handles.mask.invert = matlab.ui.internal.toolstrip.SplitButton('Invert',matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_invert_24px.png')));
obj.handles.mask.invert.ButtonPushedFcn  = @(varargin)disp('Invert mask pressed');
obj.handles.mask.invert.Description = "Invert mask";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Invert mask -> Shown slice (2D)
obj.handles.mask.invert2D =  matlab.ui.internal.toolstrip.ListItem('Shown slice (2D)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/dataset2d_24px.png')));
obj.handles.mask.invert2D.ItemPushedFcn = @(varargin)disp('Shown slice (2D) pressed');
popupList.add(obj.handles.mask.invert2D);
% % Invert mask -> Current Stack (3D)
obj.handles.mask.invert3D =  matlab.ui.internal.toolstrip.ListItem('Current stack (3D)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/dataset3d_24px.png')));
obj.handles.mask.invert3D.ItemPushedFcn = @(varargin)disp('Current stack (3D) pressed');
popupList.add(obj.handles.mask.invert3D);
% % Invert mask -> Complete volume (4D)
obj.handles.mask.invert4D =  matlab.ui.internal.toolstrip.ListItem('Complete volume (4D)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/dataset4d_24px.png')));
obj.handles.mask.invert4D.ItemPushedFcn = @(varargin)disp('Complete volume (4D) pressed');
popupList.add(obj.handles.mask.invert4D);

% add the popup list to the INVERT button
obj.handles.mask.invert.Popup = popupList;
column.add(obj.handles.mask.invert);

%% -------- Replace masked areas --------
column = section.addColumn();
obj.handles.mask.replaceImage = matlab.ui.internal.toolstrip.Button(sprintf('Replace\nmasked areas'),  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_replace_image_24px.png')));
obj.handles.mask.replaceImage.Description = 'Replace masked area in the image';
obj.handles.mask.replaceImage.ButtonPushedFcn = @(varargin)disp('Replace masked area in the image pressed');
column.add(obj.handles.mask.replaceImage);

%% -------- Smooth mask --------
column = section.addColumn();
obj.handles.mask.smooth = matlab.ui.internal.toolstrip.Button(sprintf('Smooth\nmask'),  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_smooth_24px.png')));
obj.handles.mask.smooth.Description = 'Smooth masked areas';
obj.handles.mask.smooth.ButtonPushedFcn = @(varargin)disp('Smooth masked areas pressed');
column.add(obj.handles.mask.smooth);


%% ============= Make "QUANTIFY" section =============
section = obj.handles.toolbar.mask.addSection("Quantify");
%% -------- INVERT --------
column = section.addColumn();
obj.handles.mask.quantify = matlab.ui.internal.toolstrip.Button('Quantify',  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mask_quantify_24px.png')));
obj.handles.mask.quantify.Description = 'Quantify masked areas';
obj.handles.mask.quantify.ButtonPushedFcn = @(varargin)disp('Quantify masked areas pressed');
column.add(obj.handles.mask.quantify);

%% Add tab to the tab group
obj.handles.toolbar.global.add(obj.handles.toolbar.mask);
end