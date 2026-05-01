function widgetHandles = addRibbonMask(obj, lazyInit)
% ADDRIBBONMASK - build the Mask tab group and add it to the global ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%      widgetHandles = obj.addRibbonMask()
%      widgetHandles = obj.addRibbonMask(lazyInit)
%
% Input Arguments:
%   - **lazyInit** *(optional)* — [logical] when ``true``, only a placeholder is
%     initialized; full rendering occurs on first tab activation via
%     ``MibController.globalTabGroup_SelectionCallback`` (default: ``false``)
%
% Output Arguments:
%   - **widgetHandles** — [struct] handles to the Mask ribbon section widgets
%

arguments (Input)
    obj views.MibView
    lazyInit logical = false
end

%% Lazy initialization
if lazyInit
    % lazy initialization, the real initialization is in controllers.MibController.globalTabGroup_SelectionCallback
    % Make the tab
    obj.handles.ribbon.mask = matlab.ui.internal.toolstrip.Tab("Mask");
    obj.handles.ribbon.mask.Tag = 'toolbarMask';

    % Add tab to the tab group
    obj.handles.ribbon.global.add(obj.handles.ribbon.mask);
    widgetHandles = [];
    return
end


%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.SplitButton
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.PopupListHeader
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton


%% ============= Make "Mask Convert" section =============
section = obj.handles.ribbon.mask.addSection("Convert");
% ------------- Mask->Selection -------------
column = section.addColumn();

widgetHandles.maskToSelection =  DropDownButton('Mask->Selection', Icon(fullfile(iconPath, 'mask_convert_24px.png')));
widgetHandles.maskToSelection.Description = "Convert Mask to Selection";
popupList = PopupList();
header1 = PopupListHeader('Convert Mask to Selection');
popupList.add(header1);
% % Mask->Selection -> Shown slice (2D)
widgetHandles.maskToSelection2D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Shown slice (2D)', Icon(fullfile(iconPath, 'dataset2d_24px.png')));

popupList2 = PopupList();
% % Mask to Selection -> Shown slice (2D) -> Add
widgetHandles.maskToSelection2DAdd =  ListItem('Add, 2D', Icon(fullfile(iconPath, 'add_24px.png')));
popupList2.add(widgetHandles.maskToSelection2DAdd);
% % Mask to Selection -> Shown slice (2D) -> Remove
widgetHandles.maskToSelection2DRemove =  ListItem('Remove, 2D', Icon(fullfile(iconPath, 'remove_24px.png')));
popupList2.add(widgetHandles.maskToSelection2DRemove);
% % Mask to Selection -> Shown slice (2D) -> Replace
widgetHandles.maskToSelection2DReplace =  ListItem('Replace, 2D', Icon(fullfile(iconPath, 'replace_24px.png')));
popupList2.add(widgetHandles.maskToSelection2DReplace);
widgetHandles.maskToSelection2D.Popup = popupList2;

popupList.add(widgetHandles.maskToSelection2D);

% ------------- Mask->Selection -> Current stack (3D) -------------
widgetHandles.maskToSelection3D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Current stack (3D)', Icon(fullfile(iconPath, 'dataset3d_24px.png')));

popupList2 = PopupList();
% % Mask to Selection -> Current stack (3D) -> Add
widgetHandles.maskToSelection3DAdd =  ListItem('Add, 3D', Icon(fullfile(iconPath, 'add_24px.png')));
popupList2.add(widgetHandles.maskToSelection3DAdd);
% % Mask to Selection -> Current stack (3D) -> Remove
widgetHandles.maskToSelection3DRemove =  ListItem('Remove, 3D', Icon(fullfile(iconPath, 'remove_24px.png')));
popupList2.add(widgetHandles.maskToSelection3DRemove);
% % Mask to Selection -> Current stack (3D) -> Replace
widgetHandles.maskToSelection3DReplace =  ListItem('Replace, 3D', Icon(fullfile(iconPath, 'replace_24px.png')));
popupList2.add(widgetHandles.maskToSelection3DReplace);
widgetHandles.maskToSelection3D.Popup = popupList2;

popupList.add(widgetHandles.maskToSelection3D);

% ------------- Mask->Selection -> Complete volume (4D) -------------
widgetHandles.maskToSelection4D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Complete volume (4D)', Icon(fullfile(iconPath, 'dataset4d_24px.png')));

popupList2 = PopupList();
% % Mask to Selection -> Complete volume (4D) -> Add
widgetHandles.maskToSelection4DAdd =  ListItem('Add, 4D', Icon(fullfile(iconPath, 'add_24px.png')));
popupList2.add(widgetHandles.maskToSelection4DAdd);
% % Mask to Selection -> Complete volume (4D) -> Remove
widgetHandles.maskToSelection4DRemove =  ListItem('Remove, 4D', Icon(fullfile(iconPath, 'remove_24px.png')));
popupList2.add(widgetHandles.maskToSelection4DRemove);
% % Mask to Selection -> Complete volume (4D) -> Replace
widgetHandles.maskToSelection4DReplace =  ListItem('Replace, 4D', Icon(fullfile(iconPath, 'replace_24px.png')));
popupList2.add(widgetHandles.maskToSelection4DReplace);
widgetHandles.maskToSelection4D.Popup = popupList2;

