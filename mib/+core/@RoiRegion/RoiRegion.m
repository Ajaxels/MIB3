classdef RoiRegion < matlab.mixin.Copyable
    % ROIREGION - :class:`RoiRegion` class is responsible for keeping regions of interest (ROI).
    %
    % Ported from MIB2 :class:`mibRoiRegion` class, adapted for the MIB3
    % package namespace.  This class manages ROI data storage and
    % visualization options only.  Interactive drawing of new ROIs is
    % handled by :class:`controllers.MibRoi;` this class is data-only and
    % does not hold references to any controller.
    %
    % **Supported** **ROI** **types:**
    % - **'rectangle'** - rectangular ROI (MIB2 equivalent: 'imrect')
    % - **'ellipse'**   - elliptical ROI  (MIB2 equivalent: 'imellipse')
    % - **'polygon'**   - polygonal ROI   (MIB2 equivalent: 'impoly')
    % - **'freehand'**  - freehand ROI    (MIB2 equivalent: 'imfreehand')
    %
    % **Data** **structure** — each element of the *obj.Data* struct array
    % contains:
    % - *.label*       — string/cellstr with a user-visible label
    % - *.type*        — string: 'rectangle', 'ellipse', 'polygon', 'freehand'
    % - *.X*           — vector of X-coordinates of vertices
    % - *.Y*           — vector of Y-coordinates of vertices
    % - *.orientation* — orientation when the ROI was created: 1-'zx', 2-'zy', 3-'yx'
    % - *.BoundingBox* — struct with *.x* = [xmin, xmax] and *.y* = [ymin, ymax]

    % Updates
    % 

    properties (SetAccess = public, GetAccess = public)
        Data
        % a structure array with ROI data, see class header for field descriptions

        Options
        % a structure with display/visualization options:
        %   .marker      - char, marker style (default 's')
        %   .markersize  - char, marker size  (default '6')
        %   .linestyle   - char, line style   (default '-')
        %   .linewidth   - char, line width   (default '2')
        %   .color       - char, color        (default 'y')
        %   .textcolorfg - char, text foreground color (default 'y')
        %   .textcolorbg - char, text background color (default 'none')
        %   .fontsize    - char, font size    (default '12')
        %   .showMarkers - numeric, show markers flag (default 1)
        %   .showLines   - numeric, show lines flag   (default 1)
        %   .showText    - numeric, show text flag     (default 1)

        mibDataset
        % handle to the parent @type core.MibDataset instance.
        % Used to read orientation, image dimensions, axes limits, and
        % block-mode state without requiring a controller reference.
    end

    % =====================================================================
    %  Constant map for backward compatibility with MIB2 .roi files
    % =====================================================================
    properties (Constant, Access = public)
        LegacyTypeMap = dictionary( ...
            ["imrect",    "imellipse",  "impoly",   "imfreehand"], ...
            ["rectangle", "ellipse",    "polygon",  "freehand"]);
        % dictionary that maps MIB2 type name strings to MIB3 equivalents.
        % Used by @em convertLegacyTypes() when loading old @em .roi files.
    end

    methods

        function obj = RoiRegion(mibDataset)
            % ROIREGION - Constructor for the :class:`RoiRegion` class.
            %
            % Syntax:
            %   function obj = RoiRegion(mibDataset)
            %
            % Create a new instance of the class with default parameters.
            % The class is typically instantiated inside
            % *core.MibDataset.initialize* and stored as *obj.hROI.*
            %
            % Input Arguments:
            %   - **mibDataset** — *(optional)* handle to :class:`core.MibDataset`
            %     (the parent dataset that owns this ROI collection).
            %     When omitted or empty, the class still works but methods
            %     that need orientation or image dimensions require explicit
            %     arguments.
            %
            % Output Arguments:
            %   - **obj** — instance of the :class:`core.RoiRegion` class.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     hROI = core.RoiRegion(obj);% call from MibDataset.initialize; create ROI handler attached to this dataset
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     hROI = core.RoiRegion();% create a standalone ROI handler (no dataset reference)
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI = core.RoiRegion(obj.mibModel.I{obj.mibModel.id});% call from mibController; re-create ROI handler
            %

            if nargin < 1; mibDataset = []; end
            obj.mibDataset = mibDataset;
            obj.clearContents();
        end

        function clearContents(obj)
            % CLEARCONTENTS - Set all elements of the class to default values.
            %
            % Syntax:
            %   function clearContents(obj)
            %
            % Resets both the display Options (via *setDefaultOptions)*
            % and the stored Data (via *clearData)* to their initial
            % empty/default state.
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
            %     obj.mibModel.I{obj.mibModel.id}.hROI.clearContents();% call from mibController; clear all ROIs and reset options
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
        end

        function clearData(obj)
            % CLEARDATA - Remove all values from the Data structure, resetting it to an.
            %
            % Syntax:
            %   function clearData(obj)
            %
            % empty single-element struct with the correct field names.
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
            %     obj.mibModel.I{obj.mibModel.id}.hROI.clearData();% call from mibController; remove all stored ROIs
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     clearData(obj);% call within the class
            %

            obj.Data = [];

            obj.Data.label = [];
            obj.Data.type = [];
            obj.Data.X = [];
            obj.Data.Y = [];
            obj.Data.orientation = [];
            obj.Data.BoundingBox.x = [];
            obj.Data.BoundingBox.y = [];
        end

        function setDefaultOptions(obj)
            % SETDEFAULTOPTIONS - Set all values of the Options structure to their default state.
            %
            % Syntax:
            %   function setDefaultOptions(obj)
            %
            % Default values match the original MIB2 mibRoiRegion defaults.
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
            %     obj.mibModel.I{obj.mibModel.id}.hROI.setDefaultOptions();% call from mibController; reset display options to defaults
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     setDefaultOptions(obj);% call within the class
            %

            obj.Options.marker = 's';
            obj.Options.markersize = '6';
            obj.Options.linestyle = '-';
            obj.Options.linewidth = '2';
            obj.Options.color = 'y';
            obj.Options.textcolorfg = 'y';
            obj.Options.textcolorbg = 'none';
            obj.Options.fontsize = '12';
            obj.Options.showMarkers = 1;
            obj.Options.showLines = 1;
            obj.Options.showText = 1;
        end

        function updateOptions(obj, parentFigure)
            % UPDATEOPTIONS - Show an interactive dialog to update the display Options.
            %
            % Syntax:
            %   function updateOptions(obj, parentFigure)
            %
            % Opens *utils.dlgs.inputUniversalDlg* with the current
            % option values as defaults.  If the user cancels the dialog
            % no changes are made.
            %
            % Input Arguments:
            %   - **parentFigure** — handle to the parent window used for dialog
            %     centering.  Can be an AppContainer handle, a uifigure
            %     handle, or *[]* for automatic placement.
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.updateOptions(obj.mibController.view.gui);% call from mibController; open options dialog parented to the main window
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.updateOptions([]);% call from a plugin; let MATLAB place the dialog
            %

            O = obj.Options;
            prompts = { ...
                'Marker Style:', ...
                'Marker Size:', ...
                'Line Style:', ...
                'Line Width', ...
                sprintf('Color\n( r  g  b  c  m  y  k  w none)'), ...
                'Text Foreground Color', ...
                'Text Background Color', ...
                'Text Fontsize'};

            defAns = { ...
                {'+', 'o', '*', '.', 'x', 's', 'd', '^', 'v', '>', '<', 'p', 'h'}; ...
                O.markersize; ...
                {'-', '--', ':', '-.'}; ...
                O.linewidth; ...
                {'r', 'g', 'b', 'c', 'm', 'y', 'k', 'w', 'none'}; ...
                {'r', 'g', 'b', 'c', 'm', 'y', 'k', 'w', 'none'}; ...
                {'r', 'g', 'b', 'c', 'm', 'y', 'k', 'w', 'none'}; ...
                O.fontsize};

            fields = {'marker', 'markersize', 'linestyle', 'linewidth', ...
                      'color', 'textcolorfg', 'textcolorbg', 'fontsize'};

            % set default selections for dropdown fields
            for k = [1 3 5 6 7]
                idx2 = find(ismember(defAns{k}, O.(fields{k})) == 1);
                defAns{k}{end+1} = idx2;
            end
            dlgOptions.WindowHeight = 430;
            A = utils.dlgs.inputUniversalDlg(parentFigure, '', prompts, defAns, 'ROI Options', dlgOptions);
            if isempty(A); return; end

            for k = 1:numel(fields)
                obj.Options.(fields{k}) = A{k};
            end
        end

        function index = findIndexByLabel(obj, labelStr)
            % FINDINDEXBYLABEL - Find the index of a ROI whose *Data.label* matches the.
            %
            % Syntax:
            %   function index = findIndexByLabel(obj, labelStr)
            %
            % given string.  When *labelStr* is **'All',** returns the
            % indices of every ROI visible in the current orientation.
            %
            % Input Arguments:
            %   - **labelStr** — char/string — the label to search for.
            %     Use **'All'** to retrieve all ROIs for the current
            %     dataset orientation.
            %
            % Output Arguments:
            %   - **index** — numeric vector — index (or indices) of matching ROI(s)
            %     in the *obj.Data* array.  Empty if no match is found.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     index = obj.mibModel.I{obj.mibModel.id}.hROI.findIndexByLabel('ROI 1');% call from mibController; find the ROI labelled 'ROI 1'
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     indices = obj.mibModel.I{obj.mibModel.id}.hROI.findIndexByLabel('All');% call from mibController; get all ROI indices for the current orientation
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     index = findIndexByLabel(obj, 'MyROI');% call within the class
            %

            if strcmp(labelStr, 'All')
                orient = [];
                if ~isempty(obj.mibDataset)
                    orient = obj.mibDataset.orientation;
                end
                [~, index] = obj.getNumberOfROI(orient);
            else
                index = find(ismember([obj.Data.label], labelStr));
            end
        end

        function storeROI(obj, newData, index)
            % STOREROI - Add or insert ROI information into the *obj.Data* struct.
            %
            % Syntax:
            %   function storeROI(obj, newData, index)
            %
            % array.
            %
            % If *index* is less than or equal to the current number of
            % ROIs, the new entry is inserted at that position (existing
            % entries shift forward).  Otherwise the entry is appended.
            %
            % Input Arguments:
            %   - **newData** — struct — a single element whose fields match those
            %     of *obj.Data* (*.label,* *.type,* *.X,* *.Y,*
            %     *.orientation,* *.BoundingBox).*
            %   - **index** — *(optional)* numeric — position at which to store
            %     the ROI.  Default is ``obj.getNumberOfROI(0) + 1``
            %     (append).
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     newData.label = cellstr('1');
            %     newData.type  = cellstr('rectangle');
            %     newData.X = [10; 200];
            %     newData.Y = [20; 150];
            %     newData.orientation = 3;
            %     newData.BoundingBox.x = [10; 200];
            %     newData.BoundingBox.y = [20; 150];
            %     obj.mibModel.I{obj.mibModel.id}.hROI.storeROI(newData);% call from mibController; append a new rectangle ROI
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.storeROI(newData, 3);% call from mibController; insert a ROI at position 3
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     storeROI(obj, newData, 5);% call within the class; insert at position 5
            %

            if nargin < 3; index = obj.getNumberOfROI(0) + 1; end

            noROI = obj.getNumberOfROI(0);
            if index <= noROI
                obj.Data(index+1:numel(obj.Data)+1) = obj.Data(index:numel(obj.Data));
                obj.Data(index) = newData;
            else
                obj.Data(index) = newData;
            end
        end

        function removeROI(obj, index)
            % REMOVEROI - Remove one or more ROIs from the class.
            %
            % Syntax:
            %   function removeROI(obj, index)
            %
            % When *index* is 0, empty, or omitted all ROIs are removed
            % (equivalent to *clearData).*  When *index* equals the
            % total number of ROIs, *clearData* is also called to avoid
            % leaving an empty struct array.
            %
            % Input Arguments:
            %   - **index** — *(optional)* numeric — index of the ROI to remove.
            %     Use **0** or omit to remove all ROIs.
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.removeROI(3);% call from mibController; remove the 3rd ROI
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.removeROI(0);% call from mibController; remove all ROIs
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.removeROI();% call from mibController; remove all ROIs (same as 0)
            %
            %   **Example 4**
            %
            %   .. code-block:: matlab
            %
            %
            %     removeROI(obj, 5);% call within the class; remove 5th ROI
            %

            if nargin < 2; index = 0; end
            if isempty(index); index = 0; end

            if index == 0
                obj.clearData();
            else
                if numel(index) == obj.getNumberOfROI(0)
                    obj.clearData();
                else
                    obj.Data(index) = [];
                end
            end
        end

        function [number, indices] = getNumberOfROI(obj, orientation)
            % GETNUMBEROFROI - Get the number of stored ROIs and their indices, optionally.
            %
            % Syntax:
            %   function [number, indices] = getNumberOfROI(obj, orientation)
            %
            % filtered by orientation.
            %
            % Input Arguments:
            %   - **orientation** — *(optional)* numeric — filter ROIs by plane:
            %
            %     - **1** — 'zx' plane
            %     - **2** — 'zy' plane
            %     - **3** — 'yx' plane (default in MIB3)
            %     - **0** — return all ROIs regardless of orientation
            %
            %     When omitted or empty, uses ``obj.mibDataset.orientation``.
            %
            % Output Arguments:
            %   - **number** — numeric — count of ROIs matching the filter
            %   - **indices** — numeric vector — indices into *obj.Data* of the
            %     matching ROIs
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     [number, indices] = obj.mibModel.I{obj.mibModel.id}.hROI.getNumberOfROI();% call from mibController; get ROIs for the current orientation
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     [number, indices] = obj.mibModel.I{obj.mibModel.id}.hROI.getNumberOfROI(3);% call from mibController; get ROIs for the YX orientation
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     number = obj.mibModel.I{obj.mibModel.id}.hROI.getNumberOfROI(0);% call from mibController; get total count of all ROIs
            %
            %   **Example 4**
            %
            %   .. code-block:: matlab
            %
            %
            %     [n, idx] = getNumberOfROI(obj, 0);% call within the class; get all
            %

            if nargin < 2 || isempty(orientation)
                if ~isempty(obj.mibDataset)
                    orientation = obj.mibDataset.orientation;
                else
                    orientation = 0;
                end
            end

            indices = [];
            if orientation == 0
                if isempty(obj.Data(1).orientation)
                    number = 0;
                else
                    number = numel(obj.Data);
                    indices = 1:number;
                end
            else
                indices = find(ismember([obj.Data.orientation], orientation));
                number = numel(indices);
            end
        end

        function bb = getBoundingBox(obj, index)
            % GETBOUNDINGBOX - Return the combined bounding box for one or more ROIs.
            %
            % Syntax:
            %   function bb = getBoundingBox(obj, index)
            %
            % When *index* is 0 the bounding box is the union of all
            % ROIs visible in the current orientation.  A label string can
            % be passed instead of a numeric index.
            %
            % Input Arguments:
            %   - **index** — numeric or char/string — index of the ROI.
            %     Use **0** to get a combined bounding box for all visible
            %     ROIs.  A label string (e.g. *'ROI* 1') is also accepted.
            %
            % Output Arguments:
            %   - **bb** — numeric vector ``[xmin, xmax, ymin, ymax]``
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     bb = obj.mibModel.I{obj.mibModel.id}.hROI.getBoundingBox(1);% call from mibController; bounding box of ROI #1
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     bb = obj.mibModel.I{obj.mibModel.id}.hROI.getBoundingBox(0);% call from mibController; combined bounding box of all visible ROIs
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     bb = obj.mibModel.I{obj.mibModel.id}.hROI.getBoundingBox('MyROI');% call from mibController; bounding box by label
            %
            %   **Example 4**
            %
            %   .. code-block:: matlab
            %
            %
            %     bb = getBoundingBox(obj, 3);% call within the class
            %

            if ischar(index) || isstring(index)
                index = obj.findIndexByLabel(index);
            end

            if index == 0
                [~, indexList] = obj.getNumberOfROI();
            else
                indexList = index;
            end

            bbTemp = zeros(numel(indexList), 4);
            for i = 1:numel(indexList)
                bbTemp(i, 1) = obj.Data(indexList(i)).BoundingBox.x(1);
                bbTemp(i, 2) = obj.Data(indexList(i)).BoundingBox.x(2);
                bbTemp(i, 3) = obj.Data(indexList(i)).BoundingBox.y(1);
                bbTemp(i, 4) = obj.Data(indexList(i)).BoundingBox.y(2);
            end
            bb(1) = min(bbTemp(:,1));
            bb(2) = max(bbTemp(:,2));
            bb(3) = min(bbTemp(:,3));
            bb(4) = max(bbTemp(:,4));
        end

        function mask = returnMask(obj, index, Height, Width, orient, blockModeSwitch)
            % RETURNMASK - Generate a binary (uint8) mask image for the specified ROI(s).
            %
            % Syntax:
            %   function mask = returnMask(obj, index, Height, Width, orient, blockModeSwitch)
            %
            % For *'rectangle'* ROIs the mask is filled directly.  For
            % *'ellipse'* ROIs ``inpolygon`` is used.  For
            % *'polygon'* and *'freehand'* ROIs ``poly2mask``
            % is used.
            %
            % When *blockModeSwitch* is 1 the ROI coordinates are shifted
            % by the current axes limits so that the mask aligns with the
            % visible viewport.
            %
            % Input Arguments:
            %   - **index** — numeric or char/string — ROI index.
            %     Use **0** to combine masks of all ROIs visible in the
            %     current orientation.  A label string is also accepted.
            %   - **Height** — *(optional)* numeric — height of the output mask.
            %     Default: image height from ``obj.mibDataset``.
            %   - **Width** — *(optional)* numeric — width of the output mask.
            %     Default: image width from ``obj.mibDataset``.
            %   - **orient** — *(optional)* numeric — orientation filter
            %     (1/2/3).  Default: ``obj.mibDataset.orientation``.
            %   - **blockModeSwitch** — *(optional)* numeric — override the
            %     block-mode flag (0 or 1).  Default: value from
            %     ``obj.mibDataset.blockModeSwitch``.
            %
            % Output Arguments:
            %   - **mask** — uint8 matrix ``[Height x Width]`` — binary
            %     mask where 1 indicates pixels inside the ROI.
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     mask = obj.mibModel.I{obj.mibModel.id}.hROI.returnMask(1);% call from mibController; get mask for ROI #1
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     mask = obj.mibModel.I{obj.mibModel.id}.hROI.returnMask(0);% call from mibController; combined mask of all visible ROIs
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     mask = obj.mibModel.I{obj.mibModel.id}.hROI.returnMask('MyROI');% call from mibController; mask by label
            %
            %   **Example 4**
            %
            %   .. code-block:: matlab
            %
            %
            %     mask = obj.mibModel.I{obj.mibModel.id}.hROI.returnMask(0, 512, 512, 3, 0);% call from mibController; explicit height, width, orient, block mode
            %
            %   **Example 5**
            %
            %   .. code-block:: matlab
            %
            %
            %     mask = returnMask(obj, 2);% call within the class
            %

            ds = obj.mibDataset;

            if nargin < 6
                if ~isempty(ds); blockModeSwitch = ds.blockModeSwitch;
                else;            blockModeSwitch = 0;
                end
            end
            if nargin < 5 || isnan(orient)
                if ~isempty(ds); orient = ds.orientation;
                else;            orient = 3;
                end
            end
            if nargin < 3 || isnan(Height)
                if ~isempty(ds)
                    [Height, Width, ~, ~] = ds.image.getDatasetDimensions(orient);
                else
                    Height = 512; Width = 512;
                end
            end

            mask = zeros(Height, Width, 'uint8');

            if ischar(index) || isstring(index)
                index = obj.findIndexByLabel(index);
            end

            if index == 0
                [~, indexList] = obj.getNumberOfROI(orient);
            else
                indexList = index;
            end

            % shift coordinates when block mode is enabled
            shiftX = 0;
            shiftY = 0;
            if blockModeSwitch == 1 && ~isempty(ds)
                shiftX = max([0 floor(ds.axesX(1))]);
                shiftY = max([0 floor(ds.axesY(1))]);
            end

            for i = indexList
                if obj.Data(i).orientation == orient
                    X = obj.Data(i).X - shiftX;
                    Y = obj.Data(i).Y - shiftY;
                    roiType = obj.Data(i).type;
                    if iscell(roiType); roiType = roiType{1}; end

                    switch roiType
                        case {'imrect', 'rectangle'}
                            y1 = max([1 min(Y)]);
                            y2 = min([Height max(Y)]);
                            x1 = max([1 min(X)]);
                            x2 = min([Width max(X)]);
                            mask(round(y1):round(y2), round(x1):round(x2)) = 1;

                        case {'imellipse', 'ellipse'}
                            [xGrid, yGrid] = meshgrid(1:Width, 1:Height);
                            incircle = inpolygon(xGrid, yGrid, X, Y);
                            mask(incircle) = 1;

                        case {'impoly', 'polygon', 'imfreehand', 'freehand'}
                            if numel(X) >= 3
                                mask = mask | uint8(poly2mask(double(X), double(Y), Height, Width));
                            end
                    end
                end
            end
        end

        function resample(obj, resampledRatio)
            % RESAMPLE - Recalculate ROI positions after the image has been resampled.
            %
            % Syntax:
            %   function resample(obj, resampledRatio)
            %
            % Each ROI's X, Y coordinates and BoundingBox are scaled by the
            % appropriate ratio depending on the ROI's orientation.
            % Supports both MIB2 orientation values (4 = yx) and MIB3
            % values (3 = yx).
            %
            % Input Arguments:
            %   - **resampledRatio** — numeric vector ``[ratioW, ratioH, ratioZ]``
            %     — ratio of new/old dimensions after resampling.
            %     For example ``[0.5, 0.5, 1]`` bins XY by 2.
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     resampledRatio = [0.5, 0.5, 1];% bin XY dimensions by 2
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.resample(resampledRatio);% call from mibController; resample all ROIs
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.resample([2, 2, 2]);% call from mibController; double all dimensions
            %
            %   **Example 4**
            %
            %   .. code-block:: matlab
            %
            %
            %     resample(obj, [1, 1, 0.5]);% call within the class; bin Z by 2
            %

            for i = 1:numel(obj.Data)
                orient = obj.Data(i).orientation;
                if isempty(orient); continue; end

                switch orient
                    case {4, 3}  % yx (MIB2: 4, MIB3: 3)
                        obj.Data(i).X = obj.Data(i).X * resampledRatio(1);
                        obj.Data(i).Y = obj.Data(i).Y * resampledRatio(2);
                        obj.Data(i).BoundingBox.x(1) = floor(obj.Data(i).BoundingBox.x(1) * resampledRatio(1));
                        obj.Data(i).BoundingBox.x(2) = ceil(obj.Data(i).BoundingBox.x(2) * resampledRatio(1));
                        obj.Data(i).BoundingBox.y(1) = floor(obj.Data(i).BoundingBox.y(1) * resampledRatio(2));
                        obj.Data(i).BoundingBox.y(2) = ceil(obj.Data(i).BoundingBox.y(2) * resampledRatio(2));
                    case 1  % zx
                        obj.Data(i).X = obj.Data(i).X * resampledRatio(3);
                        obj.Data(i).Y = obj.Data(i).Y * resampledRatio(1);
                        obj.Data(i).BoundingBox.x(1) = floor(obj.Data(i).BoundingBox.x(1) * resampledRatio(3));
                        obj.Data(i).BoundingBox.x(2) = ceil(obj.Data(i).BoundingBox.x(2) * resampledRatio(3));
                        obj.Data(i).BoundingBox.y(1) = floor(obj.Data(i).BoundingBox.y(1) * resampledRatio(1));
                        obj.Data(i).BoundingBox.y(2) = ceil(obj.Data(i).BoundingBox.y(2) * resampledRatio(1));
                    case 2  % zy
                        obj.Data(i).X = obj.Data(i).X * resampledRatio(3);
                        obj.Data(i).Y = obj.Data(i).Y * resampledRatio(2);
                        obj.Data(i).BoundingBox.x(1) = floor(obj.Data(i).BoundingBox.x(1) * resampledRatio(3));
                        obj.Data(i).BoundingBox.x(2) = ceil(obj.Data(i).BoundingBox.x(2) * resampledRatio(3));
                        obj.Data(i).BoundingBox.y(1) = floor(obj.Data(i).BoundingBox.y(1) * resampledRatio(2));
                        obj.Data(i).BoundingBox.y(2) = ceil(obj.Data(i).BoundingBox.y(2) * resampledRatio(2));
                end
            end
        end

        function crop(obj, cropF)
            % CROP - Recalculate ROI positions after the image has been cropped.
            %
            % Syntax:
            %   function crop(obj, cropF)
            %
            % Each ROI's X, Y coordinates and BoundingBox are shifted by
            % the crop origin, depending on the ROI's orientation.
            % Supports both MIB2 (4 = yx) and MIB3 (3 = yx) orientation
            % values.
            %
            % Input Arguments:
            %   - **cropF** — numeric vector ``[x1, y1, dx, dy, z1, dz]``
            %     — crop parameters in pixels.
            %   - *x1* — starting X coordinate
            %   - *y1* — starting Y coordinate
            %   - *dx* — width of the crop region
            %   - *dy* — height of the crop region
            %   - *z1* — starting Z slice
            %   - *dz* — number of Z slices
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1**
            %
            %   .. code-block:: matlab
            %
            %
            %     cropF = [100, 50, 200, 200, 1, 10];% crop starting at (100,50) with size 200x200, slices 1-10
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.crop(cropF);% call from mibController; adjust ROI positions after crop
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     crop(obj, [1, 1, 512, 512, 5, 20]);% call within the class
            %

            for i = 1:numel(obj.Data)
                orient = obj.Data(i).orientation;
                if isempty(orient); continue; end

                switch orient
                    case {4, 3}  % yx
                        obj.Data(i).X = obj.Data(i).X - cropF(1) + 1;
                        obj.Data(i).Y = obj.Data(i).Y - cropF(2) + 1;
                        obj.Data(i).BoundingBox.x = obj.Data(i).BoundingBox.x - cropF(1) + 1;
                        obj.Data(i).BoundingBox.y = obj.Data(i).BoundingBox.y - cropF(2) + 1;
                    case 1  % zx
                        obj.Data(i).X = obj.Data(i).X - cropF(5) + 1;
                        obj.Data(i).Y = obj.Data(i).Y - cropF(1) + 1;
                        obj.Data(i).BoundingBox.x = obj.Data(i).BoundingBox.x - cropF(5) + 1;
                        obj.Data(i).BoundingBox.y = obj.Data(i).BoundingBox.y - cropF(1) + 1;
                    case 2  % zy
                        obj.Data(i).X = obj.Data(i).X - cropF(5) + 1;
                        obj.Data(i).Y = obj.Data(i).Y - cropF(2) + 1;
                        obj.Data(i).BoundingBox.x = obj.Data(i).BoundingBox.x - cropF(5) + 1;
                        obj.Data(i).BoundingBox.y = obj.Data(i).BoundingBox.y - cropF(2) + 1;
                end
            end
        end

        function addROIsToPlot(obj, axesHandle, ~, orientation, convertFcn, selectedROI, showLabel)
            % ADDROISTOPLOT - Plot stored ROIs as line/marker overlays on the given axes.
            %
            % Syntax:
            %   function addROIsToPlot(obj, axesHandle, ~, orientation, convertFcn, selectedROI, showLabel)
            %
            % This method replaces the MIB2 version that required a
            % *mibController* handle.  Instead it receives the axes
            % handle and a coordinate-conversion function handle directly,
            % keeping the class independent of any controller.
            %
            % The conversion function *convertFcn* must accept two
            % numeric vectors (X, Y) in data coordinates and return the
            % corresponding axes (screen) coordinates:
            % ``[Xaxes, Yaxes] = convertFcn(Xdata, Ydata);``
            %
            % Input Arguments:
            %   - **axesHandle** — handle to the target *matlab.ui.control.UIAxes*
            %     or *matlab.graphics.axis.Axes* where ROIs will be drawn.
            %   - **mode** — char — rendering mode, either **'shown'** (default view)
            %     or **'full'** (used during panning).
            %   - **orientation** — numeric — current dataset orientation
            %     (3 = yx, 1 = zx, 2 = zy).  Only ROIs matching this
            %     orientation are plotted.
            %   - **convertFcn** — function_handle — ``@(X,Y) ...``
            %     that converts data coordinates to axes coordinates.
            %     Typically ``@(x,y) obj.mibModel.convertDataToMouseCoordinates(x, y, mode)``.
            %   - **selectedROI** — *(optional)* numeric — controls which ROIs are drawn:
            %
            %     - **0** — draw all ROIs matching the current orientation (default).
            %     - **>0** — draw only the ROI at that index in *obj.Data.*
            %   - **showLabel** — *(optional)* logical — whether to display ROI
            %     labels as text annotations next to each shape.
            %     Default = *false.*
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1** — Full example from controllers.MibController.showImage
            %
            %   .. code-block:: matlab
            %
            %
            %     % Full example from controllers.MibController.showImage:
            %     ds = obj.mibModel.I{datasetId};
            %     ax = obj.cImageDoc{selectedSet}.handles.imViewAxes;
            %     convertFcn = @(x,y) obj.mibModel.convertDataToMouseCoordinates(x, y, 'shown');
            %     ds.hROI.addROIsToPlot(ax, 'shown', ds.orientation, convertFcn, 0, true);
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.addROIsToPlot(ax, 'shown', 3, @(x,y) deal(x,y), 0, false);% plot all ROIs with identity conversion
            %
            %   **Example 3**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.addROIsToPlot(ax, 'shown', 3, convertFcn, 2, true);% plot only ROI #2
            %
            %   **Example 4**
            %
            %   .. code-block:: matlab
            %
            %
            %     obj.mibModel.I{obj.mibModel.id}.hROI.addROIsToPlot(ax, 'full', ds.orientation, convertFcn);% plot all, no labels
            %

            if nargin < 7; showLabel = false; end
            if nargin < 6; selectedROI = 0; end

            if isempty(find([obj.Data.orientation]' == orientation, 1))
                return;
            end

            O = obj.Options;
            marker    = O.marker;
            markersize = str2double(O.markersize);
            if isscalar(O.color) || strcmpi(O.color, 'none')
                color = O.color;
            else
                color = str2num(O.color); %#ok<ST2NM>
            end
            linestyle = O.linestyle;
            linewidth = str2double(O.linewidth);
            if isscalar(O.textcolorfg) || strcmpi(O.textcolorfg, 'none')
                textcolorfg = O.textcolorfg;
            else
                textcolorfg = str2num(O.textcolorfg); %#ok<ST2NM>
            end
            if isscalar(O.textcolorbg) || strcmpi(O.textcolorbg, 'none')
                textcolorbg = O.textcolorbg;
            else
                textcolorbg = str2num(O.textcolorbg); %#ok<ST2NM>
            end
            fontsize = str2double(O.fontsize);

            % Pre-compute effective style respecting show flags
            effectiveMarker    = marker;
            effectiveLineStyle = linestyle;
            if O.showMarkers == 0; effectiveMarker    = 'none'; end
            if O.showLines   == 0; effectiveLineStyle = 'none'; end

            axesHandle.NextPlot = 'add';
            indices = find([obj.Data.orientation]' == orientation);

            % when selectedROI > 0 restrict to that single ROI index
            if selectedROI > 0
                indices = indices(indices == selectedROI);
            end

            for i = 1:numel(indices)
                labelVal = obj.Data(indices(i)).label;
                if iscell(labelVal); labelVal = labelVal{1}; end

                X = obj.Data(indices(i)).X;
                Y = obj.Data(indices(i)).Y;

                % convert to axes coordinates
                [X, Y] = convertFcn(X, Y);

                roiType = obj.Data(indices(i)).type;
                if iscell(roiType); roiType = roiType{1}; end

                switch roiType
                    case {'imrect', 'rectangle'}
                        splX = sort(X);  splX(1) = splX(1) - 1;
                        splY = sort(Y);  splY(1) = splY(1) - 1;
                        spl_x = [splX(1) splX(2) splX(2) splX(1) splX(1)];
                        spl_y = [splY(1) splY(1) splY(2) splY(2) splY(1)];
                        h = plot(axesHandle, spl_x, spl_y, ...
                            'Color', color, 'LineStyle', effectiveLineStyle, 'LineWidth', linewidth, ...
                            'Marker', effectiveMarker, 'MarkerSize', markersize, 'MarkerEdgeColor', color, ...
                            'Tag', 'roi');
                        if showLabel
                            ht = text(spl_x(3), spl_y(3), ['   ' labelVal], 'Parent', axesHandle, ...
                                'Color', textcolorfg, 'BackgroundColor', textcolorbg, ...
                                'FontSize', fontsize, 'Tag', 'roi');
                        end

                    case {'impoly', 'polygon', 'imfreehand', 'freehand'}
                        spl_x = [X(:); X(1)];
                        spl_y = [Y(:); Y(1)];
                        h = plot(axesHandle, spl_x, spl_y, ...
                            'Color', color, 'LineStyle', effectiveLineStyle, 'LineWidth', linewidth, ...
                            'Marker', effectiveMarker, 'MarkerSize', markersize, 'MarkerEdgeColor', color, ...
                            'Tag', 'roi');
                        if showLabel
                            ht = text(spl_x(end), spl_y(end), ['  ' labelVal], 'Parent', axesHandle, ...
                                'Color', textcolorfg, 'BackgroundColor', textcolorbg, ...
                                'FontSize', fontsize, 'Tag', 'roi');
                        end

                    case {'imellipse', 'ellipse'}
                        h = plot(axesHandle, X, Y, ...
                            'Color', color, 'LineStyle', effectiveLineStyle, 'LineWidth', linewidth, ...
                            'Tag', 'roi');
                        if showLabel
                            ht = text(X(1), Y(1), ['  ' labelVal], 'Parent', axesHandle, ...
                                'Color', textcolorfg, 'BackgroundColor', textcolorbg, ...
                                'FontSize', fontsize, 'Tag', 'roi');
                        end
                end
            end
            axesHandle.NextPlot = 'replace';
        end

        function convertLegacyTypes(obj)
            % CONVERTLEGACYTYPES - Convert MIB2 ROI type-name strings to MIB3 equivalents.
            %
            % Syntax:
            %   function convertLegacyTypes(obj)
            %
            % Iterates through *obj.Data* and replaces any legacy type
            % names (*'imrect',* *'imellipse',* *'impoly',*
            % *'imfreehand')* with their MIB3 equivalents
            % (*'rectangle',* *'ellipse',* *'polygon',*
            % *'freehand')* using the *LegacyTypeMap* dictionary.
            %
            % This method should be called after loading a *.roi* file
            % that was saved by MIB2.
            %
            % Input Arguments:
            %
            % Output Arguments:
            %
            % Usage:
            %   **Example 1** — typical usage after loading an old .roi file
            %
            %   .. code-block:: matlab
            %
            %
            %     % typical usage after loading an old .roi file:
            %     res = load(fullfile(path, filename), '-mat');
            %     obj.mibModel.I{obj.mibModel.id}.hROI.Data = res.Data;
            %     obj.mibModel.I{obj.mibModel.id}.hROI.convertLegacyTypes();% convert old type names
            %
            %   **Example 2**
            %
            %   .. code-block:: matlab
            %
            %
            %     convertLegacyTypes(obj);% call within the class
            %

            if isempty(obj.Data) || isempty(obj.Data(1).type)
                return;
            end
            for i = 1:numel(obj.Data)
                t = obj.Data(i).type;
                if iscell(t); t = t{1}; end
                if isKey(obj.LegacyTypeMap, t)
                    obj.Data(i).type = cellstr(obj.LegacyTypeMap(t));
                end
            end
        end

    end
end
