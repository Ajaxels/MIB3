classdef MibController < handle
    % % main controller for MIB

    properties
        % GUI controllers for the main MIB GUI panels and ribbons
        cActiveDataset
        % Controller for the Datasets panel
        cDirContents
        % Controller for the Dir contents panel
        cQuickAccessBar
        % Controller for the Quick Access Bar
        cSelection
        % Controller for the Selection and View settings panel
        cRibbon
        % Controller for the top ribbon panel
        cRoi
        % Controller for the ROI panel
        cSegmentation
        % Controller for the Segmentation panel
        cStatus
        % Controller for the Status bar
        childControllers
        % list of opened subcontrollers
        childControllersIds
        % a cell array with names of initialized child controllers
        listeners
        % a cell array with handles to listeners
        matlabVersion
        % version of Matlab
        mibModel
        % handles to the model
        mibPath 
        % path to MIB installation directory, also available in MibModel
        mibVersion % = 'ver. 3.0001 / 23.09.2025';  % ATTENTION! it is important to have the version number between "ver." and "/"
        % version of MIB
        mibVersionNumeric 
        % version of MIB in numerical form
        mibWebWindow
        % handle of the underlying matlab.internal.webwindow class window (used for drag-and-drop of files
        view
        % handle to the view
    end

    methods (Static)
        function purgeControllers(obj, src, evnt)
            % function purgeControllers(obj, src, evnt)
            % remove child controller

            % find index of the child controller
            id = obj.findChildId(class(src));

            % delete the child controller
            delete(obj.childControllers{id});

            % clear the handle
            obj.childControllers(id) = [];
            obj.childControllersIds(id) = [];
        end
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
                
        % LISTENERS CALLBACKS
        listenerAppStateChanged(obj, src, evtData) % generic listener for change of states in the main GUI

        listner1_Standard(obj, model, evnt)    % listener type 1 callbacks

        listner2_ModelEvent(obj, model, evnt)  % listener type 2 rely on additional evnt.EventName structure

        listenerShowImage(obj, src, evtData) % render (show) the current image in the Image View panel

        listenerShowErrorDialog(obj, src, evtData) % Listener callback to show the error dialog
        
        listenerUpdateDatasetAxes(obj, src, evtData) % update obj.I (MibDataset).axesX and bj.I (MibDataset).axesY during fit screen, resize, or new dataset drawing


        % METHODS

        addGuiControllers(obj)  % add GUI components to the main view obj.view

        result = exitProgram(obj, target)        % exit mib 

        id = findChildId(obj, childName)        % find id of a child controller

        globalTabGroup_SelectionCallback(obj, hWidget, hData) % callback for the selection of the tab in the main ribbon, optimization for lazy initialization of ribbon tabs

        helpButtons_Callback(obj, hWidget, hData) % callback for click on the Help buttons in various panels of MIB

        imViewPanel_Callbacks(obj, hWidget, hData, mode)        % callbacks for widgets of the Image View panel obj.view.handles.imView{setNumber}.handles...
        
        initialize(obj)  % initialize the main MibController class

        status = loadLayout(obj, mode, layoutFilename)       % restore MIB layout from file

        filename = saveLayout(obj, mode) % store the current layout of panels
        
        showImage(obj, resize)        % show the current image in the Image View panel

        [hSplashScreen, hSplashAxes, hLabel] = showSplashScreen(obj, titleText, initText)   % show MIB splash screen
        
        startController(obj, controllerName, varargin) % start a child controller using provided name

        function obj = MibController(mibModel, mibVersion)
            % function obj = MibController(mibModel, mibVersion)
            % MibController class constructor
            %
            % Constructor for the MibController class. Create a new instance of
            % the class with default parameters
            %
            % Parameters:
            % mibModel: a handle to mibModel class
            % mibVersion: a string with the current version of MIB

            % define some global variables
            obj.childControllers = {};   % initialize child controllers
            obj.childControllersIds = {};
            obj.listeners = {};

            % init mibModel
            obj.mibModel = mibModel;
            obj.mibPath = obj.mibModel.mibPath;
            obj.mibVersion = mibVersion;
            obj.mibVersionNumeric = utils.getMibVersionNumberic(mibVersion);
            obj.mibWebWindow = []; % handle of underlying web window for MIB (to use in drag-and-drop)
            fprintf('MIB version: %s (%.4f)\n', mibVersion, obj.mibVersionNumeric);

            % init the controller parameters
            obj.initialize();

        end
        
    end
end