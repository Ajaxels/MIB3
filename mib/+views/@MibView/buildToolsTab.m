function buildToolsTab(obj)
% function buildToolsTab(obj)
% build the Tools tab group (obj.handles.toolbar.tools)
% and add it to obj.handles.toolbar.global 
arguments (Input)
    obj views.MibView
end
%% Make the tab
obj.handles.toolbar.tools = matlab.ui.internal.toolstrip.Tab("Tools");
obj.handles.toolbar.tools.Tag = 'toolbarTools';

%% ============= Make "Segmentation" section =============
section = obj.handles.toolbar.tools.addSection("Segmentation");

% ------------- Deep learning segmentation -------------
column = section.addColumn();
obj.handles.tools.deepmib = matlab.ui.internal.toolstrip.Button(sprintf('Deep learning\nsegmentation'),  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/deepMIB_24px.png')));
obj.handles.tools.deepmib.Description = 'DeepMIB: deep learning segmentation';
obj.handles.tools.deepmib.ButtonPushedFcn = @(varargin)disp('DeepMIB pressed');
column.add(obj.handles.tools.deepmib);

%% -------------- Classifiers --------------
column = section.addColumn();
obj.handles.tools.classifiers =  matlab.ui.internal.toolstrip.DropDownButton('Classifiers', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/classifiers_24px.png')));
obj.handles.tools.classifiers.Description = "Pixel classifiers";

popupList = matlab.ui.internal.toolstrip.PopupList();
% Membrane detector
obj.handles.tools.membrane =  matlab.ui.internal.toolstrip.ListItem( 'Membrane detector', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/classification_membrane_24px.png'))); 
obj.handles.tools.membrane.ItemPushedFcn = @(varargin)disp('Membrane detector pressed');
popupList.add(obj.handles.tools.membrane);
% Supervoxels classifier
obj.handles.tools.supervoxels =  matlab.ui.internal.toolstrip.ListItem( 'Supervoxels classifier', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/classification_super_24px.png'))); 
obj.handles.tools.supervoxels.ItemPushedFcn = @(varargin)disp('Supervoxels classifier pressed');
popupList.add(obj.handles.tools.supervoxels);

obj.handles.tools.classifiers.Popup = popupList;
column.add(obj.handles.tools.classifiers);

%% -------------- Semi-automatic segmentation --------------
column = section.addColumn();
obj.handles.tools.semiauto =  matlab.ui.internal.toolstrip.DropDownButton(sprintf('Semi-automatic\nsegmentation'), matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/semiauto_24px.png')));
obj.handles.tools.semiauto.Description = "Semi-automatic segmentation";

popupList = matlab.ui.internal.toolstrip.PopupList();
% Global thresholding
obj.handles.tools.globalthres =  matlab.ui.internal.toolstrip.ListItem(sprintf('Global\nthresholding'), matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/global_tresholding_24px.png')));
obj.handles.tools.globalthres.ItemPushedFcn = @(varargin)disp('Global thresholding pressed');
popupList.add(obj.handles.tools.globalthres);
% Graphcut
obj.handles.tools.graphcut =  matlab.ui.internal.toolstrip.ListItem('Graphcut', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/graphcut_24px.png'))); 
obj.handles.tools.graphcut.ItemPushedFcn = @(varargin)disp('Graphcut pressed');
popupList.add(obj.handles.tools.graphcut);
% Watershed
obj.handles.tools.watershed =  matlab.ui.internal.toolstrip.ListItem('Watershed', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/watershed_24px.png'))); 
obj.handles.tools.watershed.ItemPushedFcn = @(varargin)disp('Watershed pressed');
popupList.add(obj.handles.tools.watershed);

obj.handles.tools.semiauto.Popup = popupList;
column.add(obj.handles.tools.semiauto);

%% ============= Make "Tools" section =============
section = obj.handles.toolbar.tools.addSection("Tools");
% Measure length
column = section.addColumn();
obj.handles.tools.measure =  matlab.ui.internal.toolstrip.SplitButton(sprintf('Measure\nlength'), matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/measure_24px.png')));
obj.handles.tools.measure.ButtonPushedFcn  = @(varargin)disp('Measure length pressed');
obj.handles.tools.measure.Description = "Start Measure tool for interactive measurements";

popupList = matlab.ui.internal.toolstrip.PopupList();
% Measure tool
obj.handles.tools.measureTool =  matlab.ui.internal.toolstrip.ListItem('Measure tool',  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/measure_24px.png')));
obj.handles.tools.measureTool.ItemPushedFcn = @(varargin)disp('Measure tool pressed');
popupList.add(obj.handles.tools.measureTool);
% Line measure
obj.handles.tools.measureLine =  matlab.ui.internal.toolstrip.ListItem('Line measure', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/profileLine_24px.png')));
obj.handles.tools.measureLine.ItemPushedFcn = @(varargin)disp('Line measure pressed');
popupList.add(obj.handles.tools.measureLine);
% Freehand measure
obj.handles.tools.measureFreehand =  matlab.ui.internal.toolstrip.ListItem('Free hand measure',  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/profileArbitrary_24px.png')));
obj.handles.tools.measureFreehand.ItemPushedFcn = @(varargin)disp('Free hand measure pressed');
popupList.add(obj.handles.tools.measureFreehand);

obj.handles.tools.measure.Popup = popupList;
column.add(obj.handles.tools.measure);

% ----------------- Object separator -----------------
column = section.addColumn();
obj.handles.tools.objects = matlab.ui.internal.toolstrip.Button(sprintf('Object\nseparation'),  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/object_separation_24px.png')));
obj.handles.tools.objects.Description = 'Start a tool for object separation';
obj.handles.tools.objects.ButtonPushedFcn = @(varargin)disp('Object separation pressed');
column.add(obj.handles.tools.objects);

% ----------------- Stereology -----------------
column = section.addColumn();
obj.handles.tools.stereology = matlab.ui.internal.toolstrip.Button('Stereology',  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/stereology_24px.png')));
obj.handles.tools.stereology.Description = 'Start the stereology tool';
obj.handles.tools.stereology.ButtonPushedFcn = @(varargin)disp('Stereology pressed');
column.add(obj.handles.tools.stereology);

% ----------------- Wound healing assey -----------------
column = section.addColumn();
obj.handles.tools.wound = matlab.ui.internal.toolstrip.Button(sprintf('Wound healing\nassey'),  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/wound_healing_24px.png')));
obj.handles.tools.wound.Description = 'Perform wound healing assey';
obj.handles.tools.wound.ButtonPushedFcn = @(varargin)disp('Wound healing assey pressed');
column.add(obj.handles.tools.wound);

%% Add tab to the tab group
obj.handles.toolbar.global.add(obj.handles.toolbar.tools);

end