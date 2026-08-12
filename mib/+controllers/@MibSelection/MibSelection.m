classdef MibSelection
% MIBSELECTION - controller for methods of the Selection and View settings panel in MIB.
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
        % % declaration of listeners
        % 
        listners_Callbacks(obj, src, evtData) % Generic callback on getting listeners events
        listener_updatePanelPosition(obj, src, evtData)        % Listener callback: adapt the Selection panel grid layout when the panel is docked to a new region of the AppContainer (bottom, left, or right).
        % declaration of functions in the external files, keep empty line in between for the doc generator
        gui_Callbacks(obj, hWidget, hData) % callbacks for widgets of some the ROI panel obj.view.handles.panels.roi
        clearSelection(obj)        % Clear the Selection layer; scope set by modifier keys (no/Shift/Alt/Alt+Shift → 2D/3D/3D/4D)
        dilateSelection(obj)       % Dilate (expand) the Selection layer; reads strel, Apply-in-3D, Difference from panel + modifier keys
        erodeSelection(obj)        % Erode (shrink) the Selection layer; reads strel, Apply-in-3D, Difference from panel + modifier keys
        fillSelection(obj)         % Fill holes in the Selection layer; scope set by modifier keys
        selectionActions(obj, action)  % Add / Subtract / Replace selection to/from the active material or mask; delegates to MibModel.moveLayers
        lutTable_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of the LUT table widget (obj.view.handles.panels.selection.handles.lutTable)
        lutTable_CellEditCallback(obj, hWidget, hData, keyModifier)        % callbacks for cell edit in the LUT table (obj.view.handles.panels.selection.handles.lutTable) of the Selection and Image View panel
        lutTable_CellSelection(obj, hWidget, hData)        % callbacks for cell selection in the LUT table (obj.view.handles.panels.selection.handles.lutTable) of the Selection and Image View panel
        lutTable_update_fromModel(obj)        % Update obj.view.handles.panels.selection.handles.lutTable table and obj.view.handles.panels.selection.handles.colChannel color dropdown from obj.mibModel
        selectionPanelCheckboxes(obj, BatchOptIn)        % batch-compatible method to read or modify the state of checkboxes and the colour-channel dropdown of the Selection and View Settings panel
        updateSegmentationPreset(obj, presetId)        % update preset from the current settings of the selected segmentation tool; callback on Shift+click of preset buttons or Shift+1/2/3 shortcuts
        updateSettingsFromPreset(obj, presetId)        % update settings of the selected segmentation tool from a stored preset; callback on click of preset buttons or 1/2/3 shortcuts

        function obj = MibSelection(mainCtrl, view, guiHandles, model)
            % MIBSELECTION - Initialize Selection panel controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = MibSelection(mainCtrl, view, guiHandles, model)
            %
            % Input Arguments:
            %   - **mainCtrl** - [controllers.MibController] handle to main MIB controller
            %   - **view** - [views.MibView] handle to main MIB view
            %   - **guiHandles** - [struct] GUI component handles for the Selection panel
            %   - **model** - [models.MibModel] handle to MIB model
            %
            % Output Arguments:
            %   - **obj** - [MibSelection] initialized Selection panel controller instance
            %
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the panel (views.components.Roi)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.roi.handles ...)
            obj.mibModel = model;               % handle to the main MIB model
            obj.UIFigure = ancestor(obj.gui, 'figure');  % handle to underlying UIFigure

            %% Update widgets
            obj.lutTable_update_fromModel(); % update the LUT table in the Selection and View settings panel

            %% ---------------------- Add CALLBACKS to context menus ----------------------
            obj.handles.lutTableContextInsert.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextCopy.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextInvert.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextRotate.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextShift.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextSwap.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextDelete.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextSetLUT.MenuSelectedFcn = @obj.lutTable_ContextMenu;

            %% ---------------------- Add CALLBACKS to widgets ----------------------
            % example call using lambda functions
            % obj.handles.handleName.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event, customParameter);

            obj.handles.add.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.subtract.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.replace.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.clear.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.fill.ButtonPushedFcn = @obj.gui_Callbacks;

            obj.handles.colChannel.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.applySegmentationIn3D.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.autoFillSelection.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.preset1.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.preset2.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.preset3.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.erode.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.dilate.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.strel.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.differenceSelection.ValueChangedFcn = @obj.gui_Callbacks;

            obj.handles.lutColors.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.showModel.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.showMask.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.showAnnotations.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.hideImage.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.display.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.onFly.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.help.ButtonPushedFcn = @obj.gui_Callbacks;

            obj.handles.modelTransparency.ValueChangingFcn = @obj.gui_Callbacks;
            obj.handles.maskTransparency.ValueChangingFcn = @obj.gui_Callbacks;
            obj.handles.selectionTransparency.ValueChangingFcn = @obj.gui_Callbacks;

            obj.handles.lutTable.CellSelectionCallback = @obj.lutTable_CellSelection;
            obj.handles.lutTable.CellEditCallback = @(src, event)obj.lutTable_CellEditCallback(src, event);

            %% Add listeners
            obj.listeners{1} = addlistener(obj.view.handles.panels.selectionPanel, 'PropertyChanged', @obj.listener_updatePanelPosition); % redraw the panel when Region property gets changed
            %obj.listeners{2} = addlistener(obj.mibModel, 'ShowMask', @(s,e) obj.ViewListner_Callback(obj, s, e));  % check the Show Mask 
            obj.listeners{2} = addlistener(obj.mibModel, 'ShowMask', @obj.listners_Callbacks);  % check the Show Mask 
            
            %% ---------------------- Key press callback ----------------------
            obj.UIFigure.WindowKeyPressFcn   = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);
            obj.UIFigure.WindowKeyReleaseFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyReleaseFcn(hWidget, hData);
        end



     
    end
end
