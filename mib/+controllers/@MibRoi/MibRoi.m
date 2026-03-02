classdef MibRoi
    % classdef MibRoi
    % controller for methods of the ROI panel in MIB
    
    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the ROI panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
        UIFigure        % handle to underlying UIFigure
    end



    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator

        gui_Callbacks(obj, hWidget, hData) % callbacks for widgets of some the ROI panel obj.view.handles.panels.roi

        function obj = MibRoi(mainCtrl, view, guiHandles, model)
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the ROI panel (views.components.Roi)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.roi.handles ...)
            obj.mibModel = model;               % handle to the main MIB model
            obj.UIFigure = ancestor(obj.gui, 'figure');  % handle to underlying UIFigure
            
            % ---------------------- Add CALLBACKS to widgets ----------------------
            % example call using lambda functions
            % obj.handles.handleName.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event, customParameter);

            obj.handles.roiOptions.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.roiList.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiLoad.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.roiSave.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.roiAdd.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.roiRemove.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.roiType.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiFixAspect.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiShowLabel.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiShowROI.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiManually.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiX1.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiY1.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiWidth.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiHeight.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiToSelection.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.help.ButtonPushedFcn = @(src, event)obj.mibController.helpButtons_Callback(src, event);

            % ---------------------- Key press callback ----------------------
            obj.UIFigure.WindowKeyPressFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);

        end
        
    end
end