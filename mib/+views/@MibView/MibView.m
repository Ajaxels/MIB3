classdef MibView < handle
    % classdef mibView < handle
    % the main view class of MIB

    properties
        gui
        % handle to the main gui
        mibModel
        % handles to the model
        controller
        % handles to mibController
        handles
        % list of handles for the gui
    end

    events

    end

    methods
        %% ------------------------------ EXTERNAL FUNCTIONS DECLARATIONS ------------------------------
        % declaration of functions in the external files, keep empty line in between for the doc generator
        panelHandles = addDatasetsPanel(obj) % add the Datasets panel, add context menus and callbacks for widgets

        panelHandles = addDirContentsPanel(obj) % add the Datasets panel, add context menus and callbacks for widgets

        [ribbonHandles, ribbonWidgets] = addRibbonTabs(obj)        % Add the global ribbon, which is matlab.ui.internal.toolstrip.TabGroup()

        homeHandles = addRibbonHome(obj)        % build the Home tab group (obj.handles.ribbon.home) and add it to obj.handles.ribbon.global 

        widgetHandles = addRibbonImage(obj, lazyInit)        % build the Image tab group (obj.handles.ribbon.image) and add it to obj.handles.ribbon.global 

        datasetHandles = addRibbonDataset(obj, lazyInit)        % build the Datasets tab group (obj.handles.ribbon.dataset) and add it to obj.handles.ribbon.global 

        widgetHandles = addRibbonModel(obj, lazyInit)        % build the Model tab group (obj.handles.ribbon.model) and add it to obj.handles.ribbon.global 

        widgetHandles = addRibbonMask(obj, lazyInit)        % build the Mask tab group (obj.handles.ribbon.mask) and add it to obj.handles.ribbon.global 

        widgetHandles = addRibbonSelection(obj, lazyInit)        % build the Selection tab group (obj.handles.ribbon.selection) and add it to obj.handles.ribbon.global

        widgetHandles = addRibbonTools(obj, lazyInit)        % build the Tools tab group (obj.handles.ribbon.tools) and add it to obj.handles.ribbon.global 

        widgetHandles = addRibbonPlugins(obj, lazyInit)        % build the Plugins tab group (obj.handles.ribbon.plugins) and add it to obj.handles.ribbon.global 
        
        panelHandles = addRoiPanel(obj) % add the ROI panel, add context menus and callbacks for widgets
        
        panelHandles = addSegmentationPanel(obj) % add the Segmentation panel, add context menus and callbacks for widgets

        panelHandles = addSelectionViewSettingsPanel(obj) % add the Selection and View Settings panel, add context menus and callbacks for widgets

        statusHandles = addStatusBar(obj)     % add status bar to MIB

        qab = addQuickAccessBar(obj) % add quick access buttons

        doPostInitializationTasks(obj)  % Do some post-initialization tasks that require that the main GUI window is visible

        initialize(obj)             % initialize the view

        globalTabGroup = buildGlobalTabGroup(obj)    % build global tab group

        overrideDescriptions(obj);  % override description text by adding the widget tag

        recenterGui(obj) % recenter MIB to be on the center of the screen

        function obj = MibView(controller)
           % obj = mibView(controller)
            % mibView class constructor
            %
            % Constructor for the mibView class. Create a new instance of
            % the class with default parameters
            %
            % Parameters:
            % controller: handle to mibController class

            obj.controller = controller;
            obj.mibModel = controller.mibModel;
            obj.handles = struct();

            obj.initializeMibView(); %  initialize gui

            % add (remove, when developerMode=false) the handle label to the beginning of the Description field, which is tooltip
            if obj.mibModel.preferences.System.DeveloperMode; utils.overrideDescriptions(obj.handles, true); end
        end


    end
end