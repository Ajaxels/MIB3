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
        addDatasetsPanel(obj) % add the Datasets panel, add context menus and callbacks for widgets

        addDirContentsPanel(obj) % add the Datasets panel, add context menus and callbacks for widgets

        roiHandles = addRoiPanel(obj) % add the ROI panel, add context menus and callbacks for widgets
        
        addSegmentationPanel(obj) % add the Segmentation panel, add context menus and callbacks for widgets

        addSelectionViewSettingsPanel(obj) % add the Selection and View Settings panel, add context menus and callbacks for widgets

        addStatusBar(obj)     % add status bar to MIB

        addToolbarTabs(obj) % add the global toolbar, obj.handles.toolbar.global

        addQuickAccessBar(obj) % add quick access buttons

        buildHomeTab(obj) % build the Home tab group and and add it to obj.handles.toolbar.global 

        buildDatasetTab(obj) % build the Dataset tab group and and add it to obj.handles.toolbar.global 

        buildImageTab(obj) % build the Image tab group and and add it to obj.handles.toolbar.global 

        buildModelTab(obj) % build the Model tab group and and add it to obj.handles.toolbar.global 

        buildMaskTab(obj) % build the Mask tab group and and add it to obj.handles.toolbar.global 

        buildSelectionTab(obj) % build the Selection tab group and and add it to obj.handles.toolbar.global 

        buildToolsTab(obj) % build the Tools tab group and and add it to obj.handles.toolbar.global 
        
        buildPluginsTab(obj) % build the Plugins tab group and and add it to obj.handles.toolbar.global 
        
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

        function outputArg = method1(obj,inputArg)
            %METHOD1 Summary of this method goes here
            %   Detailed explanation goes here
            outputArg = obj.Property1 + inputArg;
        end
    end
end