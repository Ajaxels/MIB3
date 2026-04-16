classdef MibSegmentation
    % classdef MibSegmentation
    % controller for methods of the Segmentation panel in MIB

    properties
        mibController   % controllers.MibController
        view            % MibView (full app view)
        mibModel        % models.MibModel
        gui             % handle to the GUI of the ROI panel (views.components.Roi)
        handles         % struct of ROI panel handles (panel, listbox, buttons, ...)
        listeners       % cell array of listeners
        UIFigure        % handle to underlying UIFigure
        thresholdSliderStep = 1     % step for threshold slider context menu (Default/Set step...)
    end

    methods

        % ------------------ declaration of listeners

        listener_updatePanelPosition(obj, src, evtData) % Listener callback: adapt the Segmentation panel grid layout when the panel is docked to a new region of the AppContainer (bottom, left, or right).

        % ------------------ declaration of other methods and callbacks

        annotationsPanel_Callback(obj, hWidget, hData)        % callbacks for widgets in the Segmentation panel->Annotations tool

        brushPanel_Callback(obj, hWidget, hData, mode)        % callbacks for widgets in the Segmentation panel->Brush/3D ball/Spot tool

        colorWheel_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of the color wheel button (obj.view.handles.panels.segmentation.handles.colorWheel)

        dragPanel_Callback(obj, hWidget, hData)        % callbacks for widgets in the Segmentation panel->Drag-and-drop materials tool

        favTool_Callback(obj, hWidget, hData)        % callbacks for press of obj.handles.panels.segmentation.handles.favoriteTool in obj.handles.panels.segmentation panel
        
        gui_Callbacks(obj, hWidget, hData)        % callbacks for widgets of some the Segmentation panel obj.handles.panels.segmentation

        lassoPanel_Callback(obj, hWidget, hData)        % callbacks for widgets in the Segmentation panel->Lasso/Object picker tools
        
        lines3DPanel_Callback(obj, hWidget, hData)        % callbacks for widgets in the Segmentation panel->3D lines tool
        
        magicwandPanel_Callback(obj, hWidget, hData)        % callbacks for widgets in the Segmentation panel->Magicwand tool

        materialsTable_applyRowStyle(obj, rowIndex, isHighlighted, columnIndex, fontColor, highlightColor)       % apply highlighting style to material row
        
        materialsTable_CellSelectionCallback(obj, cellIndices)        % handle cell selection in materials table (obj.handles.materialsTable)
        
        materialsTable_ContextMenu(obj, menuEntry, selectedData)    % callbacks for the context menu of the segmentation table widget (obj.handles.panels.segmentation.handles.materialsTable)

        materialsTable_Materials_ContextMenu(obj, menuEntry, selectedData)      % callbacks for the context menu of 
                                                                                % - Segmentation table widget -> Materials...  entry (obj.view.handles.panels.segmentation.handles.materialsTableContextMat)
                                                                                % - Menu ribbon -> Models -> Materials (obj.view.handles.model.materials)

        materialsTable_moveLayers(obj, obj_type_from, obj_type_to, layers_id, action_type)  % callbacks for the context menu of the segmentation table to move layers
        
        materialsTable_render(obj, menuEntry, selectedData)  % callbacks for the context menu of the Segmentation table widget -> Render...  entry (obj.view.handles.panels.segmentation.handles.materialsTableContextRen)

        membranePanel_Callback(obj, hWidget, hData)        % callbacks for widgets in the Segmentation panel->Membrane click tracker tool

        restrictMask_Callback(obj)        % callbacks for press of obj.handles.panels.segmentation.handles.restrictMask in obj.handles.panels.segmentation panel. Restrict selection to the mask layer
        
        restrictMaterial_Callback(obj, hWidget, hData)        % callbacks for press of obj.handles.panels.segmentation.handles.restrictMaterial in obj.handles.panels.segmentation panel

        samPanel_Callback(obj, hWidget, hData)        % callbacks for widgets in the Segmentation panel->SAM tool

        segmentationTool_Callback(obj, segmToolIndex)        % callbacks for press of obj.handles.panels.segmentation.handles.segmTool dropdown in obj.handles.panels.segmentation panel

        thresholdingPanel_Callback(obj, hWidget, hData)        % callbacks for widgets in the Segmentation panel->Black and white thresholding tool

        thresholdSlider_ContextMenu(obj, menuEntry, selectedData)        % context menu callbacks for threshold sliders (Default, Set step...)

        update_fromModel(obj)            % update widgets of the Segmentation panel from obj.mibModel

        updateInterpolationSettings(obj) % show dialog to modify selection interpolation settings for the brush tool
        
        updateMaterialsTable(obj, position)                 % update the segmentation table from model

        updateSamSettings(obj)        % Open SAM settings dialog for configuring SAM1 or SAM2 parameters

        function obj = MibSegmentation(mainCtrl, view, guiHandles, model)
            %% Init properties
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the panel (views.components.Segmentation)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.segmentation.handles ...)
            obj.mibModel = model;               % handle to the main MIB model
            obj.UIFigure = ancestor(obj.gui, 'figure');  % handle to underlying UIFigure
            
            %% Update widgets
            % define the last selection for each of the lasso/object picker types
            obj.handles.lassoType.UserData.lassoTypeIndex = 1;
            obj.handles.lassoMode.UserData.lassoModeIndex = 1;
            obj.handles.lassoType.UserData.objectPickerTypeIndex = 1;
            obj.handles.lassoMode.UserData.objectPickerModeIndex = 1;

            obj.update_fromModel(); % update widgets of the Segmentation panel
            % render the table
            obj.updateMaterialsTable();

            

            %%  Add CALLBACKS to context menus ----------------------
            %% ---------------------- Color wheel button ----------------------
            % first section
            obj.handles.colorWheelContextSchemeDef.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeDist.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeRandom.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeSwap.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            % Qualitative section
            obj.handles.colorWheelContextSchemeQMC.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            % Diverging section
            obj.handles.colorWheelContextSchemeDDD.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeDRK.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeDBG.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeDCB.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            % Sequential section
            obj.handles.colorWheelContextSchemeSKG.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeSCB.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeSM.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeSAB.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeSD.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            % MATLAB section
            obj.handles.colorWheelContextSchemeMJ.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeMH.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            % The bottom section
            obj.handles.colorWheelContextSchemeSetDef.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            obj.handles.colorWheelContextSchemeUpdate.MenuSelectedFcn = @obj.colorWheel_ContextMenu;
            
            %% ---------------------- materialsTable ----------------------
            % first section
            obj.handles.materialsTableContextShowSelected.MenuSelectedFcn = @obj.materialsTable_ContextMenu;
            obj.handles.materialsTableContextRename.MenuSelectedFcn = @obj.materialsTable_ContextMenu;
            obj.handles.materialsTableContextSetColor.MenuSelectedFcn = @obj.materialsTable_ContextMenu;
            obj.handles.materialsTableContextQuant.MenuSelectedFcn = @obj.materialsTable_ContextMenu;
            % Materials section
            obj.handles.materialsTableContextMatRename.MenuSelectedFcn = @obj.materialsTable_Materials_ContextMenu;
            obj.handles.materialsTableContextMatAdd.MenuSelectedFcn = @obj.materialsTable_Materials_ContextMenu;
            obj.handles.materialsTableContextMatInsert.MenuSelectedFcn = @obj.materialsTable_Materials_ContextMenu;
            obj.handles.materialsTableContextMatSwap.MenuSelectedFcn = @obj.materialsTable_Materials_ContextMenu;
            obj.handles.materialsTableContextMatReorder.MenuSelectedFcn = @obj.materialsTable_Materials_ContextMenu;
            obj.handles.materialsTableContextMatExport.MenuSelectedFcn = @obj.materialsTable_Materials_ContextMenu;
            obj.handles.materialsTableContextMatSave.MenuSelectedFcn = @obj.materialsTable_Materials_ContextMenu;
            obj.handles.materialsTableContextMatRemove.MenuSelectedFcn = @obj.materialsTable_Materials_ContextMenu;
            % Material to Selection...
            obj.handles.materialsTableContextM2SN2D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'selection', '2D, Slice', 'replace');
            obj.handles.materialsTableContextM2SA2D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'selection', '2D, Slice', 'add');
            obj.handles.materialsTableContextM2SS2D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'selection', '2D, Slice', 'remove');
            obj.handles.materialsTableContextM2SN3D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'selection', '3D, Stack', 'replace');
            obj.handles.materialsTableContextM2SA3D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'selection', '3D, Stack', 'add');
            obj.handles.materialsTableContextM2SS3D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'selection', '3D, Stack', 'remove');
            obj.handles.materialsTableContextM2SN4D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'selection', '4D, Dataset', 'replace');
            obj.handles.materialsTableContextM2SA4D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'selection', '4D, Dataset', 'add');
            obj.handles.materialsTableContextM2SS4D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'selection', '4D, Dataset', 'remove');
            % Material to Mask...
            obj.handles.materialsTableContextM2MN2D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'mask', '2D, Slice', 'replace');
            obj.handles.materialsTableContextM2MA2D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'mask', '2D, Slice', 'add');
            obj.handles.materialsTableContextM2MS2D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'mask', '2D, Slice', 'remove');
            obj.handles.materialsTableContextM2MN3D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'mask', '3D, Stack', 'replace');
            obj.handles.materialsTableContextM2MA3D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'mask', '3D, Stack', 'add');
            obj.handles.materialsTableContextM2MS3D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'mask', '3D, Stack', 'remove');
            obj.handles.materialsTableContextM2MN4D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'mask', '4D, Dataset', 'replace');
            obj.handles.materialsTableContextM2MA4D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'mask', '4D, Dataset', 'add');
            obj.handles.materialsTableContextM2MS4D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('labels', 'mask', '4D, Dataset', 'remove');
            % Mask to Material...
            obj.handles.materialsTableContextM2M2N2D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('mask', 'labels', '2D, Slice', 'replace');
            obj.handles.materialsTableContextM2M2A2D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('mask', 'labels', '2D, Slice', 'add');
            obj.handles.materialsTableContextM2M2S2D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('mask', 'labels', '2D, Slice', 'remove');
            obj.handles.materialsTableContextM2M2N3D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('mask', 'labels', '3D, Stack', 'replace');
            obj.handles.materialsTableContextM2M2A3D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('mask', 'labels', '3D, Stack', 'add');
            obj.handles.materialsTableContextM2M2S3D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('mask', 'labels', '3D, Stack', 'remove');
            obj.handles.materialsTableContextM2M2N4D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('mask', 'labels', '4D, Dataset', 'replace');
            obj.handles.materialsTableContextM2M2A4D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('mask', 'labels', '4D, Dataset', 'add');
            obj.handles.materialsTableContextM2M2S4D.MenuSelectedFcn = @(~,~)obj.materialsTable_moveLayers('mask', 'labels', '4D, Dataset', 'remove');
            % Render...
            obj.handles.materialsTableContextRenMIB.MenuSelectedFcn = @obj.materialsTable_render;
            obj.handles.materialsTableContextRenMat.MenuSelectedFcn = @obj.materialsTable_render;
            obj.handles.materialsTableContextRenFiji.MenuSelectedFcn = @obj.materialsTable_render;
            % Bottom section
            obj.handles.materialsTableContextUnlink.MenuSelectedFcn = @obj.materialsTable_ContextMenu;

            %% ---------------------- Add listeners
            obj.listeners{1} = addlistener(obj.view.handles.panels.segmentationPanel, 'PropertyChanged', @obj.listener_updatePanelPosition); % redraw the panel when Region property gets changed

            %% ---------------------- Add CALLBACKS to widgets ----------------------
            obj.handles.createModel.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.loadModel.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.addMaterial.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.removeMaterial.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.colorWheel.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.materialsTable.CellSelectionCallback = @(~,~)obj.materialsTable_CellSelectionCallback();
            obj.handles.viewSettings.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.help.ButtonPushedFcn = @(src, event)obj.mibController.helpButtons_Callback(src, event);

            obj.handles.restrictMaterial.ValueChangedFcn = @(~,~)obj.restrictMaterial_Callback;
            obj.handles.restrictMask.ValueChangedFcn = @(~,~)obj.restrictMask_Callback;
            obj.handles.favoriteTool.ValueChangedFcn = @obj.favTool_Callback;

            obj.handles.segmTool.ValueChangedFcn = @(~,~)obj.segmentationTool_Callback;

            %% ---------------------- Key press callback ----------------------
            obj.UIFigure.WindowKeyPressFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);

            %% 3D ball, brush, spot panels
            obj.handles.brushRadius.ValueChangedFcn = @obj.brushPanel_Callback;
            obj.handles.eraserFactor.ValueChangedFcn = @obj.brushPanel_Callback;
            obj.handles.interpolationSettings.ButtonPushedFcn = @obj.brushPanel_Callback;
            obj.handles.brushUseClustering.SelectionChangedFcn = @obj.brushPanel_Callback;
            obj.handles.clustersPar1.ValueChangedFcn = @obj.brushPanel_Callback;
            obj.handles.clustersPar2.ValueChangedFcn = @obj.brushPanel_Callback;

            %% 3D lines panel
            obj.handles.linesTableView.ButtonPushedFcn = @obj.lines3DPanel_Callback;
            obj.handles.linesShowLines.ValueChangedFcn = @obj.lines3DPanel_Callback;
            obj.handles.linesClick.ValueChangedFcn = @obj.lines3DPanel_Callback;
            obj.handles.linesShiftClick.ValueChangedFcn = @obj.lines3DPanel_Callback;
            obj.handles.linesCtrlClick.ValueChangedFcn = @obj.lines3DPanel_Callback;
            obj.handles.linesAltClick.ValueChangedFcn = @obj.lines3DPanel_Callback;

            %% Annotations panel
            obj.handles.annAnnotationList.ButtonPushedFcn = @obj.annotationsPanel_Callback;
            obj.handles.annShowPrompt.ValueChangedFcn = @obj.annotationsPanel_Callback;
            obj.handles.annFocusOnValue.ValueChangedFcn = @obj.annotationsPanel_Callback;
            obj.handles.annPrecision.ValueChangedFcn = @obj.annotationsPanel_Callback;
            obj.handles.annDeleteAll.ButtonPushedFcn = @obj.annotationsPanel_Callback;
            obj.handles.annDisplayAs.ValueChangedFcn = @obj.annotationsPanel_Callback;

            %% Black and white thresholding
            obj.handles.thresholdAdaptive.ValueChangedFcn = @obj.thresholdingPanel_Callback;
            obj.handles.thresholdType.ValueChangedFcn = @obj.thresholdingPanel_Callback;
            obj.handles.thresholdInvert.ValueChangedFcn = @obj.thresholdingPanel_Callback;
            obj.handles.threshold3D.ValueChangedFcn = @obj.thresholdingPanel_Callback;
            obj.handles.threshold4D.ValueChangedFcn = @obj.thresholdingPanel_Callback;
            obj.handles.thresholdLow.ValueChangingFcn = @obj.thresholdingPanel_Callback;
            obj.handles.thresholdHigh.ValueChangingFcn = @obj.thresholdingPanel_Callback;
            obj.handles.thresholdLowValue.ValueChangedFcn = @obj.thresholdingPanel_Callback;
            obj.handles.thresholdHighValue.ValueChangedFcn = @obj.thresholdingPanel_Callback;
            obj.handles.threshold.ButtonPushedFcn = @obj.thresholdingPanel_Callback;
            % Threshold slider context menus
            obj.handles.thresholdSliderContextDefault.MenuSelectedFcn = @obj.thresholdSlider_ContextMenu;
            obj.handles.thresholdSliderContextSetStep.MenuSelectedFcn = @obj.thresholdSlider_ContextMenu;

            %% Drag and drop objects panel
            obj.handles.dragLayer.ValueChangedFcn = @obj.dragPanel_Callback;
            obj.handles.dragValue.ValueChangedFcn = @obj.dragPanel_Callback;
            obj.handles.dragUp.ButtonPushedFcn = @obj.dragPanel_Callback;
            obj.handles.dragRight.ButtonPushedFcn = @obj.dragPanel_Callback;
            obj.handles.dragLeft.ButtonPushedFcn = @obj.dragPanel_Callback;
            obj.handles.dragDown.ButtonPushedFcn = @obj.dragPanel_Callback;

            %% Lasso and object picker
            obj.handles.lassoType.ValueChangedFcn = @obj.lassoPanel_Callback;
            obj.handles.lassoMode.ValueChangedFcn = @obj.lassoPanel_Callback;
            obj.handles.lassoManually.ValueChangedFcn = @obj.lassoPanel_Callback;
            obj.handles.lassoSelect.ButtonPushedFcn = @obj.lassoPanel_Callback;
            obj.handles.lassoX1.ValueChangedFcn = @obj.lassoPanel_Callback;
            obj.handles.lassoY1.ValueChangedFcn = @obj.lassoPanel_Callback;
            obj.handles.lassoWidth.ValueChangedFcn = @obj.lassoPanel_Callback;
            obj.handles.lassoHeight.ValueChangedFcn = @obj.lassoPanel_Callback;
            obj.handles.objectRecalculate.ButtonPushedFcn = @obj.lassoPanel_Callback;

            %% Magic wand panel
            obj.handles.magicMethod.ValueChangedFcn = @obj.magicwandPanel_Callback;
            obj.handles.magicRange1.ValueChangedFcn = @obj.magicwandPanel_Callback;
            obj.handles.magicRange2.ValueChangedFcn = @obj.magicwandPanel_Callback;
            obj.handles.magicRadius.ValueChangedFcn = @obj.magicwandPanel_Callback;
            obj.handles.magicConnect.SelectionChangedFcn = @obj.magicwandPanel_Callback;

            %% Membrane click tracker
            obj.handles.membraneScale.ValueChangedFcn = @obj.membranePanel_Callback;
            obj.handles.membraneWidth.ValueChangedFcn = @obj.membranePanel_Callback;
            obj.handles.membraneStraightLine.ValueChangedFcn = @obj.membranePanel_Callback;
            obj.handles.membraneBlackSignal.ValueChangedFcn = @obj.membranePanel_Callback;
            obj.handles.membraneRecenterView.ValueChangedFcn = @obj.membranePanel_Callback;

            %% SAM panel
            obj.handles.samMethod.ValueChangedFcn = @obj.samPanel_Callback;
            obj.handles.samVersion.ValueChangedFcn = @obj.samPanel_Callback;
            obj.handles.samDataset.ValueChangedFcn = @obj.samPanel_Callback;
            obj.handles.samDestination.ValueChangedFcn = @obj.samPanel_Callback;
            obj.handles.samMode.ValueChangedFcn = @obj.samPanel_Callback;
            obj.handles.samSettings.ButtonPushedFcn = @obj.samPanel_Callback;
            obj.handles.samList.ButtonPushedFcn = @obj.samPanel_Callback;
            obj.handles.samClear.ButtonPushedFcn = @obj.samPanel_Callback;
            obj.handles.samSegment.ButtonPushedFcn = @obj.samPanel_Callback;


        end
    end
end