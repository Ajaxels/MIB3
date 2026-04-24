function widgetHandles = addRibbonModel(obj, lazyInit)
% function widgetHandles = addRibbonModel(obj, lazyInit)
% build the Model tab group (obj.handles.ribbon.model)
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
    obj.handles.ribbon.model = matlab.ui.internal.toolstrip.Tab("Model");
    obj.handles.ribbon.model.Tag = 'toolbarModel';
    % Add tab to the tab group
    obj.handles.ribbon.global.add(obj.handles.ribbon.model);
    widgetHandles = [];
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
import matlab.ui.internal.toolstrip.PopupListSeparator
import matlab.ui.internal.toolstrip.PopupListHeader

%% ============= Make "Model tools" section =============
section = obj.handles.ribbon.model.addSection("Convert");
%% Convert type
column = section.addColumn();
widgetHandles.convert =  DropDownButton(sprintf('Convert\ntype'), Icon(fullfile(iconPath, 'model_convert_24px.png')));
widgetHandles.convert.Description = "Convert the model type";

popupList = PopupList();
header1 = PopupListHeader('Convert the model type');
popupList.add(header1);
% % Convert to 63 materials
widgetHandles.mat63 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('63 materials', true);
popupList.add(widgetHandles.mat63);
% % Convert to 255 materials
widgetHandles.mat255 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('255 materials', false);
popupList.add(widgetHandles.mat255);
% % Convert to 65535 materials
widgetHandles.mat65535 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('65535 materials', false);
popupList.add(widgetHandles.mat65535);
% % Convert to 4294967295 materials
widgetHandles.mat4294967295 =  matlab.ui.internal.toolstrip.ListItemWithCheckBox('4294967295 materials', false);
popupList.add(widgetHandles.mat4294967295);
% separator
separator = PopupListSeparator();
popupList.add(separator);
% % Indexed objects
widgetHandles.indexed = matlab.ui.internal.toolstrip.ListItemWithPopup('Indexed objects');

popupList2 = PopupList();
% % Indexed objects -> 2D objects conn4
widgetHandles.indexed2dconn4 =  ListItem('2D objects conn4');
popupList2.add(widgetHandles.indexed2dconn4);
% % Indexed objects -> 2D objects conn8
widgetHandles.indexed2dconn8 =  ListItem('2D objects conn8');
popupList2.add(widgetHandles.indexed2dconn8);
% % Indexed objects -> 3D objects conn4
widgetHandles.indexed3dconn4 =  ListItem('3D objects conn4');
popupList2.add(widgetHandles.indexed3dconn4);
% % Indexed objects -> 3D objects conn8
widgetHandles.indexed3dconn8 =  ListItem('3D objects conn8');
popupList2.add(widgetHandles.indexed3dconn8);
widgetHandles.indexed.Popup = popupList2;
popupList.add(widgetHandles.indexed);

% add the popup list to the Mode button
widgetHandles.convert.Popup = popupList;
column.add(widgetHandles.convert);

%% ============= Make "Model Import" section =============
section = obj.handles.ribbon.model.addSection("Import");
%% New model
column = section.addColumn();
widgetHandles.new = Button(sprintf('New\nmodel'),  Icon(fullfile(iconPath, 'model_new_24px.png')));
widgetHandles.new.Description = 'Start a new model';
column.add(widgetHandles.new);
%% Load model
column = section.addColumn();
widgetHandles.load = Button(sprintf('Load\nmodel'), Icon(fullfile(iconPath, 'model_load_24px.png')));
widgetHandles.load.Description = 'Load model';
column.add(widgetHandles.load);

% Import model
column = section.addColumn();
widgetHandles.import =  Button(sprintf('Import\nmodel'), Icon(fullfile(iconPath, 'model_import_24px.png')));
widgetHandles.import.Description = "Import model to MIB from MATLAB";

column.add(widgetHandles.import);

