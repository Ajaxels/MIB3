classdef MibDirContents
% MIBDIRCONTENTS - controller for methods of the DirContents panel in MIB.
%

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the ROI panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
        listeners       % cell array of listeners
        UIFigure        % handle to underlying UIFigure
    end

    methods
        % ------------------ declaration of listeners
        listenerUpdateFileList(obj, src, evtData)        % Update list of files in "obj.view.handles.panels.dirContents.handles.fileList" executed upon catch of MibModel->"UpdateFilelist" event
        listener_updatePanelPosition(obj, src, evtData)        % Listener callback: adapt the Directory contents panel grid layout when the panel is docked to a new region of the AppContainer (bottom, left, or right)
        % ------------------ declaration of other methods and callbacks
        bioFormats_Callback(obj)        % callback for selection of the bio-formats reader by press on obj.view.handles.panels.dirContents.handles.bioFormats, updates the contents of obj.view.handles.panels.dirContents.handles.fileFilters and refresh the list of files in obj.view.handles.panels.dirContents.handles.fileList
        fileFilters_Callback(obj, hWidget, hData)        % callback for selection of a file filter in the Directory contents panel, the parent widget is obj.handles.panels.dirContents.handles.fileFilters
        fileFilters_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of the file filters widget (obj.handles.panels.activeDataset.handles.fileFilters)
        fileList_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of the file list widget (obj.handles.panels.activeDataset.handles.fileList)
        updateFileList_Callback(obj, selectedFilename)       % callback for click on the "obj.view.handles.panels.dirContents.handles.updateFileList" button to update the list of files shown in "obj.view.handles.panels.dirContents.handles.fileList" using filters specified in "obj.view.handles.panels.dirContents.handles.fileFilters"

        function obj = MibDirContents(mainCtrl, view, guiHandles, model)
            % MIBDIRCONTENTS - Constructor for the Directory Contents panel controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = MibDirContents(mainCtrl, view, guiHandles, model)
            %
            % Initializes the controller for the Directory Contents panel, which manages
            % file listing, filtering, and loading operations. Sets up all GUI callbacks
            % for file operations, filter selection, and context menus.
            %
            % Input Arguments:
            %   - **mainCtrl** — [controllers.MibController] handle to main MIB controller
            %   - **view** — [MibView] handle to main application view
            %   - **guiHandles** — [views.components.DirContents] handle to Directory Contents panel GUI component
            %   - **model** — [models.MibModel] handle to main MIB data model
            %
            % Output Arguments:
            %   - **obj** — [MibDirContents] initialized controller instance
            %
            % **Initialization sequence:**
            %   1. Stores references to main controller, view, model, and GUI handles
            %   2. Caches panel-specific handles for efficient access
            %   3. Initializes file filters dropdown with all registered file extensions
            %   4. Updates file list from current directory
            %   5. Wires callbacks for file list operations (combine, load, insert, color operations)
            %   6. Wires callbacks for file filters context menu (register/unregister extensions)
            %   7. Wires callbacks for file list context menu operations
            %   8. Wires callbacks for bioFormats reader selection
            %   9. Wires callback for file list update button
            %   10. Adds listeners for ``UpdateFileList`` events and panel region changes
            %
            % See also:
            %   ``fileList_Callback``, ``fileFilters_Callback``, ``bioFormats_Callback``, ``fileList_ContextMenu``, ``listenerUpdateFileList``
            %
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the panel (views.components.Segmentation)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.segmentation.handles ...)
            obj.mibModel = model;               % handle to the main MIB model
            obj.UIFigure = ancestor(obj.gui, 'figure'); % handle to underlying UIFigure

            %% Update widgets
            % update list of available filters for file formats
            obj.handles.fileFilters.Items = ['all known', model.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default')];
            % update list of files in obj.handles.fileList
            obj.updateFileList_Callback();

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
            
            % ---------------------- ADD CALLBACKS TO WIDGETS ----------------------
            obj.handles.fileList.DoubleClickedFcn = @obj.fileList_Callback;
            obj.handles.fileList.ClickedFcn = @obj.fileList_Callback;
            obj.handles.fileFilters.ValueChangedFcn = @obj.fileFilters_Callback;
            obj.handles.bioFormats.ValueChangedFcn = @(~,~)obj.bioFormats_Callback;
            obj.handles.fileList.DoubleClickedFcn = @obj.fileList_Callback;
            obj.handles.fileList.DoubleClickedFcn = @obj.fileList_Callback;
            obj.handles.updateFileList.ButtonPushedFcn = @(~,~)obj.updateFileList_Callback;
            obj.handles.help.ButtonPushedFcn = @(src, event)obj.mibController.helpButtons_Callback(src, event);

            %% Add listeners
            obj.listeners{1} = addlistener(obj.mibModel, 'UpdateFileList', @(src, evnt) obj.listenerUpdateFileList(src, evnt)); % update GUI from the model
            obj.listeners{1} = addlistener(obj.view.handles.panels.dirContentsPanel, 'PropertyChanged', @obj.listener_updatePanelPosition); % redraw the panel when Region property gets changed

            % ---------------------- Key press callback ----------------------
            obj.UIFigure.WindowKeyPressFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);
            
        end

    end
end
