classdef MibStatusBar
% MIBSTATUSBAR - controller for methods of the Selection and View settings panel in MIB.
%

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the ROI panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
        listeners       % cell array of listeners
    end

    methods
        % % declaration of functions in the external files, keep empty line in between for the doc generator
        % 
        listener_updateStatusBar(obj, src, evtData) % Call for update of the status bar widgets, used upon change of directory in Batch Processing executed upon catch of MibModel->"UpdateStatusBar" event
        gui_Callbacks(obj, mode) % callbacks for widgets of some the Status bar obj.handles.status
        zoomEdit_Callback(obj, recenterSwitch, BatchOptIn)       % Callback for the mibZoomEdit control to change image magnification
        updatePyramidInfoLabel(obj)  % Update infoLabel with pyramid level info for BigData/Virtual datasets

        function obj = MibStatusBar(mainCtrl, view, guiHandles, model)
            % MIBSTATUSBAR - Initialize status bar controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = MibStatusBar(mainCtrl, view, guiHandles, model)
            %
            % Input Arguments:
            %   - **mainCtrl** - [controllers.MibController] handle to main MIB controller
            %   - **view** - [views.MibView] handle to main MIB view
            %   - **guiHandles** - [struct] GUI component handles for the status bar
            %   - **model** - [models.MibModel] handle to MIB model
            %
            % Output Arguments:
            %   - **obj** - [MibStatusBar] initialized status bar controller instance
            %
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the panel (views.components.Roi)
            obj.handles = guiHandles;   % handles for the panel (equal to obj.view.handles.panels.roi.handles ...)
            obj.mibModel = model;               % handle to the main MIB model

            % update widgets
            obj.handles.currentDirectory.Value = obj.mibModel.currentDirectory; % update path in MIB status bar

            % ---------------------- Add CALLBACKS to context menus ----------------------
            obj.handles.selectWorkingDirectory.ButtonPushedFcn = @(~,~)obj.gui_Callbacks('selectWorkingDirectory');
            obj.handles.currentDirectory.ValueChangedFcn = @(~,~)obj.gui_Callbacks('currentDirectory');
            obj.handles.copyPath.ButtonPushedFcn = @(~,~)obj.gui_Callbacks('copyPath');
            obj.handles.openBrowser.ButtonPushedFcn = @(~,~)obj.gui_Callbacks('openBrowser');
            obj.handles.zoom.ValueChangedFcn = @(~,~)obj.gui_Callbacks('zoom');

            %% Add listeners
            obj.listeners{1} = addlistener(obj.mibModel, 'UpdateStatusBar', @obj.listener_updateStatusBar); % update the status bar

        end
    end
end
