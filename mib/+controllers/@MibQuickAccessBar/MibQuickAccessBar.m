classdef MibQuickAccessBar
    % classdef MibQuickAccessBar
    % controller for methods of the Quick access bar in MIB

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
        listeners       % cell array of listeners
    end

    methods

        gui_Callbacks(obj, hWidget, hData) % callbacks for widgets of the quick access bar of MIB

        function obj = MibQuickAccessBar(mainCtrl, view, guiHandles, model)
            %% Init properties
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the panel (views.components.Segmentation)
            obj.handles = guiHandles;   % handles for the panel (equal to obj.view.handles.panels.segmentation.handles ...)
            obj.mibModel = model;               % handle to the main MIB model

            %% ---------------------- ADD CALLBACKS TO BUTTONS ----------------------
            obj.handles.help.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.camera.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.saveModel.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.blockMode.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiMode.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.target.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.measurements.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.xz_orientation.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.yz_orientation.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.yx_orientation.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.fastpan.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.zoomOut.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.zoomFit.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.zoom100.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.zoomIn.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.redo.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.undo.ButtonPushedFcn = @obj.gui_Callbacks;

        end
    end
end

