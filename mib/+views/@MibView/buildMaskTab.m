function buildMaskTab(obj, lazyInit)
% function buildMaskTab(obj, lazyInit)
% build the Mask tab group (obj.handles.toolbar.mask)
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
    obj.handles.toolbar.mask = matlab.ui.internal.toolstrip.Tab("Mask");
    obj.handles.toolbar.mask.Tag = 'toolbarMask';

    % Add tab to the tab group
    obj.handles.toolbar.global.add(obj.handles.toolbar.mask);
    return
end


%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.SplitButton
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton

%% ============= Make "Mask Convert" section =============
section = obj.handles.toolbar.mask.addSection("Convert");
% ------------- Mask->Selection -------------
column = section.addColumn();

obj.handles.mask.maskToSelection =  DropDownButton('Mask->Selection', Icon(fullfile(iconPath, 'mask_convert_24px.png')));
obj.handles.mask.maskToSelection.Description = "Convert Mask to Selection";
popupList = PopupList();
% % Mask->Selection -> Shown slice (2D)
obj.handles.mask.maskToSelection2D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Shown slice (2D)', Icon(fullfile(iconPath, 'dataset2d_24px.png')));

popupList2 = PopupList();
% % Mask to Selection -> Shown slice (2D) -> Add
obj.handles.mask.maskToSelection2DAdd =  ListItem('Add', Icon(fullfile(iconPath, 'add_24px.png')));
obj.handles.mask.maskToSelection2DAdd.ItemPushedFcn = @(varargin)disp('Mask to Selection 2D Add pressed');
popupList2.add(obj.handles.mask.maskToSelection2DAdd);
% % Mask to Selection -> Shown slice (2D) -> Remove
obj.handles.mask.maskToSelection2DRemove =  ListItem('Remove', Icon(fullfile(iconPath, 'remove_24px.png')));
obj.handles.mask.maskToSelection2DRemove.ItemPushedFcn = @(varargin)disp('Mask to Selection 2D Remove pressed');
popupList2.add(obj.handles.mask.maskToSelection2DRemove);
% % Mask to Selection -> Shown slice (2D) -> Replace
obj.handles.mask.maskToSelection2DReplace =  ListItem('Replace', Icon(fullfile(iconPath, 'replace_24px.png')));
obj.handles.mask.maskToSelection2DReplace.ItemPushedFcn = @(varargin)disp('Mask to Selection 2D Replace pressed');
popupList2.add(obj.handles.mask.maskToSelection2DReplace);
obj.handles.mask.maskToSelection2D.Popup = popupList2;

popupList.add(obj.handles.mask.maskToSelection2D);

% ------------- Mask->Selection -> Current stack (3D) -------------
obj.handles.mask.maskToSelection3D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Current stack (3D)', Icon(fullfile(iconPath, 'dataset3d_24px.png')));

popupList2 = PopupList();
% % Mask to Selection -> Current stack (3D) -> Add
obj.handles.mask.maskToSelection3DAdd =  ListItem('Add', Icon(fullfile(iconPath, 'add_24px.png')));
obj.handles.mask.maskToSelection3DAdd.ItemPushedFcn = @(varargin)disp('Mask to Selection 3D Add pressed');
popupList2.add(obj.handles.mask.maskToSelection3DAdd);
% % Mask to Selection -> Current stack (3D) -> Remove
obj.handles.mask.maskToSelection3DRemove =  ListItem('Remove', Icon(fullfile(iconPath, 'remove_24px.png')));
obj.handles.mask.maskToSelection3DRemove.ItemPushedFcn = @(varargin)disp('Mask to Selection 3D Remove pressed');
popupList2.add(obj.handles.mask.maskToSelection3DRemove);
% % Mask to Selection -> Current stack (3D) -> Replace
obj.handles.mask.maskToSelection3DReplace =  ListItem('Replace', Icon(fullfile(iconPath, 'replace_24px.png')));
obj.handles.mask.maskToSelection3DReplace.ItemPushedFcn = @(varargin)disp('Mask to Selection 3D Replace pressed');
popupList2.add(obj.handles.mask.maskToSelection3DReplace);
obj.handles.mask.maskToSelection3D.Popup = popupList2;

