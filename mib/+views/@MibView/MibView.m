classdef MibView < handle
    % MIBVIEW - the main view class of MIB.
    %

    properties
        gui
        % handle to the main gui
        mibModel
        % handles to the model
        controller
        % handles to mibController
        handles
        % list of handles for the gui
        
        brushCursorShow
        % logical identifier whether or not to show the brush cursor
        brushCursorOffset
        % [x y] offsets for drawing of the brush cursor
        brushSizeNumbers
        % matrix with the font for changing of brush size
        
        ctrlPressed = 0
        % set a variable to deal with the increase of the brush size during the erasing action. Ctrl+left mouse button
        % obj.ctrlPressed:
        % obj.ctrlPressed == 0; - indicates the normal brush mode, i.e. when the control button is not pressed
        % obj.ctrlPressed > 0; - the control button is pressed and handles.ctrlPressed indicates increase of the brush radius
        % obj.ctrlPressed == -1; - a tweak to deal with Ctrl+Mouse wheel action to change size of the brush. -1 indicates that the brush size change mode was triggered
        % see in functions:
        %    imView_WindowKeyPressFcn, imView_WindowKeyReleaseFcn, imView_ScrollWheelFcn        
    end

    events

    end

    methods
        %% ------------------------------ EXTERNAL FUNCTIONS DECLARATIONS ------------------------------
        % declaration of functions in the external files, keep empty line in between for the doc generator
        panelHandles = addActiveDatasetPanel(obj) % add the Datasets panel, add context menus and callbacks for widgets

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
        
        panelHandles = addFijiConnectPanel(obj) % add the Fiji Connect panel, add context menus and callbacks for widgets
        
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
           % MIBVIEW - main view class constructor.
           %
           % Syntax:
           %   .. code-block:: matlab
           %
           %      obj = MibView(controller)
           %
           % Input Arguments:
           %   - **controller** — handle to ``MibController`` class
           %

            obj.controller = controller;
            obj.mibModel = controller.mibModel;
            obj.handles = struct();

            obj.initializeMibView(); %  initialize gui

            % add (remove, when developerMode=false) the handle label to the beginning of the Description field, which is tooltip
            if obj.mibModel.preferences.System.DeveloperMode; utils.overrideDescriptions(obj.handles, true); end
        end


    end
end
