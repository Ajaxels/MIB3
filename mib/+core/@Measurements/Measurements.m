classdef Measurements < matlab.mixin.Copyable
    % MEASUREMENTS - Container for measurement data and visualization in MIB3.
    %
    % This class stores all measurement data for a dataset and provides
    % methods for adding, removing, rendering, and coordinate-transforming
    % measurements.  It is **data-only**: it never references a controller,
    % view, or axes-creation logic.  All interactive UX (click acquisition,
    % dialogs, tool activation) is handled by
    % ``controllers.MibMeasureToolController`` (future).
    %
    % **Supported measurement types:**
    %
    % - ``'Point'``               — single labelled point
    % - ``'Distance (linear)'``   — straight-line distance between two points
    % - ``'Distance (polyline)'`` — cumulative arc-length of a polyline
    % - ``'Angle'``               — angle formed by three points (vertex = point 2)
    % - ``'Circle (R)'``          — circle fit to N points; result is radius
    % - ``'Caliper'``             — oriented bounding-box width measurement
    %
    % **Data structure** — each element of ``obj.Data`` struct array contains:
    %
    % - ``.n``              — [double] 1-based index (auto-renumbered on insert/delete)
    % - ``.type``           — [char] measurement type string (see list above)
    % - ``.value``          — [double] numeric result in physical units
    % - ``.X``              — [double vector] data-space pixel X coordinates
    % - ``.Y``              — [double vector] data-space pixel Y coordinates
    % - ``.Z``              — [double] Z slice index when measurement was made
    % - ``.T``              — [double] time-point index when measurement was made
    % - ``.orientation``    — [double] 1 = zx, 2 = zy, 3 = yx (MIB3 values)
    % - ``.spline``         — [struct | []] ppval data for ``'Distance (polyline)'``
    % - ``.circ``           — [struct | []] ``{xc, yc, R}`` for ``'Circle (R)'``
    % - ``.intensity``      — [double vector] mean intensity per colour channel
    % - ``.profile``        — [double matrix] ``[position; intensity_ch1; ...]``
    % - ``.integrateWidth`` — [double | []] integration half-width for ``'Distance (linear)'``
    % - ``.info``           — [char] user annotation / label text
    % - ``.colCh``          — [double] colour channel used when measurement was made
    %
    % Interactive UX (drawing, dialogs, export) belongs to
    % ``controllers.MibMeasureToolController``.

    properties (SetAccess = public, GetAccess = public)
        Data
        % struct array of measurements (one element per measurement).
        % See class header for the complete field list.

        Options
        % display/visualization options struct:
        %   .marker       - char, marker style  (default 'o')
        %   .markersize   - char, marker size   (default '10')
        %   .linestyle    - char, line style    (default '-')
        %   .linewidth    - char, line width    (default '1')
        %   .color        - char, color         (default 'y')
        %   .textcolorfg  - char, text foreground color (default 'y')
        %   .textcolorbg  - char, text background color (default 'none')
        %   .fontsize     - char, font size     (default '14')
        %   .splinemethod - char, spline method (default 'spline')
        %   .showMarkers  - numeric, 0 or 1     (default 1)
        %   .showLines    - numeric, 0 or 1     (default 1)
        %   .showText     - numeric, 0 or 1     (default 1)

        typeToShow
        % char — filter for rendering: 'All' or one of the type strings.
        % Set by the controller before calling addMeasurementsToPlot.

        fixZ
        % logical — when true, Z and T are preserved when a measurement is
        % re-edited; the controller toggles this before calling storeMeasurement.

        mibDataset
        % handle to the parent core.MibDataset instance.
        % Provides: .orientation, .image.pixSize, .image.height/width/depth,
        %           .axesX, .axesY, .blockModeSwitch, .slices.
        % NEVER a controller or view handle.
    end

    methods

        function obj = Measurements(mibDataset)
            % MEASUREMENTS - Constructor for the :class:`Measurements` class.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = core.Measurements(mibDataset)
            %
            % Creates a new instance with default options and empty data.
            % Typically instantiated inside ``core.MibDataset.initialize``
            % and stored as ``obj.measurements``.
            %
            % Input Arguments:
            %   - **mibDataset** — *(optional)* handle to :class:`core.MibDataset`
            %     (the parent dataset that owns this measurement collection).
            %     When omitted the class still works but methods that need
            %     image dimensions require explicit arguments.
            %
            % Output Arguments:
            %   - **obj** — instance of the :class:`core.Measurements` class.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     measurements = core.Measurements(obj);% call from MibDataset.initialize
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     measurements = core.Measurements();% standalone, no dataset reference
            %

            if nargin < 1; mibDataset = []; end
            obj.mibDataset = mibDataset;
            obj.clearContents();
        end

        function clearContents(obj)
            % CLEARCONTENTS - Reset all class properties to default values.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.clearContents()
            %
            % Calls ``setDefaultOptions()``, ``clearData()``, and resets
            % ``fixZ`` to ``false``.
            %
            % Input Arguments:
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.clearContents();
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     clearContents(obj);% call within the class
            %

            obj.setDefaultOptions();
            obj.clearData();
            obj.fixZ = false;
        end

        function clearData(obj)
            % CLEARDATA - Remove all stored measurements, resetting Data to an empty struct.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.clearData()
            %
            % Resets ``obj.Data`` to an empty single-element struct with all
            % required field names initialised to ``[]``.  Also resets
            % ``typeToShow`` to ``'All'`` if it is not already set.
            %
            % Input Arguments:
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.clearData();
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     clearData(obj);% call within the class
            %

            obj.Data = [];
            obj.Data.n              = [];
            obj.Data.type           = [];
            obj.Data.value          = [];
            obj.Data.X              = [];
            obj.Data.Y              = [];
            obj.Data.Z              = [];
            obj.Data.T              = [];
            obj.Data.orientation    = [];
            obj.Data.spline         = [];
            obj.Data.circ           = [];
            obj.Data.intensity      = [];
            obj.Data.profile        = [];
            obj.Data.integrateWidth = [];
            obj.Data.info           = [];
            obj.Data.colCh          = [];

            if isempty(obj.typeToShow)
                obj.typeToShow = 'All';
            end
        end

        function setDefaultOptions(obj)
            % SETDEFAULTOPTIONS - Set all Options fields to their default values.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.setDefaultOptions()
            %
            % Input Arguments:
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.setDefaultOptions();
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     setDefaultOptions(obj);% call within the class
            %

            obj.Options.marker       = 'o';
            obj.Options.markersize   = '10';
            obj.Options.linestyle    = '-';
            obj.Options.linewidth    = '1';
            obj.Options.color        = 'y';
            obj.Options.textcolorfg  = 'y';
            obj.Options.textcolorbg  = 'none';
            obj.Options.fontsize     = '14';
            obj.Options.splinemethod = 'spline';
            obj.Options.showMarkers  = 1;
            obj.Options.showLines    = 1;
            obj.Options.showText     = 1;
        end

        function updateOptions(obj, parentFigure)
            % UPDATEOPTIONS - Show an interactive dialog to update display Options.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateOptions(parentFigure)
            %
            % Opens ``utils.dlgs.inputUniversalDlg`` with the current option
            % values as defaults.  If the user cancels, no changes are made.
            %
            % Input Arguments:
            %   - **parentFigure** — handle to the parent window used for dialog
            %     centering.  Pass ``[]`` for automatic placement.
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.updateOptions(obj.mibController.view.gui);
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.updateOptions([]);
            %

            options = obj.Options;

            prompts = { ...
                'Marker Style:', ...
                'Marker Size:', ...
                'Line Style:', ...
                'Line Width:', ...
                sprintf('Color\n( r  g  b  c  m  y  k  w none)'), ...
                'Text Foreground Color:', ...
                'Text Background Color:', ...
                'Font Size:'};

            colorChoices  = {'r', 'g', 'b', 'c', 'm', 'y', 'k', 'w', 'none'};
            markerChoices = {'+', 'o', '*', '.', 'x', 's', 'd', '^', 'v', '>', '<', 'p', 'h'};
            lineChoices   = {'-', '--', ':', '-.'};

            defAns = { ...
                markerChoices; ...
                options.markersize; ...
                lineChoices; ...
                options.linewidth; ...
                colorChoices; ...
                colorChoices; ...
                colorChoices; ...
                options.fontsize};

            dropdownIndices    = [1, 3, 5, 6, 7];
            dropdownChoices    = {markerChoices, lineChoices, colorChoices, colorChoices, colorChoices};
            dropdownOptionKeys = {'marker', 'linestyle', 'color', 'textcolorfg', 'textcolorbg'};

            for dropdownLoopIdx = 1:numel(dropdownIndices)
                dropdownPosition = dropdownIndices(dropdownLoopIdx);
                selectedValue = options.(dropdownOptionKeys{dropdownLoopIdx});
                defaultIndex  = find(strcmp(dropdownChoices{dropdownLoopIdx}, selectedValue), 1);
                if isempty(defaultIndex); defaultIndex = 1; end
                defAns{dropdownPosition}{end+1} = defaultIndex;
            end

            dlgOptions.WindowHeight = 450;
            answer = utils.dlgs.inputUniversalDlg(parentFigure, '', prompts, defAns, 'Measurement Options', dlgOptions);
            if isempty(answer); return; end

            allFieldNames = {'marker', 'markersize', 'linestyle', 'linewidth', ...
                             'color', 'textcolorfg', 'textcolorbg', 'fontsize'};
            for fieldLoopIdx = 1:numel(allFieldNames)
                obj.Options.(allFieldNames{fieldLoopIdx}) = answer{fieldLoopIdx};
            end
        end

        function storeMeasurement(obj, newData, index)
            % STOREMEASUREMENT - Add or insert a pre-computed measurement struct.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.storeMeasurement(newData)
            %       obj.storeMeasurement(newData, index)
            %
            % If ``index`` is less than or equal to the current number of
            % measurements, the new entry is inserted at that position
            % (existing entries shift forward).  Otherwise the entry is
            % appended.  After any insert all ``.n`` fields are renumbered.
            %
            % Input Arguments:
            %   - **newData** — [struct] single measurement struct whose fields
            %     match those of ``obj.Data``.
            %   - **index** — *(optional)* [double] position at which to store the
            %     measurement.  Default = append after the last entry.
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.storeMeasurement(newData);% append
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.storeMeasurement(newData, 3);% insert at position 3
            %

            measurementCount = obj.getNumberOfMeasurements();
            if nargin < 3; index = measurementCount + 1; end
            if index < 1; index = measurementCount + 1; end

            if index <= measurementCount
                obj.Data(index+1 : numel(obj.Data)+1) = obj.Data(index : numel(obj.Data));
                obj.Data(index) = newData;
            else
                obj.Data(index) = newData;
            end

            newNs = num2cell(1:numel(obj.Data));
            [obj.Data(1:numel(obj.Data)).n] = newNs{:};
        end

        function removeMeasurement(obj, index)
            % REMOVEMEASUREMENT - Remove one or more measurements from the Data array.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.removeMeasurement(index)
            %
            % When ``index`` is ``0``, empty, or omitted all measurements are
            % removed (calls ``clearData``).  When the removal would leave the
            % array empty, ``clearData`` is also called.  Otherwise the
            % element(s) are deleted and ``.n`` is renumbered.
            %
            % No confirmation dialog is shown — caller is responsible for
            % prompting the user before invoking this method.
            %
            % Input Arguments:
            %   - **index** — *(optional)* [double] index of the measurement to
            %     remove.  Use ``0`` or omit to remove all.
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.removeMeasurement(3);% remove 3rd
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.removeMeasurement(0);% remove all
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.removeMeasurement();% remove all
            %

            if nargin < 2; index = 0; end
            if isempty(index); index = 0; end

            if index == 0
                obj.clearData();
            else
                if numel(index) >= obj.getNumberOfMeasurements()
                    obj.clearData();
                else
                    obj.Data(index) = [];
                    newNs = num2cell(1:numel(obj.Data));
                    [obj.Data(1:numel(obj.Data)).n] = newNs{:};
                end
            end
        end

        function measurementCount = getNumberOfMeasurements(obj)
            % GETNUMBEROFMEASUREMENTS - Return the total number of stored measurements.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       measurementCount = obj.getNumberOfMeasurements()
            %
            % Returns ``0`` when the Data struct array is in its empty
            % initial state (i.e. ``obj.Data(1).n`` is empty).
            %
            % Input Arguments:
            %
            % Output Arguments:
            %   - **measurementCount** — [double] number of stored measurements.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     measurementCount = obj.mibModel.I{obj.mibModel.id}.measurements.getNumberOfMeasurements();
            %

            if isempty(obj.Data(1).n)
                measurementCount = 0;
            else
                measurementCount = numel(obj.Data);
            end
        end

        function indices = findIndexByLabel(obj, queryStr)
            % FINDINDEXBYLABEL - Find measurements whose info field matches a query string.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       indices = obj.findIndexByLabel(queryStr)
            %
            % Searches ``obj.Data`` for elements whose ``.info`` field equals
            % ``queryStr``.
            %
            % Input Arguments:
            %   - **queryStr** — [char | string] label text to search for.
            %
            % Output Arguments:
            %   - **indices** — [numeric vector] indices of matching entries.
            %     Empty if no match found.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     indices = obj.mibModel.I{obj.mibModel.id}.measurements.findIndexByLabel('nucleus');
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     indices = findIndexByLabel(obj, 'dist1');% call within the class
            %

            if obj.getNumberOfMeasurements() == 0
                indices = [];
                return;
            end
            infoValues = {obj.Data.info};
            indices = find(strcmp(infoValues, queryStr));
        end

        function addMeasurementsToPlot(obj, axesHandle, ~, orientation, convertFcn, selectedIdx, showLabel)
            % ADDMEASUREMENTSTOPLOT - Render measurement overlays on the given axes.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addMeasurementsToPlot(axesHandle, mode, orientation, convertFcn)
            %       obj.addMeasurementsToPlot(axesHandle, mode, orientation, convertFcn, selectedIdx, showLabel)
            %
            % Plots measurements visible on the current Z slice and time point.
            % Coordinate conversion is injected via ``convertFcn`` so the class
            % never calls ``mibModel`` directly.
            %
            % Input Arguments:
            %   - **axesHandle** — handle to the target axes.
            %   - **mode** — [char] rendering mode (``'shown'`` or ``'full'``); passed
            %     through for callers that need it, not used internally.
            %   - **orientation** — [double] current orientation (3 = yx, 1 = zx, 2 = zy).
            %   - **convertFcn** — [function_handle] ``@(X,Y) ...`` that converts
            %     data coordinates to axes coordinates:
            %     ``[Xscreen, Yscreen] = convertFcn(Xdata, Ydata)``
            %   - **selectedIdx** — *(optional)* [double] ``0`` = all visible;
            %     ``>0`` = only that index.  Default ``0``.
            %   - **showLabel** — *(optional)* [logical] show ``.info`` text label.
            %     Default ``false``.
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     convertFcn = @(x,y) obj.mibModel.convertDataToMouseCoordinates(x, y, 'shown');
            %     ds.measurements.addMeasurementsToPlot(ax, 'shown', ds.orientation, convertFcn, 0, true);
            %

            if nargin < 7; showLabel = false; end
            if nargin < 6; selectedIdx = 0; end

            if obj.getNumberOfMeasurements() == 0; return; end

            if ~isempty(obj.mibDataset)
                sliceNo  = obj.mibDataset.slices{3}(1);
                timePnt  = obj.mibDataset.slices{5}(1);
            else
                sliceNo = 1;
                timePnt = 1;
            end

            visibleMask = false(1, numel(obj.Data));
            for measureIdx = 1:numel(obj.Data)
                if isempty(obj.Data(measureIdx).n); continue; end
                if obj.Data(measureIdx).orientation ~= orientation; continue; end
                if obj.Data(measureIdx).Z ~= sliceNo; continue; end
                if obj.Data(measureIdx).T ~= timePnt; continue; end
                visibleMask(measureIdx) = true;
            end
            visibleIndices = find(visibleMask);

            if ~strcmp(obj.typeToShow, 'All')
                visibleTypes = {obj.Data(visibleIndices).type};
                visibleIndices = visibleIndices(strcmp(visibleTypes, obj.typeToShow));
            end

            if selectedIdx > 0
                visibleIndices = visibleIndices(visibleIndices == selectedIdx);
            end

            if isempty(visibleIndices); return; end

            options = obj.Options;
            markerStyle = options.marker;
            markerSize  = str2double(options.markersize);
            lineStyle   = options.linestyle;
            lineWidth   = str2double(options.linewidth);
            fontSize    = str2double(options.fontsize);

            if isscalar(options.color) || strcmpi(options.color, 'none')
                color = options.color;
            else
                color = str2num(options.color); %#ok<ST2NM>
            end
            if isscalar(options.textcolorfg) || strcmpi(options.textcolorfg, 'none')
                textColorFG = options.textcolorfg;
            else
                textColorFG = str2num(options.textcolorfg); %#ok<ST2NM>
            end
            if isscalar(options.textcolorbg) || strcmpi(options.textcolorbg, 'none')
                textColorBG = options.textcolorbg;
            else
                textColorBG = str2num(options.textcolorbg); %#ok<ST2NM>
            end

            effectiveMarker    = markerStyle;
            effectiveLineStyle = lineStyle;
            if options.showMarkers == 0; effectiveMarker    = 'none'; end
            if options.showLines   == 0; effectiveLineStyle = 'none'; end

            axesHandle.NextPlot = 'add';

            for visibleLoopIdx = 1:numel(visibleIndices)
                dataIdx      = visibleIndices(visibleLoopIdx);
                measureType  = obj.Data(dataIdx).type;
                dataX        = obj.Data(dataIdx).X;
                dataY        = obj.Data(dataIdx).Y;
                labelText    = obj.Data(dataIdx).info;
                if isempty(labelText); labelText = num2str(obj.Data(dataIdx).n); end

                [screenX, screenY] = convertFcn(dataX, dataY);

                switch measureType

                    case {'Distance (linear)', 'Caliper'}
                        plot(axesHandle, screenX, screenY, ...
                            'Color', color, 'LineStyle', effectiveLineStyle, 'LineWidth', lineWidth, ...
                            'Marker', effectiveMarker, 'MarkerSize', markerSize, 'MarkerEdgeColor', color, ...
                            'Tag', 'measurements');
                        if showLabel && options.showText
                            text(screenX(end), screenY(end), ...
                                sprintf('  %.4g', obj.Data(dataIdx).value), ...
                                'Parent', axesHandle, ...
                                'Color', textColorFG, 'BackgroundColor', textColorBG, ...
                                'FontSize', fontSize, 'Tag', 'measurements');
                        end

                    case 'Point'
                        plot(axesHandle, screenX, screenY, ...
                            'Color', color, 'LineStyle', 'none', ...
                            'Marker', effectiveMarker, 'MarkerSize', markerSize, 'MarkerEdgeColor', color, ...
                            'Tag', 'measurements');
                        if showLabel && options.showText
                            text(screenX(1), screenY(1), ...
                                ['  ' labelText], ...
                                'Parent', axesHandle, ...
                                'Color', textColorFG, 'BackgroundColor', textColorBG, ...
                                'FontSize', fontSize, 'Tag', 'measurements');
                        end

                    case 'Angle'
                        plot(axesHandle, screenX, screenY, ...
                            'Color', color, 'LineStyle', effectiveLineStyle, 'LineWidth', lineWidth, ...
                            'Marker', effectiveMarker, 'MarkerSize', markerSize, 'MarkerEdgeColor', color, ...
                            'Tag', 'measurements');
                        if showLabel && options.showText && numel(screenX) >= 2
                            vertexIdx = ceil(numel(screenX) / 2);
                            text(screenX(vertexIdx), screenY(vertexIdx), ...
                                sprintf('  %.2f\xb0', obj.Data(dataIdx).value), ...
                                'Parent', axesHandle, ...
                                'Color', textColorFG, 'BackgroundColor', textColorBG, ...
                                'FontSize', fontSize, 'Tag', 'measurements');
                        end

                    case 'Circle (R)'
                        plot(axesHandle, screenX, screenY, ...
                            'Color', color, 'LineStyle', effectiveLineStyle, 'LineWidth', lineWidth, ...
                            'Tag', 'measurements');
                        circData = obj.Data(dataIdx).circ;
                        if ~isempty(circData)
                            [centerScreenX, centerScreenY] = convertFcn(circData.xc, circData.yc);
                            crossSize = max(3, markerSize);
                            plot(axesHandle, ...
                                [centerScreenX - crossSize, centerScreenX + crossSize], ...
                                [centerScreenY, centerScreenY], ...
                                'Color', color, 'LineStyle', '-', 'LineWidth', lineWidth, ...
                                'Tag', 'measurements');
                            plot(axesHandle, ...
                                [centerScreenX, centerScreenX], ...
                                [centerScreenY - crossSize, centerScreenY + crossSize], ...
                                'Color', color, 'LineStyle', '-', 'LineWidth', lineWidth, ...
                                'Tag', 'measurements');
                            if showLabel && options.showText
                                text(centerScreenX, centerScreenY, ...
                                    sprintf('  R=%.4g', obj.Data(dataIdx).value), ...
                                    'Parent', axesHandle, ...
                                    'Color', textColorFG, 'BackgroundColor', textColorBG, ...
                                    'FontSize', fontSize, 'Tag', 'measurements');
                            end
                        end

                    case 'Distance (polyline)'
                        splineData = obj.Data(dataIdx).spline;
                        if ~isempty(splineData) && isfield(splineData, 'x')
                            [splineScreenX, splineScreenY] = convertFcn(splineData.x, splineData.y);
                            plot(axesHandle, splineScreenX, splineScreenY, ...
                                'Color', color, 'LineStyle', effectiveLineStyle, 'LineWidth', lineWidth, ...
                                'Tag', 'measurements');
                        end
                        if options.showMarkers
                            plot(axesHandle, screenX, screenY, ...
                                'Color', color, 'LineStyle', 'none', ...
                                'Marker', markerStyle, 'MarkerSize', markerSize, 'MarkerEdgeColor', color, ...
                                'Tag', 'measurements');
                        end
                        if showLabel && options.showText
                            text(screenX(end), screenY(end), ...
                                sprintf('  %.4g', obj.Data(dataIdx).value), ...
                                'Parent', axesHandle, ...
                                'Color', textColorFG, 'BackgroundColor', textColorBG, ...
                                'FontSize', fontSize, 'Tag', 'measurements');
                        end

                    otherwise
                        plot(axesHandle, screenX, screenY, ...
                            'Color', color, 'LineStyle', effectiveLineStyle, 'LineWidth', lineWidth, ...
                            'Marker', effectiveMarker, 'MarkerSize', markerSize, 'MarkerEdgeColor', color, ...
                            'Tag', 'measurements');
                end
            end

            axesHandle.NextPlot = 'replace';
        end

        function resample(obj, resampledRatio)
            % RESAMPLE - Recalculate measurement positions after image resampling.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.resample(resampledRatio)
            %
            % Scales X, Y coordinates of every stored measurement by the
            % appropriate ratio depending on the measurement's orientation.
            % Also scales circle centre/radius and spline coordinates if present.
            %
            % Input Arguments:
            %   - **resampledRatio** — [numeric vector] ``[ratioW, ratioH, ratioZ]``
            %     ratio of new/old dimensions.  For example ``[0.5, 0.5, 1]``
            %     bins XY by 2.
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.resample([0.5, 0.5, 1]);
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     resample(obj, [2, 2, 2]);% call within the class; double all dimensions
            %

            if obj.getNumberOfMeasurements() == 0; return; end

            for measureIdx = 1:numel(obj.Data)
                orientationValue = obj.Data(measureIdx).orientation;
                if isempty(orientationValue); continue; end

                switch orientationValue
                    case 3  % yx
                        ratioX = resampledRatio(1);
                        ratioY = resampledRatio(2);
                    case 1  % zx
                        ratioX = resampledRatio(3);
                        ratioY = resampledRatio(1);
                    case 2  % zy
                        ratioX = resampledRatio(3);
                        ratioY = resampledRatio(2);
                    otherwise
                        continue;
                end

                obj.Data(measureIdx).X = obj.Data(measureIdx).X * ratioX;
                obj.Data(measureIdx).Y = obj.Data(measureIdx).Y * ratioY;

                % scale circle parameters
                if ~isempty(obj.Data(measureIdx).circ)
                    obj.Data(measureIdx).circ.xc = obj.Data(measureIdx).circ.xc * ratioX;
                    obj.Data(measureIdx).circ.yc = obj.Data(measureIdx).circ.yc * ratioY;
                    obj.Data(measureIdx).circ.R  = obj.Data(measureIdx).circ.R  * ratioX;
                end

                % scale spline coordinates
                if ~isempty(obj.Data(measureIdx).spline) && isfield(obj.Data(measureIdx).spline, 'x')
                    obj.Data(measureIdx).spline.x = obj.Data(measureIdx).spline.x * ratioX;
                    obj.Data(measureIdx).spline.y = obj.Data(measureIdx).spline.y * ratioY;
                end
            end
        end

        function crop(obj, cropF)
            % CROP - Recalculate measurement positions after image crop.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.crop(cropF)
            %
            % Shifts all stored coordinates by the crop origin depending on
            % the measurement's orientation.  Also shifts circle and spline
            % coordinates if present.
            %
            % Input Arguments:
            %   - **cropF** — [numeric vector] ``[x1, y1, dx, dy, z1, dz]``:
            %
            %     - ``cropF(1)`` — starting X coordinate (1-based)
            %     - ``cropF(2)`` — starting Y coordinate (1-based)
            %     - ``cropF(3)`` — width of crop region
            %     - ``cropF(4)`` — height of crop region
            %     - ``cropF(5)`` — starting Z slice (1-based)
            %     - ``cropF(6)`` — number of Z slices
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.measurements.crop([100, 50, 200, 200, 1, 10]);
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     crop(obj, [1, 1, 512, 512, 5, 20]);% call within the class
            %

            if obj.getNumberOfMeasurements() == 0; return; end

            for measureIdx = 1:numel(obj.Data)
                orientationValue = obj.Data(measureIdx).orientation;
                if isempty(orientationValue); continue; end

                switch orientationValue
                    case 3  % yx
                        shiftX = cropF(1) - 1;
                        shiftY = cropF(2) - 1;
                    case 1  % zx
                        shiftX = cropF(5) - 1;
                        shiftY = cropF(1) - 1;
                    case 2  % zy
                        shiftX = cropF(5) - 1;
                        shiftY = cropF(2) - 1;
                    otherwise
                        continue;
                end

                obj.Data(measureIdx).X = obj.Data(measureIdx).X - shiftX;
                obj.Data(measureIdx).Y = obj.Data(measureIdx).Y - shiftY;

                % shift circle parameters
                if ~isempty(obj.Data(measureIdx).circ)
                    obj.Data(measureIdx).circ.xc = obj.Data(measureIdx).circ.xc - shiftX;
                    obj.Data(measureIdx).circ.yc = obj.Data(measureIdx).circ.yc - shiftY;
                end

                % shift spline coordinates
                if ~isempty(obj.Data(measureIdx).spline) && isfield(obj.Data(measureIdx).spline, 'x')
                    obj.Data(measureIdx).spline.x = obj.Data(measureIdx).spline.x - shiftX;
                    obj.Data(measureIdx).spline.y = obj.Data(measureIdx).spline.y - shiftY;
                end
            end
        end

    end  % methods

    % =====================================================================
    %  Static computation methods — call as core.Measurements.methodName()
    % =====================================================================
    methods (Static)

        function angleValue = computeAngle(X, Y, pixSize, orientation)
            % COMPUTEANGLE - Compute the angle in degrees formed by three points.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       angleValue = core.Measurements.computeAngle(X, Y, pixSize, orientation)
            %
            % The second point (``X(2), Y(2)``) is the vertex of the angle.
            % Physical pixel size is applied per orientation before computing
            % the angle so that non-isotropic datasets give correct results.
            %
            % Input Arguments:
            %   - **X** — [double(1×3)] X coordinates of the three points.
            %   - **Y** — [double(1×3)] Y coordinates of the three points.
            %   - **pixSize** — [struct] pixel/voxel size with fields ``.x``, ``.y``, ``.z``.
            %   - **orientation** — *(optional)* [double] 1 = zx, 2 = zy, 3 = yx.
            %     Default ``3``.
            %
            % Output Arguments:
            %   - **angleValue** — [double] angle at the vertex in degrees.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     pixSize.x = 0.1; pixSize.y = 0.1; pixSize.z = 0.3;
            %     angleValue = core.Measurements.computeAngle([10 20 30], [10 20 10], pixSize, 3);
            %

            if nargin < 4; orientation = 3; end
            switch orientation
                case 1;   aspectRatio = pixSize.z / pixSize.x;
                case 2;   aspectRatio = pixSize.z / pixSize.y;
                otherwise; aspectRatio = pixSize.x / pixSize.y;
            end
            vector1 = [(X(1) - X(2)) * aspectRatio,  Y(1) - Y(2)];
            vector2 = [(X(3) - X(2)) * aspectRatio,  Y(3) - Y(2)];
            cosAngle = dot(vector1, vector2) / (norm(vector1) * norm(vector2));
            phi = acos(max(-1, min(1, cosAngle)));
            angleValue = phi * (180 / pi);
        end

        function distanceValue = computeDistance(X, Y, pixSize, orientation)
            % COMPUTEDISTANCE - Compute the Euclidean distance between two points in physical units.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       distanceValue = core.Measurements.computeDistance(X, Y, pixSize, orientation)
            %
            % Input Arguments:
            %   - **X** — [double(1×2)] X coordinates of the two endpoints.
            %   - **Y** — [double(1×2)] Y coordinates of the two endpoints.
            %   - **pixSize** — [struct] pixel/voxel size with fields ``.x``, ``.y``, ``.z``.
            %   - **orientation** — *(optional)* [double] 1 = zx, 2 = zy, 3 = yx.
            %     Default ``3``.
            %
            % Output Arguments:
            %   - **distanceValue** — [double] Euclidean distance in physical units.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     pixSize.x = 0.1; pixSize.y = 0.1; pixSize.z = 0.3;
            %     distanceValue = core.Measurements.computeDistance([10 20], [10 30], pixSize, 3);
            %

            if nargin < 4; orientation = 3; end
            switch orientation
                case 1;    dx = diff(X) * pixSize.z;  dy = diff(Y) * pixSize.x;
                case 2;    dx = diff(X) * pixSize.z;  dy = diff(Y) * pixSize.y;
                otherwise; dx = diff(X) * pixSize.x;  dy = diff(Y) * pixSize.y;
            end
            distanceValue = hypot(dx, dy);
        end

        function circ = computeCircleFit(x, y)
            % COMPUTECIRCLEFIT - Least-squares circle fitting to a set of 2-D points.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       circ = core.Measurements.computeCircleFit(x, y)
            %
            % Adapted from the MIB2 ``circlefit`` function.
            %
            % Input Arguments:
            %   - **x** — [double vector] X coordinates of the input points.
            %   - **y** — [double vector] Y coordinates of the input points.
            %
            % Output Arguments:
            %   - **circ** — [struct] with fields:
            %
            %     - ``.xc`` — X coordinate of the fitted circle centre
            %     - ``.yc`` — Y coordinate of the fitted circle centre
            %     - ``.R``  — radius of the fitted circle
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     circ = core.Measurements.computeCircleFit([0 1 0 -1], [1 0 -1 0]);
            %     % circ.xc ≈ 0, circ.yc ≈ 0, circ.R ≈ 1
            %

            pointCount = length(x);
            designMatrix = [x(:), y(:), ones(pointCount, 1)];
            abc = designMatrix \ -(x(:).^2 + y(:).^2);
            centreX = -abc(1) / 2;
            centreY = -abc(2) / 2;
            radius  = sqrt(centreX^2 + centreY^2 - abc(3));
            circ.xc = centreX;
            circ.yc = centreY;
            circ.R  = radius;
        end

        function profileData = computeProfile(image2D, X, Y, ~, ~)
            % COMPUTEPROFILE - Compute an intensity profile along a polyline path.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       profileData = core.Measurements.computeProfile(image2D, X, Y, pixSize, orientation)
            %
            % The caller fetches the 2-D image slice via ``getData2D`` with
            % block-mode off and passes it here.  The result is a matrix
            % suitable for line-profile plots.
            %
            % Input Arguments:
            %   - **image2D** — [H × W × C double or uint] intensity image.
            %   - **X** — [double vector] polyline vertex X coords (data space).
            %   - **Y** — [double vector] polyline vertex Y coords (data space).
            %   - **pixSize** — [struct] pixel size (currently unused but reserved
            %     for physical-unit arc lengths in future).
            %   - **orientation** — *(optional)* [double] reserved; default ``3``.
            %
            % Output Arguments:
            %   - **profileData** — [double matrix] rows = ``[position; ch1; ch2; …]``
            %     where ``position`` is cumulative arc length in pixels and
            %     each ``chN`` row contains the interpolated intensity for
            %     colour channel N.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     img = obj.mibModel.getData2D('image', [], [], [], options);
            %     profileData = core.Measurements.computeProfile(img, X, Y, pixSize);
            %

            % pixSize and orientation args are accepted for API uniformity but not used internally
            [imageHeight, imageWidth, channelCount] = size(image2D);
            [xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);

            arcLengths = [0; cumsum(hypot(diff(X(:)), diff(Y(:))))];
            numberOfSamples = max(1, round(max(arcLengths)));
            sampledArcLengths = linspace(0, max(arcLengths), numberOfSamples);
            sampledX = interp1(arcLengths, X(:), sampledArcLengths);
            sampledY = interp1(arcLengths, Y(:), sampledArcLengths);

            intensityProfile = zeros(channelCount, numberOfSamples);
            for channelIdx = 1:channelCount
                intensityProfile(channelIdx, :) = interp2( ...
                    xGrid, yGrid, double(image2D(:, :, channelIdx)), sampledX, sampledY);
            end
            profileData = [sampledArcLengths; intensityProfile];
        end

        function kymograph = computeKymograph(imageStack, X, Y)
            % COMPUTEKYMOGRAPH - Build a kymograph from a line measurement over a Z/T stack.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       kymograph = core.Measurements.computeKymograph(imageStack, X, Y)
            %
            % Input Arguments:
            %   - **imageStack** — [H × W × C × nSlices] uint or double array.
            %   - **X** — [double(1×2)] line endpoint X coords (pixel space).
            %   - **Y** — [double(1×2)] line endpoint Y coords (pixel space).
            %
            % Output Arguments:
            %   - **kymograph** — [nSlices × nPoints × C] array of the same
            %     class as ``imageStack(:,:,:,1)``, where rows = slices/frames
            %     and columns = positions along the line.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     stack = obj.mibModel.getData4D('image', [], [], options);
            %     kymo  = core.Measurements.computeKymograph(stack, [10 200], [50 50]);
            %

            [imageHeight, imageWidth, channelCount, numberOfSlices] = size(imageStack);
            numberOfPoints = max(1, round(hypot(diff(X), diff(Y))));
            lineX = linspace(X(1), X(2), numberOfPoints);
            lineY = linspace(Y(1), Y(2), numberOfPoints);

            % clamp to valid pixel indices
            rowIndices = min(imageHeight, max(1, round(lineY)));
            colIndices = min(imageWidth,  max(1, round(lineX)));
            linearIndices = sub2ind([imageHeight, imageWidth], rowIndices, colIndices);

            kymograph = zeros(numberOfSlices, numberOfPoints, channelCount, 'like', imageStack(:,:,:,1));
            for sliceIdx = 1:numberOfSlices
                for channelIdx = 1:channelCount
                    slice2D = imageStack(:, :, channelIdx, sliceIdx);
                    kymograph(sliceIdx, :, channelIdx) = slice2D(linearIndices);
                end
            end
        end

    end  % methods (Static)

end