popupList.add(obj.handles.mask.maskToSelection3D);

% ------------- Mask->Selection -> Complete volume (4D) -------------
obj.handles.mask.maskToSelection4D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Complete volume (4D)', Icon(fullfile(iconPath, 'dataset4d_24px.png')));

popupList2 = PopupList();
% % Mask to Selection -> Complete volume (4D) -> Add
obj.handles.mask.maskToSelection4DAdd =  ListItem('Add', Icon(fullfile(iconPath, 'add_24px.png')));
obj.handles.mask.maskToSelection4DAdd.ItemPushedFcn = @(varargin)disp('Mask to Selection 4D Add pressed');
popupList2.add(obj.handles.mask.maskToSelection4DAdd);
% % Mask to Selection -> Complete volume (4D) -> Remove
obj.handles.mask.maskToSelection4DRemove =  ListItem('Remove', Icon(fullfile(iconPath, 'remove_24px.png')));
obj.handles.mask.maskToSelection4DRemove.ItemPushedFcn = @(varargin)disp('Mask to Selection 4D Remove pressed');
popupList2.add(obj.handles.mask.maskToSelection4DRemove);
% % Mask to Selection -> Complete volume (4D) -> Replace
obj.handles.mask.maskToSelection4DReplace =  ListItem('Replace', Icon(fullfile(iconPath, 'replace_24px.png')));
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
obj.handles.mask.clear = Button(sprintf('Clear\nmask'),  Icon(fullfile(iconPath, 'mask_clear_24px.png')));
obj.handles.mask.clear.Description = 'Clear the mask layer';
obj.handles.mask.clear.ButtonPushedFcn = @(varargin)disp('Clear mask pressed');
column.add(obj.handles.mask.clear);
% ------------- Load mask -------------
column = section.addColumn();
obj.handles.mask.load = Button(sprintf('Load\nmask'),  Icon(fullfile(iconPath, 'mask_load_24px.png')));
obj.handles.mask.load.Description = 'Load mask from a file';
obj.handles.mask.load.ButtonPushedFcn = @(varargin)disp('Load mask pressed');
column.add(obj.handles.mask.load);
% ------------- Import mask -------------
column = section.addColumn();
obj.handles.mask.import =  SplitButton('Import', Icon(fullfile(iconPath, 'mask_import_24px.png')));
obj.handles.mask.import.Description = 'Import mask';
obj.handles.mask.import.ButtonPushedFcn = @(varargin)disp('Import mask pressed');

popupList = PopupList();
obj.handles.mask.importFromMatlab =  ListItem( 'Import mask from MATLAB',  Icon.MATLAB_24); 
obj.handles.mask.importFromMatlab.ItemPushedFcn = @(varargin)disp('Import mask from MATLAB pressed');
popupList.add(obj.handles.mask.importFromMatlab);
obj.handles.mask.importFromMIB =  ListItem( 'Import mask from another MIB dataset',  Icon(fullfile(iconPath, 'mib_icon_24px.png'))); 
obj.handles.mask.importFromMIB.ItemPushedFcn = @(varargin)disp('Import mask from another MIB dataset pressed');
popupList.add(obj.handles.mask.importFromMIB);
obj.handles.mask.import.Popup = popupList;
column.add(obj.handles.mask.import);

%% ============= Make "Mask Export" section =============
section = obj.handles.toolbar.mask.addSection("Export");
% ------------- Export to MATLAB -------------
column = section.addColumn();
obj.handles.mask.export =  SplitButton('Export', Icon(fullfile(iconPath, 'mask_export_24px.png')));
obj.handles.mask.export.Description = 'Export mask';
obj.handles.mask.export.ButtonPushedFcn = @(varargin)disp('Export mask pressed');

