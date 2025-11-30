function buildModelTab(obj)
% function buildModelTab(obj)
% build the Model tab group (obj.handles.toolbar.model)
% and add it to obj.handles.toolbar.global 

arguments (Input)
    obj views.MibView
end

%%
obj.handles.toolbar.model = matlab.ui.internal.toolstrip.Tab("Model");
obj.handles.toolbar.model.Tag = 'toolbarModel';

%% ============= Make "Model tools" section =============
section = obj.handles.toolbar.model.addSection("Convert");
%% Convert type
column = section.addColumn();
obj.handles.model.convert =  matlab.ui.internal.toolstrip.DropDownButton(sprintf('Convert\ntype'), matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_convert_24px')));
obj.handles.model.convert.Description = "Convert the model type";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Convert to 63 materials
obj.handles.model.mat63 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('63 materials', true);
obj.handles.model.mat63.ValueChangedFcn = @(varargin)disp('63 materials pressed');
popupList.add(obj.handles.model.mat63);
% % Convert to 255 materials
obj.handles.model.mat255 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('255 materials', false);
obj.handles.model.mat255.ValueChangedFcn = @(varargin)disp('255 materials pressed');
popupList.add(obj.handles.model.mat255);
% % Convert to 65535 materials
obj.handles.model.mat65535 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('65535 materials', false);
obj.handles.model.mat65535.ValueChangedFcn = @(varargin)disp('65535 materials pressed');
popupList.add(obj.handles.model.mat65535);
% % Convert to 4294967295 materials
obj.handles.model.mat4294967295 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('4294967295 materials', false);
obj.handles.model.mat4294967295.ValueChangedFcn = @(varargin)disp('4294967295 materials pressed');
popupList.add(obj.handles.model.mat4294967295);
% % Indexed objects
obj.handles.model.indexed = matlab.ui.internal.toolstrip.ListItemWithPopup('Indexed objects');

popupList2 = matlab.ui.internal.toolstrip.PopupList();
% % Indexed objects -> 2D objects conn4
obj.handles.model.indexed2dconn4 =  matlab.ui.internal.toolstrip.ListItem('2D objects conn4');
obj.handles.model.indexed2dconn4.ItemPushedFcn = @(varargin)disp('2D objects conn4 pressed');
popupList2.add(obj.handles.model.indexed2dconn4);
% % Indexed objects -> 2D objects conn8
obj.handles.model.indexed2dconn8 =  matlab.ui.internal.toolstrip.ListItem('2D objects conn8');
obj.handles.model.indexed2dconn48.ItemPushedFcn = @(varargin)disp('2D objects conn8 pressed');
popupList2.add(obj.handles.model.indexed2dconn8);
% % Indexed objects -> 3D objects conn4
obj.handles.model.indexed3dconn4 =  matlab.ui.internal.toolstrip.ListItem('3D objects conn4');
obj.handles.model.indexed3dconn4.ItemPushedFcn = @(varargin)disp('3D objects conn4 pressed');
popupList2.add(obj.handles.model.indexed3dconn4);
% % Indexed objects -> 3D objects conn8
obj.handles.model.indexed3dconn8 =  matlab.ui.internal.toolstrip.ListItem('3D objects conn8');
obj.handles.model.indexed3dconn8.ItemPushedFcn = @(varargin)disp('3D objects conn8 pressed');
popupList2.add(obj.handles.model.indexed3dconn8);
obj.handles.model.indexed.Popup = popupList2;
popupList.add(obj.handles.model.indexed);

% add the popup list to the Mode button
obj.handles.model.convert.Popup = popupList;
column.add(obj.handles.model.convert);

%% ============= Make "Model Import" section =============
section = obj.handles.toolbar.model.addSection("Import");
%% New model
column = section.addColumn();
obj.handles.model.new = matlab.ui.internal.toolstrip.Button(sprintf('New\nmodel'),  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_new_24px')));
obj.handles.model.new.Description = 'Start a new model';
obj.handles.model.new.ButtonPushedFcn = @(varargin)disp('Start a new model pressed');
column.add(obj.handles.model.new);
%% Load model
column = section.addColumn();
obj.handles.model.load = matlab.ui.internal.toolstrip.Button(sprintf('Load\nmodel'), matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_load_24px')));
obj.handles.model.load.Description = 'Load model';
obj.handles.model.load.ButtonPushedFcn = @(varargin)disp('Load model pressed');
column.add(obj.handles.model.load);

% Import model
column = section.addColumn();
obj.handles.model.import =  matlab.ui.internal.toolstrip.Button(sprintf('Import\nmodel'), matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_import_24px')));
obj.handles.model.import.Description = "Import model to MIB from MATLAB";
obj.handles.model.import.ButtonPushedFcn  = @(varargin)disp('Import model pressed');

column.add(obj.handles.model.import);

%% ============= Make "Model export" section =============
section = obj.handles.toolbar.model.addSection("Export");
column = section.addColumn();
obj.handles.model.export =  matlab.ui.internal.toolstrip.SplitButton('Export', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_export_24px')));
obj.handles.model.export.Description = "Export model to MIB";
obj.handles.model.export.ButtonPushedFcn  = @(varargin)disp('Export model pressed');

% make a popup list for the dropdown button
popupList = matlab.ui.internal.toolstrip.PopupList();
% add header
header1 = matlab.ui.internal.toolstrip.PopupListHeader('Export model to');
popupList.add(header1);
% export to MATLAB
obj.handles.model.exportToMatlab = matlab.ui.internal.toolstrip.ListItem('Export model to MATLAB', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'export_model_matlab_24px')));
obj.handles.model.exportToMatlab.ItemPushedFcn  = @(varargin)disp('Export model to MATLAB pressed');
popupList.add(obj.handles.model.exportToMatlab);
% export to Imaris
obj.handles.model.exportToImaris = matlab.ui.internal.toolstrip.ListItem('Export model to Imaris as volume', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'export_model_imaris_24px')));
obj.handles.model.exportToImaris.ItemPushedFcn  = @(varargin)disp('Export model to Imaris pressed');
popupList.add(obj.handles.model.exportToImaris);

% add the popup list to the SplitButton button
obj.handles.model.export.Popup = popupList;

% add the dropdown button to the column
column.add(obj.handles.model.export);
%% Save model
column = section.addColumn(); 
obj.handles.model.save = matlab.ui.internal.toolstrip.Button(sprintf('Save\nmodel'),  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_save_24px')));
obj.handles.model.save.Description = 'Save the model to file';
obj.handles.model.save.ButtonPushedFcn = @(varargin)disp('Save the model to file pressed');
column.add(obj.handles.model.save);
%% Save model as
column = section.addColumn(); 
obj.handles.model.saveAs = matlab.ui.internal.toolstrip.Button(sprintf('Save\nmodel as...'),  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_save_as_24px')));
obj.handles.model.saveAs.Description = 'Save as the model  to file';
obj.handles.model.saveAs.ButtonPushedFcn = @(varargin)disp('Save as the model to file pressed');
column.add(obj.handles.model.saveAs);


%% ============= Make "Model tools" section =============
section = obj.handles.toolbar.model.addSection("Model tools");

%% Model materials
column = section.addColumn();
obj.handles.model.materials =  matlab.ui.internal.toolstrip.DropDownButton('Materials', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_materials_24px')));
obj.handles.model.materials.Description = "Model materials operations";

popupList = matlab.ui.internal.toolstrip.PopupList();
% % Rename material
obj.handles.model.matRename =  matlab.ui.internal.toolstrip.ListItem('Rename material', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_materials_24px')));
obj.handles.model.matRename.Tag = 'matRename';
obj.handles.model.matRename.ItemPushedFcn =  @(src, event)obj.controller.segmentationMaterials_Callback(src, event);
popupList.add(obj.handles.model.matRename);

% separator
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);

% % Add material
obj.handles.model.matAdd =  matlab.ui.internal.toolstrip.ListItem('Add material', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_materials_add_24px')));
obj.handles.model.matAdd.ItemPushedFcn =  @(src, event)obj.controller.segmentationMaterials_Callback(src, event);
popupList.add(obj.handles.model.matAdd);
% % Insert material
obj.handles.model.matInsert =  matlab.ui.internal.toolstrip.ListItem('Insert material', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_materials_insert_24px')));
obj.handles.model.matInsert.ItemPushedFcn = @(src, event)obj.controller.segmentationMaterials_Callback(src, event);
popupList.add(obj.handles.model.matInsert);
% % Swap materials
obj.handles.model.matSwap =  matlab.ui.internal.toolstrip.ListItem('Swap materials', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_materials_swap_24px')));
obj.handles.model.matSwap.ItemPushedFcn = @(src, event)obj.controller.segmentationMaterials_Callback(src, event);
popupList.add(obj.handles.model.matSwap);
% % Reorder materials
obj.handles.model.matReorder =  matlab.ui.internal.toolstrip.ListItem('Reorder materials', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_materials_reorder_24px')));
obj.handles.model.matReorder.ItemPushedFcn = @(src, event)obj.controller.segmentationMaterials_Callback(src, event);
popupList.add(obj.handles.model.matReorder);

% separator
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);

% % Export material
obj.handles.model.matExport =  matlab.ui.internal.toolstrip.ListItem('Export material', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_materials_export_24px')));
obj.handles.model.matExport.ItemPushedFcn = @(src, event)obj.controller.segmentationMaterials_Callback(src, event);
popupList.add(obj.handles.model.matExport);
% % Save material to file
obj.handles.model.matSave =  matlab.ui.internal.toolstrip.ListItem('Save material to file', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_materials_save_24px')));
obj.handles.model.matSave.ItemPushedFcn = @(src, event)obj.controller.segmentationMaterials_Callback(src, event);
popupList.add(obj.handles.model.matSave);

% separator
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);

% % Remove materials
obj.handles.model.matRemove =  matlab.ui.internal.toolstrip.ListItem('Remove materials', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_materials_remove_24px')));
obj.handles.model.matRemove.ItemPushedFcn = @(src, event)obj.controller.segmentationMaterials_Callback(src, event);
popupList.add(obj.handles.model.matRemove);

% add the popup list to the SplitButton button
obj.handles.model.materials.Popup = popupList;

% add the dropdown button to the column
column.add(obj.handles.model.materials);

%% Annotations
column = section.addColumn();
obj.handles.model.annotations =  matlab.ui.internal.toolstrip.SplitButton(sprintf('List of\nannotations'), matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'annotation_list_24px')));
obj.handles.model.annotations.Description = "Open list of annotations";
obj.handles.model.annotations.ButtonPushedFcn  = @(varargin)disp('List of annotations pressed');

popupList = matlab.ui.internal.toolstrip.PopupList();
% % List of annotations
obj.handles.model.annotationsList =  matlab.ui.internal.toolstrip.ListItem('List of annotations', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'annotation_list_24px')));
obj.handles.model.annotationsList.ItemPushedFcn = @(varargin)disp('List of annotations pressed');
popupList.add(obj.handles.model.annotationsList);
% % Export to Imaris as Spots
obj.handles.model.annotationsImaris =  matlab.ui.internal.toolstrip.ListItem('Export to Imaris as Spots', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'annotation_imaris_24px')));
obj.handles.model.annotationsImaris.ItemPushedFcn = @(varargin)disp('Export to Imaris as Spots pressed');
popupList.add(obj.handles.model.annotationsImaris);
% separator
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);
% % Remove annotations
obj.handles.model.annotationsRemove =  matlab.ui.internal.toolstrip.ListItem('Remove all annotations', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'annotation_remove_24px')));
obj.handles.model.annotationsRemove.ItemPushedFcn = @(varargin)disp('Remove all annotations pressed');
popupList.add(obj.handles.model.annotationsRemove);

