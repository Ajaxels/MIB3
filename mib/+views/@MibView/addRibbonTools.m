function widgetHandles = addRibbonTools(obj, lazyInit)
% ADDRIBBONTOOLS - build the Tools tab group and add it to the global ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%      widgetHandles = obj.addRibbonTools()
%      widgetHandles = obj.addRibbonTools(lazyInit)
%
% Input Arguments:
%   - **lazyInit** *(optional)* — [logical] when ``true``, only a placeholder is
%     initialized; full rendering occurs on first tab activation via
%     ``MibController.globalTabGroup_SelectionCallback`` (default: ``false``)
%
% Output Arguments:
%   - **widgetHandles** — [struct] handles to the Tools ribbon section widgets
%

arguments (Input)
    obj views.MibView
    lazyInit logical = false
end

%% Lazy initialization
if lazyInit
    % lazy initialization, the real initialization is in controllers.MibController.globalTabGroup_SelectionCallback
    % Make the tab
    obj.handles.ribbon.tools = matlab.ui.internal.toolstrip.Tab("Tools");
    obj.handles.ribbon.tools.Tag = 'toolbarTools';

    % Add tab to the tab group
    obj.handles.ribbon.global.add(obj.handles.ribbon.tools);
    widgetHandles = [];
    return
end

%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.PopupListHeader
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton

%% ============= Make "Segmentation" section =============
section = obj.handles.ribbon.tools.addSection("Segmentation");

% ------------- Deep learning segmentation -------------
column = section.addColumn();
widgetHandles.deepmib = Button(sprintf('Deep learning\nsegmentation'),  Icon(fullfile(iconPath, 'deepMIB_24px.png')));
widgetHandles.deepmib.Description = 'DeepMIB: deep learning segmentation';
column.add(widgetHandles.deepmib);

%% -------------- Classifiers --------------
column = section.addColumn();
widgetHandles.classifiers =  DropDownButton('Classifiers', Icon(fullfile(iconPath, 'classifiers_24px.png')));
widgetHandles.classifiers.Description = "Pixel classifiers";

popupList = PopupList();
header1 = PopupListHeader('Pixel classifiers');
popupList.add(header1);
% Membrane detector
widgetHandles.membrane =  ListItem( 'Membrane detector', Icon(fullfile(iconPath, 'classification_membrane_24px.png'))); 
popupList.add(widgetHandles.membrane);
% Supervoxels classifier
widgetHandles.supervoxels =  ListItem( 'Supervoxels classifier', Icon(fullfile(iconPath, 'classification_super_24px.png'))); 
popupList.add(widgetHandles.supervoxels);

widgetHandles.classifiers.Popup = popupList;
column.add(widgetHandles.classifiers);

%% -------------- Semi-automatic segmentation --------------
column = section.addColumn();
widgetHandles.semiauto =  DropDownButton(sprintf('Semi-automatic\nsegmentation'), Icon(fullfile(iconPath, 'semiauto_24px.png')));
widgetHandles.semiauto.Description = "Semi-automatic segmentation";

popupList = PopupList();
header1 = PopupListHeader('Semi-automatic segmentation');
popupList.add(header1);
% Global thresholding
widgetHandles.globalthres =  ListItem(sprintf('Global\nthresholding'), Icon(fullfile(iconPath, 'global_tresholding_24px.png')));
popupList.add(widgetHandles.globalthres);
% Graphcut
widgetHandles.graphcut =  ListItem('Graphcut', Icon(fullfile(iconPath, 'graphcut_24px.png'))); 
popupList.add(widgetHandles.graphcut);
% Watershed
widgetHandles.watershed =  ListItem('Watershed', Icon(fullfile(iconPath, 'watershed_24px.png'))); 
popupList.add(widgetHandles.watershed);

widgetHandles.semiauto.Popup = popupList;
column.add(widgetHandles.semiauto);

%% ============= Make "Misc" section =============
section = obj.handles.ribbon.tools.addSection("Misc");
% Measure length
column = section.addColumn();
widgetHandles.measure =  matlab.ui.internal.toolstrip.SplitButton(sprintf('Measure\ntool'), Icon(fullfile(iconPath, 'measure_24px.png')));
widgetHandles.measure.Description = "Start Measure tool for interactive measurements";

popupList = PopupList();
header1 = PopupListHeader('Measure length');
popupList.add(header1);
% Measure tool
widgetHandles.measureTool =  ListItem('Measure tool',  Icon(fullfile(iconPath, 'measure_24px.png')));
popupList.add(widgetHandles.measureTool);
% Line measure
widgetHandles.measureLine =  ListItem('Line measure', Icon(fullfile(iconPath, 'profileLine_24px.png')));
popupList.add(widgetHandles.measureLine);
% Freehand measure
widgetHandles.measureFreehand =  ListItem('Free hand measure',  Icon(fullfile(iconPath, 'profileArbitrary_24px.png')));
popupList.add(widgetHandles.measureFreehand);

widgetHandles.measure.Popup = popupList;
column.add(widgetHandles.measure);

% ----------------- Object separator -----------------
column = section.addColumn();
widgetHandles.objects = Button(sprintf('Object\nseparation'),  Icon(fullfile(iconPath, 'object_separation_24px.png')));
widgetHandles.objects.Description = 'Start a tool for object separation';
column.add(widgetHandles.objects);

% ----------------- Stereology -----------------
column = section.addColumn();
widgetHandles.stereology = Button('Stereology',  Icon(fullfile(iconPath, 'stereology_24px.png')));
widgetHandles.stereology.Description = 'Start the stereology tool';
column.add(widgetHandles.stereology);

% ----------------- Wound healing assay -----------------
column = section.addColumn();
widgetHandles.wound = Button(sprintf('Wound healing\nassey'),  Icon(fullfile(iconPath, 'wound_healing_24px.png')));
widgetHandles.wound.Description = 'Perform wound healing assey';
widgetHandles.wound.ButtonPushedFcn = @(varargin)disp('Wound healing assey pressed');
column.add(widgetHandles.wound);

obj.handles.ribbonTools = widgetHandles;

end
