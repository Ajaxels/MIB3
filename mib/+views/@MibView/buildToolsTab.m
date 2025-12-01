function buildToolsTab(obj, lazyInit)
% function buildToolsTab(obj, lazyInit)
% build the Tools tab group (obj.handles.toolbar.tools)
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
    obj.handles.toolbar.tools = matlab.ui.internal.toolstrip.Tab("Tools");
    obj.handles.toolbar.tools.Tag = 'toolbarTools';

    % Add tab to the tab group
    obj.handles.toolbar.global.add(obj.handles.toolbar.tools);
    return
end

%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton

%% ============= Make "Segmentation" section =============
section = obj.handles.toolbar.tools.addSection("Segmentation");

% ------------- Deep learning segmentation -------------
column = section.addColumn();
obj.handles.tools.deepmib = Button(sprintf('Deep learning\nsegmentation'),  Icon(fullfile(iconPath, 'deepMIB_24px.png')));
obj.handles.tools.deepmib.Description = 'DeepMIB: deep learning segmentation';
obj.handles.tools.deepmib.ButtonPushedFcn = @(varargin)disp('DeepMIB pressed');
column.add(obj.handles.tools.deepmib);

%% -------------- Classifiers --------------
column = section.addColumn();
obj.handles.tools.classifiers =  DropDownButton('Classifiers', Icon(fullfile(iconPath, 'classifiers_24px.png')));
obj.handles.tools.classifiers.Description = "Pixel classifiers";

popupList = PopupList();
% Membrane detector
obj.handles.tools.membrane =  ListItem( 'Membrane detector', Icon(fullfile(iconPath, 'classification_membrane_24px.png'))); 
obj.handles.tools.membrane.ItemPushedFcn = @(varargin)disp('Membrane detector pressed');
popupList.add(obj.handles.tools.membrane);
% Supervoxels classifier
obj.handles.tools.supervoxels =  ListItem( 'Supervoxels classifier', Icon(fullfile(iconPath, 'classification_super_24px.png'))); 
obj.handles.tools.supervoxels.ItemPushedFcn = @(varargin)disp('Supervoxels classifier pressed');
popupList.add(obj.handles.tools.supervoxels);

obj.handles.tools.classifiers.Popup = popupList;
column.add(obj.handles.tools.classifiers);

%% -------------- Semi-automatic segmentation --------------
column = section.addColumn();
obj.handles.tools.semiauto =  DropDownButton(sprintf('Semi-automatic\nsegmentation'), Icon(fullfile(iconPath, 'semiauto_24px.png')));
obj.handles.tools.semiauto.Description = "Semi-automatic segmentation";

popupList = PopupList();
% Global thresholding
obj.handles.tools.globalthres =  ListItem(sprintf('Global\nthresholding'), Icon(fullfile(iconPath, 'global_tresholding_24px.png')));
obj.handles.tools.globalthres.ItemPushedFcn = @(varargin)disp('Global thresholding pressed');
popupList.add(obj.handles.tools.globalthres);
% Graphcut
obj.handles.tools.graphcut =  ListItem('Graphcut', Icon(fullfile(iconPath, 'graphcut_24px.png'))); 
obj.handles.tools.graphcut.ItemPushedFcn = @(varargin)disp('Graphcut pressed');
popupList.add(obj.handles.tools.graphcut);
% Watershed
obj.handles.tools.watershed =  ListItem('Watershed', Icon(fullfile(iconPath, 'watershed_24px.png'))); 
obj.handles.tools.watershed.ItemPushedFcn = @(varargin)disp('Watershed pressed');
popupList.add(obj.handles.tools.watershed);

obj.handles.tools.semiauto.Popup = popupList;
column.add(obj.handles.tools.semiauto);

%% ============= Make "Tools" section =============
section = obj.handles.toolbar.tools.addSection("Tools");
% Measure length
column = section.addColumn();
obj.handles.tools.measure =  matlab.ui.internal.toolstrip.SplitButton(sprintf('Measure\nlength'), Icon(fullfile(iconPath, 'measure_24px.png')));
obj.handles.tools.measure.ButtonPushedFcn  = @(varargin)disp('Measure length pressed');
obj.handles.tools.measure.Description = "Start Measure tool for interactive measurements";

popupList = PopupList();
% Measure tool
obj.handles.tools.measureTool =  ListItem('Measure tool',  Icon(fullfile(iconPath, 'measure_24px.png')));
obj.handles.tools.measureTool.ItemPushedFcn = @(varargin)disp('Measure tool pressed');
popupList.add(obj.handles.tools.measureTool);
% Line measure
obj.handles.tools.measureLine =  ListItem('Line measure', Icon(fullfile(iconPath, 'profileLine_24px.png')));
obj.handles.tools.measureLine.ItemPushedFcn = @(varargin)disp('Line measure pressed');
popupList.add(obj.handles.tools.measureLine);
% Freehand measure
obj.handles.tools.measureFreehand =  ListItem('Free hand measure',  Icon(fullfile(iconPath, 'profileArbitrary_24px.png')));
obj.handles.tools.measureFreehand.ItemPushedFcn = @(varargin)disp('Free hand measure pressed');
popupList.add(obj.handles.tools.measureFreehand);

obj.handles.tools.measure.Popup = popupList;
column.add(obj.handles.tools.measure);

% ----------------- Object separator -----------------
column = section.addColumn();
obj.handles.tools.objects = Button(sprintf('Object\nseparation'),  Icon(fullfile(iconPath, 'object_separation_24px.png')));
obj.handles.tools.objects.Description = 'Start a tool for object separation';
obj.handles.tools.objects.ButtonPushedFcn = @(varargin)disp('Object separation pressed');
column.add(obj.handles.tools.objects);

% ----------------- Stereology -----------------
column = section.addColumn();
obj.handles.tools.stereology = Button('Stereology',  Icon(fullfile(iconPath, 'stereology_24px.png')));
obj.handles.tools.stereology.Description = 'Start the stereology tool';
obj.handles.tools.stereology.ButtonPushedFcn = @(varargin)disp('Stereology pressed');
column.add(obj.handles.tools.stereology);

% ----------------- Wound healing assey -----------------
column = section.addColumn();
obj.handles.tools.wound = Button(sprintf('Wound healing\nassey'),  Icon(fullfile(iconPath, 'wound_healing_24px.png')));
obj.handles.tools.wound.Description = 'Perform wound healing assey';
obj.handles.tools.wound.ButtonPushedFcn = @(varargin)disp('Wound healing assey pressed');
column.add(obj.handles.tools.wound);

end