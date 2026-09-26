classdef VolRenApp < handle
    % VOLRENAPP - Controller for the 3D volume rendering viewer.
    %
    % Syntax:
    %   .. code-block:: matlab
    %
    %      obj.startController('controllers.VolRenApp');
    %
    % **Example 1** - launch as interactive GUI tool:
    %
    %   .. code-block:: matlab
    %
    %      obj.startController('controllers.VolRenApp');
    %
    % **Example 2** - launch in batch mode:
    %
    %   .. code-block:: matlab
    %
    %      BatchOpt.Parameter = 'test';
    %      BatchOpt.Checkbox = true;
    %      BatchOpt.Popup = {'value'};
    %      BatchOpt.Radio = {'Radio1'};
    %      BatchOpt.showWaitbar = true;
    %      obj.startController('controllers.VolRenApp', [], BatchOpt);
    %
    % **Example 3** - trigger return of available options via ``syncBatch`` event:
    %
    %   .. code-block:: matlab
    %
    %      obj.startController('controllers.VolRenApp', [], NaN);

    % Updates
    %

    properties
        mibModel
        % handles to mibModel
        view
        % handle to the view / mibVolRenAppGUI
        listener
        % a cell array with handles to listeners
        BatchOpt
        % a structure compatible with batch operation; field names should match widget Tags in the GUI:
        %
        % - ``.Parameter`` - [editbox], char/string
        % - ``.Checkbox`` - [checkbox], logical ``true`` or ``false``
        % - ``.Dropdown{1}`` - [dropdown], cell string for the dropdown
        % - ``.Dropdown{2}`` - *(optional)* array with possible options
        % - ``.Radio`` - [radiobuttons], cell string ``'Radio1'`` or ``'Radio2'`` etc.
        % - ``.ParameterNumeric{1}`` - [numeric editbox], cell with a number
        % - ``.ParameterNumeric{2}`` - *(optional)* vector with limits ``[min, max]``
        % - ``.ParameterNumeric{3}`` - *(optional)* ``'on'`` to round the value, ``'off'`` to not round
        childControllers
        % list of opened subcontrollers
        childControllersIds
        % a cell array with names of initialized child controllers
        alphaPlotHandle
        % handle to the alpha plot
        animationFilename
        % template for the animation filename
        animationPath
        % a structure with animation path:
        %
        % - ``.CameraPosition`` - matrix of camera positions ``[keyFrame, x, y, z]``
        % - ``.CameraUpVector`` - matrix of camera up vectors ``[keyFrame, x, y, z]``
        % - ``.CameraTarget`` - matrix of camera target positions ``[keyFrame, x, y, z]``
        animationPreviewRunning
        % logical switch defining whether the animation is previewed
        defaultView
        % a structure with the default camera position
        figPosStored
        % a structure with stored positions of the widgets for making snapshots:
        %
        % - ``.mibVolRenAppFigure`` - position of the main figure
        % - ``.mainGridLayoutRowHeights`` - heights of rows in ``obj.view.handles.mainGridLayout``
        keyFrameTableIndex
        % index of the selected key frame
        matlabVersion
        % current version of MATLAB
        maxIntValue
        % max integer value of the loaded volume
        noOverlayMaterials
        % number of materials shown in the overlay
        overlayShownMaterials
        % a vector of shown (true) or hidden (false) materials in the model overlay
        overlayAlpha
        % a vector with alpha values for overlay materials
        overlayRowMaterials
        % real material index behind each row of the model table; empty in the cycled color mode
        overlayRowNames
        % a cell array with names shown in the model table
        overlayRowColors
        % a matrix [row, R G B] with background colors of the model table
        overlayRowMap
        % a cell array; for each row of the model table, the ``OverlayAlphamap`` rows it controls
        overlayMaterialsMode
        % for models with 256 materials and more: ``'All materials'`` or ``'Selected materials'``
        overlayMaterialsSelection
        % a vector of material indices rendered in the ``'Selected materials'`` mode
        modelTableIndex
        % index of the selected material in the modelTable
        scalingTransform
        % tform to scale the dataset upon loading to have its units in um
        Settings
        % a structure with settings, initialized from ``obj.mibModel.preferences.VolRen``:
        %
        % - ``.volumeAlphaCurve.x`` - default ``[0 .3 .7 1]``
        % - ``.volumeAlphaCurve.y`` - default ``[1 1 0 0]``
        % - ``.markerSize`` - marker size for the alpha plot
        % - ``.BackgroundColor`` - color for the background
        % - ``.colormapName`` - default colormap name, or ``'custom'`` (not yet implemented)
        % - ``.colormapInvert`` - ``true``/``false``, whether to invert the colormap
        % - ``.animationPath`` - a structure with animation path
        % - ``.noFramesPreview`` - number of frames for the animation preview
        surfList
        % a cell array of generated surfaces
        surfListAlpha
        % an array of alpha values for the generated surfaces
        surfListShown
        % [logical] per-surface show/hide intent, one entry per :attr:`surfList`
        % surface. Kept beside the surfaces rather than read back from their
        % ``Visible`` property, because "hide all" has to be able to turn every
        % surface off and then put each one back the way the user left it -
        % ``Visible`` can only hold one of those two answers at a time. Same split
        % as ``overlayShownMaterials`` against the model's hide-all checkbox.
        surfaceTableIndex
        % index of the selected row in the surfaceTable
        viewer
        % handle to the main viewer widget
        volume
        % main image volume
        volumeAlphaCurve
        % a structure with alpha curve details:
        %
        % - ``.x`` - vector of intensity points ``[0..1]``
        % - ``.y`` - alpha value for each intensity point ``[0..1]``
        % - ``.alphamap`` - calculated alpha map used in ``volshow``
        % - ``.activePoint`` - index of the currently selected point
        volumeColormap
        % vector with the colormap
        volumeScaleFactor
        % scale factor to downsample the datasets, below 1
        pyramidLevel
        % for BigData datasets: 1-based pyramid level currently loaded into the viewer (1 = full resolution)
        overlayMaterialId
        % material index last loaded into the overlay (``NaN`` = all materials); used by the live overlay refresh
        liveUpdateListener
        % cell array of listeners that drive live overlay updates during segmentation (empty/{} when off):
        % ``SetData`` on the model (moveLayers) and ``SetData`` on the active dataset (core setData2D/3D/4D)
        liveUpdateTimer
        % one-shot ``timer`` debouncing live overlay refreshes so a burst of edits collapses into one refetch
        liveUpdatePending
        % logical flag set when a live overlay refresh is queued and waiting for the debounce timer
    end

    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
    end

    methods (Static)
        function ViewListner_Callback(obj, src, evnt)
            switch evnt.EventName
                case {'updateGuiWidgets'}
                    obj.updateWidgets();
                case 'SlicePlanesChanged'
                    % update slice sliders and editboxes
                    obj.view.handles.xSlider.Value = max([1, floor(double(obj.volume.SlicePlaneValues(1,4)))]);      % x-plane
                    obj.view.handles.ySlider.Value = max([1, floor(double(obj.volume.SlicePlaneValues(2,4)))]);      % y-plane
                    obj.view.handles.zSlider.Value = max([1, floor(double(obj.volume.SlicePlaneValues(3,4)))]);      % z-plane
                    obj.view.handles.xSliderEdit.Value = obj.view.handles.xSlider.Value;
                    obj.view.handles.ySliderEdit.Value = obj.view.handles.ySlider.Value;
                    obj.view.handles.zSliderEdit.Value = obj.view.handles.zSlider.Value;
            end
        end

        function cameraListner_Callback(obj, src, evnt)
            % listener callback for camera moving

            if ~isfield(obj.defaultView, 'CameraPosition')
                % for some reason, the camera settings can not be
                % obtained in grabVolume function unless a
                % breakpoint is used. To fix that somehow, init the
                % values after first user interaction with the volume
                obj.defaultView.CameraPosition = obj.viewer.CameraPosition;
                obj.defaultView.CameraTarget = obj.viewer.CameraTarget;
                obj.defaultView.CameraUpVector = [0 0 1];%obj.viewer.CameraUpVector;
                obj.defaultView.CameraZoom = 1; % obj.viewer.CameraZoom;
            end

            % update current camera status
            if strcmp(obj.view.handles.topTabGroup.SelectedTab.Tag, 'viewerTab')
                obj.updateCameraWidgets();
            end
        end
    end

    methods
        % declaration of methods in external files
        [overlayIdx, overlayInfo] = buildOverlayIndexVolume(obj, overlayData, overlayType)   % map an overlay layer onto the 255 color slots of volshow
        
        function obj = VolRenApp(mibModel, varargin)
            % VOLRENAPP - Class constructor for the VolRenApp controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = VolRenApp(mibModel)
            %      obj = VolRenApp(mibModel, options)
            %
            % Input Arguments:
            %   - **mibModel** - [handle] handle to the MibModel instance
            %   - **options** *(optional)* - struct with initialization parameters:
            %
            %     - ``.Settings`` - settings for initialization of the volume viewer
            
            obj.mibModel = mibModel;    % assign model
            id = obj.mibModel.getActiveId();

            if nargin < 2
                options = struct();
            else
                options = varargin{1};
            end

            % default parameters
            obj.Settings = mibModel.preferences.VolRen;
            % Prefs.VolRen.Viewer.backgroundColor = [0 0.329 0.529];
            % Prefs.VolRen.Viewer.gradientColor = [0 0.561 1];
            % Prefs.VolRen.Viewer.backgroundGradient = 'on';
            % Prefs.VolRen.Viewer.lighting = 'on';
            % Prefs.VolRen.Viewer.lightColor = [1 1 1];
            % Prefs.VolRen.Viewer.showScaleBar = 'on';
            % Prefs.VolRen.Viewer.scaleBarUnits = 'um';
            % Prefs.VolRen.Viewer.showOrientationAxes = 'on';
            % Prefs.VolRen.Viewer.showBox = 'off';
            %
            % Prefs.VolRen.Volume.volumeAlphaCurve.x = [0 .3 .7 1];
            % Prefs.VolRen.Volume.volumeAlphaCurve.y = [1 1 0 0];
            % Prefs.VolRen.Volume.isosurfaceValue = 0.5;
            % Prefs.VolRen.Volume.colormapName = 'gray';
            % Prefs.VolRen.Volume.colormapInvert = true;
            % Prefs.VolRen.Volume.markerSize = 15;

            obj.Settings.animationPath = struct();
            obj.Settings.noFramesPreview = 120;     % number of frames for the animation preview mode

            obj.childControllers = {};    % initialize child controllers
            obj.childControllersIds = {};

            % update class variables
            % combine provided and default structures
            % obj.Settings = mibConcatenateStructures(obj.Settings, options);
            obj.volume = [];
            obj.volumeScaleFactor = 1;
            obj.pyramidLevel = 1;
            obj.keyFrameTableIndex = [];
            obj.modelTableIndex = [];
            obj.surfaceTableIndex = [];
            obj.animationPath = obj.Settings.Animation.animationPath;
            obj.animationPreviewRunning = false;
            obj.noOverlayMaterials = 0;     % number of the model overlay materials
            obj.overlayShownMaterials = [];          % vertor of shown/hidden materials of the overlay
            obj.overlayAlpha = [];        % a vector with alpha values for overlay materials
            obj.overlayRowMaterials = [];
            obj.overlayRowNames = {};
            obj.overlayRowColors = zeros([0, 3]);
            obj.overlayRowMap = {};
            obj.overlayMaterialsMode = 'All materials';     % for models with 256 materials and more
            obj.overlayMaterialsSelection = [];
            obj.surfList = {};  % cell array with the generated surface
            obj.surfListAlpha = []; % array of alpha values for the generated surfaces
            obj.surfListShown = logical([]); % per-surface show/hide intent

            % check for the virtual stacking mode and close the controller
            % BigData ('B') is supported via pyramid-level reads (see grabVolume);
            % only the browse-only Virtual ('V') mode is rejected here
            if obj.mibModel.I{id}.datasetType(1) == 'V'
                dlgOpt.MsgBoxOnly = true; dlgOpt.Icon = 'puffin_warning';
                header = 'The 3D volume rendering is not available in the virtual mode!';
                dlgOpt.HeaderLines = 2;
                % obj.view is not yet created here - use mibGUI as parent
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {}, {'Switch to the memory-resident or BigData mode and try again'}, 'Not implemented', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            guiName = 'views.VolRenAppGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme
            % the model and surface tables paint their text cells with a uistyle, which a theme switch does not remap
            obj.view.gui.ThemeChangedFcn = @(src, evnt) volRenAppThemeChanged(obj, src);

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.showScaleBar.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.showScaleBar.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            % move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            % generate output filename for animations
            [pathstr, name] = fileparts(obj.mibModel.I{id}.image.filename);
            fn_out = fullfile(pathstr, [name '.animation']);
            if isempty(strfind(fn_out, '/')) && isempty(strfind(fn_out, '\')) %#ok<STREMP>
                fn_out = fullfile(obj.mibModel.currentDirectory, fn_out);
            end
            if isempty(fn_out); fn_out = obj.mibModel.currentDirectory; end
            obj.animationFilename = fn_out;

            % show the gui
            obj.view.gui.Visible = 'on';
            
            % start 3D viewer in a separate window
            utils.startController(obj, 'controllers.VolRenAppViewer', obj);
            drawnow;
            
            % init the viewer
            obj.viewer = viewer3d(obj.childControllers{1}.view.handles.volumeViewerPanel, ...
                'BackgroundColor', obj.Settings.Viewer.backgroundColor, ...
                'backgroundGradient', obj.Settings.Viewer.backgroundGradient, ...
                'GradientColor', obj.Settings.Viewer.gradientColor);

            % show scale bar
            obj.viewer.ScaleBar =  obj.Settings.Viewer.showScaleBar;
            obj.viewer.ScaleBarUnits = obj.Settings.Viewer.scaleBarUnits;
            obj.volumeAlphaCurve.x = obj.Settings.Volume.volumeAlphaCurve.x;
            obj.volumeAlphaCurve.y = obj.Settings.Volume.volumeAlphaCurve.y;
            obj.volumeAlphaCurve.activePoint = [];
            obj.alphaPlotHandle = [];
            obj.defaultView = struct();

            if numel(fieldnames(options)) == 0  % grab volume
                status = obj.grabVolume();
            else
                status = obj.grabVolume(options.dataType, options.colorChannel);
            end
            if status == 0; return; end     % action cancelled from grabVolume

            obj.updateWidgets();
            obj.generateColorMap();     % generate colormap vector from the selected colormap

            % add listner to obj.mibModel and call controller function as a callback
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
            obj.listener{2} = addlistener(obj.viewer, 'CameraMoving', @(src,evnt) obj.cameraListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
            obj.listener{3} = addlistener(obj.volume, 'SlicePlanesChanged', @(src,evnt) obj.ViewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
        end

        function updateVolumeRenderingStyle(obj)
            % UPDATEVOLUMERENDERINGSTYLE - Update the volume rendering style.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateVolumeRenderingStyle()
            %
            % Reads ``obj.view.handles.rendererDropDown.Value`` and updates
            % widget states and ``obj.volume.RenderingStyle`` accordingly.
            % Supported styles: ``'VolumeRendering'``, ``'MaximumIntensityProjection'``,
            % ``'MinimumIntensityProjection'``, ``'GradientOpacity'``,
            % ``'Isosurface'``, ``'SlicePlanes'``.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.updateVolumeRenderingStyle: triggered\n');
            end
            obj.view.handles.slicesGridLayout.Visible = 'off';

            switch obj.view.handles.rendererDropDown.Value
                case 'Isosurface'
                    obj.view.handles.isovalueSlider.Enable = 'on';
                    obj.view.handles.isovalueEdit.Enable = 'on';
                    obj.view.handles.isovalueLabel.Text = 'Iso-value';
                    obj.view.handles.isovalueEdit.Value = obj.Settings.Volume.isosurfaceValue;
                    obj.view.handles.isovalueSlider.Value = obj.Settings.Volume.isosurfaceValue;
                case  'GradientOpacity'
                    obj.view.handles.isovalueSlider.Enable = 'on';
                    obj.view.handles.isovalueEdit.Enable = 'on';
                    obj.view.handles.isovalueLabel.Text = 'Opacity';
                    obj.view.handles.isovalueEdit.Value = obj.Settings.Volume.gradientOpacityValue;
                    obj.view.handles.isovalueSlider.Value = obj.Settings.Volume.gradientOpacityValue;
                case 'SlicePlanes'
                    obj.view.handles.slicesGridLayout.Visible = 'on';
                    obj.view.handles.isovalueSlider.Enable = 'off';
                    obj.view.handles.isovalueEdit.Enable = 'off';
                otherwise
                    obj.view.handles.isovalueSlider.Enable = 'off';
                    obj.view.handles.isovalueEdit.Enable = 'off';
            end
            obj.volume.RenderingStyle = obj.view.handles.rendererDropDown.Value;
            %obj.volume.RenderingStyle = 'CinematicRendering';
            %obj.volume.RenderingStyle = 'LightScattering';
            
        end

        function updateIsovalue(obj, newIsovalue)
            % UPDATEISOVALUE - Update the isosurface or gradient opacity value of the volume.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateIsovalue(newIsovalue)
            %
            % Input Arguments:
            %   - **newIsovalue** - [numeric] new isovalue or gradient opacity value ``[0..1]``

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.updateIsovalue: triggered\n');
            end
            switch obj.view.handles.rendererDropDown.Value
                case 'Isosurface'
                    obj.Settings.Volume.isosurfaceValue = newIsovalue;
                    obj.volume.IsosurfaceValue = obj.Settings.Volume.isosurfaceValue;
                case 'GradientOpacity'
                    obj.Settings.Volume.gradientOpacityValue = newIsovalue;
                    obj.volume.GradientOpacityValue = obj.Settings.Volume.gradientOpacityValue;
            end
        end

        function alphaAxesButtonDown(obj, event)
            % ALPHAAXESBUTTONDOWN - Handle mouse button-down event on the alpha axes.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.alphaAxesButtonDown(event)
            %
            % Input Arguments:
            %   - **event** - [event] MATLAB UI callback event from ``obj.view.handles.alphaAxes``

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.alphaAxesButtonDown: triggered\n');
            end
            xy = obj.view.handles.alphaAxes.CurrentPoint;
            seltype = obj.view.gui.SelectionType;
            modifier = obj.view.gui.CurrentModifier;

            xy = [xy(1,1); xy(1,2)];    % get x,y coordinates
            % correct y-coordinate
            xy(2) = min([xy(2), 1]);
            xy(2) = max([xy(2), 0]);

            if isempty(modifier)
                switch seltype
                    case {'normal', 'extend'}    % left click
                        if isempty(obj.volumeAlphaCurve.activePoint)
                            %warndlg(sprintf('!!! Warning !!!\n\nPlease select a point for modification!\n\nThe right mouse click: selects a point that should be modified\nShift + left mouse click: adds a new point\nCtrl + left mouse click: removes the closest point'), ...
                            %    'No active point');
                            uialert(obj.view.gui, ...
                                sprintf('!!! Warning !!!\n\nPlease select a point for modification!\n\nThe right mouse click: selects a point that should be modified\nShift + left mouse click: adds a new point\nCtrl + left mouse click: removes the closest point'), ...
                                'No active point', 'Icon', 'info');
                            return;
                        end
                        if xy(1) > 0 && xy(1) < obj.maxIntValue
                            if obj.volumeAlphaCurve.activePoint > 1 && obj.volumeAlphaCurve.x(obj.volumeAlphaCurve.activePoint) < 1
                                if xy(1) >= obj.volumeAlphaCurve.x(obj.volumeAlphaCurve.activePoint+1)*obj.maxIntValue
                                    xy(1) = obj.volumeAlphaCurve.x(obj.volumeAlphaCurve.activePoint+1)*obj.maxIntValue - obj.maxIntValue/256;
                                end
                                if xy(1) <= obj.volumeAlphaCurve.x(obj.volumeAlphaCurve.activePoint-1)*obj.maxIntValue
                                    xy(1) = obj.volumeAlphaCurve.x(obj.volumeAlphaCurve.activePoint-1)*obj.maxIntValue + obj.maxIntValue/256;
                                end
                                obj.volumeAlphaCurve.x(obj.volumeAlphaCurve.activePoint) = xy(1)/obj.maxIntValue;
                            end

                        end
                        obj.volumeAlphaCurve.y(obj.volumeAlphaCurve.activePoint) = xy(2);
                        obj.plotAlphaPlot();
                        obj.recalculateAlphamap();

                    case 'open'      % double click, select an active point

                    case 'alt'       % right click, modify the closest point
                        [~, pointIndex] = min(abs(obj.volumeAlphaCurve.x-xy(1)/obj.maxIntValue)); % find the closest point
                        obj.volumeAlphaCurve.activePoint = pointIndex;
                        obj.plotAlphaPlot();
                end
            else
                switch modifier{1}
                    case 'shift'    % add a point
                        xy(1) = xy(1)/obj.maxIntValue;
                        obj.volumeAlphaCurve.x(end+1) = xy(1);
                        obj.volumeAlphaCurve.y(end+1) = xy(2);
                        [obj.volumeAlphaCurve.x, sortIndices] = sort(obj.volumeAlphaCurve.x);
                        obj.volumeAlphaCurve.y = obj.volumeAlphaCurve.y(sortIndices);
                        obj.volumeAlphaCurve.activePoint = find(obj.volumeAlphaCurve.x == xy(1));
                        obj.plotAlphaPlot();
                        obj.recalculateAlphamap();
                    case 'control'  % remove the point
                        if numel(obj.volumeAlphaCurve.x) < 3; return; end     % the border points can't be deleted
                        [~, pointIndex] = min(abs(obj.volumeAlphaCurve.x(2:end-1)-xy(1)/obj.maxIntValue)); % find the closest point
                        pointIndex = pointIndex + 1;
                        obj.volumeAlphaCurve.x(pointIndex) = [];
                        obj.volumeAlphaCurve.y(pointIndex) = [];
                        obj.volumeAlphaCurve.activePoint = [];
                end
                obj.plotAlphaPlot();
                obj.recalculateAlphamap();
            end
        end

        function updateBackgroundColor(obj, event)
            % UPDATEBACKGROUNDCOLOR - Update the viewer background colour settings.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateBackgroundColor(event)
            %
            % Input Arguments:
            %   - **event** - [event] UI callback event; ``event.Source.Tag`` selects the operation:
            %
            %     - ``'menuBackgroundColor'`` - update the primary background colour
            %     - ``'menuBackgroundGradientColor'`` - update the gradient background colour

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.updateBackgroundColor(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'menuBackgroundColor'
                    obj.Settings.Viewer.backgroundColor = uisetcolor(obj.Settings.Viewer.backgroundColor, 'Select main background color');
                    obj.viewer.BackgroundColor = obj.Settings.Viewer.backgroundColor;
                case 'menuBackgroundGradientColor'
                    newColor = uisetcolor(obj.Settings.Viewer.gradientColor, 'Select secondary background color');
                    if newColor == 0; return; end
                    obj.Settings.Viewer.gradientColor = newColor;
                case 'menuBackgroundGradient'
                    if event.Source.Checked
                        event.Source.Checked = "off";
                        obj.viewer.BackgroundGradient = 'off';
                        obj.Settings.Viewer.backgroundGradient = 'off';
                    else
                        event.Source.Checked = "on";
                        obj.viewer.BackgroundGradient = 'on';
                        obj.Settings.Viewer.backgroundGradient = 'on';
                    end

            end
        end

        function updateColormap(obj, event)
            % UPDATECOLORMAP - Update the volume colormap from a widget selection event.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateColormap(event)
            %
            % Input Arguments:
            %   - **event** - [event] UI callback event; ``event.Source.Tag`` selects the field to update:
            %
            %     - ``'colormapName'`` - name of the selected colormap
            %     - ``'colormapInvert'`` - logical flag to invert the colormap
            %     - ``'colormapBlackPoint'`` - black-point adjustment value
            %     - ``'colormapWhitePoint'`` - white-point adjustment value

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.updateColormap(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'colormapName'
                    obj.Settings.Volume.colormapName = event.Source.Value;
                case 'colormapInvert'
                    obj.Settings.Volume.colormapInvert = event.Source.Value;
                case 'colormapBlackPoint'
                    obj.Settings.Volume.colormapBlackPoint = event.Source.Value;
                case 'colormapWhitePoint'
                    obj.Settings.Volume.colormapWhitePoint = event.Source.Value;
            end
            obj.generateColorMap();
        end


        function generateColorMap(obj)
            % GENERATECOLORMAP - Build ``obj.volumeColormap`` from current colormap settings.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.generateColorMap()
            %
            % Constructs the colormap vector from ``obj.Settings.Volume.colormapName``
            % and ``obj.Settings.Volume.colormapInvert``, then applies it to the volume and axes.

            % find points to stretch the colormap
            pnt1 = ceil(obj.view.handles.colormapBlackPoint.Value/4)+1;
            pnt2 = floor(obj.view.handles.colormapWhitePoint.Value/4);
            
            switch obj.Settings.Volume.colormapName
                case 'green'
                    color = zeros([64, 3]);
                    color(pnt1:pnt2, 2) = linspace(0, 1, pnt2-pnt1+1)';
                    if pnt2 < 64; color(pnt2+1:end,2) = 1; end
                case 'red' 
                    color = zeros([64, 3]);
                    color(pnt1:pnt2, 1) = linspace(0, 1, pnt2-pnt1+1)';
                    if pnt2 < 64; color(pnt2+1:end,1) = 1; end
                case 'blue'
                    color = zeros([64, 3]);
                    color(pnt1:pnt2, 3) = linspace(0, 1, pnt2-pnt1+1)';
                    if pnt2 < 64; color(pnt2+1:end, 3) = 1; end
                case 'custom'
                    color = obj.volumeColormap;
                otherwise
                    %cmdString = sprintf('color = %s(64);', obj.Settings.Volume.colormapName);
                    %eval(cmdString);
                    
                    cmdString = sprintf('color_temp = %s;', obj.Settings.Volume.colormapName);
                    eval(cmdString);
                    color = repmat(color_temp(1,:), [64, 1]); %#ok<USENS> 
                    queryPoints = linspace(1, 256, (pnt2-pnt1+1));
                    for colCh = 1:size(color_temp,2)
                        color(pnt1:pnt2, colCh) = interp1(1:256, color_temp(:,colCh), queryPoints);
                    end
                    if pnt2 < 64; color(pnt2+1:end, :) = repmat(color_temp(end,:), [64-pnt2, 1]); end

            end

            if obj.Settings.Volume.colormapInvert; color = flip(color); end
            colorPoints = linspace(0, 1, size(color,1));
            queryPoints = linspace(0, 1, 256);
            obj.volumeColormap = interp1(colorPoints, color, queryPoints);

            colormap(obj.view.handles.colormapAxes, color);
            colorbar(obj.view.handles.colormapAxes, 'Location', 'north', ...
                'Ticks', [0 0.25 0.5 0.75 1], 'TickLabels', {'0','64','128', '192', '255'}, ...
                'FontSize', 9);
            
            if ~isempty(obj.volume)
                obj.volume.Colormap = obj.volumeColormap;
                obj.view.handles.alphaAxes.Colormap = obj.volumeColormap;
            end
        end

        function updateCameraWidgets(obj)
            % UPDATECAMERAWIDGETS - Refresh camera position and orientation widgets.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateCameraWidgets()
            if ~isvalid(obj.viewer); return; end % skip when the viewer is closed

            obj.view.handles.cameraZoomEdit.Value = double(obj.viewer.CameraZoom);
            obj.view.handles.cameraPositionX.Value = double(obj.viewer.CameraPosition(1));
            obj.view.handles.cameraPositionY.Value = double(obj.viewer.CameraPosition(2));
            obj.view.handles.cameraPositionZ.Value = double(obj.viewer.CameraPosition(3));
            obj.view.handles.cameraTargetX.Value = double(obj.viewer.CameraTarget(1));
            obj.view.handles.cameraTargetY.Value = double(obj.viewer.CameraTarget(2));
            obj.view.handles.cameraTargetZ.Value = double(obj.viewer.CameraTarget(3));
            obj.view.handles.cameraUpVectorX.Value = double(obj.viewer.CameraUpVector(1));
            obj.view.handles.cameraUpVectorY.Value = double(obj.viewer.CameraUpVector(2));
            obj.view.handles.cameraUpVectorZ.Value = double(obj.viewer.CameraUpVector(3));
            obj.view.handles.cameraDistanceEdit.Value = double(sqrt(sum((obj.viewer.CameraPosition - obj.viewer.CameraTarget).^2)));
        end

        function menuChangeView(obj, event)
            % MENUCHANGEVIEW - Callback for standard orthogonal view menu items.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.menuChangeView(event)
            %
            % Input Arguments:
            %   - **event** - [event] UI callback event; ``event.Source.Tag`` selects the view:
            %
            %     - ``'menuDefaultView'`` - restore the saved default view
            %     - ``'menuXYview'`` - show the XY (top-down) view
            %     - ``'menuXZview'`` - show the XZ (front) view
            %     - ``'menuYZview'`` - show the YZ (side) view

            %cameraPos = obj.volume.CameraPosition
            %cameraTarget = obj.volume.CameraTarget
            %cameraDirection = (cameraPos - cameraTarget) / norm(cameraPos - cameraTarget)    % cameraDirection = glm::normalize(cameraPos - cameraTarget);

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.menuChangeView(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'menuDefaultView'
                    obj.viewer.CameraPosition = obj.defaultView.CameraPosition;
                    obj.viewer.CameraTarget = obj.defaultView.CameraTarget;
                    obj.viewer.CameraUpVector = obj.defaultView.CameraUpVector;
                    obj.viewer.CameraZoom = obj.defaultView.CameraZoom;
                case 'menuXYview'
                    obj.viewer.CameraPosition = [obj.defaultView.CameraTarget(1) obj.defaultView.CameraTarget(2) obj.defaultView.CameraTarget(3)*5];
                    obj.viewer.CameraTarget = obj.defaultView.CameraTarget;
                    obj.viewer.CameraUpVector = [1 0 0];
                case 'menuXZview'
                    obj.viewer.CameraPosition = [obj.defaultView.CameraTarget(1) obj.defaultView.CameraTarget(2)*5 obj.defaultView.CameraTarget(3)];
                    obj.viewer.CameraTarget = obj.defaultView.CameraTarget;
                    obj.viewer.CameraUpVector = [0 0 1];
                case 'menuYZview'
                    obj.viewer.CameraPosition = [obj.defaultView.CameraTarget(1)*5 obj.defaultView.CameraTarget(2) obj.defaultView.CameraTarget(3)];
                    obj.viewer.CameraTarget = obj.defaultView.CameraTarget;
                    obj.viewer.CameraUpVector = [0 0 1];
            end
            obj.viewer.CameraZoom = 1;
            %obj.viewer.CameraPosition = obj.viewer.CameraPosition.*obj.volumeScaleFactor;
        end

        function closeWindow(obj)
            % CLOSEWINDOW - Close the VolRenApp window and release resources.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.closeWindow()
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end

            % delete listeners, otherwise they stay after deleting of the
            % controller
            for i=1:numel(obj.listener)
                delete(obj.listener{i});
            end

            % tear down the live overlay update listener + debounce timer
            obj.disableLiveUpdate();

            % close child controllers
            for i=numel(obj.childControllers):-1:1
                if isvalid(obj.childControllers{i})
                    obj.childControllers{i}.closeWindow();
                end
            end
            obj.mibModel.preferences.VolRen = obj.Settings;

            notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
        end

        function delete(obj)
            % DELETE - Destructor: release live-update listeners/timer.
            %
            % Safety net for the case where the controller is destroyed without
            % ``closeWindow`` running - the live-update listeners live on the
            % persistent ``mibModel`` and would otherwise keep firing on a stale handle.
            obj.disableLiveUpdate();
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh all widgets in the VolRenApp panel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()

            obj.view.handles.showScaleBar.Value = obj.Settings.Viewer.showScaleBar;
            obj.view.handles.showOrientationAxes.Value = obj.Settings.Viewer.showOrientationAxes;
            obj.view.handles.showBox.Value = obj.Settings.Viewer.showBox;
            obj.view.handles.AmbientLight.Value = obj.Settings.Viewer.AmbientLight;
            obj.view.handles.DiffuseLight.Value = obj.Settings.Viewer.DiffuseLight;
            obj.view.handles.rendererDropDown.Value = obj.Settings.Volume.renderer;
            obj.view.handles.isovalueSlider.Value = obj.Settings.Volume.isosurfaceValue;
            obj.view.handles.isovalueEdit.Value = obj.Settings.Volume.isosurfaceValue;
            obj.view.handles.colormapName.Value = obj.Settings.Volume.colormapName;
            obj.view.handles.colormapInvert.Value = obj.Settings.Volume.colormapInvert;
            obj.view.handles.noFramesEditField.Value = obj.Settings.Animation.noFrames;
            obj.view.handles.colormapBlackPoint.Value = obj.Settings.Volume.colormapBlackPoint;
            obj.view.handles.colormapWhitePoint.Value = obj.Settings.Volume.colormapWhitePoint;
            
            % update lights
            obj.viewer.AmbientLight = obj.Settings.Viewer.AmbientLight;
            obj.viewer.DiffuseLight = obj.Settings.Viewer.DiffuseLight;

            % define rotation mode, in try as it is not documented 
            try
                % 'orbit' - rotation is done around the center of the volume
                % 'cursor' - rotation around the clicked object
                obj.viewer.Mode.Rotate.Style = obj.Settings.Viewer.rotationMode;
            catch err
                obj.view.handles.rotationMode.Items = {'orbit'};
                obj.Settings.Viewer.rotationMode = 'orbit';
            end
            obj.view.handles.rotationMode.Value = obj.Settings.Viewer.rotationMode;

            obj.plotAlphaPlot();
            obj.updateKeyFrameTable();
            obj.updateOverlayMaterialWidgets();
            obj.view.handles.menuBackgroundGradient.Checked = obj.Settings.Viewer.backgroundGradient;

            obj.childControllers{1}.view.handles.statusText.Text = sprintf('CameraPosition: %.3f x %.3f x %.3f --- CameraUpVector: %.3f x %.3f x %.3f --- CameraTarget: %.3f x %.3f x %.3f --- CameraZoom: %f', ...
                obj.viewer.CameraPosition(1), obj.viewer.CameraPosition(2), obj.viewer.CameraPosition(3), ...
                obj.viewer.CameraUpVector(1), obj.viewer.CameraUpVector(2), obj.viewer.CameraUpVector(3), ...
                obj.viewer.CameraTarget(1), obj.viewer.CameraTarget(2), obj.viewer.CameraTarget(3), ...
                obj.viewer.CameraZoom);

            % update child controllers
            for i=1:numel(obj.childControllers)
                obj.childControllers{i}.updateWidgets()
            end
        end

        function updateKeyFrameTable(obj)
            % UPDATEKEYFRAMETABLE - Refresh the key-frame table widget.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateKeyFrameTable()

            if ~isfield(obj.animationPath, 'CameraPosition')
                obj.view.handles.keyFrameTable.Data = [];
                return;
            end
            noFrames = size(obj.animationPath.CameraPosition, 1);
            Data = 1:noFrames;
            obj.view.handles.keyFrameTable.Data = Data;
            obj.view.handles.keyFrameTable.ColumnWidth = repmat({23}, [1, size(Data, 2)]);
            obj.view.handles.keyFrameTable.RowName = 'KeyFrames';
        end

        function addAnimationKeyFrame(obj, posIndex)
            % ADDANIMATIONKEYFRAME - Add or insert an animation key frame at the current view.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addAnimationKeyFrame()
            %      obj.addAnimationKeyFrame(posIndex)
            %
            % Input Arguments:
            %   - **posIndex** *(optional)* - [numeric] insertion position; ``1`` inserts at the beginning
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.addAnimationKeyFrame: triggered\n');
            end
            if nargin < 2
                if ~isfield(obj.animationPath, 'CameraPosition')
                    posIndex = 1;
                    obj.animationPath.CameraPosition = [];
                    obj.animationPath.CameraUpVector = [];
                    obj.animationPath.CameraTarget = [];
                else
                    posIndex = size(obj.animationPath.CameraPosition,1)+1;
                end
            end

            if posIndex == 1
                obj.animationPath.CameraPosition = [obj.viewer.CameraPosition; obj.animationPath.CameraPosition];
                obj.animationPath.CameraUpVector = [obj.viewer.CameraUpVector; obj.animationPath.CameraUpVector];
                obj.animationPath.CameraTarget = [obj.viewer.CameraTarget; obj.animationPath.CameraTarget];
            elseif posIndex <= size(obj.animationPath.CameraPosition,1)
                obj.animationPath.CameraPosition = [obj.animationPath.CameraPosition(1:posIndex-1, :); obj.viewer.CameraPosition; obj.animationPath.CameraPosition(posIndex:end, :)];
                obj.animationPath.CameraUpVector = [obj.animationPath.CameraUpVector(1:posIndex-1, :); obj.viewer.CameraUpVector; obj.animationPath.CameraUpVector(posIndex:end, :)];
                obj.animationPath.CameraTarget = [obj.animationPath.CameraTarget(1:posIndex-1, :); obj.viewer.CameraTarget; obj.animationPath.CameraTarget(posIndex:end, :)];
            else
                obj.animationPath.CameraPosition(posIndex, :) = obj.viewer.CameraPosition;
                obj.animationPath.CameraUpVector(posIndex, :) = obj.viewer.CameraUpVector;
                obj.animationPath.CameraTarget(posIndex, :) = obj.viewer.CameraTarget;
            end
            obj.updateKeyFrameTable();
        end

        function keyFrameTable_CellSelection(obj, indices)
            % KEYFRAMETABLE_CELLSELECTION - Handle cell selection in the key-frame table.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.keyFrameTable_CellSelection(indices)
            %
            % Input Arguments:
            %   - **indices** - [numeric] selected cell indices ``[row, col]``

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.keyFrameTable_CellSelection: triggered\n');
            end
            if nargin < 2; indices = obj.keyFrameTableIndex; end

            obj.keyFrameTableIndex = indices;
            if obj.view.handles.autoJumpCheckBox.Value == 1 && ~isempty(indices)
                % update the view
                obj.viewer.CameraPosition = obj.animationPath.CameraPosition(obj.keyFrameTableIndex, :);
                obj.viewer.CameraUpVector = obj.animationPath.CameraUpVector(obj.keyFrameTableIndex, :);
                obj.viewer.CameraTarget = obj.animationPath.CameraTarget(obj.keyFrameTableIndex, :);
            end
        end

        function surfaceTable_CellSelection(obj, indices)
            % SURFACETABLE_CELLSELECTION - Handle cell selection in the surface table.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.surfaceTable_CellSelection(indices)
            %
            % Input Arguments:
            %   - **indices** - [numeric] selected cell indices ``[row, col]``
            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.surfaceTable_CellSelection: triggered\n');
            end
            if nargin < 2; indices = obj.surfaceTableIndex; end
            try
                obj.surfaceTableIndex = unique(indices(:,1));
            catch err
                utils.dlgs.showErrorDialog(obj.view.gui, err, 'surfaceTable_CellSelection errpor');
                return;
            end
            
            if numel(obj.surfaceTableIndex) == 1 && indices(2) == 1  % change color
                newColor = uisetcolor(obj.surfList{obj.surfaceTableIndex}.Color, 'Set color');
                if newColor==0; return; end

                obj.surfList{obj.surfaceTableIndex}.Color = newColor;
                obj.updateSurfaceTable();
            end
        end

        
        function modelTable_CellSelection(obj, indices)
            % MODELTABLE_CELLSELECTION - Handle cell selection in the model/overlay table.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.modelTable_CellSelection(indices)
            %
            % Input Arguments:
            %   - **indices** - [numeric] selected cell indices ``[row, col]``
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.modelTable_CellSelection: triggered\n');
            end
            if nargin < 2; indices = obj.modelTableIndex; end

            obj.modelTableIndex = indices;
        end

        function loadAnimationPath(obj)
            % LOADANIMATIONPATH - Load an animation path from a ``.animation`` file.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.loadAnimationPath()

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.loadAnimationPath: triggered\n');
            end
            mypath = fileparts(obj.animationFilename);
            [filename, path] = utils.dlgs.mibUiGetFile(...
                {'*.animation;',  'Matlab format (*.animation)'; ...
                '*.*', 'All Files (*.*)'}, ...
                'Load animation...', mypath);
            if isequal(filename, 0); return; end % check for cancel
            obj.animationFilename = fullfile(path, filename{1});

            res = load(obj.animationFilename, '-mat');
            if ~isfield(res, 'animPath')
                uialert(obj.view.gui, ...
                    'Missing the animPath field!', 'Error');
                return;
            end
            obj.animationPath = res.animPath;
            fprintf('The animation was loaded:\n%s\n', obj.animationFilename);
            obj.updateWidgets();
        end

        function saveAnimationPath(obj)
            % SAVEANIMATIONPATH - Save the current animation path to a ``.animation`` file.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.saveAnimationPath()
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.saveAnimationPath: triggered\n');
            end
            if ~isfield(obj.animationPath, 'CameraPosition')
                uialert(obj.view.gui, ...
                    sprintf('!!! Error !!!\n\nThe animation path is not present!\nPlease use the Animation tab to make it!'), ...
                    'Missing animation');
                return;
            end

            [filename, path, FilterIndex] = uiputfile(...
                {'*.animation',  'Matlab format (*.animation)'; ...
                '*.*',  'All Files (*.*)'}, ...
                'Save animation...', obj.animationFilename);
            if isequal(filename, 0); return; end % check for cancel
            obj.animationFilename = fullfile(path, filename);

            animPath = obj.animationPath;
            save(obj.animationFilename, 'animPath', '-v7.3');
            fprintf('The animation was saved to\n%s\n', obj.animationFilename);
        end


        function deleteAllAnimationKeyFrames(obj)
            % DELETEALLANIMATIONKEYFRAMES - Delete all animation key frames after user confirmation.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.deleteAllAnimationKeyFrames()

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.deleteAllAnimationKeyFrames: triggered\n');
            end
            answer = uiconfirm(obj.view.gui, ...
                sprintf('!!! Warning !!!\nYou are going to remove all key frames!\nContinue?'), ...
                'Delete key frames', 'Options', {'Continue','Cancel'}, ...
                'Icon','warning', 'DefaultOption', 'Cancel');
            if strcmp(answer, 'Cancel'); return; end

            obj.animationPath = struct();
            obj.updateKeyFrameTable();
        end

        function previewAnimation(obj, noFrames)
            % PREVIEWANIMATION - Preview the key-frame animation in the viewer.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.previewAnimation()
            %      obj.previewAnimation(noFrames)
            %
            % Input Arguments:
            %   - **noFrames** *(optional)* - [numeric] number of interpolated frames
            %     (default: ``obj.Settings.Animation.noFrames``)

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.previewAnimation: triggered\n');
            end
            if nargin < 2; noFrames = obj.Settings.Animation.noFrames; end
            if ~isfield(obj.animationPath, 'CameraPosition'); return; end

            if obj.animationPreviewRunning
                % cancel animation
                obj.animationPreviewRunning = false;
                return;
            end
            obj.animationPreviewRunning = true;
            obj.view.handles.previewAnimationButton.Text = 'Stop animation';
            obj.view.handles.previewAnimationButton.BackgroundColor = utils.themeColors(obj.view.gui).dialogStop;

            positions = obj.generatePositionsForKeyFramesAnimation(noFrames);

            framerate = 24;
            for idx = 1:size(positions.CameraPosition, 1)
                if ~obj.animationPreviewRunning
                    % stop animation
                    obj.view.handles.previewAnimationButton.Text = 'Preview';
                    obj.view.handles.previewAnimationButton.BackgroundColor = utils.themeColors(obj.view.gui).dialogAction;
                    return
                end
                obj.viewer.CameraPosition = positions.CameraPosition(idx, :);
                obj.viewer.CameraUpVector = positions.CameraUpVector(idx, :);
                if ~isempty(positions.CameraTarget)
                    obj.viewer.CameraUpVector = positions.CameraTarget(idx, :);
                end
                %obj.volume.CameraUpVector = myUpVector(idx, :);
                % obj.mibVolRenGUI_VolumeMotionFcn();
                pause(1/framerate);
            end
            obj.view.handles.previewAnimationButton.Text = 'Preview';
            obj.view.handles.previewAnimationButton.BackgroundColor = utils.themeColors(obj.view.gui).dialogAction;
            obj.animationPreviewRunning = false;
        end

        function positions = generatePositionsForKeyFramesAnimation(obj, noFrames, options)
            % GENERATEPOSITIONSFORKEYFRAMESANIMATION - Interpolate camera positions from key frames.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      positions = obj.generatePositionsForKeyFramesAnimation(noFrames)
            %      positions = obj.generatePositionsForKeyFramesAnimation(noFrames, options)
            %
            % Input Arguments:
            %   - **noFrames** - [numeric] total number of interpolated frames
            %   - **options** *(optional)* - struct with additional parameters:
            %
            %     - ``.back_and_forth`` - [logical] when ``1``, animate forward then reverse
            %
            % Output Arguments:
            %   - **positions** - struct with per-frame camera data:
            %
            %     - ``.CameraPosition`` - ``[N x 3]`` interpolated camera positions
            %     - ``.CameraUpVector`` - ``[N x 3]`` interpolated camera-up vectors
            %     - ``.CameraTarget`` - ``[]`` (target is fixed; reserved for future use)

            if nargin < 3; options = struct(); end
            if nargin < 2; noFrames = obj.Settings.Animation.noFrames; end
            if ~isfield(obj.animationPath, 'CameraPosition')
                uialert(obj.view.gui, ...
                    sprintf('!!! Error !!!\n\nThe key frames are required for the animation\nAdd key frames by pressing the Add button and repeat!'), ...
                    'Missing key frames');
                return;
            end

            if ~isfield(options, 'back_and_forth'); options.back_and_forth = 0; end

            % cumulative sum of distances
            distVec = [0; cumsum(sqrt(sum(diff(obj.animationPath.CameraPosition).^2,2)))];
            notOk = 1;
            while notOk
                [~, ids] = unique(distVec);     % shift duplicates slightly
                if numel(ids) < numel(distVec)
                    distVec(~ismember(1:numel(distVec), ids)) = distVec(~ismember(1:numel(distVec), ids))+.000001;
                else
                    notOk = 0;
                end
            end

            % interpolate points for camera path
            warning_state = warning('off');
            flyCameraPath = interp1(distVec, obj.animationPath.CameraPosition, unique([distVec(:)' linspace(0, distVec(end), noFrames)]), 'v5cubic');
            warning(warning_state); % Switch warning back to initial settings

            % preview the camera path
            %             figure(322);
            %             plot3(obj.animationPath.CameraPosition(:,1), obj.animationPath.CameraPosition(:,2), obj.animationPath.CameraPosition(:,3));
            %             hold on;
            %             plot3(flyCameraPath(:,1), flyCameraPath(:,2), flyCameraPath(:,3));

            %                     distVec = [0; cumsum(sqrt(sum(diff(obj.animationPath.CameraUpVector).^2,2)))];
            %                     notOk = 1;
            %                     while notOk
            %                         [~, ids] = unique(distVec);     % shift duplicates slightly
            %                         if numel(ids) < numel(distVec)
            %                             distVec(~ismember(1:5, ids)) = distVec(~ismember(1:5, ids))+.000001;
            %                         else
            %                             notOk = 0;
            %                         end
            %                     end
            flyCameraUpVectorPath = interp1(distVec, obj.animationPath.CameraUpVector, unique([distVec(:)' linspace(0, distVec(end), noFrames)]), 'pchip');

            if options.back_and_forth == 1
                flyCameraPath = [flyCameraPath; flip(flyCameraPath, 1)];
                flyCameraUpVectorPath = [flyCameraUpVectorPath; flip(flyCameraUpVectorPath, 1)];
            end

            positions.CameraPosition = flyCameraPath;
            positions.CameraUpVector = flyCameraUpVectorPath;
            positions.CameraTarget = [];
            %obj.viewer.CameraUpVector = positions.CameraUpVector;
            %obj.viewer.CameraTarget = positions.CameraTarget;
        end

        function updateAnimationNumberOfFrames(obj, noFrames)
            % UPDATEANIMATIONNUMBEROFFRAMES - Update the stored animation frame count.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateAnimationNumberOfFrames(noFrames)
            %
            % Input Arguments:
            %   - **noFrames** - [numeric] new frame count stored in ``obj.Settings.Animation.noFrames``

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.updateAnimationNumberOfFrames: triggered\n');
            end
            obj.Settings.Animation.noFrames = noFrames;
        end

        function modelTable_cm_Callback(obj, event)
            % MODELTABLE_CM_CALLBACK - Callback for the model table context menu.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.modelTable_cm_Callback(event)
            %
            % Input Arguments:
            %   - **event** - [event] UI callback event; ``event.Source.Tag`` selects the action:
            %
            %     - ``'modelTable_cm_generateSurface'`` - generate a surface mesh from the selected rows
            %     - ``'modelTable_cm_generateSurfaceByIndex'`` - ask for a material index and generate
            %       its surface; the only option in the cycled color mode, where a table row stands
            %       for 255 materials rather than one
            %     - ``'modelTable_cm_removeMaterials'`` - drop the selected rows from the
            %       ``'Selected materials'`` list and refresh the overlay
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.modelTable_cm_Callback(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'modelTable_cm_generateSurface'
                    rowIds = obj.modelTableIndex;     % get indices of the selected rows
                    if isempty(rowIds); return; end
                    if isempty(obj.overlayRowMaterials)
                        if obj.overlayIsFusedInstances()
                            % The objects were fused on read, so the displayed layer
                            % genuinely has one material and a single merged surface is
                            % the only thing this row can mean. Offer it rather than
                            % refusing - refusing would be advising the user to switch
                            % to a mode that this layer is deliberately not in.
                            if obj.generateFusedInstancesSurface(); obj.updateSurfaceTable(); end
                            return;
                        end
                        % In the cycled-colour mode the single row stands for every
                        % material, so the row's own meaning is "all of them" - one
                        % surface per object.
                        if obj.generateAllObjectSurfaces(); obj.updateSurfaceTable(); end
                        return;
                    end

                    wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Generating surfaces\nPlease wait...'), ...
                        'Title', 'Generate surfaces', 'Cancelable', 'on');
                    for rowIndex = 1:numel(rowIds)
                        if wb.CancelRequested; break; end
                        wb.Value = rowIndex/numel(rowIds);
                        rowId = rowIds(rowIndex);
                        mask = (obj.volume.OverlayData == rowId);   % generate mask from the material
                        obj.addSurfaceFromMask(mask, obj.overlayRowNames{rowId}, obj.overlayRowColors(rowId, :));
                    end
                    cancelled = wb.CancelRequested;
                    delete(wb);
                    obj.updateSurfaceTable();
                    if cancelled
                        fprintf('controllers.VolRenApp: surface generation cancelled, %d of %d surfaces were made\n', ...
                            rowIndex-1, numel(rowIds));
                    end
                case 'modelTable_cm_generateSurfaceByIndex'
                    obj.generateSurfaceByMaterialIndex();
                case 'modelTable_cm_removeMaterials'
                    rowIds = obj.modelTableIndex;
                    if isempty(rowIds) || isempty(obj.overlayRowMaterials); return; end
                    if ~strcmp(obj.overlayMaterialsMode, 'Selected materials'); return; end
                    obj.overlayMaterialsSelection = setdiff(obj.overlayMaterialsSelection, obj.overlayRowMaterials(rowIds));
                    obj.view.handles.overlayMaterialsList.Value = obj.materialsSelectionAsText();
                    obj.modelTableIndex = [];
                    obj.modelUpdateOverlay();
            end
        end

        function surfaceTable_cm_Callback(obj, event)
            % SURFACETABLE_CM_CALLBACK - Callback for the surface table context menu.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.surfaceTable_cm_Callback(event)
            %
            % Input Arguments:
            %   - **event** - [event] UI callback event; ``event.Source.Tag`` selects the action:
            %
            %     - ``'surfaceTable_cm_saveSurface'`` - save the selected surface to an STL file
            %     - ``'surfaceTable_cm_removeSurface'`` - delete the selected surface from the viewer
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.surfaceTable_cm_Callback(%s): triggered\n', event.Source.Tag);
            end
            id = obj.mibModel.getActiveId();
            switch event.Source.Tag
                case 'surfaceTable_cm_saveSurface'
                    if isempty(obj.surfaceTableIndex); return; end

                    [path, fnTemplate] = fileparts(obj.mibModel.I{id}.image.filename);
                    outputFilename = fullfile(path, sprintf('Surf_%s.stl', fnTemplate));
                    [filename, path] = uiputfile(...
                        {'*.stl',  'STL format (*.stl)'; ...
                        '*.*',  'All Files (*.*)'}, ...
                        'Set template filename for saving...', outputFilename);
                    if isequal(filename, 0); return; end % check for cancel
                    [~, filenameTemplate, ext] = fileparts(filename);
                    
                    % make waitbar
                    pwb = core.PoolWaitbar(numel(obj.surfaceTableIndex), sprintf('Exporting surface(s)\nPlease wait...'), obj.view.gui, 'Export surfaces', true);

                    for surfIndex = 1:numel(obj.surfaceTableIndex)
                        surfId = obj.surfaceTableIndex(surfIndex);
                        pwb.updateText(sprintf('Exporting %s surface\nPlease wait...', obj.view.handles.surfaceTable.Data{surfId,2}));

                        [fv.faces, fv.vertices] = extractIsosurface(obj.surfList{surfId}.Data, 0.5);
                        outputFilename = fullfile(path, sprintf('%s_%s%s', filenameTemplate, obj.view.handles.surfaceTable.Data{surfId,2}, ext));

                        stlwrite(outputFilename, fv, 'FaceColor',obj.surfList{surfId}.Color*255);
                        if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
                        pwb.increment();
                    end
                    pwb.deletePoolWaitbar();
                case 'surfaceTable_cm_removeSurface'
                    selection = uiconfirm(obj.view.gui, ...
                        sprintf('!!! Warning !!!\n\nYou are going to remove selected surfaces!\nContinue?'), ...
                        'Remove surface(s)',...
                        'Icon','warning');
                    if strcmp(selection, 'Cancel'); return; end
                    wb = waitbar(0, sprintf('Removing surface(s)\nPlease wait...'));
                    obj.viewer.Children(obj.surfaceTableIndex+1).delete();
                    obj.surfList(obj.surfaceTableIndex) = [];
                    obj.surfListAlpha(obj.surfaceTableIndex) = [];
                    obj.surfListShown(obj.surfaceTableIndex) = [];
                    obj.surfaceTableIndex = [];
                    if isempty(obj.surfList)
                        obj.view.handles.surfaceTable.Data = [];
                    else
                        obj.updateSurfaceTable();
                    end
                    delete(wb);
            end
        end
        
        
        function keyFrameTable_cm_Callback(obj, event)
            % KEYFRAMETABLE_CM_CALLBACK - Callback for the key-frame table context menu.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.keyFrameTable_cm_Callback(event)
            %
            % Input Arguments:
            %   - **event** - [event] UI callback event; ``event.Source.Tag`` selects the action:
            %
            %     - ``'keyFrameTable_cm_jumpToKeyFrame'`` - jump to the selected key frame
            %     - ``'keyFrameTable_cm_insertKeyFrame'`` - insert a key frame at the current position
            %     - ``'keyFrameTable_cm_replaceKeyFrame'`` - replace the selected key frame with the current view
            %     - ``'keyFrameTable_cm_removeKeyFrame'`` - remove the selected key frame

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.keyFrameTable_cm_Callback(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'keyFrameTable_cm_jumpToKeyFrame'
                    obj.viewer.CameraPosition = obj.animationPath.CameraPosition(obj.keyFrameTableIndex, :);
                    obj.viewer.CameraUpVector = obj.animationPath.CameraUpVector(obj.keyFrameTableIndex, :);
                    obj.viewer.CameraTarget = obj.animationPath.CameraTarget(obj.keyFrameTableIndex, :);
                    return;
                case 'keyFrameTable_cm_insertKeyFrame'
                    if obj.keyFrameTableIndex == 1
                        answer = questdlg(sprintf('Would you like to insert a frame before or after the selected frame index?'), 'Insert frame', 'Before', 'After', 'Cancel', 'Before');
                        if strcmp(answer, 'Cancel'); return; end
                        if strcmp(answer, 'Before'); obj.keyFrameTableIndex = 0; end
                    end
                    obj.addAnimationKeyFrame(obj.keyFrameTableIndex+1);
                    obj.keyFrameTableIndex = [];
                case 'keyFrameTable_cm_replaceKeyFrame'
                    obj.animationPath.CameraPosition(obj.keyFrameTableIndex, :) = obj.viewer.CameraPosition;
                    obj.animationPath.CameraUpVector(obj.keyFrameTableIndex, :) = obj.viewer.CameraUpVector;
                    obj.animationPath.CameraTarget(obj.keyFrameTableIndex, :) = obj.viewer.CameraTarget;
                case 'keyFrameTable_cm_removeKeyFrame'
                    obj.animationPath.CameraPosition(obj.keyFrameTableIndex, :) = [];
                    obj.animationPath.CameraUpVector(obj.keyFrameTableIndex, :) = [];
                    obj.animationPath.CameraTarget(obj.keyFrameTableIndex, :) = [];
                    obj.keyFrameTableIndex = [];
            end
            obj.updateKeyFrameTable();
        end

        function alphaCurveOperations(obj, event)
            % ALPHACURVEOPERATIONS - Callback for alpha curve control buttons.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.alphaCurveOperations(event)
            %
            % Input Arguments:
            %   - **event** - [event] UI callback event; ``event.Source.Tag`` selects the action:
            %
            %     - ``'resetAlphaCurve'`` - reset the alpha curve to the default
            %     - ``'invertAlphaCurve'`` - invert the alpha curve along the x-axis

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.alphaCurveOperations(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'resetAlphaCurve'      % reset the alpha curve
                    obj.volumeAlphaCurve.x = obj.Settings.Volume.volumeAlphaCurve.x;
                    obj.volumeAlphaCurve.y = obj.Settings.Volume.volumeAlphaCurve.y;
                    %Prefs.VolRen.Volume.volumeAlphaCurve.x = [0 .3 .7 1];
                    %Prefs.VolRen.Volume.volumeAlphaCurve.y = [1 1 0 0];
                case 'invertAlphaCurve'   % invert the alpha curve
                    obj.volumeAlphaCurve.x = 1 - obj.volumeAlphaCurve.x;
                    [obj.volumeAlphaCurve.x, indices] = sort(obj.volumeAlphaCurve.x);
                    obj.volumeAlphaCurve.y = obj.volumeAlphaCurve.y(indices);
            end
            obj.volumeAlphaCurve.activePoint = [];
            obj.recalculateAlphamap();
            obj.plotAlphaPlot();
        end

        function plotAlphaPlot(obj)
            % PLOTALPHAPLOT - Redraw the alpha curve plot in ``obj.view.handles.alphaAxes``.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.plotAlphaPlot()

            cla(obj.view.handles.alphaAxes);
            hold(obj.view.handles.alphaAxes, 'on');
            obj.alphaPlotHandle{1} = plot(obj.view.handles.alphaAxes, [0 obj.maxIntValue], [0 0], 'Color', [0.5 0.5 0.5]);
            obj.alphaPlotHandle{2} = plot(obj.view.handles.alphaAxes, [0 obj.maxIntValue], [1 1], 'Color', [0.5 0.5 0.5]);

            obj.alphaPlotHandle{3} = plot(obj.view.handles.alphaAxes, obj.volumeAlphaCurve.x*obj.maxIntValue, obj.volumeAlphaCurve.y, '.-', 'Color', [0    0.4470    0.7410]);
            obj.alphaPlotHandle{3}.MarkerSize = obj.Settings.Volume.markerSize;

            if ~isempty(obj.volumeAlphaCurve.activePoint)
                obj.alphaPlotHandle{4} = plot(obj.view.handles.alphaAxes, obj.volumeAlphaCurve.x(obj.volumeAlphaCurve.activePoint)*obj.maxIntValue, obj.volumeAlphaCurve.y(obj.volumeAlphaCurve.activePoint), 'r.');
                obj.alphaPlotHandle{4}.MarkerSize = obj.Settings.Volume.markerSize+2;
            end

            obj.view.handles.alphaAxes.XLim = [0, obj.maxIntValue];
            obj.view.handles.alphaAxes.YLim = [-0.1, 1.1];
            obj.view.handles.alphaAxes.YLabel.String = 'Opacity';
        end

        function toggleViewerSettings(obj, event)
            % TOGGLEVIEWERSETTINGS - Toggle viewer display settings on or off.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.toggleViewerSettings(event)
            %
            % Input Arguments:
            %   - **event** - [event] UI callback event from the toggled widget
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.toggleViewerSettings(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'showScaleBar'
                    obj.viewer.ScaleBar = event.Value;
                    obj.Settings.Viewer.showScaleBar = event.Value;
                    obj.viewer.ScaleBarUnits = obj.Settings.Viewer.scaleBarUnits;
                case 'showOrientationAxes'
                    obj.viewer.OrientationAxes = event.Value;
                    obj.Settings.Viewer.showOrientationAxes = event.Value;
                case 'showBox'
                    obj.viewer.Box  = event.Value;
                    obj.Settings.Viewer.showBox = event.Value;
                case 'rotationMode'
                    % update the rotation mode
                    % 'orbit' - rotation is done around the center of the volume
                    % 'cursor' - rotation around the clicked object
                    obj.viewer.Mode.Rotate.Style = event.Value;
                    obj.Settings.Viewer.rotationMode = event.Value;
                case 'AmbientLight'
                    obj.viewer.AmbientLight  = event.Value;
                    obj.Settings.Viewer.AmbientLight = event.Value;
                case 'DiffuseLight'
                    obj.viewer.DiffuseLight  = event.Value;
                    obj.Settings.Viewer.DiffuseLight = event.Value;
            end
        end


        function updateScalingTransform(obj, pixSize)
            % UPDATESCALINGTRANSFORM - Generate the affine scaling transform for the volume.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateScalingTransform(pixSize)
            %
            % Builds ``obj.scalingTransform`` (an ``affinetform3d``) from the pixel size
            % so that the dataset is displayed with units in µm.
            %
            % Input Arguments:
            %   - **pixSize** - [struct] MIB pixel-size structure:
            %
            %     - ``.x`` - pixel size in X (µm/pixel)
            %     - ``.y`` - pixel size in Y (µm/pixel)
            %     - ``.z`` - slice thickness in Z (µm/slice)

            Sx = pixSize.x;   % scaling pixels to um ratio, x-axis
            Sy = pixSize.y;   % scaling pixels to um ratio, y-axis
            Sz = pixSize.z;   % scaling pixels to um ratio, z-axis

            % Create the transformation matrix
            T = [Sx 0 0 0; 0 Sy 0 0; 0 0 Sz 0; 0 0 0 1];

            % Create an affine transform
            % use this transform later during initialization of volumes as:
            % vol = volshow(V, 'Transformation', obj.scalingTransform, parent=obj.viewer);
            obj.scalingTransform = affinetform3d(T);
        end

        function imgOut = grabFrame(obj, width, height, options)
            % GRABFRAME - Capture a frame image from the volume viewer panel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      imgOut = obj.grabFrame(width, height)
            %      imgOut = obj.grabFrame(width, height, options)
            %
            % The ``getframe`` call below costs close to a second because the pixels have to
            % be read back out of the WebGL canvas that ``viewer3d`` renders into; the volume
            % rendering itself takes about 20 ms. That is a MATLAB limitation with no faster
            % public API - see ``development/notes/volren_movie_capture_speed.md`` for the
            % measurements and the routes already ruled out, before trying to optimise it.
            %
            % Input Arguments:
            %   - **width** - [numeric] snapshot width in pixels; ``[]`` uses the current panel width
            %   - **height** - [numeric] snapshot height in pixels; ``[]`` uses the current panel height
            %   - **options** *(optional)* - struct with extra parameters:
            %
            %     - ``.resizeWindow`` - [numeric] ``1`` resize window before capture, ``0`` skip (default: ``1``)
            %     - ``.showWaitbar`` - [logical] show a progress waitbar (default: ``true``)
            %     - ``.hWaitbar`` - [handle] handle to an existing waitbar dialog
            %     - ``.waitbarProgress`` - [numeric] waitbar fill fraction (default: ``0.5``)
            %
            % Output Arguments:
            %   - **imgOut** - [uint8] ``[height x width x 3]`` RGB image array
            %
            % Errors:
            %   - ``MIB:VolRenApp:grabFrame:frameTooLarge`` - the requested width/height
            %     exceeds the visible area of the screen, so the viewer window cannot be
            %     resized to fit the frame. The window is restored before the error is
            %     thrown; callers are expected to catch it and show
            %     ``utils.dlgs.showErrorDialog``. When ``options.resizeWindow`` is ``0``
            %     restoring the window is left to the caller.
            %
            % **Example 1** - capture frames inside an animation loop:
            %
            %   .. code-block:: matlab
            %
            %      obj.prepareWindowForGrabFrame(width, height);
            %      options.resizeWindow = 0;
            %      for i = 1:100
            %          % change view
            %          imgOut = obj.extraController.grabFrame(width, height, options);
            %      end
            %      obj.extraController.restoreWindowAfterGrabFrame();
            %
            % **Example 2** - single snapshot (e.g., from mibSnapshotController):
            %
            %   .. code-block:: matlab
            %
            %      imgOut = obj.extraController.grabFrame(width, height);

            deleteWaitbar = 0;  % delete or not waitbar after in the end

            if nargin < 4; options = struct; end
            if ~isfield(options, 'resizeWindow'); options.resizeWindow = 1; end
            if ~isfield(options, 'showWaitbar'); options.showWaitbar = 1; end
            if ~isfield(options, 'hWaitbar')
                if options.showWaitbar
                    options.hWaitbar = waitbar(0, sprintf('Grabbing the frame\nPlease wait...'));
                    deleteWaitbar = 1;
                end
            end
            if ~isfield(options, 'waitbarProgress'); options.waitbarProgress = 0.5; end

            if options.showWaitbar; waitbar(options.waitbarProgress, options.hWaitbar); end

            if isempty(width)
                width = obj.childControllers{1}.view.handles.volumeViewerPanel.Position(3);
            end
            if isempty(height)
                height = obj.childControllers{1}.view.handles.volumeViewerPanel.Position(4);
            end
            if options.resizeWindow == 1; obj.prepareWindowForGrabFrame(width, height); end

            panelPosition = obj.childControllers{1}.view.handles.volumeViewerPanel.Position;
            panelPosition(1) = panelPosition(1)-1;
            panelPosition(2) = panelPosition(2)-1;
            panelPosition(3) = width;
            panelPosition(4) = height;

            % the window cannot grow past the desktop, so a frame larger than the screen
            % (minus taskbar and title bar) leaves the panel smaller than requested and
            % getframe fails with "the specified rectangle is not fully contained within
            % the figure". Detect it here and report the largest frame that can be grabbed
            figurePosition = obj.childControllers{1}.view.gui.Position;
            if panelPosition(1) < 0 || panelPosition(2) < 0 || ...
                    panelPosition(1) + panelPosition(3) > figurePosition(3) || ...
                    panelPosition(2) + panelPosition(4) > figurePosition(4)
                maxWidth = floor(obj.childControllers{1}.view.handles.volumeViewerPanel.Position(3));
                maxHeight = floor(obj.childControllers{1}.view.handles.volumeViewerPanel.Position(4));
                if options.resizeWindow == 1; obj.restoreWindowAfterGrabFrame(); end
                if deleteWaitbar; delete(options.hWaitbar); end
                error('MIB:VolRenApp:grabFrame:frameTooLarge', ...
                    ['The requested frame (%d x %d px) does not fit on the screen.\n\n' ...
                     'Frames of the volume rendering are grabbed from the viewer window, so they ' ...
                     'cannot be larger than the visible area of the screen.\n\n' ...
                     'The largest frame that can be grabbed now is %d x %d px.'], ...
                    width, height, maxWidth, maxHeight);
            end

            I = getframe(obj.childControllers{1}.view.gui, panelPosition);

            imgOut = I.cdata;
            % imclipboard('copy', I.cdata);

            % restore the widget sizes
            if options.resizeWindow == 1; obj.restoreWindowAfterGrabFrame(); end

            if deleteWaitbar; delete(options.hWaitbar); end
        end

        function prepareWindowForGrabFrame(obj, width, height)
            % PREPAREWINDOWFORGRABFRAME - Resize and prepare the viewer window for frame capture.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.prepareWindowForGrabFrame(width, height)
            %
            % Stores current window geometry, hides the toolbar, and sets the
            % viewer panel to exactly ``width × height`` pixels ready for ``grabFrame``.
            %
            % Input Arguments:
            %   - **width** - [numeric] desired capture width in pixels
            %   - **height** - [numeric] desired capture height in pixels
            %
            % Usage example:
            %
            %   .. code-block:: matlab
            %
            %      obj.extraController.prepareWindowForGrabFrame(width, height);
            %      imgOut = obj.extraController.grabFrame(width, height);
            %      obj.extraController.restoreWindowAfterGrabFrame();

            % store current positions
            obj.figPosStored.mibVolRenAppFigure = obj.childControllers{1}.view.gui.Position;
            obj.figPosStored.mainGridLayoutRowHeights = obj.childControllers{1}.view.handles.mainGridLayout.RowHeight;

            % collapse elements of the grid
            obj.childControllers{1}.view.handles.mainGridLayout.RowHeight = [{'1x'}, {0}];

            obj.childControllers{1}.view.gui.Position(1) = 1;
            obj.childControllers{1}.view.gui.Position(2) = 1;
            obj.childControllers{1}.view.gui.Position(3) = width+obj.childControllers{1}.view.handles.mainGridLayout.Padding(1)+obj.childControllers{1}.view.handles.mainGridLayout.Padding(3)+1;
            obj.childControllers{1}.view.gui.Position(4) = height+obj.childControllers{1}.view.handles.mainGridLayout.Padding(2)+obj.childControllers{1}.view.handles.mainGridLayout.Padding(4)+1;
            % hide menu
            %obj.childControllers{1}.view.handles.FileMenu.Visible = 'off';
            % hide toolbar
            obj.viewer.Toolbar = 'off';

            drawnow;
            pause(.5);
        end

        function restoreWindowAfterGrabFrame(obj)
            % RESTOREWINDOWAFTERGRABFRAME - Restore viewer window geometry after frame capture.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.restoreWindowAfterGrabFrame()
            %
            % Reverses the changes made by ``prepareWindowForGrabFrame``,
            % restoring the original panel size and toolbar visibility.

            % restore positions of the widgets
            obj.childControllers{1}.view.gui.Position = obj.figPosStored.mibVolRenAppFigure;
            obj.childControllers{1}.view.handles.mainGridLayout.RowHeight = obj.figPosStored.mainGridLayoutRowHeights;

            % show menu
            %obj.view.handles.FileMenu.Visible = 'on';
            % restore toolbar
            obj.viewer.Toolbar = 'on';
            
            obj.figPosStored.mibVolRenAppFigure = [];
            obj.figPosStored.mainGridLayoutRowHeights = [];
        end

        function makeAnimation(obj, mode)
            % MAKEANIMATION - Open the MakeMovie dialog for recording an animation.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.makeAnimation(mode)
            %
            % Input Arguments:
            %   - **mode** - [char] animation type:
            %
            %     - ``'spin'`` - rotate camera around the selected axis
            %     - ``'animation'`` - animate the scene using stored key frames

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.makeAnimation(%s): triggered\n', mode);
            end
            options.mode = mode;    % mode for movie make
            utils.startController(obj, 'controllers.MakeMovie', obj, options);
        end


        function getOptions = levelReadOptions(obj, layerType)
            % LEVELREADOPTIONS - ``getData3D`` options that read one layer at the level picked in the dialog.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      getOptions = obj.levelReadOptions(layerType)
            %
            % ``obj.pyramidLevel`` indexes the **image** pyramid, which is the only
            % list the level dialog shows. Passing it straight through as
            % ``options.pyramidLevel`` is right for every layer served from that same
            % pyramid, and wrong for a ``core.MibBigDataLabelsIndex`` overlay, which
            % is served from a pyramid of its own that starts coarser and has fewer
            % levels: ``jrc_mus-kidney``'s ``nuc`` has 5 levels from 128 nm where the
            % EM has 12 from 8 nm, so image level 5 means the labels' level 5 - two
            % levels past the end of the store, clamped to its coarsest - and the
            % overlay arrives 16x too coarse, then stretched onto the volume by the
            % ``imresize3`` fallback.
            %
            % For that layer the level is therefore expressed as a **magnification**
            % instead: the scale factor of the chosen image level, in the shared
            % scale space :attr:`core.MibBigDataLabelsIndex.imageScaleFactors`
            % registers both pyramids into. ``getData`` then picks the nearest label
            % level itself and gathers it onto the image level's grid, so the overlay
            % comes back at the image level's dimensions - aligned rather than
            % resized, which is the distinction the class exists for.
            %
            % Input Arguments:
            %   - **layerType** - [char] layer about to be read: ``'image'``,
            %     ``'labels'``, ``'mask'`` or ``'selection'``
            %
            % Output Arguments:
            %   - **getOptions** - [struct] options for ``getData3D``; empty for a
            %     Standard dataset, which downsamples with ``obj.volumeScaleFactor``
            %     after the read instead

            getOptions = struct();
            id = obj.mibModel.getActiveId();
            if obj.mibModel.I{id}.datasetType(1) ~= 'B'; return; end

            getOptions.blockModeSwitch = 0;   % render the whole level, not the shown block

            labels = obj.mibModel.I{id}.labels;
            if strcmp(layerType, 'labels') && isa(labels, 'core.MibBigDataLabelsIndex') && ...
                    ~isempty(labels.imageScaleFactors)
                levelIndex = max(1, min(obj.pyramidLevel, size(labels.imageScaleFactors, 1)));
                getOptions.magFactor = labels.imageScaleFactors(levelIndex, 1);
            else
                getOptions.pyramidLevel = obj.pyramidLevel;
            end
        end

        function status = grabVolume(obj, volumeType, colorChannel)
            % GRABVOLUME - Fetch the current MIB dataset volume into the 3D viewer.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      status = obj.grabVolume()
            %      status = obj.grabVolume(volumeType, colorChannel)
            %
            % For **BigData** datasets a pyramid-level picker dialog is shown rather than the
            % downsample-factor dialog.  Each entry lists the spatial dimensions of that level
            % and an estimated in-memory footprint (budget cap: 512 MB).  The selected level is
            % stored in ``obj.pyramidLevel``; the read options come from
            % :func:`levelReadOptions`, which retrieves the full pyramid level rather than just
            % the current viewport block - and translates the level for a label pyramid that is
            % not the image's own.  ``obj.volumeScaleFactor`` is set to ``1`` because the
            % pyramid already provides the downsampling.  The voxel size at the chosen level is
            % taken from ``image.pyramid.levelVoxelSizes`` (``[y x z]``) - directly when that
            % array holds a per-level row, otherwise the full-resolution base row scaled by
            % ``image.pyramid.levelScaleFactors(obj.pyramidLevel, :)`` - to preserve physical
            % (µm) units in the 3D viewer.  Note BioFormats-backed BigData leaves
            % ``image.pixSize`` empty, so the voxel size is always sourced from the pyramid.
            %
            % For **Standard** datasets the original user-entered downsample-factor dialog is used.
            %
            % For models with **256 materials and more** the material dropdown is replaced by a
            % spinner for the material index, because ``labels.materialNames`` only keeps two
            % renameable slots for those model types and cannot list the materials.
            %
            % Input Arguments:
            %   - **volumeType** *(optional)* - [char] volume layer to load (default: ``'image'``):
            %
            %     - ``'image'`` - intensity image data
            %     - ``'labels'`` - segmentation labels
            %     - ``'selection'`` - selection layer
            %     - ``'mask'`` - mask layer
            %
            %   - **colorChannel** *(optional)* - [numeric] color channel or material index (default: ``1``)
            %
            % Output Arguments:
            %   - **status** - [numeric] ``1`` on success, ``0`` if cancelled

            status = 0;

            if nargin < 3; colorChannel = 0; end
            if nargin < 2; volumeType = 'image'; end

            id = obj.mibModel.getActiveId();

            % MIB3 axis order: [y(height), x(width), z(depth), colors, time]
            [height, width, depth] = obj.mibModel.I{id}.getDatasetDimensions('image', 3);

            isBigData = obj.mibModel.I{id}.datasetType(1) == 'B';

            % models with 256 materials and more keep only two renameable slots in
            % labels.materialNames, so they get a spinner for the material index
            % instead of a dropdown listing every material
            isLargeModel = strcmp(volumeType, 'labels') && obj.mibModel.I{id}.labels.maxMaterials >= 256;

            colorChannelPrompt = 'Select color channel:';
            if strcmp(volumeType, 'image')
                colorChannelList = arrayfun(@(x) sprintf('ColCh %d', x), 1:obj.mibModel.I{id}.image.colors, 'UniformOutput', false);
                colorChannelList = [{'Selected'}, {'All'}, colorChannelList];
                colorChannelEntry = [colorChannelList, colorChannel+1];
            elseif isLargeModel
                maxMaterials = obj.mibModel.I{id}.labels.maxMaterials;
                defMaterialIndex = max(0, obj.mibModel.I{id}.getSelectedMaterialIndex());
                colorChannelPrompt = sprintf('Material index (0 - all materials, max %d):', maxMaterials);
                colorChannelEntry = struct('Spinner', true, 'Value', defMaterialIndex, ...
                    'Limits', [0 maxMaterials], 'Step', 1, 'Round', true);
            elseif strcmp(volumeType, 'labels')
                colorChannelList = [{'All materials'}, obj.mibModel.I{id}.labels.materialNames'];
                colorChannelPrompt = 'Select material:';
                colorChannelEntry = [colorChannelList, colorChannel+1];
            else
                colorChannelList = {'Selected'};
                colorChannelEntry = [colorChannelList, 1];
            end

            dlgOptions.HeaderLines = 2;
            dlgOptions.WindowWidth = 540;
            dlgOptions.Columns = 1;
            dlgOptions.Focus = 1;
            dlgOptions.WindowHeight = 310;
            dlgOptions.OkBtnText = 'Continue';

            if isBigData
                % BigData: select a pre-built pyramid level instead of downsampling
                % (the full-resolution volume would not fit in memory)
                levelSizes = obj.mibModel.I{id}.image.pyramid.levelImageSizes;   % [N x 3], [Y X Z]
                noLevels = size(levelSizes, 1);
                dataClass = obj.mibModel.I{id}.image.dataClass;
                bytesPerVoxel = max(1, numel(typecast(cast(0, dataClass), 'uint8')));
                if strcmp(volumeType, 'image')
                    memChannels = obj.mibModel.I{id}.image.colors;
                else
                    memChannels = 1;
                end

                % build the level dropdown items and pick a memory-budgeted default level
                memBudgetMB = 512;
                levelList = cell([1, noLevels]);
                defLevel = noLevels;
                defLevelFound = false;
                for levId = 1:noLevels
                    yL = levelSizes(levId, 1); xL = levelSizes(levId, 2); zL = levelSizes(levId, 3);
                    memMB = prod([yL, xL, zL]) * bytesPerVoxel * memChannels / 1024 / 1024;
                    levelList{levId} = sprintf('Level %d: %d x %d x %d  (~%.0f MB)', levId, xL, yL, zL, memMB);
                    if ~defLevelFound && memMB <= memBudgetMB    % finest level under the budget
                        defLevel = levId;
                        defLevelFound = true;
                    end
                end
                % keep the previously selected level when still valid
                if ~isempty(obj.pyramidLevel) && obj.pyramidLevel >= 1 && obj.pyramidLevel <= noLevels
                    defLevel = obj.pyramidLevel;
                end

                prompts = {'Select pyramid level to render:'; colorChannelPrompt};
                defAns = {[levelList, defLevel]; colorChannelEntry};
                dlgTitle = 'Pyramid level and color channel';
                header = 'Select a pyramid level (resolution) and a color channel (or material) to render in 3D';
                [answer, selIndices] = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, dlgTitle, dlgOptions);
                if isempty(answer); obj.closeWindow(); return; end

                obj.pyramidLevel = selIndices(1);
                obj.volumeScaleFactor = 1;   % the pyramid already provides the downsampling

                if strcmp(volumeType, 'image')
                    colorChannel = selIndices(2) - 2; % Selected, All, ColCh1, ColCh2...
                    if colorChannel == -1       % take selected color channel
                        colorChannel = [];
                    elseif colorChannel == 0    % take all color channels
                        colorChannel = NaN;
                    end
                elseif isLargeModel
                    colorChannel = answer{2};   % spinner with the material index
                    if colorChannel == 0; colorChannel = NaN; end   % take all materials
                else
                    colorChannel = selIndices(2) - 1; % All materials, mat1, mat2...
                    if colorChannel == 0; colorChannel = NaN; end   % take all materials of the layer
                end
            else
                prompts = {sprintf('Would you like to downsample the volume?\nVolume dimensions: %d x %d x %d\n\nDownsample factor (times):', width, height, depth); sprintf('or\nnew width in pixels:'); colorChannelPrompt};
                defAns = {num2str(obj.volumeScaleFactor); num2str(width); colorChannelEntry};
                dlgTitle = 'Color channel and downsample';
                header = 'Select color channel (or material) to render and possibly downsample the dataset to improve performance';
                [answer, selIndices] = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, dlgTitle, dlgOptions);
                if isempty(answer); obj.closeWindow(); return; end

                if strcmp(volumeType, 'image')
                    colorChannel = selIndices(3) - 2; % Selected, All, ColCh1, ColCh2...
                    if colorChannel == -1  % take selected color channel
                        colorChannel = [];
                    elseif colorChannel == 0
                        colorChannel = NaN; %take all color channel
                    end
                elseif isLargeModel
                    colorChannel = answer{3};   % spinner with the material index
                    if colorChannel == 0; colorChannel = NaN; end   % take all materials
                else
                    colorChannel = selIndices(3) - 1; % All materials, mat1, mat2...
                    if colorChannel == 0; colorChannel = NaN; end   % take all materials of the layer
                end

                if str2double(answer{1}) == 1
                    obj.volumeScaleFactor = round(str2double(answer{2})/width, 3);
                else
                    obj.volumeScaleFactor = round(1/str2double(answer{1}), 3);
                end
            end

            pwb = core.PoolWaitbar(5, 'Fetching volume data...', obj.view.gui, 'Import volume', true);
            timePnt = obj.mibModel.I{id}.getCurrentTimePoint();
            pixSize = obj.mibModel.I{id}.image.pixSize;

            getOptions = obj.levelReadOptions(volumeType);
            img = obj.mibModel.getData3D(volumeType, timePnt, 3, colorChannel, getOptions);

            if numel(img) > 1
                pwb.deletePoolWaitbar();
                utils.dlgs.showErrorDialog(obj.view.gui, 'Please select a ROI to render!', 'Error!');
                obj.closeWindow(); return;
            end
            img = cell2mat(img);
            pwb.increment();

            % % keep only selected color channels
            % if isempty(colorChannel) % selected
            %     img = img(:,:,obj.mibModel.I{id}.slices{3},:);
            % end

            % resize the volume
            if isBigData
                % the pyramid level already provides the downsampling; derive the
                % voxel size at the chosen level so the rendered volume keeps
                % physical (um) units. BioFormats-backed BigData leaves
                % image.pixSize empty and stores voxel sizes in
                % pyramid.levelVoxelSizes ([y x z]); that array is either per-level
                % ([N x 3]) or just the full-resolution base ([1 x 3]).
                pyr = obj.mibModel.I{id}.image.pyramid;
                if isfield(pyr, 'levelVoxelSizes') && ~isempty(pyr.levelVoxelSizes)
                    if size(pyr.levelVoxelSizes, 1) >= obj.pyramidLevel
                        vox = pyr.levelVoxelSizes(obj.pyramidLevel, :);     % already per-level [y x z]
                    else
                        vox = pyr.levelVoxelSizes(1, :) .* pyr.levelScaleFactors(obj.pyramidLevel, :);  % base x per-axis scale
                    end
                else
                    vox = [1 1 1];
                end
                if isempty(pixSize) || ~isstruct(pixSize); pixSize = struct(); end
                pixSize.y = vox(1);
                pixSize.x = vox(2);
                pixSize.z = vox(3);
                if ~isfield(pixSize, 'units'); pixSize.units = 'um'; end
            elseif obj.volumeScaleFactor ~= 1
                pwb.updateText('Resizing volume...');
                img = utils.resizeImage3d(img,  obj.volumeScaleFactor);

                pixSize.x = pixSize.x/obj.volumeScaleFactor;
                pixSize.y = pixSize.y/obj.volumeScaleFactor;
                pixSize.z = pixSize.z/obj.volumeScaleFactor;
            end
            pwb.increment();
            if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
            pwb.updateText('Preparing image...');

            if strcmp(volumeType, 'image')
                % permute image to show it as RGB
                % requires [h,w,d,c] format
                [imgH, imgW, imgD, imgC] = size(img);
                % add one extra slice for single images
                if imgD < 2; img = repmat(img, [1 1 2 1]); imgD = 2; end

                if ~isempty(colorChannel) && colorChannel == 0 && size(img, 4) == 2    % add extra channel
                    img(:,:,:,3) = zeros([imgH, imgW, imgD, 1], class(img(1)));
                    imgC = 3;
                end
            else    % mask/model
                [imgH, imgW, imgD] = size(img);
                % add one extra slice for single images
                if imgD < 2; img = repmat(img, [1 1 2]); imgD = 2; end
                obj.view.handles.rendererDropDown.Value = 'Isosurface';
            end
            pwb.increment();
            if pwb.getCancelState(); pwb.deletePoolWaitbar(); return; end
            
            % generate tform to scale the dataset upon loading to have its units in um
            % to update obj.scalingTransform variable
            obj.updateScalingTransform(pixSize);

            pwb.updateText('Rendering volume...');
            % set the volume to obj.viewer
            if isempty(obj.volume)
                obj.volume = volshow(squeeze(img), ...
                   'Transformation', obj.scalingTransform, ...
                   'RenderingStyle', obj.view.handles.rendererDropDown.Value, ...
                   'Parent', obj.viewer);
            else
                obj.volume.Data = squeeze(img);
            end
            pwb.increment();

            obj.volume.IsosurfaceValue = obj.Settings.Volume.isosurfaceValue;
            obj.volume.GradientOpacityValue = obj.Settings.Volume.gradientOpacityValue;

            % store default camera position
            %obj.defaultView.CameraPosition = [pixSize.x*imgW pixSize.y*imgH, pixSize.z*imgD]; %obj.viewer.CameraPosition = [pixSize.x*imgW pixSize.y*imgH, pixSize.z*imgD];
            %obj.defaultView.CameraPosition = obj.viewer.CameraPosition;
            %obj.defaultView.CameraTarget = [pixSize.x*imgW/2 pixSize.y*imgH/2, pixSize.z*imgD/2]; % obj.viewer.CameraTarget;
            %obj.defaultView.CameraUpVector = [0 0 1];%obj.viewer.CameraUpVector;
            %obj.defaultView.CameraZoom = 1; % obj.viewer.CameraZoom;

            % update the scaling factor
            %obj.viewer.CameraPosition = obj.viewer.CameraPosition.*obj.volumeScaleFactor;

            obj.maxIntValue = obj.mibModel.I{id}.image.maxInt;
            obj.view.handles.isovalueSlider.Value = obj.Settings.Volume.isosurfaceValue;
            obj.view.handles.isovalueEdit.Value = obj.Settings.Volume.isosurfaceValue;
            obj.recalculateAlphamap();
            
            % update settings for the slice sliders and editboxes
            % the sliders needs to be visible, i.e. if Isosurface is on,
            % the sliders are hidden and cannot be set
            obj.view.handles.xSlider.Limits = [1 imgW];
            obj.view.handles.xSlider.Value = double(obj.volume.SlicePlaneValues(1,4));
            obj.view.handles.xSlider.MinorTicks = linspace(1,imgW, 9);
            obj.view.handles.xSliderEdit.Limits = [1 imgW];
            obj.view.handles.xSliderEdit.Value = double(obj.volume.SlicePlaneValues(1,4));
            
            obj.view.handles.ySlider.Limits = [1 imgH];
            obj.view.handles.ySlider.Value = double(obj.volume.SlicePlaneValues(2,4));
            obj.view.handles.ySlider.MinorTicks = linspace(1,imgH, 9);
            obj.view.handles.ySliderEdit.Limits = [1 imgH];
            obj.view.handles.ySliderEdit.Value = double(obj.volume.SlicePlaneValues(2,4));
            
            obj.view.handles.zSlider.Limits = [1 imgD];
            obj.view.handles.zSlider.Value = double(obj.volume.SlicePlaneValues(3,4));
            obj.view.handles.zSlider.MinorTicks = linspace(1,imgD, 9);
            obj.view.handles.zSliderEdit.Limits = [1 imgD];
            obj.view.handles.zSliderEdit.Value = double(obj.volume.SlicePlaneValues(3,4));
            
            % update widgets to take care about Isosurface mode
            if strcmp(obj.view.handles.rendererDropDown.Value, 'Isosurface')
                obj.updateVolumeRenderingStyle();
            end

            %             % check overlay
            %             noMaterials = numel(dataset.labels.materialNames);
            %             img = obj.mibModel.getData3D('labels', timePnt, 4);
            %             % resize the volume
            %             if obj.volumeScaleFactor ~= 1
            %                 rescaleOpt.imgType = '3D';
            %                 rescaleOpt.method = 'nearest';
            %                 img{1} = mibResize3d(img{1},  obj.volumeScaleFactor, rescaleOpt);
            %             end
            %             obj.volume.OverlayData = img{1};
            %
            %             obj.volume.OverlayAlphamap = [0 1 1 1 1];
            %             %obj.volume.OverlayAlphamap = 0;
            %             obj.volume.OverlayColormap = [0, 0, 0; obj.mibModel.I{id}.modelMaterialColors(1:noMaterials,:)];
            %             obj.volume.OverlayThreshold = .001;
            %
            %             mask1 = (img{1} == 1);
            %             surf1 = images.ui.graphics3d.Surface(obj.viewer, 'Color', obj.mibModel.I{id}.modelMaterialColors(1,:), 'Data', mask1, ...
            %                 'Transformation', obj.scalingTransform);
            %             surf1.Alpha = 1;

            %obj.visualizationModePopup_Callback();
            pwb.increment();
            status = 1;
            pwb.deletePoolWaitbar();
        end

        function recalculateAlphamap(obj, transparentVolume)
            % RECALCULATEALPHAMAP - Recalculate and apply the volume alpha map.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.recalculateAlphamap()
            %      obj.recalculateAlphamap(transparentVolume)
            %
            % Input Arguments:
            %   - **transparentVolume** *(optional)* - [logical] when ``true``, set alphamap to ``0``
            %     making the volume fully transparent (default: ``false``)

            if nargin < 2; transparentVolume = false; end
            if transparentVolume
                obj.volume.Alphamap = 0;
            else
                queryPoints = linspace(0, obj.maxIntValue, 256);
                obj.volumeAlphaCurve.alphamap = interp1(obj.volumeAlphaCurve.x*obj.maxIntValue, ...
                    obj.volumeAlphaCurve.y, queryPoints)';
                if ~isempty(obj.volume)
                    obj.volume.Alphamap = obj.volumeAlphaCurve.alphamap;
                end
                obj.view.handles.showVolumeCheckBox.Value = true;   % check 'show volume'
            end
        end

        function spinDataset(obj)
            % SPINDATASET - Preview a camera spin animation around the dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.spinDataset()

            % CameraPosition:   the position of the camera itself
            % CameraTarget:     the camera's look-at point
            % CameraUpVector:   the roll angle (rotation) of the camera
            %                   around it's view axis, defines which axis is up: [0, 0, 1] indicates Z-axis is up
            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.spinDataset: triggered\n');
            end
            if obj.animationPreviewRunning
                % cancel animation
                obj.animationPreviewRunning = false;
                return;
            end

            options.clockwise = 1;
            options.back_and_forth = 0;

            positions = obj.generatePositionsForSpinAnimation(120, options);
            framerate = 24;

            obj.animationPreviewRunning = true;
            obj.view.handles.spinTestButton.Text = 'Stop spin';
            obj.view.handles.spinTestButton.BackgroundColor = [1 0 0];

            obj.viewer.CameraUpVector = positions.CameraUpVector;
            obj.viewer.CameraTarget = positions.CameraTarget;

            for idx = 1:size(positions.CameraPosition,1)
                if ~obj.animationPreviewRunning
                    % stop spin
                    obj.view.handles.spinTestButton.Text = 'Spin test';
                    obj.view.handles.spinTestButton.BackgroundColor = [0 1 0];
                    return;
                end
                obj.viewer.CameraPosition = positions.CameraPosition(idx, :);
                %obj.volume.CameraUpVector = myUpVector(idx, :);
                %obj.mibVolRenGUI_VolumeMotionFcn();
                pause(1/framerate);
            end
            obj.view.handles.spinTestButton.Text = 'Spin test';
            obj.view.handles.spinTestButton.BackgroundColor = [0 1 0];
            obj.animationPreviewRunning = false;
        end

        function positions = generatePositionsForSpinAnimation(obj, noFrames, options)
            % GENERATEPOSITIONSFORSPINANIMATION - Generate camera positions for a spin animation.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      positions = obj.generatePositionsForSpinAnimation(noFrames)
            %      positions = obj.generatePositionsForSpinAnimation(noFrames, options)
            %
            % Input Arguments:
            %   - **noFrames** - [numeric] number of frames (default: ``120``)
            %   - **options** *(optional)* - struct with rotation parameters:
            %
            %     - ``.back_and_forth`` - [logical] animate forward then reverse (default: ``0``)
            %     - ``.clockwise`` - [numeric] ``1`` for clockwise, ``0`` for anticlockwise (default: ``0``)
            %     - ``.rotAxis`` - [char] rotation axis: ``'X-axis'``, ``'Y-axis'``, or ``'Z-axis'``
            %
            % Output Arguments:
            %   - **positions** - struct with per-frame camera data:
            %
            %     - ``.CameraPosition`` - ``[N x 3]`` array of camera positions
            %     - ``.CameraUpVector`` - ``[1 x 3]`` fixed up-vector for the chosen spin axis
            %     - ``.CameraTarget`` - ``[1 x 3]`` fixed camera target (centre of volume)

            if nargin < 3; options = struct(); end
            if nargin < 2; noFrames = 120; end
            if ~isfield(options, 'back_and_forth'); options.back_and_forth = 0; end
            if ~isfield(options, 'clockwise'); options.clockwise = 0; end
            if ~isfield(options, 'rotAxis'); options.rotAxis = obj.view.handles.spinAxis.Value; end

            positions.CameraTarget = obj.viewer.CameraTarget;

            % obtain current position
            currX = obj.viewer.CameraPosition(1) - obj.viewer.CameraTarget(1);
            currY = obj.viewer.CameraPosition(2) - obj.viewer.CameraTarget(2);
            currZ = obj.viewer.CameraPosition(3) - obj.viewer.CameraTarget(3);

            switch obj.view.handles.spinAxis.Value
                case 'X-axis'  % around x-axis
                    positions.CameraUpVector = [-1 0 0];
                    %positions.CameraUpVector = obj.viewer.CameraUpVector;

                    if currZ>=0 && currY>=0
                        currAngle = atan(currZ/currY)+pi();  % calculate the angle
                    else
                        currAngle = atan(currZ/currY);  % calculate the angle
                    end

                    radius = sqrt(currY^2+currZ^2); % calculate distance from the target point
                    % calculate new positions for the camera for the spin
                    if options.back_and_forth == 0
                        if options.clockwise == 1
                            vec = linspace(currAngle, currAngle+2*pi(), noFrames)';
                        else
                            vec = linspace(currAngle+2*pi(), currAngle, noFrames)';
                        end
                    else
                        if options.clockwise == 1
                            vec = [linspace(currAngle, currAngle+2*pi(), noFrames)'; ...
                                linspace(currAngle+2*pi(), currAngle, noFrames)'];
                        else
                            vec = [linspace(currAngle+2*pi(), currAngle, noFrames)';...
                                linspace(currAngle, currAngle+2*pi(), noFrames)'];
                        end
                    end
                    positions.CameraPosition = [zeros(size(vec))+currX+obj.viewer.CameraTarget(1) ...
                        cos(vec)*radius+obj.viewer.CameraTarget(2) ...
                        sin(vec)*radius+obj.viewer.CameraTarget(3)];

                case 'Y-axis'  % around y-axis
                    positions.CameraUpVector = [0 1 0];

                    if currZ>=0 && currX>=0
                        currAngle = atan(currZ/currX)+pi();  % calculate the angle
                    else
                        currAngle = atan(currZ/currX);  % calculate the angle
                    end

                    radius = sqrt(currX^2+currZ^2); % calculate distance from the target point
                    % calculate new positions for the camera for the spin
                    if options.back_and_forth == 0
                        if options.clockwise == 1
                            vec = linspace(currAngle, currAngle+2*pi(), noFrames)';
                        else
                            vec = linspace(currAngle+2*pi(), currAngle, noFrames)';
                        end
                    else
                        if options.clockwise == 1
                            vec = [linspace(currAngle, currAngle+2*pi(), noFrames)'; ...
                                linspace(currAngle+2*pi(), currAngle, noFrames)'];
                        else
                            vec = [linspace(currAngle+2*pi(), currAngle, noFrames)';...
                                linspace(currAngle, currAngle+2*pi(), noFrames)'];
                        end
                    end
                    positions.CameraPosition = [cos(vec)*radius+obj.viewer.CameraTarget(1) ...
                        zeros(size(vec))+currY+obj.viewer.CameraTarget(2) ...
                        sin(vec)*radius+obj.viewer.CameraTarget(3)];
                case 'Z-axis'  % around z-axis
                    positions.CameraUpVector = [0 0 1];

                    if currY>=0 && currX>=0
                        currAngle = atan(currY/currX);  % calculate the angle
                    else
                        currAngle = atan(currY/currX)+pi();  % calculate the angle
                    end
                    radius = sqrt(currX^2+currY^2); % calculate distance from the target point
                    % calculate new positions for the camera for the spin
                    if options.back_and_forth == 0
                        if options.clockwise == 1
                            vec = linspace(currAngle, currAngle+2*pi(), noFrames)';
                        else
                            vec = linspace(currAngle+2*pi(), currAngle, noFrames)';
                        end
                    else
                        if options.clockwise == 1
                            vec = [linspace(currAngle, currAngle+2*pi(), noFrames)'; ...
                                linspace(currAngle+2*pi(), currAngle, noFrames)'];
                        else
                            vec = [linspace(currAngle+2*pi(), currAngle, noFrames)';...
                                linspace(currAngle, currAngle+2*pi(), noFrames)'];
                        end
                    end

                    positions.CameraPosition = [ cos(vec)*radius+obj.viewer.CameraTarget(1) ...
                        sin(vec)*radius+obj.viewer.CameraTarget(2) ...
                        zeros(size(vec))+currZ+obj.viewer.CameraTarget(3)];
            end
        end

        function makeSnapshop(obj)
            % MAKESNAPSHOP - Open the Snapshot dialog for the current viewer state.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.makeSnapshop()
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.makeSnapshop: triggered\n');
            end
            utils.startController(obj, 'controllers.Snapshot', obj);
        end

        function modelUpdateOverlay(obj, overlayType, materialId)
            % MODELUPDATEOVERLAY - Fetch an overlay layer from MIB and apply it to the volume.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.modelUpdateOverlay()
            %      obj.modelUpdateOverlay(overlayType, materialId)
            %
            % For **BigData** datasets the overlay is read at the level chosen in the
            % ``grabVolume`` dialog, through :func:`levelReadOptions` - which is also what keeps a
            % ``core.MibBigDataLabelsIndex`` overlay at the right resolution, since its pyramid is
            % not the image's and the level indices do not correspond.  If the returned overlay
            % dimensions still differ from the in-memory image volume (``obj.volume.Data``), a
            % nearest-neighbour ``imresize3`` is applied so the overlay aligns pixel-for-pixel with
            % the rendered volume.  For **Standard** datasets the same downsample path as
            % ``grabVolume`` is used (``obj.volumeScaleFactor`` resize via ``imresize3``).
            %
            % The fetched layer is passed through :func:`buildOverlayIndexVolume`, which packs it
            % into the 255 colour slots that ``volshow`` provides. That is what makes models with
            % 65535 or 4294967295 materials renderable: they are either cycled through 255 colours
            % or reduced to the material indices listed in the ``overlayMaterialsList`` widget.
            %
            % Input Arguments:
            %   - **overlayType** *(optional)* - [char] overlay layer type:
            %
            %     - ``'labels'`` - segmentation labels (model) layer
            %     - ``'mask'`` - mask layer
            %     - ``'selection'`` - selection layer
            %
            %   - **materialId** *(optional)* - [numeric] material index; ``NaN`` to load all materials

            if nargin < 3; materialId = NaN; end    % get all materials
            if nargin < 2; overlayType = obj.view.handles.overlaySourceDropDown.Value; end    % get all materials

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.modelUpdateOverlay(%s): triggered\n', overlayType);
            end
            obj.overlayMaterialId = materialId;     % remember for the live overlay refresh
            id = obj.mibModel.getActiveId();
            isBigData = obj.mibModel.I{id}.datasetType(1) == 'B';
            dataset = obj.mibModel.I{id};
            existStatus = dataset.enableSelection;
            switch overlayType
                case 'labels'
                    existStatus = dataset.modelExist;
                case 'mask'
                    existStatus = dataset.maskExist;
            end
            if existStatus == 0
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.Icon        = 'puffin_error';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, sprintf('The %s is not present in MIB!', overlayType), {''}, {''}, ...
                    'Missing model', dlgOpt);
                return;
            end

            getOptions = obj.levelReadOptions(overlayType);
            overlay = cell2mat(obj.mibModel.getData3D(overlayType, [], 3, materialId, getOptions));
            % resize the volume
            if ~isBigData && obj.volumeScaleFactor ~= 1
                rescaleOpt.imgType = '3D';
                rescaleOpt.method = 'nearest';
                overlay = utils.resizeImage3d(overlay,  obj.volumeScaleFactor, rescaleOpt);
            elseif isBigData && ~isempty(obj.volume) && isvalid(obj.volume)
                % BigData: pyramid already downsampled; match overlay dims to image volume if needed
                [volH, volW, volD] = size(obj.volume.Data);
                [overlayH, overlayW, overlayD] = size(overlay);
                if overlayH ~= volH || overlayW ~= volW || overlayD ~= volD
                    overlay = imresize3(overlay, [volH, volW, volD], 'nearest');
                end
            end
            [imgH, imgW, imgD] = size(overlay);
            % add one extra slice for single images
            if imgD < 2; overlay = repmat(overlay, [1 1 2]); end

            % pack the layer into the 255 color slots available in volshow
            [overlayIdx, overlayInfo] = obj.buildOverlayIndexVolume(overlay, overlayType);
            obj.overlayRowMaterials = overlayInfo.rowMaterials;
            obj.overlayRowNames = overlayInfo.rowNames;
            obj.overlayRowColors = overlayInfo.rowColors;
            obj.overlayRowMap = overlayInfo.rowMap;
            obj.noOverlayMaterials = numel(overlayInfo.rowNames);
            obj.overlayAlpha = ones([obj.noOverlayMaterials, 1]);
            obj.overlayShownMaterials = true([obj.noOverlayMaterials, 1]);
            obj.view.handles.modelHideAllCheckBox.Value = false;   % a fresh overlay starts visible

            % update volume
            obj.volume.OverlayData = overlayIdx;
            obj.volume.OverlayColormap = overlayInfo.colormap;

            % MATLAB keeps the overlay colormap in a fixed 256-entry table, so a manual
            % display range of [0 255] is what makes index N land on colormap row N+1.
            % With 'data-range' the mapping would depend on the labels present in the
            % volume and every material would shift color as soon as one is missing.
            obj.volume.OverlayDisplayRangeMode = 'manual';
            obj.volume.OverlayDisplayRange = [0 255];
            obj.volume.OverlayThreshold = 0.0001;
            obj.applyOverlayAlphamap();

            % update rendering style
            obj.volume.OverlayRenderingStyle = obj.view.handles.overlayRenderingStyle.Value; % LabelOverlay, VolumeOverlay, GradientOverlay
            obj.updateModelTable(); % update table with materials
        end

        function applyOverlayAlphamap(obj)
            % APPLYOVERLAYALPHAMAP - Rebuild ``obj.volume.OverlayAlphamap`` from the material table state.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.applyOverlayAlphamap()
            %
            % The alphamap of ``volshow`` is a fixed 256-entry vector. Each row of the material
            % table controls the entries listed in ``obj.overlayRowMap`` - one entry per material
            % in the normal case, and all 255 color bins for the single row of the cycled mode.
            % Row 1 is the background and always stays transparent.

            if isempty(obj.volume) || ~isvalid(obj.volume); return; end

            alphamap = zeros([256, 1]);
            if ~obj.view.handles.modelHideAllCheckBox.Value
                for rowId = 1:numel(obj.overlayRowMap)
                    if obj.overlayShownMaterials(rowId)
                        alphamap(obj.overlayRowMap{rowId}) = obj.overlayAlpha(rowId);
                    end
                end
            end
            alphamap(1) = 0;    % background
            obj.volume.OverlayAlphamap = alphamap;
        end

        function updateOverlayMaterialWidgets(obj)
            % UPDATEOVERLAYMATERIALWIDGETS - Enable the large-model overlay widgets when they apply.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateOverlayMaterialWidgets()
            %
            % The materials mode, the index list and the "Add current" button only make sense for
            % the ``'labels'`` overlay of a model with 256 materials or more; for everything else
            % the material table already lists every material.

            if ~isfield(obj.view.handles, 'overlayMaterialsMode'); return; end

            id = obj.mibModel.getActiveId();
            isLargeModel = obj.mibModel.I{id}.labels.maxMaterials >= 256 && ...
                strcmp(obj.view.handles.overlaySourceDropDown.Value, 'labels');
            selectedMode = obj.overlayMaterialsMode;

            obj.view.handles.overlayMaterialsMode.Enable = isLargeModel;
            obj.view.handles.overlayMaterialsMode.Value = selectedMode;
            obj.view.handles.overlayMaterialsList.Enable = isLargeModel && strcmp(selectedMode, 'Selected materials');
            obj.view.handles.addCurrentMaterialButton.Enable = obj.view.handles.overlayMaterialsList.Enable;
        end

        function overlayMaterialsModeChanged(obj)
            % OVERLAYMATERIALSMODECHANGED - Switch between the cycled and the selected materials mode.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.overlayMaterialsModeChanged()
            %
            % Callback target for the ``overlayMaterialsMode`` dropdown. When the
            % ``'Selected materials'`` mode is entered with an empty list, the list is seeded from
            % the material selected in the main MIB window so that something is rendered.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.overlayMaterialsModeChanged: triggered\n');
            end
            obj.overlayMaterialsMode = obj.view.handles.overlayMaterialsMode.Value;

            if strcmp(obj.overlayMaterialsMode, 'Selected materials') && isempty(obj.overlayMaterialsSelection)
                id = obj.mibModel.getActiveId();
                seedIndex = obj.mibModel.I{id}.getSelectedMaterialIndex();
                if seedIndex < 1; seedIndex = 1; end
                obj.overlayMaterialsSelection = seedIndex;
                obj.view.handles.overlayMaterialsList.Value = obj.materialsSelectionAsText();
            end
            obj.updateOverlayMaterialWidgets();
            if ~isempty(obj.volume) && isvalid(obj.volume) && obj.noOverlayMaterials > 0
                obj.modelUpdateOverlay();
            end
        end

        function applyOverlayMaterialsList(obj)
            % APPLYOVERLAYMATERIALSLIST - Parse the material index list and refresh the overlay.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.applyOverlayMaterialsList()
            %
            % Callback target for the ``overlayMaterialsList`` edit field. The text is parsed with
            % ``str2num``, so indices and ranges can be mixed: ``1:10, 45, 900:5:1000``. Indices
            % outside the model are dropped and the list is capped at the 255 colors that
            % ``volshow`` provides.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.applyOverlayMaterialsList: triggered\n');
            end
            id = obj.mibModel.getActiveId();
            maxMaterials = obj.mibModel.I{id}.labels.maxMaterials;

            % str2num evaluates its argument, so accept digits and range syntax only
            materialsText = obj.view.handles.overlayMaterialsList.Value;
            if isempty(regexp(materialsText, '^[\d\s,;:]*$', 'once'))
                selectedMaterials = [];
            else
                selectedMaterials = str2num(['[' materialsText ']']); %#ok<ST2NM>
            end
            if (isempty(selectedMaterials) && ~isempty(strtrim(materialsText))) || ...
                    ~isnumeric(selectedMaterials) || any(~isfinite(selectedMaterials))
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('Can not read the list of materials!\n\nUse indices and ranges, for example: 1:10, 45, 900'), ...
                    'Wrong material list');
                obj.view.handles.overlayMaterialsList.Value = obj.materialsSelectionAsText();
                return;
            end

            selectedMaterials = unique(round(selectedMaterials(:)'));
            selectedMaterials = selectedMaterials(selectedMaterials >= 1 & selectedMaterials <= maxMaterials);
            if numel(selectedMaterials) > 255
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.Icon        = 'puffin_warning';
                dlgOpt.HeaderLines = 2;
                utils.dlgs.inputUniversalDlg(obj.view.gui, 'Only 255 materials can be rendered at once!', ...
                    {''}, {sprintf('The list was cut down to the first 255 of %d materials', numel(selectedMaterials))}, ...
                    'Too many materials', dlgOpt);
                selectedMaterials = selectedMaterials(1:255);
            end

            obj.overlayMaterialsSelection = selectedMaterials;
            obj.view.handles.overlayMaterialsList.Value = obj.materialsSelectionAsText();
            if ~isempty(obj.volume) && isvalid(obj.volume) && obj.noOverlayMaterials > 0
                obj.modelUpdateOverlay();
            end
        end

        function addCurrentMaterialToList(obj)
            % ADDCURRENTMATERIALTOLIST - Append the material selected in MIB to the rendered list.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addCurrentMaterialToList()
            %
            % Callback target for the ``addCurrentMaterialButton`` button. For large models
            % ``core.MibDataset.getSelectedMaterialIndex`` resolves the selected table slot to the
            % real material index, so the index appended here is the one shown in the 2D view.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.addCurrentMaterialToList: triggered\n');
            end
            id = obj.mibModel.getActiveId();
            materialIndex = obj.mibModel.I{id}.getSelectedMaterialIndex();
            if materialIndex < 1
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.Icon        = 'puffin_warning';
                dlgOpt.HeaderLines = 2;
                utils.dlgs.inputUniversalDlg(obj.view.gui, 'No material is selected in the main MIB window!', ...
                    {''}, {'Select a material in the Segmentation panel and try again'}, ...
                    'Missing material', dlgOpt);
                return;
            end

            obj.overlayMaterialsSelection = union(obj.overlayMaterialsSelection, materialIndex);
            obj.view.handles.overlayMaterialsList.Value = obj.materialsSelectionAsText();
            obj.applyOverlayMaterialsList();
        end

        function materialsText = materialsSelectionAsText(obj)
            % MATERIALSSELECTIONASTEXT - Format ``obj.overlayMaterialsSelection`` for the edit field.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      materialsText = obj.materialsSelectionAsText()
            %
            % Output Arguments:
            %   - **materialsText** - [char] comma separated list of the rendered material
            %     indices, without spaces, for example ``1,2,3,4``

            if isempty(obj.overlayMaterialsSelection)
                materialsText = '';
            else
                materialsText = strjoin(arrayfun(@(x) sprintf('%d', x), ...
                    obj.overlayMaterialsSelection(:)', 'UniformOutput', false), ',');
            end
        end

        function generateSurfaceByMaterialIndex(obj)
            % GENERATESURFACEBYMATERIALINDEX - Generate a surface for a material given by its index.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.generateSurfaceByMaterialIndex()
            %
            % Asks for a material index and refetches that material from MIB as a binary mask, so
            % it works for any material of a large model, including those that are not currently
            % listed in the material table.

            id = obj.mibModel.getActiveId();
            if ~obj.mibModel.I{id}.modelExist
                utils.dlgs.showErrorDialog(obj.view.gui, 'The model is not present in MIB!', 'Missing model');
                return;
            end
            maxMaterials = obj.mibModel.I{id}.labels.maxMaterials;
            defIndex = max(1, obj.mibModel.I{id}.getSelectedMaterialIndex());

            dlgOpt.Type = 'spinner';
            dlgOpt.WindowWidth = 320;
            materialIndex = utils.dlgs.inputSingleDlg(obj.view.gui, ...
                sprintf('Please enter the material index\n(max. value is %d)', maxMaterials), ...
                struct('Value', defIndex, 'Limits', [1 maxMaterials], 'Step', 1, 'Round', true), ...
                'Generate surface by index', dlgOpt);
            if isempty(materialIndex); return; end

            wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Generating the surface\nPlease wait...'), ...
                'Title', 'Generate surface', 'Cancelable', 'on');
            mask = obj.fetchOverlayMask('labels', materialIndex);
            if wb.CancelRequested || isempty(mask); delete(wb); return; end
            wb.Value = 0.7;

            palette = obj.mibModel.I{id}.labels.materialColors;
            surfaceColor = palette(mod(materialIndex-1, size(palette, 1)) + 1, :);
            obj.addSurfaceFromMask(mask ~= 0, sprintf('%d', materialIndex), surfaceColor);
            delete(wb);
            obj.updateSurfaceTable();
        end

        function isFused = overlayIsFusedInstances(obj)
            % OVERLAYISFUSEDINSTANCES - Is the shown overlay an instance model collapsed to one material?
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      isFused = obj.overlayIsFusedInstances()
            %
            % True for a ``core.MibBigDataLabelsIndex`` overlay read with
            % :attr:`core.MibBigDataLabelsIndex.renderPerObject` off. That layer
            % declares ``maxMaterials = 65535``, so the material table takes the
            % cycled-colour branch and calls the single row "255 materials" - but the
            % values were fused to 1 on read, so the row really is one material. The
            % two disagree, and every per-material action has to ask which is true.
            %
            % Only meaningful for the ``'labels'`` source; a mask or selection overlay
            % is a single material already and never reaches the cycled branch.
            %
            % Output Arguments:
            %   - **isFused** - [logical] true when the row stands for every object
            %     fused into one material rather than for 255 cycled ones

            isFused = false;
            if ~strcmp(obj.view.handles.overlaySourceDropDown.Value, 'labels'); return; end
            id = obj.mibModel.getActiveId();
            labels = obj.mibModel.I{id}.labels;
            isFused = isa(labels, 'core.MibBigDataLabelsIndex') && ~labels.renderPerObject;
        end

        function generated = generateAllObjectSurfaces(obj)
            % GENERATEALLOBJECTSURFACES - One surface per object, for the cycled-colour mode.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      generated = obj.generateAllObjectSurfaces()
            %
            % In the ``'All materials'`` mode a large model has a single table row
            % standing for every material, because the overlay colours cycle through
            % 255 slots. Generating from that row used to be refused; it now means
            % what it says, one surface for each object present.
            %
            % The prompt comes first and names the count, because this is the one
            % action in the table whose cost scales with the model rather than with
            % the selection: each object is meshed separately and each becomes its
            % own :class:`images.ui.graphics3d.Surface`, so a few hundred objects is
            % a wait and several thousand is a long one. Cancelling stops at the
            % object in progress and keeps the surfaces already made - they are
            % complete in themselves, unlike a half-read volume.
            %
            % Output Arguments:
            %   - **generated** - [logical] true when at least one surface was added

            generated = false;
            id = obj.mibModel.getActiveId();
            overlayType = obj.view.handles.overlaySourceDropDown.Value;
            highestId = obj.mibModel.I{id}.labels.materialsCount;

            dlgOpt.Icon         = 'puffin_warning';
            dlgOpt.WindowHeight = 280;
            dlgOpt.WindowWidth  = 540;
            question = sprintf(['In this mode the table row stands for every material in the ' ...
                'model, not for one, because the overlay colours repeat every 255 objects.\n\n' ...
                'Generating from it builds a separate surface for each object - about %d of ' ...
                'them here. This can take several minutes, and the viewer has to draw every ' ...
                'surface afterwards, which slows down rotating and zooming.\n\n' ...
                'To surface one object instead, cancel and use "Generate surface by index...", ' ...
                'or switch the Materials to show dropdown to "Selected materials".'], highestId);
            answer = utils.dlgs.inputQuestDlg(obj.view.gui, question, ...
                'Generate a surface for every object', 'Continue', 'Cancel', 'Cancel', dlgOpt);
            if ~strcmp(answer, 'Continue'); return; end

            wb = uiprogressdlg(obj.view.gui, 'Title', 'Generate surfaces', ...
                'Message', 'Reading the model...', 'Indeterminate', 'on', 'Cancelable', 'on');
            % The rendered overlay carries cycled bin numbers rather than material
            % indices, so the object ids have to come from the layer itself.
            labelVolume = obj.fetchOverlayMask(overlayType, NaN);
            if wb.CancelRequested || isempty(labelVolume); delete(wb); return; end

            objectIds = unique(labelVolume(labelVolume > 0));
            if isempty(objectIds)
                delete(wb);
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'The model has no objects at the rendered pyramid level.', 'Nothing to surface');
                return;
            end

            % Every bounding box in one pass. Letting addSurfaceFromMask find each
            % box itself would mean building a full-size mask per object and
            % reducing it - 0.52 s each against 0.015 s, four minutes against eight
            % seconds here - because the search costs more than the meshing it saves.
            wb.Message = 'Locating objects...';
            objectBoxes = regionprops3(labelVolume, 'BoundingBox');
            if wb.CancelRequested; delete(wb); return; end

            volumeSize = size(labelVolume);
            palette = obj.mibModel.I{id}.labels.materialColors;
            wb.Indeterminate = 'off';
            addedCount = 0;
            totalVertices = 0;
            totalFaces = 0;
            for objectIndex = 1:numel(objectIds)
                if wb.CancelRequested; break; end
                wb.Value   = objectIndex / numel(objectIds);
                wb.Message = sprintf('Generating surface %d of %d...', objectIndex, numel(objectIds));

                objectId = double(objectIds(objectIndex));
                % regionprops3 gives [xMin yMin zMin xLen yLen zLen] with the corner
                % at a half-voxel, so +0.5 is the first voxel. The one-voxel margin
                % is what keeps the mesh closed - see addSurfaceFromMask.
                box = objectBoxes.BoundingBox(objectId, :);
                firstYXZ = round(box([2 1 3]) + 0.5);
                lastYXZ  = firstYXZ + round(box([5 4 6])) - 1;
                rowRange  = max(1, firstYXZ(1)-1) : min(volumeSize(1), lastYXZ(1)+1);
                colRange  = max(1, firstYXZ(2)-1) : min(volumeSize(2), lastYXZ(2)+1);
                pageRange = max(1, firstYXZ(3)-1) : min(volumeSize(3), lastYXZ(3)+1);

                objectMask = labelVolume(rowRange, colRange, pageRange) == objectIds(objectIndex);
                surfaceColor = palette(mod(objectId-1, size(palette, 1)) + 1, :);
                obj.addSurfaceFromMask(objectMask, sprintf('%d', objectId), surfaceColor, ...
                    [rowRange(1), colRange(1), pageRange(1)]);
                addedCount = addedCount + 1;
                totalVertices = totalVertices + obj.surfList{end}.NumVertices;
                totalFaces    = totalFaces    + obj.surfList{end}.NumFaces;
            end
            cancelled = wb.CancelRequested;
            delete(wb);

            generated = addedCount > 0;
            if ~generated; return; end

            % Edges are not a property of the surface, but a triangle mesh with no
            % boundary has exactly 3/2 as many edges as faces - every edge is shared
            % by two triangles. Marching cubes leaves a boundary only where an object
            % runs into the edge of the volume, so this is exact for anything fully
            % inside it and a slight undercount for anything clipped.
            totalEdges = round(totalFaces * 3 / 2);
            summary = sprintf('Surfaces: %s\nVertices: %s\nFaces: %s\nEdges: %s', ...
                obj.groupDigits(addedCount), obj.groupDigits(totalVertices), ...
                obj.groupDigits(totalFaces), obj.groupDigits(totalEdges));
            if cancelled
                summary = sprintf('Cancelled after %s of %s objects.\n\n%s', ...
                    obj.groupDigits(addedCount), obj.groupDigits(numel(objectIds)), summary);
            end
            fprintf('controllers.VolRenApp.generateAllObjectSurfaces: %s\n', ...
                regexprep(summary, '\n', '  '));

            dlgOpt.MsgBoxOnly  = true;
            dlgOpt.Icon        = 'puffin_info';
            dlgOpt.HeaderLines = 1;
            dlgOpt.WindowHeight = 180;
            utils.dlgs.inputUniversalDlg(obj.view.gui, 'Surfaces stats:', {''}, {summary}, ...
                'Surfaces generated', dlgOpt);
        end

        function text = groupDigits(~, value)
            % GROUPDIGITS - Thousands separators, so a seven-digit face count can be read at a glance.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      text = obj.groupDigits(value)
            %
            % Input Arguments:
            %   - **value** - [numeric] non-negative integer
            %
            % Output Arguments:
            %   - **text** - [char] the number with a space every three digits
            text = regexprep(fliplr(sprintf('%d', round(value))), '(\d{3})(?=\d)', '$1 ');
            text = fliplr(text);
        end

        function generated = generateFusedInstancesSurface(obj)
            % GENERATEFUSEDINSTANCESSURFACE - One surface over every object of a fused instance model.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      generated = obj.generateFusedInstancesSurface()
            %
            % Confirms first, because the result is not what "generate surface" means
            % anywhere else in this table: one mesh spanning every object, with
            % touching objects joined into single connected components and no way to
            % pick one of them apart afterwards. The count is named in the prompt so
            % the scale of that is visible before the wait, and the alternative is
            % named too, since "Generate surface by index..." reads the store's own
            % ids and is unaffected by the fusing.
            %
            % Output Arguments:
            %   - **generated** - [logical] false when cancelled or when nothing was
            %     found to surface; the caller refreshes the table only on true

            generated = false;
            id = obj.mibModel.getActiveId();
            objectCount = obj.mibModel.I{id}.labels.materialsCount;

            dlgOpt.Icon         = 'puffin_warning';
            dlgOpt.WindowHeight = 260;
            dlgOpt.WindowWidth  = 520;
            question = sprintf(['This model is shown with all of its objects fused into a single ' ...
                'material, so a surface generated here covers %d objects at once.\n\n' ...
                'Objects that touch become one connected surface, and the result cannot be ' ...
                'separated back into individual objects afterwards.\n\n' ...
                'To surface one object on its own, cancel and use "Generate surface by index...", ' ...
                'which reads the object ids from the store.'], objectCount);
            answer = utils.dlgs.inputQuestDlg(obj.view.gui, question, ...
                'Objects are fused', 'Continue', 'Cancel', 'Cancel', dlgOpt);
            if ~strcmp(answer, 'Continue'); return; end

            wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Generating the merged surface\nPlease wait...'), ...
                'Title', 'Generate surface', 'Cancelable', 'on');
            % Every object already carries the same value, so the fusing IS the mask;
            % taking every non-zero voxel is the merge the dialog just described.
            mask = obj.volume.OverlayData ~= 0;
            if wb.CancelRequested || ~any(mask(:))
                delete(wb);
                return;
            end

            % The colour the fused objects are actually drawn in: index 1 of the
            % overlay maps to row 2 of the colormap (see buildOverlayIndexVolume).
            surfaceColor = obj.volume.OverlayColormap(2, :);
            obj.addSurfaceFromMask(mask, sprintf('all objects (%d fused)', objectCount), surfaceColor);
            delete(wb);
            generated = true;
        end

        function [croppedMask, cropOriginYXZ] = cropMaskToObject(~, mask)
            % CROPMASKTOOBJECT - Tight bounding box of a binary mask, with a one-voxel margin.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [croppedMask, cropOriginYXZ] = obj.cropMaskToObject(mask)
            %
            % The margin is what keeps the mesh identical to one built from the
            % full array: marching cubes needs a ring of background around the
            % object to close the surface, and a box cut exactly at the object
            % would leave it open wherever it touched the edge. Where the object
            % already reaches the array border there is no margin to add and the
            % surface is open there either way, so nothing changes.
            %
            % Input Arguments:
            %   - **mask** - [logical] 3-D binary mask
            %
            % Output Arguments:
            %   - **croppedMask** - [logical] the bounding box plus margin; the
            %     input itself when the mask is empty, so a caller still gets an
            %     array of the expected rank
            %   - **cropOriginYXZ** - [1x3 numeric] 1-based ``[row col page]`` the
            %     crop starts at; ``[1 1 1]`` when nothing was cropped

            cropOriginYXZ = [1 1 1];
            croppedMask = mask;
            if ~any(mask(:)); return; end

            % any() along the other two axes is what makes this cheap: three
            % reductions over the array rather than ind2sub over every set voxel.
            rowsUsed  = find(any(any(mask, 2), 3));
            colsUsed  = find(any(any(mask, 1), 3));
            pagesUsed = find(any(any(mask, 1), 2));

            rowRange  = max(1, rowsUsed(1)-1)  : min(size(mask, 1), rowsUsed(end)+1);
            colRange  = max(1, colsUsed(1)-1)  : min(size(mask, 2), colsUsed(end)+1);
            pageRange = max(1, pagesUsed(1)-1) : min(size(mask, 3), pagesUsed(end)+1);

            croppedMask   = mask(rowRange, colRange, pageRange);
            cropOriginYXZ = [rowRange(1), colRange(1), pageRange(1)];
        end

        function addSurfaceFromMask(obj, mask, surfaceName, surfaceColor, cropOriginYXZ)
            % ADDSURFACEFROMMASK - Append a surface generated from a binary mask to the viewer.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addSurfaceFromMask(mask, surfaceName, surfaceColor)
            %      obj.addSurfaceFromMask(croppedMask, surfaceName, surfaceColor, cropOriginYXZ)
            %
            % **The mask is cropped to the object before meshing.** Marching cubes
            % costs the whole array it is handed, while one object of an instance
            % segmentation occupies a thousandth of it: on a 792x804x863 model the
            % median object fills 0.03% of the volume, and the ``Surface`` call
            % drops from 0.60 s to 0.038 s once the box is all it sees.
            %
            % **Finding that box is the expensive half**, which is why the fourth
            % argument exists. Reducing a full-size mask with ``any`` costs 0.44 s -
            % it eats almost the whole saving, leaving the crop worth only about
            % 1.2x. A caller with many objects should instead compute every box in
            % one pass over the label volume (``regionprops3``, ~1 s for the lot),
            % cut each object straight out of its box and pass the origin here:
            % 0.015 s per object rather than 0.52 s, which is 4 minutes against
            % 8 seconds over 489 objects. :func:`generateAllObjectSurfaces` does that.
            %
            % Cropping moves the vertices into the crop's own coordinates, so the
            % offset is put back through the transform rather than the data: the
            % viewer's ``scalingTransform`` is a pure diagonal scale, and the same
            % matrix with the crop origin in its translation column lands the
            % surface exactly where the uncropped one sat. ``isosurface`` orders
            % vertices ``(x, y, z) = (column, row, page)``, which is why the
            % translation is built in that order and not in MIB's ``[y x z]``.
            %
            % Input Arguments:
            %   - **mask** - [logical] 3-D binary mask of the object; the whole
            %     dataset unless ``cropOriginYXZ`` says otherwise
            %   - **surfaceName** - [char] name shown in the surface table
            %   - **surfaceColor** - [numeric] ``[R G B]`` color of the surface
            %   - **cropOriginYXZ** *(optional)* - [1x3 numeric] 1-based
            %     ``[row col page]`` that ``mask`` was already cut at. Supplying it
            %     skips the search. The block must keep a one-voxel background
            %     margin wherever the object does not reach the dataset edge, or the
            %     surface is left open on that side.

            if nargin >= 5 && ~isempty(cropOriginYXZ)
                croppedMask = mask;
            else
                [croppedMask, cropOriginYXZ] = obj.cropMaskToObject(mask);
            end
            surfaceTransform = obj.scalingTransform;
            if any(cropOriginYXZ > 1)
                scaleMatrix = surfaceTransform.A;
                % column 4 is the translation, in world units, ordered (x, y, z)
                scaleMatrix(1, 4) = scaleMatrix(1, 4) + (cropOriginYXZ(2) - 1) * scaleMatrix(1, 1);
                scaleMatrix(2, 4) = scaleMatrix(2, 4) + (cropOriginYXZ(1) - 1) * scaleMatrix(2, 2);
                scaleMatrix(3, 4) = scaleMatrix(3, 4) + (cropOriginYXZ(3) - 1) * scaleMatrix(3, 3);
                surfaceTransform = affinetform3d(scaleMatrix);
            end

            surfId = numel(obj.surfList) + 1;
            obj.surfList{surfId} = images.ui.graphics3d.Surface(obj.viewer, ...
                'Color', surfaceColor, ...
                'Data', croppedMask, ...
                'Transformation', surfaceTransform, ...
                'Visible', true);
            obj.surfList{surfId}.UserData.Name = surfaceName;
            obj.surfListAlpha(surfId) = 1;
            obj.surfListShown(surfId) = true;
            obj.surfList{surfId}.Alpha = 1;
            % A surface made while "hide all" is ticked must not appear: the
            % checkbox describes the view, not the surfaces that existed when it
            % was ticked.
            obj.surfList{surfId}.Visible = ~obj.surfacesHiddenAll();
        end

        function overlayMask = fetchOverlayMask(obj, overlayType, materialIndex)
            % FETCHOVERLAYMASK - Read one material from MIB and match it to the rendered volume.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      overlayMask = obj.fetchOverlayMask(overlayType, materialIndex)
            %
            % Uses the same pyramid level and downsample factor as :func:`modelUpdateOverlay`, so
            % the returned mask is aligned with ``obj.volume.Data`` voxel for voxel.
            %
            % Input Arguments:
            %   - **overlayType** - [char] layer type, normally ``'labels'``
            %   - **materialIndex** - [numeric] material index to fetch, or ``NaN``
            %     for every material at once - which returns the layer's own values
            %     rather than a binary map, and is how :func:`generateAllObjectSurfaces`
            %     gets at the object ids (the rendered overlay holds cycled bin
            %     numbers, not indices)
            %
            % Output Arguments:
            %   - **overlayMask** - binary ``uint8`` map of the requested material,
            %     or the label volume itself when ``materialIndex`` is ``NaN``

            id = obj.mibModel.getActiveId();
            isBigData = obj.mibModel.I{id}.datasetType(1) == 'B';

            getOptions = obj.levelReadOptions(overlayType);
            overlayMask = cell2mat(obj.mibModel.getData3D(overlayType, [], 3, materialIndex, getOptions));

            if ~isBigData && obj.volumeScaleFactor ~= 1
                rescaleOpt.imgType = '3D';
                rescaleOpt.method = 'nearest';
                overlayMask = utils.resizeImage3d(overlayMask, obj.volumeScaleFactor, rescaleOpt);
            end

            if ~isempty(obj.volume) && isvalid(obj.volume)
                [volH, volW, volD] = size(obj.volume.Data);
                [maskH, maskW, maskD] = size(overlayMask);
                if maskH ~= volH || maskW ~= volW || maskD ~= volD
                    overlayMask = imresize3(overlayMask, [volH, volW, volD], 'nearest');
                end
            end
        end

        function refreshOverlay(obj)
            % REFRESHOVERLAY - Pull the latest segmentation into the overlay (manual Refresh button).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.refreshOverlay()
            %
            % Callback target for ``refreshOverlayButton`` (``ButtonPushedFcn``).
            % On the first call (no overlay yet) it does a full
            % :func:`modelUpdateOverlay` so the colormap, alphamap and material table
            % are initialised; afterwards it does the lightweight
            % :func:`refreshOverlayData` that preserves per-material visibility.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.refreshOverlay: triggered\n');
            end
            if isempty(obj.noOverlayMaterials) || obj.noOverlayMaterials < 1
                obj.modelUpdateOverlay();
            else
                obj.refreshOverlayData();
            end
        end

        function toggleLiveUpdate(obj)
            % TOGGLELIVEUPDATE - Enable or disable live overlay updates from the GUI checkbox.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.toggleLiveUpdate()
            %
            % Callback target for ``liveUpdateCheckBox`` (``ValueChangedFcn``).
            % When checked, debounced ``SetData`` listeners re-fetch the model overlay
            % as the user segments in the main MIB window; when unchecked the listeners
            % and the debounce timer are removed.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.toggleLiveUpdate: triggered\n');
            end
            if obj.view.handles.liveUpdateCheckBox.Value
                obj.enableLiveUpdate();
            else
                obj.disableLiveUpdate();
            end
        end

        function enableLiveUpdate(obj)
            % ENABLELIVEUPDATE - Register the debounced listeners that drive live overlay updates.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.enableLiveUpdate()
            %
            % Registers ``SetData`` listeners that funnel into the debounced
            % :func:`liveUpdateRequest`. ``SetData`` (not ``ShowImage``) is used because it
            % fires only when the data actually changes, whereas ``ShowImage`` also fires on
            % every pan / zoom / slice change and would trigger needless refetches:
            %
            % - ``SetData`` on ``mibModel`` - fired by :func:`models.MibModel.moveLayers`
            %   (e.g. add/subtract to model).
            % - ``SetData`` on the **active dataset** (``mibModel.I{id}``) - fired by the core
            %   ``setData2D/3D/4D`` whenever a listener exists (``event.hasListener`` guard),
            %   which is how a **brush selection** commit is caught (it goes through
            %   ``setData2D`` and emits no ``mibModel`` notification).

            obj.disableLiveUpdate();   % clear any previous registration first
            obj.liveUpdateListener = {};
            obj.liveUpdateListener{end+1} = addlistener(obj.mibModel, 'SetData', @(src,evnt) obj.liveUpdateRequest());
            id = obj.mibModel.getActiveId();
            obj.liveUpdateListener{end+1} = addlistener(obj.mibModel.I{id}, 'SetData', @(src,evnt) obj.liveUpdateRequest());
        end

        function disableLiveUpdate(obj)
            % DISABLELIVEUPDATE - Remove the live-update listeners and stop the debounce timer.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.disableLiveUpdate()

            if ~isempty(obj.liveUpdateListener) && iscell(obj.liveUpdateListener)
                for i = 1:numel(obj.liveUpdateListener)
                    if ~isempty(obj.liveUpdateListener{i}) && isvalid(obj.liveUpdateListener{i})
                        delete(obj.liveUpdateListener{i});
                    end
                end
            end
            obj.liveUpdateListener = {};
            obj.stopLiveUpdateTimer();
            obj.liveUpdatePending = false;
        end

        function liveUpdateRequest(obj)
            % LIVEUPDATEREQUEST - Queue a debounced overlay refresh in response to a SetData event.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.liveUpdateRequest()
            %
            % Called on every ``SetData`` notification while live update is on. Restarts a
            % one-shot timer so a burst of segmentation strokes collapses into a single
            % overlay refetch after the user pauses (~0.2 s).

            % the listeners live on the persistent mibModel, so they can outlive a
            % closed VolRenApp window; if the view is gone, self-remove and bail out
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view) || ~isvalid(obj.view.gui)
                if isvalid(obj); obj.disableLiveUpdate(); end
                return;
            end
            obj.liveUpdatePending = true;

            if isempty(obj.liveUpdateTimer) || ~isvalid(obj.liveUpdateTimer)
                obj.liveUpdateTimer = timer('ExecutionMode', 'singleShot', 'StartDelay', 0.2, ...
                    'TimerFcn', @(~,~) obj.liveUpdateFire());
                start(obj.liveUpdateTimer);
            else
                stop(obj.liveUpdateTimer);    % restart → debounce to the last event
                start(obj.liveUpdateTimer);
            end
        end

        function liveUpdateFire(obj)
            % LIVEUPDATEFIRE - Debounce-timer callback that performs the queued overlay refresh.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.liveUpdateFire()

            if ~isvalid(obj); return; end
            if ~obj.liveUpdatePending; return; end
            obj.liveUpdatePending = false;
            if isempty(obj.view) || ~isvalid(obj.view) || ~isvalid(obj.view.gui)
                obj.disableLiveUpdate(); return;
            end
            if isempty(obj.volume) || ~isvalid(obj.volume); return; end
            % only refresh once an overlay has been initialised at least once
            if isempty(obj.noOverlayMaterials) || obj.noOverlayMaterials < 1; return; end
            try
                obj.refreshOverlayData();
            catch err
                % never let a transient read error crash the viewer
                fprintf('VolRenApp live overlay update skipped: %s\n', err.message);
            end
        end

        function stopLiveUpdateTimer(obj)
            % STOPLIVEUPDATETIMER - Stop and delete the live-update debounce timer if present.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.stopLiveUpdateTimer()

            if ~isempty(obj.liveUpdateTimer) && isvalid(obj.liveUpdateTimer)
                stop(obj.liveUpdateTimer);
                delete(obj.liveUpdateTimer);
            end
            obj.liveUpdateTimer = [];
        end

        function refreshOverlayData(obj)
            % REFRESHOVERLAYDATA - Lightweight overlay re-fetch for live updates.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.refreshOverlayData()
            %
            % Re-reads the active overlay layer at the current pyramid level, passes it
            % through :func:`buildOverlayIndexVolume` and updates only
            % ``obj.volume.OverlayData`` - material visibility, colormap, alphamap and
            % the material table are left untouched (unlike ``modelUpdateOverlay`` which
            % re-initialises them). Used as the manual "Refresh overlay" action and the
            % debounced live-update refetch.

            if isempty(obj.volume) || ~isvalid(obj.volume); return; end
            id = obj.mibModel.getActiveId();
            overlayType = obj.view.handles.overlaySourceDropDown.Value;

            % verify the requested layer still exists before reading
            switch overlayType
                case 'labels';    if ~obj.mibModel.I{id}.modelExist; return; end
                case 'mask';      if ~obj.mibModel.I{id}.maskExist; return; end
                case 'selection'; if obj.mibModel.I{id}.enableSelection == 0; return; end
            end

            isBigData = obj.mibModel.I{id}.datasetType(1) == 'B';
            materialId = obj.overlayMaterialId;
            if isempty(materialId); materialId = NaN; end

            getOptions = obj.levelReadOptions(overlayType);
            overlay = cell2mat(obj.mibModel.getData3D(overlayType, [], 3, materialId, getOptions));

            if ~isBigData && obj.volumeScaleFactor ~= 1
                rescaleOpt.imgType = '3D';
                rescaleOpt.method = 'nearest';
                overlay = utils.resizeImage3d(overlay, obj.volumeScaleFactor, rescaleOpt);
            end

            % match the overlay dimensions to the loaded image volume
            [volH, volW, volD] = size(obj.volume.Data);
            [overlayH, overlayW, overlayD] = size(overlay);
            if overlayH ~= volH || overlayW ~= volW || overlayD ~= volD
                overlay = imresize3(overlay, [volH, volW, volD], 'nearest');
            end

            % the colormap and the table stay as they are, only the index volume is refreshed
            obj.volume.OverlayData = obj.buildOverlayIndexVolume(overlay, overlayType);
        end

        function updateOverlayRenderingStyle(obj)
            % UPDATEOVERLAYRENDERINGSTYLE - Update the overlay rendering style.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateOverlayRenderingStyle()

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.updateOverlayRenderingStyle: triggered\n');
            end
            obj.volume.OverlayRenderingStyle = obj.view.handles.overlayRenderingStyle.Value; % LabelOverlay, VolumeOverlay, GradientOverlay
        end

        function updateSurfaceTable(obj)
            % UPDATESURFACETABLE - Refresh the surface table widget with current surface data.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateSurfaceTable()
            noSurfaces = numel(obj.surfList);
            data = cell([noSurfaces, 5]);
            materialNames = cellfun(@(x) x.UserData.Name, obj.surfList, 'UniformOutput', false)';
            % The row shows the surface's own state, not whether it happens to be on
            % screen: with "hide all" ticked every Visible is off, and reading them
            % back would silently untick every row.
            if numel(obj.surfListShown) < noSurfaces
                obj.surfListShown(numel(obj.surfListShown)+1:noSurfaces) = true;
            end
            % reshape rather than transpose: the column the table wants does not
            % depend on how the array happened to grow.
            surfaceShown = reshape(obj.surfListShown(1:noSurfaces), [], 1);
            surfaceColors = cellfun(@(x) x.Color, obj.surfList, 'UniformOutput', false)';
            wireframeShown = cellfun(@(x) strcmp(x.Wireframe, 'on'), obj.surfList)';
            data(:,2) = materialNames;
            data(:,3) = num2cell(obj.surfListAlpha');
            data(:,4) = num2cell(surfaceShown);
            data(:,5) = num2cell(wireframeShown);
            
            obj.view.handles.surfaceTable.Data = data;

            % Update colors for the table: the row colors show the surface colors in
            % column 1, the other columns are plain cells in the colors of the theme
            palette = utils.themeColors(obj.view.gui);
            bgColorsList = cell2mat(surfaceColors);
            obj.view.handles.surfaceTable.BackgroundColor = bgColorsList;
            removeStyle(obj.view.handles.surfaceTable);    % remove current styles
            s1 = uistyle('BackgroundColor', palette.tableCell, 'FontColor', palette.text);
            addStyle(obj.view.handles.surfaceTable, s1, 'column', 2:5);
            
            % set current object to volume to make sure that orthoslices
            % are interactive
            obj.viewer.CurrentObject = obj.viewer.Children(1);
        end
        
        function modelHideAllMaterials(obj, hideMaterialsSwitch)
            % MODELHIDEALLMATERIALS - Hide or show all overlay materials at once.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.modelHideAllMaterials()
            %      obj.modelHideAllMaterials(hideMaterialsSwitch)
            %
            % Input Arguments:
            %   - **hideMaterialsSwitch** *(optional)* - [logical] ``true`` to hide, ``false`` to show
            %     (default: reads ``obj.view.handles.modelHideAllCheckBox.Value``)

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.modelHideAllMaterials: triggered\n');
            end
            if nargin < 2; hideMaterialsSwitch = obj.view.handles.modelHideAllCheckBox.Value; end

            obj.view.handles.modelHideAllCheckBox.Value = hideMaterialsSwitch;
            obj.applyOverlayAlphamap();
        end


        function modelHideAllSurfaces(obj, hideSurfacesSwitch)
            % MODELHIDEALLSURFACES - Hide every surface at once, or restore them individually.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.modelHideAllSurfaces()
            %      obj.modelHideAllSurfaces(hideSurfacesSwitch)
            %
            % Callback of the ``surfacesHideAll`` checkbox. ``true`` hides every
            % surface; ``false`` puts each one back to its **own** show state from
            % the surface table rather than turning all of them on, so a surface the
            % user had unticked stays unticked.
            %
            % That is only possible because the per-surface intent lives in
            % :attr:`surfListShown`. Reading it back from each surface's ``Visible``
            % would not work: hiding everything overwrites exactly the answer that
            % would have to be restored.
            %
            % Input Arguments:
            %   - **hideSurfacesSwitch** *(optional)* - [logical] ``true`` to hide
            %     all, ``false`` to restore (default: reads the checkbox)

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.modelHideAllSurfaces: triggered\n');
            end
            if nargin < 2; hideSurfacesSwitch = obj.surfacesHiddenAll(); end

            if isfield(obj.view.handles, 'surfacesHideAll')
                obj.view.handles.surfacesHideAll.Value = hideSurfacesSwitch;
            end
            obj.applySurfaceVisibility();
        end

        function hideAll = surfacesHiddenAll(obj)
            % SURFACESHIDDENALL - State of the "hide all surfaces" checkbox.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      hideAll = obj.surfacesHiddenAll()
            %
            % Behind an accessor because the checkbox is the newest widget on the
            % Surfaces tab: a view built before it was added has no such handle, and
            % every surface would then be invisible rather than the feature simply
            % being absent.
            %
            % Output Arguments:
            %   - **hideAll** - [logical] false when the checkbox does not exist

            hideAll = false;
            if isfield(obj.view.handles, 'surfacesHideAll')
                hideAll = logical(obj.view.handles.surfacesHideAll.Value);
            end
        end

        function applySurfaceVisibility(obj)
            % APPLYSURFACEVISIBILITY - Push show state onto the surfaces.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.applySurfaceVisibility()
            %
            % A surface is visible when its own row is ticked **and** "hide all" is
            % off. The two are kept apart so that either can change without losing
            % the other; this is the single place they are combined.

            hideAll = obj.surfacesHiddenAll();
            for surfId = 1:numel(obj.surfList)
                if surfId > numel(obj.surfListShown); obj.surfListShown(surfId) = true; end
                obj.surfList{surfId}.Visible = obj.surfListShown(surfId) && ~hideAll;
            end
        end

        function updateModelTable(obj)
            % UPDATEMODELTABLE - Refresh the model/overlay material table widget.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateModelTable()
            %
            % The rows come from the mapping generated by :func:`buildOverlayIndexVolume`, so a
            % model with 65535 materials produces either a single row (cycled colors) or one row
            % per selected material index, never one row per material.

            removeStyle(obj.view.handles.modelTable);    % remove current styles
            if isempty(obj.overlayRowNames)
                obj.view.handles.modelTable.Data = [];
                return;
            end

            data = cell([numel(obj.overlayRowNames), 4]);
            data(:,2) = obj.overlayRowNames;
            data(:,3) = num2cell(obj.overlayAlpha);
            data(:,4) = num2cell(obj.overlayShownMaterials);
            obj.view.handles.modelTable.Data = data;

            % Update colors for the table: the row colors show the material colors in
            % column 1, the other columns are plain cells in the colors of the theme
            palette = utils.themeColors(obj.view.gui);
            obj.view.handles.modelTable.BackgroundColor = obj.overlayRowColors;
            s1 = uistyle('BackgroundColor', palette.tableCell, 'FontColor', palette.text);
            addStyle(obj.view.handles.modelTable, s1, 'column', 2:4);
        end

        function surfaceTableCellEdit(obj, event)
            % SURFACETABLECELLEDIT - Handle in-place edits in the surface table.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.surfaceTableCellEdit(event)
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.surfaceTableCellEdit: triggered\n');
            end
            indices = event.Indices;
            newData = event.NewData;
            surfaceId = indices(1);
            if indices(2) == 3  % update transparency
                if ~isnumeric(newData) || newData<0 || newData > 1
                    obj.view.handles.surfaceTable.Data(surfaceId, 3) = {event.PreviousData};
                    uialert(obj.view.gui, ...
                        sprintf('!!! Error !!!\n\nAlpha value describes transparency\n(0-transparent, 1-opaque) for the surface!\n\nPlease make sure the Alpha value between 0 and 1'), 'Wrong Alpha');
                    return;
                end
                obj.surfList{surfaceId}.Alpha = newData;
            elseif indices(2) == 4  % show / hide surface
                % Recorded as intent and then applied, so that ticking a row while
                % "hide all" is on is remembered for when it is switched off rather
                % than making this one surface reappear on its own.
                obj.surfListShown(surfaceId) = logical(newData);
                obj.applySurfaceVisibility();
            elseif indices(2) == 5  % show / hide wireframe
                if newData == 0     % hide wireframe
                    obj.surfList{surfaceId}.Wireframe = false;
                else                % show wireframe
                    obj.surfList{surfaceId}.Wireframe = true;
                end
            elseif indices(2) == 2  % change name
                obj.surfList{surfaceId}.UserData.Name = newData;
            end
        end

        function modelTableCellEdit(obj, event)
            % MODELTABLECELLEDIT - Handle in-place edits in the model/overlay material table.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.modelTableCellEdit(event)
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.modelTableCellEdit: triggered\n');
            end
            indices = event.Indices;
            newData = event.NewData;
            materialId = indices(1);

            if indices(2) == 3  % update transparency
                if ~isnumeric(newData) || newData<0 || newData > 1
                    obj.view.handles.modelTable.Data(materialId, 3) = {event.PreviousData};
                    uialert(obj.view.gui, ...
                        sprintf('!!! Error !!!\n\nAlpha value describes transparency\n(0-transparent, 1-opaque) for the material!\n\nPlease make sure the Alpha value between 0 and 1'), 'Wrong Alpha');
                    return;
                end
                obj.overlayAlpha(materialId) = newData;
                obj.applyOverlayAlphamap();
            elseif indices(2) == 4  % show / hide material
                if obj.view.handles.modelHideAllCheckBox.Value % deal with the Hide All button
                    obj.view.handles.modelHideAllCheckBox.Value = false;
                end
                obj.overlayShownMaterials(materialId) = logical(newData);
                obj.applyOverlayAlphamap();
            end
        end

        function updateCameraPosition(obj, event)
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.updateCameraPosition(%s): triggered\n', event.Source.Tag);
            end
            if ~isvalid(obj.viewer); return; end % skip when the viewer is closed
            
            switch event.Source.Tag
                case 'cameraDistanceEdit'
                    % change camera distance
                    newDistance = event.Source.Value;
                    prevDistance = event.PreviousValue;
                    ratio = newDistance/prevDistance;
                    obj.viewer.CameraPosition = obj.viewer.CameraTarget + (obj.viewer.CameraPosition-obj.viewer.CameraTarget)*ratio;
                case 'cameraZoomEdit'
                    obj.viewer.CameraZoom = event.Source.Value;
                case 'cameraPositionX'
                    obj.viewer.CameraPosition(1) = event.Source.Value;
                case 'cameraPositionY'
                    obj.viewer.CameraPosition(2) = event.Source.Value;
                case 'cameraPositionZ'
                    obj.viewer.CameraPosition(3) = event.Source.Value;
                case 'cameraTargetX'
                    obj.viewer.CameraTarget(1) = event.Source.Value;
                case 'cameraTargetY'
                    obj.viewer.CameraTarget(2) = event.Source.Value;
                case 'cameraTargetZ'
                    obj.viewer.CameraTarget(3) = event.Source.Value;
                case 'cameraUpVectorX'
                    obj.viewer.CameraUpVector(1) = event.Source.Value;
                case 'cameraUpVectorY'
                    obj.viewer.CameraUpVector(2) = event.Source.Value;
                case 'cameraUpVectorZ'
                    obj.viewer.CameraUpVector(3) = event.Source.Value;
            end
        end

        function changeSlice(obj, sourceWidget, value)
            % CHANGESLICE - Update a slice plane position from a slider or edit box.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.changeSlice(sourceWidget, value)
            %
            % Input Arguments:
            %   - **sourceWidget** - [char] tag of the source widget:
            %     ``'xSliderEdit'``, ``'ySliderEdit'``, or ``'zSliderEdit'``
            %   - **value** - [numeric] new slice index

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.changeSlice(%s): triggered\n', sourceWidget);
            end
            if nargin == 3; obj.view.handles.(sourceWidget).Value = value;  end

            switch sourceWidget
                case 'xSliderEdit'
                    obj.view.handles.xSlider.Value = obj.view.handles.(sourceWidget).Value;
                    obj.volume.SlicePlaneValues(1,4) = obj.view.handles.(sourceWidget).Value;
                case 'ySliderEdit'
                    obj.view.handles.ySlider.Value = obj.view.handles.(sourceWidget).Value;
                    obj.volume.SlicePlaneValues(2,4) = obj.view.handles.(sourceWidget).Value;
                case 'zSliderEdit'
                    obj.view.handles.zSlider.Value = obj.view.handles.(sourceWidget).Value;
                    obj.volume.SlicePlaneValues(3,4) = obj.view.handles.(sourceWidget).Value;
            end
        end

        function showVolume(obj, showSwitch)
            % SHOWVOLUME - Toggle visibility of the main volume object.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.showVolume()
            %      obj.showVolume(showSwitch)
            %
            % Input Arguments:
            %   - **showSwitch** *(optional)* - [logical] ``true`` to show, ``false`` to hide
            %     (default: reads ``obj.view.handles.showVolumeCheckBox.Value``)
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.showVolume: triggered\n');
            end
            if nargin < 2; showSwitch = obj.view.handles.showVolumeCheckBox.Value; end

            if showSwitch
                obj.volume.Visible = 'on';
            else
                obj.volume.Visible = 'off';
            end
        end

        function transparentVolume(obj, transparentSwitch)
            % TRANSPARENTVOLUME - Make the volume transparent to reveal the overlay model.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.transparentVolume()
            %      obj.transparentVolume(transparentSwitch)
            %
            % Input Arguments:
            %   - **transparentSwitch** *(optional)* - [logical] ``true`` to make transparent, ``false`` to restore
            %     (default: reads ``obj.view.handles.transparentVolumeCheckBox.Value``)
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.transparentVolume: triggered\n');
            end
            if nargin < 2; transparentSwitch = obj.view.handles.transparentVolumeCheckBox.Value; end

            if transparentSwitch
                transparentVolume = true;
                obj.recalculateAlphamap(transparentVolume);
            else
                transparentVolume = false;
                obj.recalculateAlphamap(transparentVolume);
            end
        end

        function showHelp(obj)
            % SHOWHELP - Open the MIB 3D viewer help page in the system browser.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.showHelp()

            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenApp.showHelp: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'home', 'home-mib3Dviewer.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-mib3Dviewer.html');
            
        end

    end
end

function volRenAppThemeChanged(obj, hFig)
% VOLRENAPPTHEMECHANGED - ThemeChangedFcn of the VolRenApp window: remap the
% standard dialog colors and redraw the model and surface tables, whose text cells
% are painted with a uistyle in the colors of the current theme (utils.themeColors
% tableCell and text). updateSurfaceTable is skipped without surfaces: it also
% makes the first viewer child current, which needs a rendered scene.
utils.applyThemeColors(hFig);
obj.updateModelTable();
if ~isempty(obj.surfList)
    obj.updateSurfaceTable();
end
end