% add the popup list to the SplitButton button
obj.handles.model.annotations.Popup = popupList;

% add the dropdown button to the column
column.add(obj.handles.model.annotations);

%% Model render
column = section.addColumn();
obj.handles.model.render =  matlab.ui.internal.toolstrip.SplitButton('Render', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_render_24px')));
obj.handles.model.render.Description = "Render the model";
obj.handles.model.render.ButtonPushedFcn = @(varargin)disp('Render the model pressed');

popupList = matlab.ui.internal.toolstrip.PopupList();
% % MIB rendering
obj.handles.model.renderMIB =  matlab.ui.internal.toolstrip.ListItem('MIB rendering', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'mib_icon_24px')));
obj.handles.model.renderMIB.ItemPushedFcn = @(varargin)disp('MIB rendering pressed');
popupList.add(obj.handles.model.renderMIB);
% % MATLAB isosurface
obj.handles.model.renderMatlab =  matlab.ui.internal.toolstrip.ListItem('MATLAB isosurface', matlab.ui.internal.toolstrip.Icon.MATLAB_24);
obj.handles.model.renderMatlab.ItemPushedFcn = @(varargin)disp('MATLAB isosurface pressed');
popupList.add(obj.handles.model.renderMatlab);
% % MATLAB isosurface+Imaris
obj.handles.model.renderMatlabImaris =  matlab.ui.internal.toolstrip.ListItem('MATLAB isosurface and export to Imaris', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_render_matImaris_24px')));
obj.handles.model.renderMatlabImaris.ItemPushedFcn = @(varargin)disp('MATLAB isosurface and export to Imaris pressed');
popupList.add(obj.handles.model.renderMatlabImaris);
% % MATLAB volume viewer
obj.handles.model.renderMatlabVolView =  matlab.ui.internal.toolstrip.ListItem('MATLAB volume viewer', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_render_matVolView_24px')));
obj.handles.model.renderMatlabVolView.ItemPushedFcn = @(varargin)disp('MATLAB volume viewer pressed');
popupList.add(obj.handles.model.renderMatlabVolView);
% % Fiji volume viewer
obj.handles.model.renderFiji =  matlab.ui.internal.toolstrip.ListItem('Fiji volume viewer', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'fiji_24px')));
obj.handles.model.renderFiji.ItemPushedFcn = @(varargin)disp('Fiji volume viewer pressed');
popupList.add(obj.handles.model.renderFiji);
% % Imaris surface
obj.handles.model.renderImaris =  matlab.ui.internal.toolstrip.ListItem('Imaris surface', matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'imaris_24px')));
obj.handles.model.renderImaris.ItemPushedFcn = @(varargin)disp('Imaris surface pressed');
popupList.add(obj.handles.model.renderImaris);

% add the popup list to the SplitButton button
obj.handles.model.render.Popup = popupList;

% add the dropdown button to the column
column.add(obj.handles.model.render);

%% ============= Make "Quantification" section =============
section = obj.handles.toolbar.model.addSection("Quantification");
%% Model quantification
column = section.addColumn(); 
% Model quantification
obj.handles.model.quantification = matlab.ui.internal.toolstrip.Button('Quantify',  matlab.ui.internal.toolstrip.Icon(core.MibIconCache.get('icons', 'model_quantify_24px')));
obj.handles.model.quantification.Description = 'Start model quantification tool';
obj.handles.model.quantification.ButtonPushedFcn = @(varargin)disp('Start model quantification pressed');
column.add(obj.handles.model.quantification);

%%
obj.handles.toolbar.global.add(obj.handles.toolbar.model);

end