popupList = PopupList();
obj.handles.mask.exportToMatlab =  ListItem( 'Export mask to MATLAB', Icon.MATLAB_24); 
obj.handles.mask.exportToMatlab.ItemPushedFcn = @(varargin)disp('Export mask to MATLAB pressed');
popupList.add(obj.handles.mask.exportToMatlab);
obj.handles.mask.exportToMIB =  ListItem( 'Export mask to another MIB dataset',  Icon(fullfile(iconPath, 'mib_icon_24px.png'))); 
obj.handles.mask.exportToMIB.ItemPushedFcn = @(varargin)disp('Export mask to another MIB dataset pressed');
popupList.add(obj.handles.mask.exportToMIB);

obj.handles.mask.export.Popup = popupList;
column.add(obj.handles.mask.export);

% ------------- Save mask -------------
column = section.addColumn();
obj.handles.mask.save = Button(sprintf('Save\nmask'), Icon(fullfile(iconPath, 'mask_save_24px.png')));
obj.handles.mask.save.Description = 'Save the mask layer';
obj.handles.mask.save.ButtonPushedFcn = @(varargin)disp('Save the mask layer pressed');
column.add(obj.handles.mask.save);

%% ============= Make "Mask Tools" section =============
section = obj.handles.toolbar.mask.addSection("Tools");
%% -------- INVERT --------
column = section.addColumn();
obj.handles.mask.invert = SplitButton('Invert',Icon(fullfile(iconPath, 'mask_invert_24px.png')));
obj.handles.mask.invert.ButtonPushedFcn  = @(varargin)disp('Invert mask pressed');
obj.handles.mask.invert.Description = "Invert mask";

popupList = PopupList();
% % Invert mask -> Shown slice (2D)
obj.handles.mask.invert2D =  ListItem('Shown slice (2D)', Icon(fullfile(iconPath, 'dataset2d_24px.png')));
obj.handles.mask.invert2D.ItemPushedFcn = @(varargin)disp('Shown slice (2D) pressed');
popupList.add(obj.handles.mask.invert2D);
% % Invert mask -> Current Stack (3D)
obj.handles.mask.invert3D =  ListItem('Current stack (3D)', Icon(fullfile(iconPath, 'dataset3d_24px.png')));
obj.handles.mask.invert3D.ItemPushedFcn = @(varargin)disp('Current stack (3D) pressed');
popupList.add(obj.handles.mask.invert3D);
% % Invert mask -> Complete volume (4D)
obj.handles.mask.invert4D =  ListItem('Complete volume (4D)', Icon(fullfile(iconPath, 'dataset4d_24px.png')));
obj.handles.mask.invert4D.ItemPushedFcn = @(varargin)disp('Complete volume (4D) pressed');
popupList.add(obj.handles.mask.invert4D);

% add the popup list to the INVERT button
obj.handles.mask.invert.Popup = popupList;
column.add(obj.handles.mask.invert);

%% -------- Replace masked areas --------
column = section.addColumn();
obj.handles.mask.replaceImage = Button(sprintf('Replace\nmasked areas'),  Icon(fullfile(iconPath, 'mask_replace_image_24px.png')));
obj.handles.mask.replaceImage.Description = 'Replace masked area in the image';
obj.handles.mask.replaceImage.ButtonPushedFcn = @(varargin)disp('Replace masked area in the image pressed');
column.add(obj.handles.mask.replaceImage);

%% -------- Smooth mask --------
column = section.addColumn();
obj.handles.mask.smooth = Button(sprintf('Smooth\nmask'),  Icon(fullfile(iconPath, 'mask_smooth_24px.png')));
obj.handles.mask.smooth.Description = 'Smooth masked areas';
obj.handles.mask.smooth.ButtonPushedFcn = @(varargin)disp('Smooth masked areas pressed');
column.add(obj.handles.mask.smooth);


%% ============= Make "QUANTIFY" section =============
section = obj.handles.toolbar.mask.addSection("Quantify");
%% -------- INVERT --------
column = section.addColumn();
obj.handles.mask.quantify = Button('Quantify',  Icon(fullfile(iconPath, 'mask_quantify_24px.png')));
obj.handles.mask.quantify.Description = 'Quantify masked areas';
obj.handles.mask.quantify.ButtonPushedFcn = @(varargin)disp('Quantify masked areas pressed');
column.add(obj.handles.mask.quantify);

end