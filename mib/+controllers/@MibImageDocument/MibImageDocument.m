classdef MibImageDocument < handle
    % classdef MibImageDocument
    % Controller for a single image document (FigureDocument + ImageView component)
    %
    % This class encapsulates a single image document view in MIB, managing
    % the FigureDocument container, ImageView component, and all associated
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
    %   doc.updateBrushCursor([100, 100], ':', true);
    %
    %   % access tothe class
    %   obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}


    properties
        mibController           % controllers.MibController, handle to main controller
        view                    % MibView, handle to the main view
        mibModel                % models.MibModel, handle to the main model
        gui                     % views.components.ImageView, the ImageView component
        handles                 % struct with ImageView component handles (axes, buttons, etc.)
        UIFigure                % handle to underlying UIFigure
        
        figureDoc               % matlab.ui.internal.FigureDocument, the document container
        setOfDatasetsIndex      % double, index of this document in the Sets
        brushCursor             % matlab.graphics.chart.primitive.Line, handle to brush cursor plot
        brushCursorOffset       % 2×N double array, [X offsets; Y offsets] for brush cursor circle
        centralMarker           % marker for the center of the axes
        imageHandle = matlab.graphics.primitive.Image('CData', []); % handle to the rendered image
        sliderStep = 1          % z-slider step, can be updated in obj.sliceNumberSlider_ContextMenu
        sliderShiftStep = 10    % z-slider step with shift pressed obj.sliceNumberSlider_ContextMenu
    end

    methods
        % declaration of methods

        title = getTitle(obj)        % Get the title of this image document

        gui_Callbacks(obj, hWidget, hData, mode)        % callbacks for widgets of the Image View documents obj.cImageDoc{setId}

        gui_ScrollWheelFcn(obj, eventdata)        % Callback for mouse scroll wheel

        gui_WinMouseMotionFcn(obj)        % Callback for mouse movement over the figure window

        gui_SizeChangedFcn(obj)        % Callback when figure size changes

        selectDocument(obj)        % Select this document in the document group

        setDescription(obj, description)        % Update the description text of this document

        setTitle(obj, title)        % Set the title of this image document

        setupCallbacks(obj)        % Setup all callbacks for this image document

        sliceNumber_Callback(obj, parameter, BatchOptIn)        % callback for changing the slices of the 3D dataset by entering a new slice number

        sliceNumberSlider_ContextMenu(obj, menuEntry, selectedData)        % callbacks for the context menu of change of slices slider

        sliceNumberSlider_Callback(obj, sliderValue)        % callback for change of slices using the slice number slider 

        updateBrushCursor(obj, xyCoordinate, lineStyle, isInsideAxes)        % Update brush cursor position and visibility

        updateBrushCursorOffset(obj)        % Update brush cursor offset based on current brush radius and magnification

        function obj = MibImageDocument(mainCtrl, view, title, docGroupTag, setOfDatasetsIndex, model)
            % Create a new MibImageDocument controller
            %
            % Creates a FigureDocument with an embedded ImageView component,
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

            %% Create ImageView component
            obj.gui = views.components.ImageView('Parent', obj.figureDoc.Figure, ...
                'Units', 'normalized', 'Position', [0 0 1 1]);
            
            % populate handles structure
            obj.handles = obj.gui.handles;
            obj.centralMarker = obj.gui.centralMarker;
            obj.UIFigure = obj.gui.imViewFigure; % handle to the underlying figure

            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.gui.handles, true, 'obj.cImageDoc{obj.mibModel.Sets.selectedSet}'); 
            end

            % Hold axes once (Note: requires YDir = 'reverse' defined in ImageView.mlapp)
            hold(obj.handles.imViewAxes, 'on');

            %% Configure axes properties
            obj.handles.imViewAxes.Box = 'on';
            obj.handles.imViewAxes.XTick = [];
            obj.handles.imViewAxes.YTick = [];
            obj.handles.imViewAxes.Interruptible = 'off';
            obj.handles.imViewAxes.BusyAction = 'queue';
            obj.handles.imViewAxes.HandleVisibility = 'callback';

            %% add context menu to the slider 
            obj.handles.sliceNumberSliderContext = uicontextmenu(obj.UIFigure);
            obj.handles.sliceNumberSliderContextDefault = uimenu(obj.handles.sliceNumberSliderContext, ...
                'Text', 'Default', 'Tag', 'sliceNumberSliderContextDefault');
            obj.handles.sliceNumberSliderContextSetStep = uimenu(obj.handles.sliceNumberSliderContext, ...
                'Text', 'Set step...', 'Tag', 'sliceNumberSliderContextSetStep');
            % Add context menu to buttons
            obj.handles.sliceNumberSlider.ContextMenu = obj.handles.sliceNumberSliderContext;
            % Add callbacks
            obj.handles.sliceNumberSliderContextDefault.MenuSelectedFcn = @obj.sliceNumberSlider_ContextMenu;
            obj.handles.sliceNumberSliderContextSetStep.MenuSelectedFcn = @obj.sliceNumberSlider_ContextMenu;


            %% Setup callbacks
            obj.setupCallbacks();

        end

        function delete(obj)
            % function delete(obj)
            % Destructor for MibImageDocument
            %
            % Properly cleans up resources when the document is deleted.
            % Removes the FigureDocument, brush cursor, and ImageView component.
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

                % Delete the ImageView component
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
