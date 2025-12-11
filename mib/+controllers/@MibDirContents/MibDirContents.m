classdef MibDirContents
    % classdef MibDirContents
    % controller for methods of the DirContents panel in MIB

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the ROI panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
    end

    methods
    
        bioFormats_Callback(obj, hWidget, hData)        % callback for selection of the bio-formats reader by press on obj.view.handles.panels.dirContents.handles.bioFormats, updates the contents of obj.view.handles.panels.dirContents.handles.fileFilters and refresh the list of files in obj.view.handles.panels.dirContents.handles.fileList
        
        fileFilters_Callback(obj, hWidget, hData)        % callback for selection of a file filter in the Directory contents panel, the parent widget is obj.handles.panels.dirContents.handles.fileFilters
        
        fileFilters_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of the file filters widget (obj.handles.panels.activeDataset.handles.fileFilters)

        fileList_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of the file list widget (obj.handles.panels.activeDataset.handles.fileList)

        updateFileList_Callback(obj, hWidget, hData, selectedFilename)       % callback for click on the "obj.view.handles.panels.dirContents.handles.updateFileList" button to update the list of files shown in "obj.view.handles.panels.dirContents.handles.fileList" using filters specified in "obj.view.handles.panels.dirContents.handles.fileFilters"

        function obj = MibDirContents(mainCtrl, view, guiHandles, model)
            %% Init properties
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the panel (views.components.Segmentation)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.segmentation.handles ...)
            obj.mibModel = model;               % handle to the main MIB model

            %%  Add CALLBACKS to context menus ----------------------
            % ---------------------- Add context menu for fileList ----------------------
            % obj.handles.fileListContext
            obj.handles.fileListContextCombine.MenuSelectedFcn = @obj.fileList_ContextMenu;
            obj.handles.fileListContextLoadPart.MenuSelectedFcn = @obj.fileList_ContextMenu;
            obj.handles.fileListContextLoadNth.MenuSelectedFcn = @obj.fileList_ContextMenu;
            obj.handles.fileListContextInsert.MenuSelectedFcn = @obj.fileList_ContextMenu;
            % 
            obj.handles.fileListContextColorCombine.MenuSelectedFcn = @obj.fileList_ContextMenu;
            obj.handles.fileListContextColorAdd.MenuSelectedFcn = @obj.fileList_ContextMenu;
            obj.handles.fileListContextColorAddNth.MenuSelectedFcn = @obj.fileList_ContextMenu;
            %
            obj.handles.fileListContextRename.MenuSelectedFcn = @obj.fileList_ContextMenu;
            obj.handles.fileListContextDelete.MenuSelectedFcn = @obj.fileList_ContextMenu;
            %
            obj.handles.fileListContextProps.MenuSelectedFcn = @obj.fileList_ContextMenu;

            % ---------------------- Add context menu for fileFilters ----------------------
            obj.handles.fileFiltersContextRegister.MenuSelectedFcn = @obj.fileFilters_ContextMenu;
            obj.handles.fileFiltersContextUnregister.MenuSelectedFcn = @obj.fileFilters_ContextMenu;
            
            % ----------------------ADD CALLBACKS TO WIDGETS ----------------------
            obj.handles.fileList.DoubleClickedFcn = @obj.fileList_Callback;
            obj.handles.fileFilters.ValueChangedFcn = @obj.fileFilters_Callback;
            obj.handles.bioFormats.ValueChangedFcn = @obj.bioFormats_Callback;
            obj.handles.fileList.DoubleClickedFcn = @obj.fileList_Callback;
            obj.handles.fileList.DoubleClickedFcn = @obj.fileList_Callback;
            obj.handles.updateFileList.ButtonPushedFcn = @obj.updateFileList_Callback;
            obj.handles.help.ButtonPushedFcn = @(src, event)obj.mibController.helpButtons_Callback(src, event);

        end

    end
end