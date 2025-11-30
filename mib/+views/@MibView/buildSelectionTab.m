function buildSelectionTab(obj)
% function buildSelectionTab(obj)
% build the Selection tab group (obj.handles.toolbar.selection)
% and add it to obj.handles.toolbar.global 
arguments (Input)
    obj views.MibView
end
%% Make the tab
obj.handles.toolbar.selection = matlab.ui.internal.toolstrip.Tab("Selection");
obj.handles.toolbar.selection.Tag = 'toolbarSelection';

%% ============= Make "Mask Convert" section =============
section = obj.handles.toolbar.selection.addSection("Convert");

%% -------------- Selection to mask --------------
column = section.addColumn();

obj.handles.selection.selectionToMask =  matlab.ui.internal.toolstrip.DropDownButton('Selection->Mask', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_to_mask_24px')));
obj.handles.selection.selectionToMask.Description = "Convert Selection to Mask";

popupList = matlab.ui.internal.toolstrip.PopupList();
% ------------- Selection->Mask -> Shown slice (2D) -------------
obj.handles.selection.selection2mask2D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Shown slice (2D)', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dataset2d_24px')));

popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Selection to Mask -> Shown slice (2D) -> Add
obj.handles.selection.selectionToMask2DAdd =  matlab.ui.internal.toolstrip.ListItem('Add', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'add_24px')));
obj.handles.selection.selectionToMask2DAdd.ItemPushedFcn = @(varargin)disp('Selection to Mask 2D Add pressed');
popupList2.add(obj.handles.selection.selectionToMask2DAdd);
% % Selection to Mask -> Shown slice (2D) -> Remove
obj.handles.selection.selectionToMask2DRemove =  matlab.ui.internal.toolstrip.ListItem('Remove', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'remove_24px')));
obj.handles.selection.selectionToMask2DRemove.ItemPushedFcn = @(varargin)disp('Selection to Mask 2D Remove pressed');
popupList2.add(obj.handles.selection.selectionToMask2DRemove);
% % Selection to Mask -> Shown slice (2D) -> Replace
obj.handles.selection.selectionToMask2DReplace =  matlab.ui.internal.toolstrip.ListItem('Replace', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'replace_24px')));
obj.handles.selection.selectionToMask2DReplace.ItemPushedFcn = @(varargin)disp('Selection to Mask 2D Replace pressed');
popupList2.add(obj.handles.selection.selectionToMask2DReplace);

obj.handles.selection.selection2mask2D.Popup = popupList2;
popupList.add(obj.handles.selection.selection2mask2D);

% ------------- Selection->Mask -> Current stack (3D) -------------
obj.handles.selection.selection2mask3D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Current stack (3D)', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dataset3d_24px')));

popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Selection to Mask -> Current stack (3D) -> Add
obj.handles.selection.selectionToMask3DAdd =  matlab.ui.internal.toolstrip.ListItem('Add', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'add_24px')));
obj.handles.selection.selectionToMask3DAdd.ItemPushedFcn = @(varargin)disp('Selection to Mask 3D Add pressed');
popupList2.add(obj.handles.selection.selectionToMask3DAdd);
% % Selection to Mask -> Current stack (3D) -> Remove
obj.handles.selection.selectionToMask3DRemove =  matlab.ui.internal.toolstrip.ListItem('Remove', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'remove_24px')));
obj.handles.selection.selectionToMask3DRemove.ItemPushedFcn = @(varargin)disp('Selection to Mask 3D Remove pressed');
popupList2.add(obj.handles.selection.selectionToMask3DRemove);
% % Selection to Mask -> Current stack (3D) -> Replace
obj.handles.selection.selectionToMask3DReplace =  matlab.ui.internal.toolstrip.ListItem('Replace', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'replace_24px')));
obj.handles.selection.selectionToMask3DReplace.ItemPushedFcn = @(varargin)disp('Selection to Mask 3D Replace pressed');
popupList2.add(obj.handles.selection.selectionToMask3DReplace);

obj.handles.selection.selection2mask3D.Popup = popupList2;
popupList.add(obj.handles.selection.selection2mask3D);