%% ============= Make "Model export" section =============
section = obj.handles.ribbon.model.addSection("Export");
column = section.addColumn();
widgetHandles.export =  SplitButton('Export', Icon(fullfile(iconPath, 'model_export_24px.png')));
widgetHandles.export.Description = "Export model to MIB";

% make a popup list for the dropdown button
popupList = PopupList();
% add header
header1 = matlab.ui.internal.toolstrip.PopupListHeader('Export model to');
popupList.add(header1);
% export to MATLAB
widgetHandles.exportToMatlab = ListItem('Export model to MATLAB', Icon(fullfile(iconPath, 'export_model_matlab_24px.png')));
popupList.add(widgetHandles.exportToMatlab);
widgetHandles.exportToMIB =  ListItem( 'Export model to another MIB dataset',  Icon(fullfile(iconPath, 'mib_icon_24px.png'))); 
popupList.add(widgetHandles.exportToMIB);
% export to Imaris
widgetHandles.exportToImaris = ListItem('Export model to Imaris as volume', Icon(fullfile(iconPath, 'export_model_imaris_24px.png')));
popupList.add(widgetHandles.exportToImaris);

% add the popup list to the SplitButton button
widgetHandles.export.Popup = popupList;

% add the dropdown button to the column
column.add(widgetHandles.export);
%% Save model
column = section.addColumn(); 
widgetHandles.save = Button(sprintf('Save\nmodel'),  Icon(fullfile(iconPath, 'model_save_24px.png')));
widgetHandles.save.Description = 'Save the model to file';
column.add(widgetHandles.save);
%% Save model as
column = section.addColumn(); 
widgetHandles.saveAs = Button(sprintf('Save\nmodel as...'),  Icon(fullfile(iconPath, 'model_save_as_24px.png')));
widgetHandles.saveAs.Description = 'Save as the model  to file';
column.add(widgetHandles.saveAs);


%% ============= Make "Model tools" section =============
section = obj.handles.ribbon.model.addSection("Model tools");

%% Model materials
column = section.addColumn();
widgetHandles.materials =  DropDownButton('Materials', Icon(fullfile(iconPath, 'model_materials_24px.png')));
widgetHandles.materials.Description = "Model materials operations";

popupList = PopupList();
header1 = PopupListHeader('Operations with materials of the model');
popupList.add(header1);
% % Rename material
widgetHandles.matRename =  ListItem('Rename material', Icon(fullfile(iconPath, 'model_materials_24px.png')));
widgetHandles.matRename.Tag = 'matRename';
popupList.add(widgetHandles.matRename);

% separator
separator = PopupListSeparator();
popupList.add(separator);

% % Add material
widgetHandles.matAdd =  ListItem('Add material', Icon(fullfile(iconPath, 'model_materials_add_24px.png')));
popupList.add(widgetHandles.matAdd);
% % Insert material
widgetHandles.matInsert =  ListItem('Insert material', Icon(fullfile(iconPath, 'model_materials_insert_24px.png')));
popupList.add(widgetHandles.matInsert);
% % Swap materials
widgetHandles.matSwap =  ListItem('Swap materials', Icon(fullfile(iconPath, 'model_materials_swap_24px.png')));
popupList.add(widgetHandles.matSwap);
% % Reorder materials
widgetHandles.matReorder =  ListItem('Reorder materials', Icon(fullfile(iconPath, 'model_materials_reorder_24px.png')));
popupList.add(widgetHandles.matReorder);

% separator
separator = PopupListSeparator();
popupList.add(separator);

% % Export material
widgetHandles.matExport =  ListItem('Export material', Icon(fullfile(iconPath, 'model_materials_export_24px.png')));
popupList.add(widgetHandles.matExport);
% % Save material to file
widgetHandles.matSave =  ListItem('Save material to file', Icon(fullfile(iconPath, 'model_materials_save_24px.png')));
popupList.add(widgetHandles.matSave);

% separator
separator = PopupListSeparator();
popupList.add(separator);