popupList.add(widgetHandles.maskToSelection4D);

widgetHandles.maskToSelection.Popup = popupList;
column.add(widgetHandles.maskToSelection);

%% ============= Make "Mask Input" section =============
section = obj.handles.ribbon.mask.addSection("Import");
% ------------- Clear mask -------------
column = section.addColumn();
widgetHandles.clear = Button(sprintf('Clear\nmask'),  Icon(fullfile(iconPath, 'mask_clear_24px.png')));
widgetHandles.clear.Description = 'Clear the mask layer';
column.add(widgetHandles.clear);
% ------------- Load mask -------------
column = section.addColumn();
widgetHandles.load = Button(sprintf('Load\nmask'),  Icon(fullfile(iconPath, 'mask_load_24px.png')));
widgetHandles.load.Description = 'Load mask from a file';
column.add(widgetHandles.load);
% ------------- Import mask -------------
column = section.addColumn();
widgetHandles.import =  SplitButton('Import', Icon(fullfile(iconPath, 'mask_import_24px.png')));
widgetHandles.import.Description = 'Import mask';

popupList = PopupList();
header1 = PopupListHeader('Import mask');
popupList.add(header1);
widgetHandles.importFromMatlab =  ListItem( 'Import mask from MATLAB',  Icon.MATLAB_24); 
popupList.add(widgetHandles.importFromMatlab);
widgetHandles.importFromMIB =  ListItem( 'Import mask from another MIB dataset',  Icon(fullfile(iconPath, 'mib_icon_24px.png'))); 
popupList.add(widgetHandles.importFromMIB);
widgetHandles.import.Popup = popupList;
column.add(widgetHandles.import);

%% ============= Make "Mask Export" section =============
section = obj.handles.ribbon.mask.addSection("Export");
% ------------- Export to MATLAB -------------
column = section.addColumn();
widgetHandles.export =  SplitButton('Export', Icon(fullfile(iconPath, 'mask_export_24px.png')));
widgetHandles.export.Description = 'Export mask';

popupList = PopupList();
header1 = PopupListHeader('Export mask');
popupList.add(header1);
widgetHandles.exportToMatlab =  ListItem( 'Export mask to MATLAB', Icon.MATLAB_24); 
popupList.add(widgetHandles.exportToMatlab);
widgetHandles.exportToMIB =  ListItem( 'Export mask to another MIB dataset',  Icon(fullfile(iconPath, 'mib_icon_24px.png'))); 
popupList.add(widgetHandles.exportToMIB);

widgetHandles.export.Popup = popupList;
column.add(widgetHandles.export);

% ------------- Save mask -------------
column = section.addColumn();
widgetHandles.saveMask = Button(sprintf('Save\nmask'), Icon(fullfile(iconPath, 'mask_save_24px.png')));
widgetHandles.saveMask.Description = 'Save the mask layer';
column.add(widgetHandles.saveMask);

%% ============= Make "Mask Tools" section =============
section = obj.handles.ribbon.mask.addSection("Tools");
%% -------- INVERT --------
column = section.addColumn();
widgetHandles.invert = SplitButton('Invert',Icon(fullfile(iconPath, 'mask_invert_24px.png')));
widgetHandles.invert.Description = "Invert mask";

popupList = PopupList();
header1 = PopupListHeader('Invert mask');
popupList.add(header1);
% popupList.add(header1);
% % Invert mask -> Shown slice (2D)
widgetHandles.invert2D =  ListItem('Shown slice (2D)', Icon(fullfile(iconPath, 'dataset2d_24px.png')));
popupList.add(widgetHandles.invert2D);
% % Invert mask -> Current Stack (3D)
widgetHandles.invert3D =  ListItem('Current stack (3D)', Icon(fullfile(iconPath, 'dataset3d_24px.png')));
popupList.add(widgetHandles.invert3D);
% % Invert mask -> Complete volume (4D)
widgetHandles.invert4D =  ListItem('Complete volume (4D)', Icon(fullfile(iconPath, 'dataset4d_24px.png')));
popupList.add(widgetHandles.invert4D);

% add the popup list to the INVERT button
widgetHandles.invert.Popup = popupList;
column.add(widgetHandles.invert);

%% -------- Replace masked areas --------
column = section.addColumn();
widgetHandles.replaceImage = Button(sprintf('Replace\nmasked areas'),  Icon(fullfile(iconPath, 'mask_replace_image_24px.png')));
widgetHandles.replaceImage.Description = 'Replace masked area in the image';
column.add(widgetHandles.replaceImage);

%% -------- Smooth mask --------
column = section.addColumn();
widgetHandles.smooth = Button(sprintf('Smooth\nmask'),  Icon(fullfile(iconPath, 'mask_smooth_24px.png')));
widgetHandles.smooth.Description = 'Smooth masked areas';
column.add(widgetHandles.smooth);


%% ============= Make "QUANTIFY" section =============
section = obj.handles.ribbon.mask.addSection("Quantify");
%% -------- INVERT --------
column = section.addColumn();
widgetHandles.quantify = Button('Quantify',  Icon(fullfile(iconPath, 'mask_quantify_24px.png')));
widgetHandles.quantify.Description = 'Quantify masked areas';
column.add(widgetHandles.quantify);

obj.handles.ribbonMask = widgetHandles;

end
