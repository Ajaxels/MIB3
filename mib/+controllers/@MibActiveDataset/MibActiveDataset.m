classdef MibActiveDataset
% MIBACTIVEDATASET - Controller for the Datasets panel in MIB.
%
% This class manages the Datasets panel UI, which handles:
%   - Selection and switching between dataset buffers (10 available)
%   - Dataset set operations (add new sets, rename, sort, remove)
%   - Dataset type selection (Standard, Virtual, BigData)
%   - Buffer synchronization (XY, XYZ, XYZT dimensions)
%   - Linked view management across buffers
%   - Context menu operations for buffer management
%
% The controller maintains references to the main MIB controller, view, model,
% and panel GUI handles. It synchronizes the UI state with the model via event
% listeners and propagates user actions back to the model for processing.
%
% See also:
%   ``MibController``, ``MibModel``, ``models.MibModel.buffers_Callback``, ``models.MibModel.setsOps_Callbacks``
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
        % % declaration of functions in the external files, keep empty line in between for the doc generator
        % 
        buffers_Callback(obj, hWidget, hData, buttonId)        % callbacks for press obj.handles.panels.activeDataset.handles.buffer1 buttons, selects the dataset stored in a buffer defined by the pressed button
        buffers_ContextMenu(obj, parameter, buttonID, BatchOptIn)        % callbacks for the context menu of the buffers (obj.handles.panels.activeDataset.handles.buffer1) buttons; batch-compatible
        setsOps_Callbacks(obj, hWidget, hData, mode)        % callbacks for press of sets-related widgets in obj.view.handles.panels.activeDataset.handles
        datasetTypeChange_Callback(obj, hWidget, hData)        % callback for selection of entry in Datasets.datasetType dropdown to choose the type of the dataset stored in the selected buffer/container
        update_fromModel(obj, src, evtData)        % update widgets of the Datasets panel from obj.mibModel

        function obj = MibActiveDataset(mainCtrl, view, guiHandles, model)
            % MIBACTIVEDATASET - Constructor for the Datasets panel controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = MibActiveDataset(mainCtrl, view, guiHandles, model)
            %
            % Initializes the controller for the Datasets panel, which manages dataset/buffer
            % selection, set operations, and dataset type changes. Sets up all GUI callbacks
            % for buffer buttons, context menus, dropdown controls, and model event listeners.
            %
            % Input Arguments:
            %   - **mainCtrl** — [controllers.MibController] handle to main MIB controller
            %   - **view** — [MibView] handle to main application view
            %   - **guiHandles** — [views.components.Datasets] handle to Datasets panel GUI component
            %   - **model** — [models.MibModel] handle to main MIB data model
            %
            % Output Arguments:
            %   - **obj** — [MibActiveDataset] initialized controller instance
            %
            % **Initialization sequence:**
            %   1. Stores references to main controller, view, model, and GUI handles
            %   2. Caches panel-specific handles for efficient access
            %   3. Updates widgets from current model state (``update_fromModel``)
            %   4. Wires callbacks for 10 buffer buttons (buffer1–buffer10)
            %   5. Wires callbacks for dataset set operations (add, rename, sort, remove)
            %   6. Wires callbacks for dataset type dropdown
            %   7. Wires context menus for buffer operations (duplicate, sync, link, close)
            %   8. Adds listener for ``DatasetsPanelUpdate`` events from model
            %
            % **Supported buffer operations:**
            %   - ``'duplicate'`` — duplicate selected buffer
            %   - ``'sync_xy'`` — synchronize XY dimensions across buffers
            %   - ``'sync_xyz'`` — synchronize XYZ dimensions across buffers
            %   - ``'sync_xyzt'`` — synchronize all dimensions and time across buffers
            %   - ``'link_views'`` — link view state across buffers
            %   - ``'close'`` — close selected buffer
            %   - ``'closeSet'`` — close entire dataset set
            %
            % See also:
            %   ``buffers_Callback``, ``setsOps_Callbacks``, ``buffers_ContextMenu``, ``update_fromModel``
            %
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the panel (views.components.Datasets)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.activeDataset.handles ...)
            obj.mibModel = model;               % handle to the main MIB model
            obj.UIFigure = ancestor(obj.gui, 'figure');  % handle to underlying UIFigure

            %% Update widgets
            obj.update_fromModel(); % update widgets of the Datasets panel from the values of obj.MibModel

            %%  Add CALLBACKS to context menus ----------------------
            %% ---------------------- Add context menu for the Buffer buttons ----------------------
            % obj.handles.datasets
            obj.handles.buffersContextDuplicate.MenuSelectedFcn  = @(src,evtData) obj.buffers_ContextMenu('duplicate',   str2double(evtData.ContextObject.Text));
            obj.handles.buffersContextSyncXY.MenuSelectedFcn     = @(src,evtData) obj.buffers_ContextMenu('sync_xy',     str2double(evtData.ContextObject.Text));
            obj.handles.buffersContextSyncXYZ.MenuSelectedFcn    = @(src,evtData) obj.buffers_ContextMenu('sync_xyz',    str2double(evtData.ContextObject.Text));
            obj.handles.buffersContextSyncXYZT.MenuSelectedFcn   = @(src,evtData) obj.buffers_ContextMenu('sync_xyzt',   str2double(evtData.ContextObject.Text));
            obj.handles.buffersContextLink.MenuSelectedFcn       = @(src,evtData) obj.buffers_ContextMenu('link_views',  str2double(evtData.ContextObject.Text));
            obj.handles.buffersContextClose.MenuSelectedFcn      = @(src,evtData) obj.buffers_ContextMenu('close',       str2double(evtData.ContextObject.Text));
            obj.handles.buffersContextCloseSet.MenuSelectedFcn   = @(src,evtData) obj.buffers_ContextMenu('closeSet',    str2double(evtData.ContextObject.Text));
            
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
            obj.handles.datasetType.ValueChangedFcn = @obj.datasetTypeChange_Callback;

            % ---------------------- Key press callback ----------------------
            obj.UIFigure.WindowKeyPressFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);

            %% Add listeners
            obj.listeners{1} = addlistener(obj.mibModel, 'DatasetsPanelUpdate', @(src, evnt) obj.update_fromModel(src, evnt)); % update GUI from the model

        end
    end
end
