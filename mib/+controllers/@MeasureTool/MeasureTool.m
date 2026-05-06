classdef MeasureTool < handle
    % MEASURETOOL - Controller for the interactive Measurement Tool panel.
    %
    % Owns all UX for measurement creation and management:
    % interactive ROI drawing (via ``images.roi.*`` objects), routing to
    % ``core.Measurements`` static helpers for math, measurement table
    % refresh, edit/recalculate flow, kymograph generation, and load/save.
    %
    % The companion view is ``views.MeasureToolGUI.mlapp`` (created by the
    % user with widget tags matching those listed in the plan).
    %
    % **Architecture:**
    %
    % - ``core.Measurements`` — data-only class on the dataset; this controller drives it.
    % - ``controllers.MibController`` — parent; provides ``cImageDoc`` and model.
    % - All interactive drawing lives here, never in ``core.Measurements``.
    %
    % **Launch via** ``utils.startController``::
    %
    %   obj.startController('controllers.MeasureTool', obj)
    %
    % The second argument is the calling ``MibController`` handle, which
    % ``utils.startController`` forwards as ``varargin{1}`` to the constructor.

    properties (SetAccess = public, GetAccess = public)
        mibController
        % handle to controllers.MibController (passed as varargin{1} by startController)
        mibModel
        % handle to models.MibModel
        view
        % handle to views.MeasureToolGUI (set by core.ChildView in constructor)
        listener
        % {1×N cell} listener handles — deleted on close
        indices
        % [N×2] currently selected row indices in measureTable
    end

    events
        CloseEvent
        % fired by closeWindow so utils.purgeChildController can clean up the
        % childControllers / childControllersIds arrays on the parent controller
    end

    methods
        % --- split method signatures ---
        addCallbacks(obj)
        gui_Callbacks(obj, source, event)
        updateWidgets(obj)
        updateTable(obj)
        addMeasurement(obj)
        editMeasurement(obj, datasetId, measurementIndex, colCh, integrationWidth, finetuneCheck, calcIntensity, useFixedZT)
        contextMenu(obj, parameter)
        annotationText = measureAngle(obj, datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
        annotationText = measureCaliper(obj, datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
        annotationText = measureCircle(obj, datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
        annotationText = measureDistance(obj, datasetId, colCh, finetuneCheck, integrationWidth, calcIntensity, insertIndex)
        annotationText = measureDistancePoly(obj, datasetId, colCh, finetuneCheck, calcIntensity, insertIndex)
        annotationText = measureDistanceFree(obj, datasetId, colCh, finetuneCheck, calcIntensity, insertIndex)
        measurePoint(obj, datasetId, colCh, finetuneCheck, calcIntensity, showInfoDlg, insertIndex)
        [pixelX, pixelY, wasCancelled] = drawROI(obj, roiType, finetuneCheck, maxVertices, initialDataPos)
        generateKymograph(obj, datasetId, measurementIndex)
        loadMeasurements(obj)
        saveMeasurements(obj)
        plotIntensityProfile(obj, rowIndex)
        previewIntensityProfile(obj)
        updatePlotSettings(obj)

        function obj = MeasureTool(mibModel, varargin)
            % MEASURETOOL - Constructor for the MeasureTool controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       cTool = controllers.MeasureTool(mibModel, mibController)
            %
            % Follows the ``utils.startController`` contract: first argument is
            % always ``mibModel``; the parent ``MibController`` handle is passed
            % as ``varargin{1}`` by the caller.
            %
            % Input Arguments:
            %   - **mibModel** — handle to :class:`models.MibModel`
            %   - **varargin{1}** — handle to :class:`controllers.MibController`
            %
            % Output Arguments:
            %   - **obj** — instance of :class:`controllers.MeasureTool`
            %
            % Usage:
            %   **Example 1** — launched via ribbon button callback
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.startController('controllers.MeasureTool', obj);
            %

            obj.mibModel = mibModel;
            obj.mibController = varargin{1};
            obj.indices = [];

            obj.view = core.ChildView(obj, 'views.MeasureToolGUI');
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.voxelSizeTxt.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.voxelSizeTxt.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, obj.mibModel.preferences.System.Font);
            end
            utils.moveWindowOutside(obj.view.gui, obj.mibController.view.gui, 'left');
            obj.addCallbacks();

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(source, event) controllers.MeasureTool.ViewListner_Callback2(obj, source, event));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(source, event) controllers.MeasureTool.ViewListner_Callback2(obj, source, event));
            obj.listener{3} = addlistener(obj.mibModel, 'AddMeasurement', @(~, ~) obj.addMeasurement);

            % initialise per-type annotation defaults on first launch; preserve on reopen
            if ~isfield(obj.mibModel.sessionSettings, 'measureTool')
                obj.mibModel.sessionSettings.measureTool.Angle.Info        = '';
                obj.mibModel.sessionSettings.measureTool.Caliper.Info      = '';
                obj.mibModel.sessionSettings.measureTool.Circle.Info       = '';
                obj.mibModel.sessionSettings.measureTool.Distance.Info     = '';
                obj.mibModel.sessionSettings.measureTool.DistancePoly.Info = '';
                obj.mibModel.sessionSettings.measureTool.DistanceFree.Info = '';
                obj.mibModel.sessionSettings.measureTool.Point.Info        = '';
            end

            obj.updateWidgets();

            % add handle tags to tooltips in developer mode
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end
            
            obj.view.gui.Visible = true;

        end

        function closeWindow(obj)
            % CLOSEWINDOW - Close the MeasureTool window and clean up.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.closeWindow()
            %
            % Restores ``disableSegmentation``, deletes listeners, deletes the
            % view, and fires ``CloseEvent`` so ``utils.purgeChildController``
            % removes this entry from the parent's ``childControllers`` array.
            %

            % safety: restore segmentation if it was left disabled
            if obj.mibModel.disableSegmentation; obj.mibModel.disableSegmentation = false; end

            for listenerIdx = 1:numel(obj.listener)
                delete(obj.listener{listenerIdx});
            end
            obj.listener = {};

            if ~isempty(obj.view) && isvalid(obj.view.gui)
                delete(obj.view.gui);
            end

            notify(obj, 'CloseEvent');
        end

    end  % methods

    methods (Static)

        function ViewListner_Callback2(obj, ~, event)
            % VIEWLISTNER_CALLBACK2 - Static model-event relay.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       controllers.MeasureTool.ViewListner_Callback2(obj, src, evt)
            %
            % Discards the listener and returns silently when the controller
            % or its view has been deleted.
            %
            % Input Arguments:
            %   - **obj** — :class:`controllers.MeasureTool` instance
            %   - **event** — model event object
            %

            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for listenerIdx = 1:numel(obj.listener)
                    delete(obj.listener{listenerIdx});
                end
                return;
            end
            switch event.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end

    end  % methods (Static)

end
