classdef MibStatusBar
    % classdef MibStatusBar
    % controller for methods of the Selection and View settings panel in MIB

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the ROI panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator

        gui_Callbacks(obj, mode) % callbacks for widgets of some the Status bar obj.handles.status

        function obj = MibStatusBar(mainCtrl, view, guiHandles, model)
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
        end
    end
end