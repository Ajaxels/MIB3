classdef MibRoi < handle
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
        drawingROI      % struct tracking an in-progress interactive ROI:
        %   .active       - logical, true while a draw tool is waiting for user input
        %   .roi          - handle to the drawrectangle/drawellipse/drawpolygon/drawfreehand object
        %   .type         - char: 'Rectangle','Ellipse','Polyline','Lasso'
        %   .dataPos      - data-pixel coords (updated on MovingROI; used by repositionDrawingROI)
        %   .repositioning - logical guard to prevent re-entry during programmatic repositioning
        %   .placementMode    - logical, true during custom Polyline Stage 1 vertex collection
        %   .placementVertices - [Nx2 double] data-pixel vertices collected during custom placement
        %   .placementLine    - handle to line object visualizing polygon outline during placement
        %   .rubberBandLine   - handle to line object connecting last vertex to current cursor
        %   .previewPatch     - handle to semi-transparent patch filling the preview polygon
    end



    methods
        % % ------------------------- declaration of listeners

        listener_updatePanelPosition(obj, src, evtData)        % redraw the panel based on its position within the main GUI
        % ------------------------- declaration of functions in the external files, 
        gui_Callbacks(obj, hWidget, hData) % callbacks for widgets of some the ROI panel obj.view.handles.panels.roi
        addROI(obj) % interactively add a new ROI or create one from manual coordinates
        removeROI(obj) % remove selected ROI(s) from the current dataset
        refreshROIList(obj, previousValue) % rebuild the ROI list-box items from current hROI.Data
        repositionDrawingROI(obj) % reposition the active drawing tool after zoom/pan changes the axes coordinate system
        updatePlacementLine(obj, axH)  % update polygon outline during custom Polyline placement
        roiModify(obj) % interactively modify (redraw) an existing ROI in-place
        roiSave(obj) % save ROIs of the current dataset to a .roi (MAT) file
        roiLoad(obj) % load ROIs from a .roi (MAT) file into the current dataset
        roiToSelection(obj) % rasterise selected ROI(s) into the Selection layer

        function obj = MibRoi(mainCtrl, view, guiHandles, model)
            % MIBROI - Initialize ROI panel controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = MibRoi(mainCtrl, view, guiHandles, model)
            %
            % Input Arguments:
            %   - **mainCtrl** — [controllers.MibController] handle to main MIB controller
            %   - **view** — [views.MibView] handle to main MIB view
            %   - **guiHandles** — [struct] GUI component handles for the ROI panel
            %   - **model** — [models.MibModel] handle to MIB model
            %
            % Output Arguments:
            %   - **obj** — [MibRoi] initialized ROI panel controller instance
            %
            obj.mibController = mainCtrl;       % handle to the main MIB controller
            obj.view = view;                    % handle to the main MIB view
            obj.gui = guiHandles;               % handle to the GUI of the ROI panel (views.components.Roi)
            obj.handles = guiHandles.handles;   % handles for the panel (equal to obj.view.handles.panels.roi.handles ...)
            obj.mibModel = model;               % handle to the main MIB model
            obj.UIFigure = ancestor(obj.gui, 'figure');  % handle to underlying UIFigure
            obj.drawingROI = struct('active', false, 'roi', [], 'type', '', 'dataPos', [], ...
                'repositioning', false, 'placementMode', false, ...
                'placementVertices', [], 'placementLine', [], 'rubberBandLine', [], 'previewPatch', []);

            % ---------------------- Add CALLBACKS to widgets ----------------------
            % example call using lambda functions
            % obj.handles.handleName.ButtonPushedFcn = @(src, event)obj.gui_Callbacks(src, event, customParameter);

            obj.handles.roiOptions.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.roiList.ValueChangedFcn = @obj.gui_Callbacks;
            obj.handles.roiLoad.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.roiSave.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.roiAdd.ButtonPushedFcn = @obj.gui_Callbacks;
            obj.handles.roiModify.ButtonPushedFcn = @obj.gui_Callbacks;
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

            %% Add listeners
            obj.listeners{1} = addlistener(obj.view.handles.panels.roiPanel, 'PropertyChanged', @obj.listener_updatePanelPosition); % redraw the panel when Region property gets changed

            %% ---------------------- Key press callback ----------------------
            obj.UIFigure.WindowKeyPressFcn   = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);
            obj.UIFigure.WindowKeyReleaseFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyReleaseFcn(hWidget, hData);

        end
        
    end
end