% ------------- Selection->Mask -> Complete volume (4D) -------------
obj.handles.selection.selection2mask4D =  matlab.ui.internal.toolstrip.ListItemWithPopup('Complete volume (4D)', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dataset4d_24px')));

popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Selection to Mask -> Complete volume (4D) -> Add
obj.handles.selection.selectionToMask4DAdd =  matlab.ui.internal.toolstrip.ListItem('Add', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'add_24px')));
obj.handles.selection.selectionToMask4DAdd.ItemPushedFcn = @(varargin)disp('Selection to Mask 3D Add pressed');
popupList2.add(obj.handles.selection.selectionToMask4DAdd);
% % Selection to Mask -> Complete volume (4D) -> Remove
obj.handles.selection.selectionToMask4DRemove =  matlab.ui.internal.toolstrip.ListItem('Remove', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'remove_24px')));
obj.handles.selection.selectionToMask4DRemove.ItemPushedFcn = @(varargin)disp('Selection to Mask 3D Remove pressed');
popupList2.add(obj.handles.selection.selectionToMask4DRemove);
% % Selection to Mask -> Complete volume (4D) -> Replace
obj.handles.selection.selectionToMask4DReplace =  matlab.ui.internal.toolstrip.ListItem('Replace', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'replace_24px')));
obj.handles.selection.selectionToMask4DReplace.ItemPushedFcn = @(varargin)disp('Selection to Mask 3D Replace pressed');
popupList2.add(obj.handles.selection.selectionToMask4DReplace);

obj.handles.selection.selection2mask4D.Popup = popupList2;
popupList.add(obj.handles.selection.selection2mask4D);

obj.handles.selection.selectionToMask.Popup = popupList;
column.add(obj.handles.selection.selectionToMask);

%% ------------- Selection to buffer -------------
column = section.addColumn();

