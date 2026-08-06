classdef MibFijiConnect < handle
% MIBROI - controller for methods of the ROI panel in MIB.
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
        % % ------------------------- declaration of listeners

        listener_updatePanelPosition(obj, src, evtData)        % redraw the panel based on its position within the main GUI
        exportToFiji(obj) % Export the currently open dataset to Fiji/ImageJ.
        importFromFiji(obj) % Import a dataset from Fiji/ImageJ into MIB.

        % ------------------------- declaration of functions in the external files,
        gui_Callbacks(obj, hWidget, hData) % callbacks for widgets of some the ROI panel obj.view.handles.panels.roi
        runMacro(obj)                       % run a Fiji macro command or a text file of macro commands
        
        function obj = MibFijiConnect(mainCtrl, view, guiHandles, model)
            % MIBROI - Initialize ROI panel controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = MibFijiConnect(mainCtrl, view, guiHandles, model)
            %
            % Input Arguments:
            %   - **mainCtrl** - [controllers.MibController] handle to main MIB controller
            %   - **view** - [views.MibView] handle to main MIB view
            %   - **guiHandles** - [struct] GUI component handles for the ROI panel
            %   - **model** - [models.MibModel] handle to MIB model
            %
            % Output Arguments:
            %   - **obj** - [MibFijiConnect] initialized ROI panel controller instance
            %
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the ROI panel (views.components.Roi)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.roi.handles ...)
            obj.mibModel = model;               % handle to the main MIB model
            obj.UIFigure = ancestor(obj.gui, 'figure');  % handle to underlying UIFigure
            
            % ---------------------- Add CALLBACKS to widgets ----------------------
            % example call using lambda functions
            obj.handles.startFijiButton.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event);
            obj.handles.stopFijiButton.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event);
            obj.handles.exportButton.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event);
            obj.handles.importButton.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event);
            obj.handles.selectFileButton.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event);
            obj.handles.runButton.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event);
            obj.handles.helpButton.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event);

            %% Add listeners
            obj.listeners{1} = addlistener(obj.view.handles.panels.fijiPanel, 'PropertyChanged', @obj.listener_updatePanelPosition); % redraw the panel when Region property gets changed

            %% ---------------------- Key press callback ----------------------
            obj.UIFigure.WindowKeyPressFcn   = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);
            obj.UIFigure.WindowKeyReleaseFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyReleaseFcn(hWidget, hData);

        end
        
    end
end
