classdef MibController < handle
    % % main controller for MIB

    properties
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
        listner1_Standard(obj, model, evnt)    % listener type 1 callbacks

        listner2_ModelEvent(obj, model, evnt)  % listener type 2 rely on additional evnt.EventName structure

        % METHODS

        devTest_Callback(obj, varargin) % callback for developmental purposes

        datasetsBuffers_ContextMenu(obj, menuEntry, selectedData) % callbacks for the context menu of the obj.view.handles.panels.datasets.handles.buffers buttons
        
        datasetsBuffers_Callback(obj, hWidget, hData) % callbacks for press of obj.view.handles.panels.datasets.handles.buffers buttons

        datasetsSetsOps_Callbacks(obj, hWidget, hData, mode) % callbacks for press of sets-related widgets in obj.view.handles.panels.datasets.handles

        datasetsType_Callbacks(obj, hWidget, hData) % callback for selection of entry in Datasets.datasetType dropdown to choose the type of the dataset stored in the selected buffer/container

        datasetsPanelUpdate(obj, src, evtData) % update widgets of the Datasets panel

        dirContentsBioFormats_Callback(obj, hWidget, hData) % 
        
        dirContentsFileFilters_Callback(obj, hWidget, hData) % callback for selection of a file filter in the Directory contents panel, the parent widget is obj.handles.panels.dirContents.handles.fileFilters

        dirContentsFileFilters_ContextMenu(obj, menuEntry, selectedData) % callbacks for the context menu of the file filters widget (obj.handles.panels.datasets.handles.fileFilters)
        
        dirContentsFileList_ContextMenu(obj, menuEntry, selectedData) % callbacks for the context menu of the file list widget (obj.handles.panels.datasets.handles.fileList)

        dirContentsFileList_Callback(obj, hWidget, hData) % callback for double click on a filename in obj.handles.panels.dirContents.handles.fileList
        
        dirContentsUpdateFileList_Callback(obj, hWidget, hData) % callback for click on the obj.handles.panels.dirContents.handles.updateFileList button to update the list of files shown in obj.handles.panels.dirContents.handles.fileList

        result = exitProgram(obj, target)        % exit mib 

        helpButtons_Callback(obj, hWidget, hData) % callback for click on the Help buttons in various panels of MIB

        listenerShowErrorDialog(obj, src, evtData) % Listener callback to show the error dialog

        status = loadLayout(obj, mode, layoutFilename)       % restore MIB layout from file

        plotImage(obj) % plot (show) the current image in the Image View panel

        roiPanel_Callbacks(obj, hWidget, hData, mode) % callbacks for widgets of some the ROI panel obj.handles.panels.roi

        segmentationFavTool_Callback(obj, hWidget, hData)  % callbacks for press of obj.handles.panels.segmentation.handles.favoriteTool in obj.handles.panels.segmentation panel. Select the current tool as favorite, the favorite tools available upon press of the 'D' key shortkey
        
        segmentationMaterials_Callback(obj, menuEntry, selectedData) % callbacks for the context menu of Segmentation table widget -> Materials...  entry (obj.view.handles.panels.segmentation.handles.materialsTableContextMat) and Menu ribbon -> Models -> Materials (obj.view.handles.model.materials)

        segmentationMaterialsTable_ContextMenu(obj, menuEntry, selectedData) % callbacks for the context menu of the segmentation table widget (obj.handles.panels.segmentation.handles.materialsTable)

        segmentationMaterialsTable_moveLayers(obj, menuEntry, selectedData) % callbacks for the context menu of the segmentation table widget (obj.handles.panels.segmentation.handles.materialsTableContextM2S)

        segmentationMaterialsTable_Render(obj, menuEntry, selectedData)  % callbacks for the context menu of the Segmentation table widget -> Render...  entry (obj.view.handles.panels.segmentation.handles.materialsTableContextRen)

        segmentationMaterialsTable_Schemes(obj, menuEntry, selectedData) % callbacks for the context menu of the segmentation table widget -> Color schemes entry (obj.handles.panels.segmentation.handles.materialsTableContextScheme)

        segmentationPanel_Callbacks(obj, hWidget, hData, mode) % callbacks for widgets of some the Segmentation panel obj.handles.panels.segmentation

        segmentationRestrictMask_Callback(obj, hWidget, hData) % callbacks for press of obj.handles.panels.segmentation.handles.restrictMask in obj.handles.panels.segmentation panel. Restrict selection to the mask layer
        
        segmentationRestrictMaterial_Callback(obj, hWidget, hData) % callbacks for press of obj.handles.panels.segmentation.handles.restrictMaterial in obj.handles.panels.segmentation panel. Restrict selection to the selected material in obj.handles.panels.segmentation.handles.materialsTable
        
        segmToolsAnnotationsPanel_Callback(obj, hWidget, hData, mode) % callbacks for widgets in the Segmentation panel->Annotations tool
        
        segmToolsBrushPanel_Callback(obj, hWidget, hData, mode)  % callbacks for widgets in the Segmentation panel->Brush/3D ball/Spot tool

        segmToolsDragPanel_Callback(obj, hWidget, hData, mode) % callbacks for widgets in the Segmentation panel->Drag-and-drop materials tool

        segmToolsLassoPanel_Callback(obj, hWidget, hData, mode) % callbacks for widgets in the Segmentation panel->Lasso/Object picker tools

        segmToolsLines3DPanel_Callback(obj, hWidget, hData, mode) % callbacks for widgets in the Segmentation panel->3D lines tool

        segmToolsMagicwandPanel_Callback(obj, hWidget, hData, mode) % callbacks for widgets in the Segmentation panel->Magicwand tool

        segmToolsMembranePanel_Callback(obj, hWidget, hData, mode) % callbacks for widgets in the Segmentation panel->Membrane click tracker tool

        segmToolsSamPanel_Callback(obj, hWidget, hData, mode) % callbacks for widgets in the Segmentation panel->SAM tool
        
        segmToolsThresholdingPanel_Callback(obj, hWidget, hData, mode) % callbacks for widgets in the Segmentation panel->Black and white thresholding tool

        selectionPanel_Callbacks(obj, hWidget, hData, mode) % callbacks for widgets of some the Segmentation panel obj.handles.panels.segmentation

        selectionLutTable_ContextMenu(obj, menuEntry, selectedData) % callbacks for the context menu of the LUT table widget (obj.handles.panels.selection.handles.lutTable)
        
        [hSplashScreen, hSplashAxes, hLabel] = showSplashScreen(obj, titleText, initText)   % show MIB splash screen
        
        filename = saveLayout(obj, mode) % store the current layout of panels

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

            obj.mibModel = mibModel;
            obj.mibVersion = mibVersion;
            obj.mibVersionNumeric = utils.getMibVersionNumberic(mibVersion);
            obj.mibWebWindow = []; % handle of underlying web window for MIB (to use in drag-and-drop)
            fprintf('MIB version: %s (%.4f)\n', mibVersion, obj.mibVersionNumeric);

            obj.childControllers = {};   % initialize child controllers
            obj.childControllersIds = {};
            obj.listeners = {};

            % ---- obtain path to MIB
            obj.mibPath = utils.getInstallationPath('mib3');
            obj.mibModel.mibPath = obj.mibPath; % send also to mibModel as it is needed to get relative dirs
            fprintf('MIB installation path: %s\n', obj.mibPath);

            % ---- show splash screen
            showSplashScreen = false;
            if showSplashScreen
                [hSplashScreen, hSplashAxes, hLabel] = obj.showSplashScreen(sprintf('MIB %s', obj.mibVersion), sprintf('Staring MIB\nPlease wait...'));
                hLabel.String = 'adding something else';
            end
            
            obj.view = views.MibView(obj);
            
            % --------- update listeners
            obj.listeners{1} = addlistener(obj.mibModel, 'ShowErrorDialog', @(src, evnt) obj.listenerShowErrorDialog(src, evnt));
            obj.listeners{end+1} = addlistener(obj.mibModel, 'DatasetsPanelUpdate', @(src, evnt) obj.datasetsPanelUpdate(src, evnt));
            
            %obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @(src, evnt) obj.listner_ModelEvent_Callback(src, evnt));
            %obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @obj.listner_ModelEvent_Callback);
            %obj.listeners{end+1} = addlistener(obj.model, 'keyPressEvent', @obj.listner2_Callback);
            %obj.listeners{end+1} = addlistener(obj.model, 'newFileCreated', @obj.listner2_Callback);

            % Update GUI widgets
            obj.datasetsPanelUpdate(); % update widgets of the Datasets panel


            % Make the GUI visible
            obj.view.gui.Visible = true;
            if showSplashScreen; hSplashScreen.focus; end  % focus on the splash screen
            pause(2);
            obj.view.doPostInitializationTasks();
            
            if showSplashScreen
                hLabel.String = 'finishing'; drawnow nocallbacks; 
                % close the splash screen
                delete(hSplashScreen);
            end

            %obj.plotImage();
        end
        
    end
end