%% -------------- Selection to buffer --------------
obj.handles.selection.toBuffer =  matlab.ui.internal.toolstrip.DropDownButton('Selection to buffer', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_to_buffer_24px')));
obj.handles.selection.toBuffer.Description = "Copy selection to buffer";

popupList = matlab.ui.internal.toolstrip.PopupList();
obj.handles.selection.copy =  matlab.ui.internal.toolstrip.ListItem( 'Copy (Ctrl+C)', matlab.ui.internal.toolstrip.Icon.COPY_24); 
obj.handles.selection.copy.ItemPushedFcn = @(varargin)disp('Copy (Ctrl+C) pressed');
popupList.add(obj.handles.selection.copy);
obj.handles.selection.paste =  matlab.ui.internal.toolstrip.ListItem( 'Paste (Ctrl+V)', matlab.ui.internal.toolstrip.Icon.PASTE_24); 
obj.handles.selection.paste.ItemPushedFcn = @(varargin)disp('Paste (Ctrl+V) pressed');
popupList.add(obj.handles.selection.paste);
obj.handles.selection.pasteAll =  matlab.ui.internal.toolstrip.ListItem( 'Paste to all slices (Ctrl+Shift+V)',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_pasteAll_24px')));
obj.handles.selection.pasteAll.ItemPushedFcn = @(varargin)disp('Paste to all slices (Ctrl+Shift+V) pressed');
popupList.add(obj.handles.selection.pasteAll);
obj.handles.selection.clear =  matlab.ui.internal.toolstrip.ListItem( 'Clear', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_clear_24px')));
obj.handles.selection.clear.ItemPushedFcn = @(varargin)disp('Clear pressed');
popupList.add(obj.handles.selection.clear);

obj.handles.selection.toBuffer.Popup = popupList;
column.add(obj.handles.selection.toBuffer);


%% ============= Make "Tools" section =============
section = obj.handles.toolbar.selection.addSection("Tools");

column = section.addColumn();
%% -------------- Morphological 2D/3D operations --------------
obj.handles.selection.morphOps =  matlab.ui.internal.toolstrip.DropDownButton(sprintf('Morphological\n2D/3D operations'), matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_morphops_24px')));
obj.handles.selection.morphOps.Description = "Copy selection to buffer";

popupList = matlab.ui.internal.toolstrip.PopupList();
% Branch points
obj.handles.selection.branch =  matlab.ui.internal.toolstrip.ListItem('Branch points', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_branch_24px')));
obj.handles.selection.branch.ItemPushedFcn = @(varargin)disp('Branch points pressed');
popupList.add(obj.handles.selection.branch);
% Diagonal fill
obj.handles.selection.diag =  matlab.ui.internal.toolstrip.ListItem('Diagonal fill', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_diag_24px')));
obj.handles.selection.diag.ItemPushedFcn = @(varargin)disp('Diagonal fill pressed');
popupList.add(obj.handles.selection.diag);
% Endpoints
obj.handles.selection.endpoints =  matlab.ui.internal.toolstrip.ListItem('Endpoints', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_endpoints_24px')));
obj.handles.selection.endpoints.ItemPushedFcn = @(varargin)disp('Endpoints pressed');
popupList.add(obj.handles.selection.endpoints);
% Skeleton
obj.handles.selection.skeleton =  matlab.ui.internal.toolstrip.ListItem('Skeleton', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_skeleton_24px')));
obj.handles.selection.skeleton.ItemPushedFcn = @(varargin)disp('Skeleton pressed');
popupList.add(obj.handles.selection.skeleton);
% Spur
obj.handles.selection.spur =  matlab.ui.internal.toolstrip.ListItem('Spur', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_spur_24px')));
obj.handles.selection.spur.ItemPushedFcn = @(varargin)disp('Spur pressed');
popupList.add(obj.handles.selection.spur);
% Thin
obj.handles.selection.thin =  matlab.ui.internal.toolstrip.ListItem('Thin', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_thin_24px')));
obj.handles.selection.thin.ItemPushedFcn = @(varargin)disp('Thin pressed');
popupList.add(obj.handles.selection.thin);
% Ultimate erosion
obj.handles.selection.ultErosion =  matlab.ui.internal.toolstrip.ListItem('Ultimate erosion', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_ulterode_24px')));
obj.handles.selection.ultErosion.ItemPushedFcn = @(varargin)disp('Ultimate erosion pressed'); 
popupList.add(obj.handles.selection.ultErosion);

obj.handles.selection.morphOps.Popup = popupList;
column.add(obj.handles.selection.morphOps);

%% -------- INVERT --------
column = section.addColumn();
obj.handles.selection.invert = matlab.ui.internal.toolstrip.SplitButton('Invert',matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_invert_24px')));
obj.handles.selection.invert.ButtonPushedFcn  = @(varargin)disp('Invert selection pressed');
obj.handles.selection.invert.Description = "Invert selection";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Invert selection -> Shown slice (2D)
obj.handles.selection.invert2D =  matlab.ui.internal.toolstrip.ListItem('Shown slice (2D)', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dataset2d_24px')));
obj.handles.selection.invert2D.ItemPushedFcn = @(varargin)disp('Shown slice (2D) pressed');
popupList.add(obj.handles.selection.invert2D);
% % Invert selection -> Current Stack (3D)
obj.handles.selection.invert3D =  matlab.ui.internal.toolstrip.ListItem('Current stack (3D)', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dataset3d_24px')));
obj.handles.selection.invert3D.ItemPushedFcn = @(varargin)disp('Current stack (3D) pressed');
popupList.add(obj.handles.selection.invert3D);
% % Invert selection -> Complete volume (4D)
obj.handles.selection.invert4D =  matlab.ui.internal.toolstrip.ListItem('Complete volume (4D)', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'dataset4d_24px')));
obj.handles.selection.invert4D.ItemPushedFcn = @(varargin)disp('Complete volume (4D) pressed');
popupList.add(obj.handles.selection.invert4D);

% add the popup list to the INVERT button
obj.handles.selection.invert.Popup = popupList;
column.add(obj.handles.selection.invert);

% ------------- Expand to mask border -------------
column = section.addColumn();
obj.handles.selection.expandToMask = matlab.ui.internal.toolstrip.Button(sprintf('Expand to\nmask border'),  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_expand_24px')));
obj.handles.selection.expandToMask.Description = 'Expand to mask border';
obj.handles.selection.expandToMask.ButtonPushedFcn = @(varargin)disp('Expand to mask border pressed');
column.add(obj.handles.selection.expandToMask);

% ------------- Interpolate as Shape (I) -------------
column = section.addColumn();
obj.handles.selection.interpolate = matlab.ui.internal.toolstrip.ToggleButton(sprintf('Interpolate as\nshape'),  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_shape_24px')));
obj.handles.selection.interpolate.Description = 'Interpolate the selected areas';
obj.handles.selection.interpolate. ValueChangedFcn = @(varargin)disp('Interpolate pressed');
column.add(obj.handles.selection.interpolate);

% ------------- Replace selected areas in the image -------------
column = section.addColumn();
obj.handles.selection.replaceImage = matlab.ui.internal.toolstrip.Button(sprintf('Replace\nselected areas'),  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_replace_24px')));
obj.handles.selection.replaceImage.Description = 'Replace selected areas in the image';
obj.handles.selection.replaceImage.ButtonPushedFcn = @(varargin)disp('Replace selected areas in the image pressed');
column.add(obj.handles.selection.replaceImage);

% ------------- Smooth selection -------------
column = section.addColumn();
obj.handles.selection.smooth = matlab.ui.internal.toolstrip.Button(sprintf('Smooth\nselection'),  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'selection_smooth_24px')));
obj.handles.selection.smooth.Description = 'Smooth selection';
obj.handles.selection.smooth.ButtonPushedFcn = @(varargin)disp('Smooth selection pressed');
column.add(obj.handles.selection.smooth);

%% Add tab to the tab group
obj.handles.toolbar.global.add(obj.handles.toolbar.selection);

end