% % Remove materials
widgetHandles.matRemove =  ListItem('Remove materials', Icon(fullfile(iconPath, 'model_materials_remove_24px.png')));
popupList.add(widgetHandles.matRemove);

% add the popup list to the SplitButton button
widgetHandles.materials.Popup = popupList;

% add the dropdown button to the column
column.add(widgetHandles.materials);

%% Annotations
column = section.addColumn();
widgetHandles.annotations =  SplitButton(sprintf('List of\nannotations'), Icon(fullfile(iconPath, 'annotation_list_24px.png')));
widgetHandles.annotations.Description = "Open list of annotations";

popupList = PopupList();
header1 = PopupListHeader('Operations with annotations');
popupList.add(header1);
% % List of annotations
widgetHandles.annotationsList =  ListItem('List of annotations', Icon(fullfile(iconPath, 'annotation_list_24px.png')));
popupList.add(widgetHandles.annotationsList);
% % Export to Imaris as Spots
widgetHandles.annotationsImaris =  ListItem('Export to Imaris as Spots', Icon(fullfile(iconPath, 'annotation_imaris_24px.png')));
popupList.add(widgetHandles.annotationsImaris);
% separator
separator = PopupListSeparator();
popupList.add(separator);
% % Remove annotations
widgetHandles.annotationsRemove =  ListItem('Remove all annotations', Icon(fullfile(iconPath, 'annotation_remove_24px.png')));
popupList.add(widgetHandles.annotationsRemove);

% add the popup list to the SplitButton button
widgetHandles.annotations.Popup = popupList;

% add the dropdown button to the column
column.add(widgetHandles.annotations);

%% Model render
column = section.addColumn();
widgetHandles.render =  SplitButton('Render', Icon(fullfile(iconPath, 'model_render_24px.png')));
widgetHandles.render.Description = "Render the model";

popupList = PopupList();
header1 = PopupListHeader('3D rendering of models');
popupList.add(header1);

% % MIB rendering
widgetHandles.renderMIB =  ListItem('MIB rendering', Icon(fullfile(iconPath, 'mib_icon_24px.png')));
popupList.add(widgetHandles.renderMIB);
% % MATLAB isosurface
widgetHandles.renderMatlab =  ListItem('MATLAB isosurface', Icon.MATLAB_24);
popupList.add(widgetHandles.renderMatlab);
% % MATLAB isosurface+Imaris
widgetHandles.renderMatlabImaris =  ListItem('MATLAB isosurface and export to Imaris', Icon(fullfile(iconPath, 'model_render_matImaris_24px.png')));
popupList.add(widgetHandles.renderMatlabImaris);
% % MATLAB volume viewer
widgetHandles.renderMatlabVolView =  ListItem('MATLAB volume viewer', Icon(fullfile(iconPath, 'model_render_matVolView_24px.png')));
popupList.add(widgetHandles.renderMatlabVolView);
% % Fiji volume viewer
widgetHandles.renderFiji =  ListItem('Fiji volume viewer', Icon(fullfile(iconPath, 'fiji_24px.png')));
popupList.add(widgetHandles.renderFiji);
% % Imaris surface
widgetHandles.renderImaris =  ListItem('Imaris surface', Icon(fullfile(iconPath, 'imaris_24px.png')));
popupList.add(widgetHandles.renderImaris);

% add the popup list to the SplitButton button
widgetHandles.render.Popup = popupList;

% add the dropdown button to the column
column.add(widgetHandles.render);

%% ============= Make "Quantification" section =============
section = obj.handles.ribbon.model.addSection("Quantification");
%% Model quantification
column = section.addColumn(); 
% Model quantification
widgetHandles.quantification = Button('Quantify',  Icon(fullfile(iconPath, 'model_quantify_24px.png')));
widgetHandles.quantification.Description = 'Start model quantification tool';
column.add(widgetHandles.quantification);

obj.handles.ribbonModel = widgetHandles;

end