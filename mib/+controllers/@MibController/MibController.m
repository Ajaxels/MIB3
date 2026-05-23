classdef MibController < handle
% MIBCONTROLLER - % main controller for MIB.
%

    properties
        % GUI controllers for the main MIB GUI panels and ribbons
        cActiveDataset
        % Controller for the Datasets panel
        cDirContents
        % Controller for the Dir contents panel
        cImageDoc = {}        % cell array of controllers.MibImageDocument
        % Image document controllers (cell array for multiple documents)
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
        % list of opened sub-controllers
        childControllersIds
        % a cell array with names of initialized child controllers
        currentModifier = {}
        % cell array of modifier keys currently held (e.g. {'shift'}, {'alt','shift'}).
        % Updated by gui_WindowKeyPressFcn and cleared by gui_WindowKeyReleaseFcn.
        % Use this property (via obj.mibController.currentModifier) instead of
        % UIFigure.CurrentModifier inside button callbacks — UIFigure.CurrentModifier
        % is only updated by keyboard events on that specific sub-figure, so it
        % returns {} when a Selection-panel button is clicked with a modifier held.
        fastPanningMode = false
        % use the fast panning mode, defined in qab by pressing on obj.view.handles.qab.fastpan
        propagatingLinkedView = false
        % guard flag: true while showImage is recursively rendering a linked-partner panel;
        % prevents infinite mutual propagation between two linked datasets
        globalResizeTimer
        % global timer for proper resizing of panels (used in MibImageDocument.gui_SizeChangedFcn)
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
        dndBridgeButton = []
        % hidden uibutton returned by utils.attachFileDnD; state for the
        % drag-and-drop bridge lives in its UserData
        view
    end

    methods (Static)
        function purgeControllers(obj, src, evnt)
            % PURGECONTROLLERS - remove child controller.
            %
            % Syntax:
            %   function purgeControllers(obj, src, evnt)
            %
            utils.purgeChildController(obj, src);
        end
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
        % LISTENERS CALLBACKS
        listener_appStateChanged(obj, src, evtData) % generic listener for change of states in the main GUI
        listner1_Standard(obj, model, evnt)    % listener type 1 callbacks
        listner_ModelEvent(obj, model, evnt)  % listener type 2 rely on additional evnt.EventName structure, generic listener for small event callbacks
        listener_newDataset(obj, src, evtData) % Update obj.I (MibDataset) by resizing it to fit on the screen executed upon catch of MibModel->"NewDataset" event
        listener_showImage(obj, src, evtData) % render (show) the current image in the Image View panel
        listener_showErrorDialog(obj, src, evtData) % Listener callback to show the error dialog
        listener_updateDatasetAxes(obj, src, evtData) % update obj.I (MibDataset).axesX and bj.I (MibDataset).axesY during fit screen, resize, or new dataset drawing
        listener_updateToolbar(obj, src, evtData) % update buttons in MIB toolbar "obj.view.handles.qab.handles"
        % METHODS
        addGuiControllers(obj)  % add GUI components to the main view obj.view
        deleteImageDocument(obj, docIndex)        % Delete an image document and reindex remaining documents
        datasetSlices(obj, parameter)             % Dispatcher for Menu -> Dataset -> Slice operations (copy, swap, insert, delete, reslice)
        result = exitProgram(obj, target)        % exit mib 
        id = findChildId(obj, childName)        % find id of a child controller
        globalTabGroup_SelectionCallback(obj, hWidget) % callback for the selection of the tab in the main ribbon, optimization for lazy initialization of ribbon tabs
        helpButtons_Callback(obj, hWidget, hData) % callback for click on the Help buttons in various panels of MIB
        initialize(obj)  % initialize the main MibController class
        initializeLibraries(obj, initList)            % initialize external libraries and Java paths
        gui_WindowKeyPressFcn(obj, hWidget, hData)        % Callback for a key press in MIB
        gui_WindowKeyReleaseFcn(obj, hWidget, hData)       % Callback for a key release in MIB; restores brush radius after Ctrl eraser mode
        status = loadLayout(obj, mode, layoutFilename)       % restore MIB layout from file
        filename = saveLayout(obj, mode) % store the current layout of panels
        measureLength(obj, type)                % quick line or freehand path length measurement
        scaleBarCalibration(obj) % Calibrate pixel size using a scale bar drawn on the image
        showImage(obj, resizeToMagnification, setId, sImgIn)        % show the current image in the Image View panel
        [hSplashScreen, hSplashAxes, hLabel] = showSplashScreen(obj, titleText, initText)   % show MIB splash screen
        startController(obj, controllerName, varargin) % start a child controller using provided name
        updateFrameNumber(obj, BatchOptIn)             % change the currently displayed time frame in the active image document (batch-aware wrapper)
        updateGuiWidgets(obj, updatePanels)            % update user interface widgets in obj.mibView.gui based on the properties of the opened dataset
        updateSliceNumber(obj, BatchOptIn)             % change the currently displayed slice number in the active image document (batch-aware wrapper)
        updateInterpolationMode(obj, options)        % Function to set the state of the interpolation button in the Selection ribbon
        updateVisualizationMode(obj, mode)        % Function to set type of image interpolation for the visualization (from Image Ribbon)

        function obj = MibController(mibModel, mibVersion)
            % MIBCONTROLLER - MibController class constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = MibController(mibModel, mibVersion)
            %
            % Constructor for the MibController class. Create a new instance of
            % the class with default parameters
            %
            % Input Arguments:
            %   - **mibModel** — a handle to mibModel class
            %   - **mibVersion** — a string with the current version of MIB
            %

            % define some global variables
            obj.childControllers = {};   % initialize child controllers
            obj.childControllersIds = {};
            obj.listeners = {};

            obj.mibVersion = mibVersion;
            obj.mibVersionNumeric = utils.getMibVersionNumberic(mibVersion);

            % init mibModel
            obj.mibModel = mibModel;
            obj.mibPath = obj.mibModel.mibPath;
            
            obj.mibWebWindow = []; % handle of underlying web window for MIB (to use in drag-and-drop)
            fprintf('MIB version: %s (%.4f)\n', mibVersion, obj.mibVersionNumeric);

            % init the controller parameters
            obj.initialize();

        end
        
    end
end
