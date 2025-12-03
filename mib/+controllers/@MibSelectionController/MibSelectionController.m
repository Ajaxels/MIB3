classdef MibSelectionController
    % classdef MibSelectionController
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

        gui_Callbacks(obj, hWidget, hData) % callbacks for widgets of some the ROI panel obj.view.handles.panels.roi

        lutTable_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of the LUT table widget (obj.view.handles.panels.selection.handles.lutTable)

        lutTable_CellEditCallback(obj, hWidget, hData, keyModifier)        % callbacks for cell edit in the LUT table (obj.view.handles.panels.selection.handles.lutTable) of the Selection and Image View panel

        lutTable_CellSelection(obj, hWidget, hData)        % callbacks for cell selection in the LUT table (obj.view.handles.panels.selection.handles.lutTable) of the Selection and Image View panel

        lutTable_update_fromModel(obj)        % Update obj.view.handles.panels.selection.handles.lutTable table and obj.view.handles.panels.selection.handles.colChannel color dropdown from obj.mibModel

        function obj = MibSelectionController(mainCtrl, view, guiHandles, model)
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the panel (views.components.Roi)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.roi.handles ...)
            obj.mibModel = model;               % handle to the main MIB model

            % ---------------------- Add CALLBACKS to context menus ----------------------
            obj.handles.lutTableContextInsert.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextCopy.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextInvert.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextRotate.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextShift.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextSwap.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextDelete.MenuSelectedFcn = @obj.lutTable_ContextMenu;
            obj.handles.lutTableContextSetLUT.MenuSelectedFcn = @obj.lutTable_ContextMenu;

            % ---------------------- Add CALLBACKS to widgets ----------------------
            % example call using lambda functions
            % obj.handles.handleName.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event, customParameter);

            obj.handles.add.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.subtract.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.replace.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.clear.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.fill.ButtonPushedFcn = @obj.gui_Callbacks;

            obj.handles.colChannel.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.apply3D.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.autoFill.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.preset1.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.preset2.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.preset3.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.erode.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.dilate.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.strel.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.difference.ValueChangedFcn = @obj.gui_Callbacks;

            obj.handles.lutColors.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.showModel.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.showMask.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.showAnnotations.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.hideImage.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.display.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.onFly.ValueChangedFcn = @obj.gui_Callbacks;

            obj.handles.modelTransparency.ValueChangingFcn = @obj.gui_Callbacks;
            obj.handles.maskTransparency.ValueChangingFcn = @obj.gui_Callbacks;
            obj.handles.selectionTransparency.ValueChangingFcn = @obj.gui_Callbacks;

            obj.handles.lutTable.CellSelectionCallback = @obj.lutTable_CellSelection;
            obj.handles.lutTable.CellEditCallback = @obj.lutTable_CellEditCallback;
        end



     
    end
end