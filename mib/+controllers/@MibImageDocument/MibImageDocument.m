classdef MibImageDocument < handle
    % classdef MibImageDocument
    % Controller for a single image document (FigureDocument + ImageViewDocument component)
    %
    % This class encapsulates a single image document view in MIB, managing
    % the FigureDocument container, ImageViewDocument component, and all associated
    % callbacks including mouse interactions and brush cursor visualization.
    %
    % Example:
    %   % Create new image document
    %   doc = controllers.MibImageDocument(obj.mibController, obj.view, ...
    %       'Dataset 1', docGroupTag, 1, obj.mibModel);
    %
    %   % Add to document group
    %   obj.view.gui.add(doc.figureDoc);
    %
    %   % Update description
    %   doc.setDescription('Buffer 1: myimage.tif');
    %
    %   % Update brush cursor
    %   doc.updateBrushCursor([100, 100], ':');
    %
    %   % access tothe class
    %   obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}


    properties
        mibController           % controllers.MibController, handle to main controller
        view                    % MibView, handle to the main view
        mibModel                % models.MibModel, handle to the main model
        gui                     % views.components.ImageViewDocument, the ImageViewDocument component
        handles                 % struct with ImageDocument component handles (axes, buttons, etc.)
        UIFigure                % handle to underlying UIFigure
        
        figureDoc               % matlab.ui.internal.FigureDocument, the document container
        setOfDatasetsIndex      % double, index of this document in the Sets
        brushCursor             % matlab.graphics.chart.primitive.Line, handle to brush cursor plot
        brushCursorOffset       % 2×N double array, [X offsets; Y offsets] for brush cursor circle
        brushPrevXY             % coordinates of the previous pixel for the @em Brush tool,
                                % @note dimensions: [x, y] or []
        brushSelection = []     % selection layer during the brush tool movement, @code {1:2}[1:height,1:width] or NaN @endcode
                                % brushSelection{1} 
                                %   .selection - contains brush selection during drawing
                                %   .travelPathInPixels - distance of brush travelled during painting
                                % brushSelection{2} - contains labels of the supervoxels and some additional information
                                %   .slic - a label image with superpixels
                                %   .selectedSlic - a bitmap image of the selected with the Brush tool superpixels 
                                %   .selectedSlicIndices - indices of the selected Slic superpixels
                                %   .selectedSlicIndicesNew - a list of freshly selected Slic indices when moving the brush, used for the undo with Ctrl+Z
                                %   .CData - a copy of the shown in the imageAxes image, to be used for the undo
                                % brushSelection{3} - a structure that contains information for
                                % the adaptive mode:
                                %   .meanVals - array of mean intensity values for each superpixels
                                %   .mean - mean intensity value for the initial selection
                                %   .std - standard deviation of intensities for the initial selection
                                %   .factor - factor that defines variation of STD variation
                                % @note the 'brushSelection' is modified with respect to @code magFactor @endcode and crop of the image within the viewing window
        centralMarker           % marker for the center of the axes
        imageHandle = matlab.graphics.primitive.Image('CData', []); % handle to the rendered image
        listeners = {}          % cell array with handles to listeners
        quickMeasure = []       % struct with active quick measurement: .roi .textH .datasetId .lastPos; or []
        sliderTStep = 1          % t-slider step, can be updated in obj.sliceNumberSlider_ContextMenu
        sliderTShiftStep = 10    % t-slider step with shift pressed obj.sliceNumberSlider_ContextMenu
        sliderZStep = 1          % z-slider step, can be updated in obj.sliceNumberSlider_ContextMenu
        sliderZShiftStep = 10    % z-slider step with shift pressed obj.sliceNumberSlider_ContextMenu
        sliderDebounceTimer = [] % timer used to debounce rapid slider dragging (slice and frame sliders);

        trackerYXZ = [NaN; NaN; NaN]  % [y; x; z] coordinates for the Membrane ClickTracker tool starting point

        % switches that are updated within obj.gui_WinMouseMotionFcn
        isInsideAxes = false;   % mouse inside image axes
        wasInsideAxes = [];     % mouse was inside the image axes
        isInsideImage = false;  % indicating the cursor inside the image frames

    end

    methods
        % declaration of methods

        clearQuickMeasure(obj)        % Silently remove the active quick-measurement ROI and text label

        frameNumber_Callback(obj, parameter, BatchOptIn)        % Callback for changing the time points of the dataset by entering a new time value
        listener_frameChanged(obj)    % Listener for MibModel 'FrameChanged' event — syncs frame widgets and redraws
        listener_sliceChanged(obj)    % Listener for MibModel 'SliceChanged' event — syncs slice widgets and redraws
        
        frameNumberSlider_Callback(obj, sliderValue)        % Change the currently displayed frame using the time-number slider

        title = getTitle(obj)        % Get the title of this image document

        gui_panAxesFcn(obj, xy, imgWidth, imgHeight)        % Moves the image in obj.handles.imViewAxes during a pan gesture.

        gui_Callbacks(obj, hWidget, hData, mode)        % callbacks for widgets of the Image View documents obj.cImageDoc{setId}

        gui_ScrollWheelFcn(obj, eventdata)        % Callback for mouse scroll wheel

        gui_SizeChangedFcn(obj)        % Callback when figure size changes

        gui_Brush_scrollWheelFcn(obj, eventdata)        % Handle scroll wheel during adaptive superpixel brush mode

        gui_WindowBrushMotionFcn(obj, structElement)        % Draw brush trace during brush tool use

        gui_WindowButtonDownFcn(obj)        % Callback for mouse button press in the image view.

        gui_WindowButtonUpFcn(obj, brush_switch)        % Callback for release of the mouse button.

        gui_WindowKeyPressFcn_BrushSuperpixel(obj, eventdata)        % Handle key callbacks during brush superpixel mode
        
        gui_WinMouseMotionFcn(obj)        % Callback for mouse movement over the figure window

        segmentationAnnotation(obj, y, x, z, t, modifier, options)        % Add or remove a text annotation at the given dataset coordinate

        segmentationBall3D(obj, y, x, z, modifier, BatchOptIn)        % Do segmentation using the 3D ball tool

        segmentationLines3D(obj, y, x, z, modifier)        % Handle mouse clicks for 3D line skeleton annotation

        segmentationBrush(obj, y, x, modifier)        % Start segmentation using the brush tool

        segmentBlackWhiteThreshold(obj, BatchOptIn)        % Black and white thresholding for segmentation

        segmentationDragAndDrop(obj, y, x, modifier)        % Initiate drag-and-drop of materials/selection/mask

        gui_WindowDragAndDropMotionFcn(obj, brushSelection)  % Visual feedback during drag-and-drop motion

        gui_WindowButtonUpDragAndDropFcn(obj, mode, diffX, diffY, BatchOptIn)  % Commit drag-and-drop shift on mouse release

        output = segmentationClickTracker(obj, yxzCoordinate, yx, modifier)  % Trace membranes using the click tracker tool

        segmentationLasso(obj, modifier)        % Do segmentation using the lasso tool

        segmentationObjectPicker(obj, yxzCoordinate, modifier)  % Select objects from mask/model layers

        recalculateObjects(obj)  % Recalculate object stats for Object Picker 3D mode

        segmentationMagicWand(obj, yxzCoordinate, BatchOptIn)  % Do segmentation using the magic wand tool

        segmentationRegionGrowing(obj, yxzCoordinate, BatchOptIn)  % Do segmentation using the region growing method

        segmentationLassoManual(obj, BatchOptIn)  % Do manual segmentation using the lasso tool

        segmentationSAM(obj, extraOptions, BatchOptIn)        % Segment using SAM1 (Segment Anything Model)

        segmentationSAM2(obj, extraOptions, BatchOptIn)       % Segment using SAM2 (Segment Anything Model 2)

        status = segmentationSAM_requirements(obj, samVersion) % Check SAM requirements and download models

        segmentationSpot(obj, y, x, modifier, BatchOptIn)        % Do segmentation using the spot tool

        selectDocument(obj)        % Select this document in the document group
        
        setDescription(obj, description)        % Update the description text of this document

        setTitle(obj, title)        % Set the title of this image document

        setupCallbacks(obj)        % Setup all callbacks for this image document

        sliceNumber_Callback(obj, parameter, BatchOptIn)        % callback for changing the slices of the 3D dataset by entering a new slice number

        sliceNumberSlider_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of change of slices slider

        sliceNumberSlider_Callback(obj, sliderValue)        % callback for change of slices using the slice number slider 

        changed = syncActiveSet(obj)        % Lightweight sync of mibModel's active set to this document's setOfDatasetsIndex.

        updateBrushCursor(obj, xyCoordinate, lineStyle, resetOffset)        % Update brush cursor position and visibility

        updateBrushCursorOffset(obj)        % Update brush cursor offset based on current brush radius and magnification

        updateMeasureText(obj, pos)        % Refresh the quick-measurement text label (called on zoom/pan/drag/dataset-change)

        function obj = MibImageDocument(mainCtrl, view, title, docGroupTag, setOfDatasetsIndex, model)
            % Create a new MibImageDocument controller
            %
            % Creates a FigureDocument with an embedded ImageViewDocument component,
            % configures axes properties, and sets up all necessary callbacks
            % for mouse interactions and navigation controls.
            %
            % Parameters:
            %   mainCtrl: controllers.MibController, main MIB controller
            %   view: MibView, main MIB view
            %   title: char, title for the document tab
            %   docGroupTag: char, document group tag for MDI grouping
            %   setOfDatasetsIndex: double, index of this document (typically current set number)
            %   model: models.MibModel, main MIB model
            %
            % Return values:
            %   obj: controllers.MibImageDocument, the created controller instance
            %
            % Example:
            %   docCtrl = controllers.MibImageDocument(obj.mibController, ...
            %       obj.view, 'Buffer 1', 'imageViewGroup', 1, obj.mibModel);

            %% Init properties
            obj.mibController = mainCtrl;
            obj.view = view;
            obj.mibModel = model;
            obj.setOfDatasetsIndex = setOfDatasetsIndex;
            obj.brushCursor = [];
            obj.brushCursorOffset = [];

            %% Create FigureDocument
            figOptions.Title = title;
            figOptions.DocumentGroupTag = docGroupTag;
            obj.figureDoc = matlab.ui.internal.FigureDocument(figOptions);
            obj.figureDoc.EnableDockControls = true;
            obj.figureDoc.Closable = false;
            obj.figureDoc.Figure.AutoResizeChildren = 'off';

            %% Create ImageViewDocument component
            obj.gui = views.components.ImageViewDocument('Parent', obj.figureDoc.Figure, ...
                'Units', 'normalized', 'Position', [0 0 1 1]);
            
            % populate handles structure
            obj.handles = obj.gui.handles;
            obj.centralMarker = obj.gui.centralMarker;
            obj.UIFigure = ancestor(obj.gui, 'figure'); % handle to underlying UIFigure

            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.gui.handles, true, 'obj.cImageDoc{obj.mibModel.Sets.selectedSet}', {'mainGridLayout'}); 
            end

            % Hold axes once (Note: requires YDir = 'reverse' defined in ImageViewDocument.mlapp)
            hold(obj.handles.imViewAxes, 'on');

            %% Configure axes properties
            obj.handles.imViewAxes.Box = 'on';
            obj.handles.imViewAxes.XTick = [];
            obj.handles.imViewAxes.YTick = [];
            obj.handles.imViewAxes.Interruptible = 'off';
            obj.handles.imViewAxes.BusyAction = 'queue';
            obj.handles.imViewAxes.HandleVisibility = 'callback';

            %% Setup callbacks
            obj.setupCallbacks();

        end

        function delete(obj)
            % function delete(obj)
            % Destructor for MibImageDocument
            %
            % Properly cleans up resources when the document is deleted.
            % Removes the FigureDocument, brush cursor, and ImageViewDocument component.
            % This method is automatically called when the object is deleted.
            %
            % Parameters:
            %   none
            %
            % Return values:
            %   none
            %
            % Example:
            %   % Explicit deletion
            %   delete(obj.mibController.cImageDoc{setOfDatasetsIndex});
            %
            %   % Automatic deletion when removed from array
            %   obj.mibController.cImageDoc(setOfDatasetsIndex) = [];

            try
                % Delete brush cursor if it exists
                if ~isempty(obj.brushCursor) && isvalid(obj.brushCursor)
                    delete(obj.brushCursor);
                end

                % Delete the ImageViewDocument component
                if ~isempty(obj.gui) && isvalid(obj.gui)
                    delete(obj.gui);
                end

                % Delete the FigureDocument
                if ~isempty(obj.figureDoc) && isvalid(obj.figureDoc)
                    delete(obj.figureDoc);
                end
            catch err
                % Silently handle errors during cleanup
                warning('MibImageDocument:delete', 'Error during cleanup: %s', err.message);
            end
        end


    end
end
