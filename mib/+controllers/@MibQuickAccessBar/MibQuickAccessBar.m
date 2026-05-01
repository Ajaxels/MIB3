classdef MibQuickAccessBar
% MIBQUICKACCESSBAR - controller for methods of the Quick access bar in MIB.
%

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        handles         % struct of QAB panel handles (panel, listbox, buttons, ...)
        listeners       % cell array of listeners
    end

    methods

        % createCentralMarker(obj, centerX, centerY, options)        % create a central marker on the image axes
        % 
        % gui_Callbacks(obj, hWidget, hData) % callbacks for widgets of the quick access bar of MIB
        % 
        % orientationChange(obj, hWidget, moveMouseSw)  % switch viewing plane to YX/XZ/YZ orientation

        function obj = MibQuickAccessBar(mainCtrl, view, guiHandles, model)
            % MIBQUICKACCESSBAR - Initialize Quick Access Bar controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = MibQuickAccessBar(mainCtrl, view, guiHandles, model)
            %
            % Input Arguments:
            %   - **mainCtrl** — [controllers.MibController] handle to main MIB controller
            %   - **view** — [views.MibView] handle to main MIB view
            %   - **guiHandles** — [struct] GUI component handles for the Quick Access Bar
            %   - **model** — [models.MibModel] handle to MIB model
            %
            % Output Arguments:
            %   - **obj** — [MibQuickAccessBar] initialized Quick Access Bar controller instance
            %
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.handles = guiHandles;           % handles for the panel (equal to obj.view.handles.qab.handles ...)
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

