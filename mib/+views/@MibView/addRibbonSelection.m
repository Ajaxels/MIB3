function widgetHandles = addRibbonSelection(obj, lazyInit)
% function widgetHandles = addRibbonSelection(obj, lazyInit)
% build the Selection tab group (obj.handles.ribbon.selection)
% and add it to obj.handles.ribbon.global 
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
    obj.handles.ribbon.selection = matlab.ui.internal.toolstrip.Tab("Selection");
    obj.handles.ribbon.selection.Tag = 'toolbarSelection';

    % Add tab to the tab group
    obj.handles.ribbon.global.add(obj.handles.ribbon.selection);
    widgetHandles = [];
    return
end

%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton

%% ============= Make "Mask Convert" section =============
section = obj.handles.ribbon.selection.addSection("Convert");

%% -------------- Selection to mask --------------
column = section.addColumn();

widgetHandles.selectionToMask =  DropDownButton('Selection->Mask', Icon(fullfile(iconPath, 'selection_to_mask_24px.png')));
widgetHandles.selectionToMask.Description = "Convert Selection to Mask";

popupList = PopupList();
% ------------- Selection->Mask -> Shown slice (2D) -------------
widgetHandles.selection2mask2D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Shown slice (2D)', Icon(fullfile(iconPath, 'dataset2d_24px.png')));

popupList2 = PopupList();
% % Selection to Mask -> Shown slice (2D) -> Add
widgetHandles.selectionToMask2DAdd =  ListItem('Add, 2D', Icon(fullfile(iconPath, 'add_24px.png')));
popupList2.add(widgetHandles.selectionToMask2DAdd);
% % Selection to Mask -> Shown slice (2D) -> Remove
widgetHandles.selectionToMask2DRemove =  ListItem('Remove, 2D', Icon(fullfile(iconPath, 'remove_24px.png')));
popupList2.add(widgetHandles.selectionToMask2DRemove);
% % Selection to Mask -> Shown slice (2D) -> Replace
widgetHandles.selectionToMask2DReplace =  ListItem('Replace, 2D', Icon(fullfile(iconPath, 'replace_24px.png')));
popupList2.add(widgetHandles.selectionToMask2DReplace);

widgetHandles.selection2mask2D.Popup = popupList2;
popupList.add(widgetHandles.selection2mask2D);

% ------------- Selection->Mask -> Current stack (3D) -------------
widgetHandles.selection2mask3D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Current stack (3D)', Icon(fullfile(iconPath, 'dataset3d_24px.png')));

popupList2 = PopupList();
% % Selection to Mask -> Current stack (3D) -> Add
widgetHandles.selectionToMask3DAdd =  ListItem('Add, 3D', Icon(fullfile(iconPath, 'add_24px.png')));
popupList2.add(widgetHandles.selectionToMask3DAdd);
% % Selection to Mask -> Current stack (3D) -> Remove
widgetHandles.selectionToMask3DRemove =  ListItem('Remove, 3D', Icon(fullfile(iconPath, 'remove_24px.png')));
popupList2.add(widgetHandles.selectionToMask3DRemove);
% % Selection to Mask -> Current stack (3D) -> Replace
widgetHandles.selectionToMask3DReplace =  ListItem('Replace, 3D', Icon(fullfile(iconPath, 'replace_24px.png')));
popupList2.add(widgetHandles.selectionToMask3DReplace);

widgetHandles.selection2mask3D.Popup = popupList2;
popupList.add(widgetHandles.selection2mask3D);

% ------------- Selection->Mask -> Complete volume (4D) -------------
widgetHandles.selection2mask4D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Complete volume (4D)', Icon(fullfile(iconPath, 'dataset4d_24px.png')));

popupList2 = PopupList();
% % Selection to Mask -> Complete volume (4D) -> Add
widgetHandles.selectionToMask4DAdd =  ListItem('Add, 4D', Icon(fullfile(iconPath, 'add_24px.png')));
popupList2.add(widgetHandles.selectionToMask4DAdd);
% % Selection to Mask -> Complete volume (4D) -> Remove
widgetHandles.selectionToMask4DRemove =  ListItem('Remove, 4D', Icon(fullfile(iconPath, 'remove_24px.png')));
popupList2.add(widgetHandles.selectionToMask4DRemove);
% % Selection to Mask -> Complete volume (4D) -> Replace
widgetHandles.selectionToMask4DReplace =  ListItem('Replace, 4D', Icon(fullfile(iconPath, 'replace_24px.png')));
popupList2.add(widgetHandles.selectionToMask4DReplace);

widgetHandles.selection2mask4D.Popup = popupList2;
popupList.add(widgetHandles.selection2mask4D);

widgetHandles.selectionToMask.Popup = popupList;
column.add(widgetHandles.selectionToMask);

%% ------------- Selection to buffer -------------
column = section.addColumn();

%% -------------- Selection to buffer --------------
widgetHandles.toBuffer =  DropDownButton(sprintf('Selection\nto buffer'), Icon(fullfile(iconPath, 'selection_to_buffer_24px.png')));
widgetHandles.toBuffer.Description = "Copy selection to buffer";

