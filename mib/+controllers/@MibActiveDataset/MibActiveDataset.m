classdef MibActiveDataset
    % classdef MibActiveDataset
    % controller for methods of the Datasets panel in MIB

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the ROI panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
        listeners       % cell array of listeners
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator

        buffers_Callback(obj, hWidget, hData)        % callbacks for press obj.handles.panels.activeDataset.handles.buffer1 buttons, selects the dataset stored in a buffer defined by the pressed button

        buffers_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of the buffers (obj.handles.panels.activeDataset.handles.buffer1) buttons

        setsOps_Callbacks(obj, hWidget, hData, mode)        % callbacks for press of sets-related widgets in obj.view.handles.panels.activeDataset.handles

        type_Callback(obj, hWidget, hData)        % callback for selection of entry in Datasets.datasetType dropdown to choose the type of the dataset stored in the selected buffer/container

        update_fromModel(obj, src, evtData)        % update widgets of the Datasets panel from obj.mibModel

        function obj = MibActiveDataset(mainCtrl, view, guiHandles, model)
            %% Init properties
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the panel (views.components.Datasets)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.activeDataset.handles ...)
            obj.mibModel = model;               % handle to the main MIB model

            %%  Add CALLBACKS to context menus ----------------------
            %% ---------------------- Add context menu for the Buffer buttons ----------------------
            % obj.handles.datasets
            obj.handles.buffersContextDuplicate.MenuSelectedFcn = @obj.buffers_ContextMenu;
            obj.handles.buffersContextSyncXY.MenuSelectedFcn = @obj.buffers_ContextMenu;
            obj.handles.buffersContextSyncXYZ.MenuSelectedFcn = @obj.buffers_ContextMenu;
            obj.handles.buffersContextSyncXYZT.MenuSelectedFcn = @obj.buffers_ContextMenu;
            obj.handles.buffersContextLink.MenuSelectedFcn = @obj.buffers_ContextMenu;
            obj.handles.buffersContextClose.MenuSelectedFcn = @obj.buffers_ContextMenu;
            obj.handles.buffersContextCloseSet.MenuSelectedFcn = @obj.buffers_ContextMenu;
            
            %% ---------------------- Add context menu for the Sets dropdown ----------------------
            obj.handles.setsContextAdd.MenuSelectedFcn = @obj.setsOps_Callbacks;
            obj.handles.setsContextRename.MenuSelectedFcn = @obj.setsOps_Callbacks;
            obj.handles.setsContextSort.MenuSelectedFcn = @obj.setsOps_Callbacks;
            obj.handles.setsContextRemove.MenuSelectedFcn = @obj.setsOps_Callbacks;
            
            %% ---------------------- ADD CALLBACKS TO WIDGETS ----------------------
            obj.handles.buffer1.ButtonPushedFcn = @obj.buffers_Callback;
            obj.handles.buffer2.ButtonPushedFcn = @obj.buffers_Callback;
            obj.handles.buffer3.ButtonPushedFcn = @obj.buffers_Callback;
            obj.handles.buffer4.ButtonPushedFcn = @obj.buffers_Callback;
            obj.handles.buffer5.ButtonPushedFcn = @obj.buffers_Callback;
            obj.handles.buffer6.ButtonPushedFcn = @obj.buffers_Callback;
            obj.handles.buffer7.ButtonPushedFcn = @obj.buffers_Callback;
            obj.handles.buffer8.ButtonPushedFcn = @obj.buffers_Callback;
            obj.handles.buffer9.ButtonPushedFcn = @obj.buffers_Callback;
            obj.handles.buffer10.ButtonPushedFcn = @obj.buffers_Callback;
            
            obj.handles.sets.ValueChangedFcn = @obj.setsOps_Callbacks;
            obj.handles.addSet.ButtonPushedFcn = @(src, event)obj.setsOps_Callbacks(src, event, 'setsContextAdd');
            obj.handles.datasetType.ValueChangedFcn = @obj.type_Callback;

            %% Add listeners
            obj.listeners{1} = addlistener(obj.mibModel, 'DatasetsPanelUpdate', @(src, evnt) obj.update_fromModel(src, evnt)); % update GUI from the model

        end
    end
end