popupList = PopupList();
widgetHandles.copy =  ListItem( 'Copy (Ctrl+C)', Icon.COPY_24); 
popupList.add(widgetHandles.copy);
widgetHandles.paste =  ListItem( 'Paste (Ctrl+V)', Icon.PASTE_24); 
popupList.add(widgetHandles.paste);
widgetHandles.pasteAll =  ListItem( 'Paste to all slices (Ctrl+Shift+V)',  Icon(fullfile(iconPath, 'selection_pasteAll_24px.png')));
popupList.add(widgetHandles.pasteAll);
widgetHandles.clear =  ListItem( 'Clear', Icon(fullfile(iconPath, 'selection_clear_24px.png')));
popupList.add(widgetHandles.clear);

widgetHandles.toBuffer.Popup = popupList;
column.add(widgetHandles.toBuffer);


%% ============= Make "Tools" section =============
section = obj.handles.ribbon.selection.addSection("Tools");

column = section.addColumn();
%% -------------- Morphological 2D/3D operations --------------
widgetHandles.morphOps =  DropDownButton(sprintf('Morphological\n2D/3D operations'), Icon(fullfile(iconPath, 'selection_morphops_24px.png')));
widgetHandles.morphOps.Description = "Copy selection to buffer";

popupList = PopupList();
% Branch points
widgetHandles.branch =  ListItem('Branch points', Icon(fullfile(iconPath, 'selection_branch_24px.png')));
popupList.add(widgetHandles.branch);
% Diagonal fill
widgetHandles.diag =  ListItem('Diagonal fill', Icon(fullfile(iconPath, 'selection_diag_24px.png')));
popupList.add(widgetHandles.diag);
% Endpoints
widgetHandles.endpoints =  ListItem('Endpoints', Icon(fullfile(iconPath, 'selection_endpoints_24px.png')));
popupList.add(widgetHandles.endpoints);
% Skeleton
widgetHandles.skeleton =  ListItem('Skeleton', Icon(fullfile(iconPath, 'selection_skeleton_24px.png')));
popupList.add(widgetHandles.skeleton);
% Spur
widgetHandles.spur =  ListItem('Spur', Icon(fullfile(iconPath, 'selection_spur_24px.png'))); 
popupList.add(widgetHandles.spur);
% Thin
widgetHandles.thin =  ListItem('Thin', Icon(fullfile(iconPath, 'selection_thin_24px.png')));
popupList.add(widgetHandles.thin);
% Ultimate erosion
widgetHandles.ultErosion =  ListItem('Ultimate erosion', Icon(fullfile(iconPath, 'selection_ulterode_24px.png')));
popupList.add(widgetHandles.ultErosion);

widgetHandles.morphOps.Popup = popupList;
column.add(widgetHandles.morphOps);

%% -------- INVERT --------
column = section.addColumn();
widgetHandles.invert = matlab.ui.internal.toolstrip.SplitButton('Invert',Icon(fullfile(iconPath, 'selection_invert_24px.png')));
widgetHandles.invert.Description = "Invert selection";

popupList = PopupList();
% % Invert selection -> Shown slice (2D)
widgetHandles.invert2D =  ListItem('Shown slice (2D)', Icon(fullfile(iconPath, 'dataset2d_24px.png')));
popupList.add(widgetHandles.invert2D);
% % Invert selection -> Current Stack (3D)
widgetHandles.invert3D =  ListItem('Current stack (3D)', Icon(fullfile(iconPath, 'dataset3d_24px.png')));
popupList.add(widgetHandles.invert3D);
% % Invert selection -> Complete volume (4D)
widgetHandles.invert4D =  ListItem('Complete volume (4D)', Icon(fullfile(iconPath, 'dataset4d_24px.png')));
popupList.add(widgetHandles.invert4D);

% add the popup list to the INVERT button
widgetHandles.invert.Popup = popupList;
column.add(widgetHandles.invert);

% ------------- Expand to mask border -------------
column = section.addColumn();
widgetHandles.expandToMask = Button(sprintf('Expand to\nmask border'),  Icon(fullfile(iconPath, 'selection_expand_24px.png')));
widgetHandles.expandToMask.Description = 'Expand to mask border';
column.add(widgetHandles.expandToMask);

% ------------- Interpolate as Shape (I) -------------
column = section.addColumn();
widgetHandles.interpolate = matlab.ui.internal.toolstrip.ToggleButton(sprintf('Interpolate as\nshape'),  Icon(fullfile(iconPath, 'selection_shape_24px.png')));
widgetHandles.interpolate.Description = 'Interpolate the selected areas';
column.add(widgetHandles.interpolate);

% ------------- Replace selected areas in the image -------------
column = section.addColumn();
widgetHandles.replaceImage = Button(sprintf('Replace\nselected areas'),  Icon(fullfile(iconPath, 'selection_replace_24px.png')));
widgetHandles.replaceImage.Description = 'Replace selected areas in the image';
column.add(widgetHandles.replaceImage);

% ------------- Smooth selection -------------
column = section.addColumn();
widgetHandles.smooth = Button(sprintf('Smooth\nselection'),  Icon(fullfile(iconPath, 'selection_smooth_24px.png')));
widgetHandles.smooth.Description = 'Smooth selection';
column.add(widgetHandles.smooth);

obj.handles.ribbonSelection = widgetHandles;

end