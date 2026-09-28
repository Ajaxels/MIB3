classdef StitchingInspector < handle
    % STITCHINGINSPECTOR - Seam inspector: manual QC + fixing of a stitch.
    %
    % Reviews the measured tile-pair seams worst-first and lets the user
    % confirm, exclude, or (Phase C) fix them; fixes re-steer the global solve
    % through high-weight user edges. Launched from the Stitching tool
    % (``inspectSeamsBtn``) with the parent ``controllers.Stitching`` handle -
    % the parent's ``layout``/``edges``/``positions``/``tforms`` are the single
    % source of truth and are mutated in place. Design + phasing:
    % ``development/stitching/plan_inspector.md``.
    %
    % Seams are ranked by ``utils.stitch.scoreSeams`` (pixel NCC at the SOLVED
    % positions - catches confidently-wrong measurements that solver residuals
    % miss on chain graphs), pruned edges first.

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (StitchingInspectorGUI)
        listener
        % cell array of listener handles
        stitching
        % handle to the parent controllers.Stitching (source of truth for
        % layout / edges / positions / tforms / BatchOpt)
        ranking
        % worst-first edge review order (indices into stitching.edges)
        currentEdgeIdx
        % index (into stitching.edges) of the seam shown in the pair view
        readerFcn
        % shared LRU tile reader (utils.stitch.makeTileReader); built once by
        % obj.tileReader(), never directly - see there
        readerCachedFcn
        % companion predicate of readerFcn: is that tile resident? Used to put a
        % progress dialog around the reads that will actually stall on disk
        tileOrderMenu
        % uicontextmenu of the pair view (tile order) - created in addCallbacks,
        % set as the ContextMenu of pairAxes and of every pair image, and refilled
        % by fillTileOrderMenu each time it opens
        rightDragMoved = false
        % true once the current right-button press has moved >= 3 screen px, i.e.
        % turned into a pan (pairViewButtonDown); fillTileOrderMenu then leaves the
        % menu empty so a pan does not end with a menu popping up
        readerCorrectionStamp
        % what the correction readerFcn was built with looked like - method and,
        % for 'Re-exposure damage', the positions its footprints were placed at;
        % tileReader rebuilds the reader when the live correction no longer matches
        pairImageHandles
        % [2x1] image handles on pairAxes for the flicker overlay ([] otherwise)
        flickerState
        % which flicker image is visible (1 = tile i, 2 = tile j)
        autoBackup
        % cell (per edge) with the original automatic edge before the first
        % user fix - Z / undoFixBtn restores it (in-memory only, not persisted)
        pairStrip
        % struct with the current pair view geometry (.bboxA = tile-i strip
        % [rowStart rowEnd; colStart colEnd], .deltaYX) - maps clicks on the
        % strip back to tile-i pixels; [] when no overlap is rendered
        twoClick
        % two-click landmark match state: .active, .stage (1|2), .scale,
        % .leftWidth, .gap, .clickA ([x y] in tile-i full-res pixels)
        shiftDown
        % true while Shift is held over the inspector - the pair-view cursor
        % becomes the correlation ROI box and a click runs click-to-correlate
        roiBoxHandle
        % line handle of the hover ROI box on pairAxes ([] until first shown)
        pairZoom
        % wheel-zoom state of the pair view: struct .edgeIdx (the seam it
        % belongs to), .xLim, .yLim - re-applied across re-renders of the
        % same seam so nudges/drags keep the zoom; [] = fit to view.
        % Selecting ANOTHER seam keeps the magnification and re-centres it on
        % that pair's overlap (renderPairView/carriedZoomOnNewSeam), rewriting
        % .edgeIdx - only fitView_Callback (F) and a fix-mode switch clear it
        tileThumbs
        % cell (per tile) of low-res greyscale thumbnails for the mini-map
        % fused preview, jointly normalised to [0 1]; built lazily once by
        % ensureTileThumbs ({} until then, {} forever if tiles are too big)
        thumbScale
        % full-res pixels per thumbnail pixel (NaN until thumbs are built)
        viewSlice
        % browsed z-slices of the pair view: struct .edgeIdx, .sliceA
        % (tile-i slice), .sliceB (tile-j slice), .depthA, .depthB (stack
        % depths) and .boundaryTile - [] in Fix XY (sliceA/sliceB are the
        % dz-aligned pair of the seam's tiles), or the tile index in Fix Z,
        % where the view is the mosaic Z BOUNDARY: that ONE tile at slices
        % z-1 (sliceA, cyan) vs z (sliceB, magenta). Browsing is VIEW ONLY.
        % [] = defaults (central slice)
    end

    properties (Dependent)
        resolvePending
        % true when a user fix was applied WITHOUT the global re-solve
        % (auto-re-solve off / deferred), so the positions no longer follow from
        % the edges. An ALIAS of controllers.Stitching.resolvePending, which is
        % where the flag actually lives: the debt belongs to the mosaic, not to
        % this window, and while it was stored here closing the inspector took
        % the pending re-solve with it - the chip stopped warning and Stitch
        % fused the stale placement. Kept as a property so the inspector's own
        % code (and its tests) read and write it unchanged
    end

    events
        CloseEvent
        % fired when the window is closed
        SeamsUpdated
        % fired after a re-solve / edge edit so the parent Stitching refreshes
    end

    methods

        % ---------------------------------------------------------------
        function obj = StitchingInspector(mibModel, stitchController, options)
            % STITCHINGINSPECTOR - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = controllers.StitchingInspector(mibModel, stitchController)
            %      obj = controllers.StitchingInspector(mibModel, stitchController, struct('createView', false))
            %
            % Input Arguments:
            %   - **mibModel** - handle to MibModel
            %   - **stitchController** - handle to the launching
            %     ``controllers.Stitching``; must hold a measured ``edges`` set
            %     and solved ``positions``
            %   - **options** *(optional)* - [struct] with field ``createView``
            %     [logical]: ``false`` builds the inspector WITHOUT its window -
            %     the seams are scored and ranked and every review/fix method
            %     works, but nothing is rendered. Used by the unit tests; every
            %     widget access in this class is guarded by
            %     :meth:`hasWidget`, so the review logic is the same code the
            %     GUI drives. Default ``true``
            %

            obj.mibModel  = mibModel;
            obj.stitching = stitchController;
            obj.ranking = [];
            obj.currentEdgeIdx = [];
            obj.readerFcn = [];
            obj.readerCachedFcn = [];
            obj.pairImageHandles = [];
            obj.flickerState = 1;
            obj.autoBackup = {};
            obj.pairStrip = [];
            obj.twoClick = struct('active', false);
            obj.shiftDown = false;
            obj.roiBoxHandle = [];
            obj.pairZoom = [];
            obj.tileThumbs = {};
            obj.thumbScale = NaN;
            obj.viewSlice = [];

            createView = true;
            if nargin > 2 && isstruct(options) && isfield(options, 'createView')
                createView = logical(options.createView);
            end

            if isempty(obj.stitching.edges) || isempty(obj.stitching.positions)
                message = 'Measure overlaps and Optimize positions first - the inspector reviews seams at the SOLVED placement.';
                if createView
                    utils.dlgs.showErrorDialog(obj.stitching.guiFigure(), message, 'Seam inspector');
                    notify(obj, 'CloseEvent');
                    return;
                end
                error('StitchingInspector:noSeams', '%s', message);
            end

            if ~createView
                % Headless: no widgets, but the same review state a freshly
                % opened window would show (scored, ranked, worst seam current).
                obj.view = [];
                obj.scoreAndRank();
                obj.updateWidgets();
                initialRanking = obj.visibleRanking();
                if ~isempty(initialRanking)
                    obj.selectSeam(initialRanking(1));
                end
                return;
            end

            % ---- GUI
            obj.view = core.ChildView(obj, 'views.StitchingInspectorGUI');
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.closeButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, stitchController.view.gui, 'right');

            obj.addCallbacks();
            % Before the first ranking: the restored Fix mode decides which
            % seams the table lists and therefore where the review starts.
            obj.restoreSessionSettings();
            obj.scoreAndRank();
            obj.updateWidgets();
            initialRanking = obj.visibleRanking();
            if ~isempty(initialRanking)
                obj.selectSeam(initialRanking(1));
            end
            % A restored Fix Z goes through the dropdown's own handler, which
            % knows where the boundary view can start (a single-layer Z-stack has
            % no cross-layer seam to list).
            if strcmp(obj.fixMode(), 'z') && obj.hasWidget('fixModeDropdown')
                obj.view.handles.fixModeDropdown.ValueChangedFcn([], []);
            end

            obj.view.gui.Visible = 'on';
        end

        % ---------------------------------------------------------------
        function storeSessionSettings(obj)
            % STORESESSIONSETTINGS - Remember the dialog's settings for its next opening.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.storeSessionSettings()
            %
            % Written by :meth:`closeWindow` into
            % ``mibModel.sessionSettings.stitchingInspector`` and read back by
            % :meth:`restoreSessionSettings`, like the Stitching dialog's own
            % ``sessionSettings.stitching``. On close rather than per change:
            % sessionSettings lives in RAM, so an earlier write survives nothing
            % this one does not. Covers overlay mode, fix mode, ROI size, search
            % radius and auto re-solve; the seam, zoom and slice are properties of
            % the mosaic being reviewed, not settings, and are not carried over.
            %
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            widgetFields = inspectorSessionFields();
            stored = struct();
            for fieldIdx = 1:size(widgetFields, 1)
                widgetName = widgetFields{fieldIdx, 2};
                if obj.hasWidget(widgetName)
                    stored.(widgetFields{fieldIdx, 1}) = obj.view.handles.(widgetName).Value;
                end
            end
            obj.mibModel.sessionSettings.stitchingInspector = stored;
        end

        % ---------------------------------------------------------------
        function restoreSessionSettings(obj)
            % RESTORESESSIONSETTINGS - Reopen the dialog on the settings it was closed with.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.restoreSessionSettings()
            %
            % Reads ``mibModel.sessionSettings.stitchingInspector`` (see
            % :meth:`storeSessionSettings`). Nothing stored - the first opening
            % of the session - leaves the mlapp / addCallbacks defaults, so the
            % overlay starts on ``Falsecolor (cyan/magenta)``. Each value is
            % applied only if the widget would accept it (a dropdown item that
            % exists, a spinner value inside its limits), so a setting from an
            % older build cannot break the window. **Fix Z is restored only when
            % some tile has Z slices**: on a 2D mosaic that mode cannot engage,
            % and restoring it would open the window on the "Fix Z needs Z
            % slices" dialog.
            %
            if isempty(obj.view) || ~isstruct(obj.mibModel.sessionSettings) || ...
                    ~isfield(obj.mibModel.sessionSettings, 'stitchingInspector')
                return;
            end
            stored = obj.mibModel.sessionSettings.stitchingInspector;
            if ~isstruct(stored); return; end
            layout = obj.stitching.layout;
            tileSizes = reshape([layout.tileSize], 4, []).';
            hasDepth = any(tileSizes(:, 3) > 1);

            widgetFields = inspectorSessionFields();
            for fieldIdx = 1:size(widgetFields, 1)
                fieldName = widgetFields{fieldIdx, 1};
                widgetName = widgetFields{fieldIdx, 2};
                if ~isfield(stored, fieldName) || ~obj.hasWidget(widgetName); continue; end
                widget = obj.view.handles.(widgetName);
                value = stored.(fieldName);
                if isprop(widget, 'Items')
                    if ~ischar(value) || ~ismember(value, widget.Items); continue; end
                    if strcmp(widgetName, 'fixModeDropdown') && ~hasDepth && ...
                            ~strcmp(value, widget.Items{1})
                        continue;   % Fix Z on a 2D mosaic
                    end
                elseif isprop(widget, 'Limits')
                    if ~isnumeric(value) || ~isscalar(value) || ...
                            value < widget.Limits(1) || value > widget.Limits(2)
                        continue;
                    end
                elseif ~islogical(value) && ~isnumeric(value)
                    continue;
                end
                widget.Value = value;
            end
        end

        % ---------------------------------------------------------------
        function tf = get.resolvePending(obj)
            tf = false;
            if ~isempty(obj.stitching) && isvalid(obj.stitching)
                tf = obj.stitching.resolvePending;
            end
        end

        function set.resolvePending(obj, tf)
            if ~isempty(obj.stitching) && isvalid(obj.stitching)
                obj.stitching.resolvePending = logical(tf);
            end
        end

        % ---------------------------------------------------------------
        function readerFcn = tileReader(obj)
            % TILEREADER - The inspector's one shared LRU tile reader.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      readerFcn = obj.tileReader()
            %
            % Every place that reads pixels goes through this - the pair view,
            % the mini-map thumbnails, the seam scoring, the click-to-correlate
            % fixes - so they share ONE cache. Built lazily on first use and kept
            % for the session; ``obj.readerCachedFcn`` comes with it.
            %
            % **It carries the intensity correction.** The inspector used to
            % build its reader with ``makeTileReader(layout)`` in four separate
            % places, none of them passing one, so with a correction selected the
            % inspector reviewed - and scored - different pixels from the ones
            % the mosaic is measured and fused on. That is exactly the split
            % ``utils.stitch.makeTileReader`` exists to prevent.
            %
            % **It is rebuilt when that correction changes.** Every other method
            % is fixed for the session, but ``'Re-exposure damage'`` is placed at
            % the solved positions, so a re-solve moves it. A reader kept from
            % before would review the mosaic with the damage patches where the
            % tiles used to be. The rebuild drops the tile cache, so with that
            % method the first read after a re-solve decodes from disk again.
            %
            % Output Arguments:
            %   - **readerFcn** - [function_handle] see :func:`utils.stitch.makeTileReader`
            %
            correction = obj.stitching.ensureIntensityCorrection();
            correctionStamp = {[], []};
            if isstruct(correction)
                correctionStamp{1} = correction.method;
                if isfield(correction, 'damage') && isstruct(correction.damage)
                    correctionStamp{2} = correction.damage.positions;
                end
            end
            if isempty(obj.readerFcn) || ~isequal(correctionStamp, obj.readerCorrectionStamp)
                [obj.readerFcn, obj.readerCachedFcn] = utils.stitch.makeTileReader( ...
                    obj.stitching.layout, struct('correction', correction));
                obj.readerCorrectionStamp = correctionStamp;
            end
            readerFcn = obj.readerFcn;
        end

        % ---------------------------------------------------------------
        function stack = currentTileStack(obj)
            % CURRENTTILESTACK - The Overwrite drawing order in force, bottom first.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      stack = obj.currentTileStack()
            %
            % The user's explicit order (``stitching.tileStack``) if one was set
            % here, otherwise the default :func:`utils.stitch.tileDrawOrder`
            % derives - the SAME function the fusers use, so the tile the pair
            % view colours as "on top" is the one Stitch keeps.
            %
            % Output Arguments:
            %   - **stack** - [1 x N double] tile indices, bottom first
            %
            stack = utils.stitch.tileDrawOrder(numel(obj.stitching.layout), ...
                obj.stitching.ensureIntensityCorrection(), obj.stitching.tileStack);
        end

        % ---------------------------------------------------------------
        function tf = tilesAreResident(obj, tileIndices)
            % TILESARERESIDENT - Would reading these tiles return immediately?
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      tf = obj.tilesAreResident([edge.i, edge.j])
            %
            % False (the pessimistic answer) whenever the reader has not been
            % built yet or offers no cache predicate, so a caller that gates a
            % progress dialog on this errs towards showing one.
            %
            tf = false;
            if isempty(obj.readerCachedFcn); return; end
            tf = all(arrayfun(@(idx) obj.readerCachedFcn(idx), tileIndices));
        end

        % ---------------------------------------------------------------
        function tf = hasWidget(obj, widgetName)
            % HASWIDGET - Is this widget available to write to?
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      tf = obj.hasWidget('seamTable')
            %
            % False both when the mlapp does not (yet) carry the widget - most
            % of the inspector's UI is optional, see ``mlapp_widgets.md`` - and
            % when the controller runs without a view at all (headless
            % construction). Every widget access in this class goes through it,
            % so the review logic runs identically in both cases.
            %
            % Input Arguments:
            %   - **widgetName** - [char] handle name in ``obj.view.handles``
            %
            tf = ~isempty(obj.view) && isfield(obj.view.handles, widgetName);
        end

        % ---------------------------------------------------------------
        function [xLim, yLim] = pairAxesFillLimits(obj, xLim, yLim)
            % PAIRAXESFILLLIMITS - Widen a data window to the pair axes' shape.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [xLim, yLim] = obj.pairAxesFillLimits()
            %      [xLim, yLim] = obj.pairAxesFillLimits(xLim, yLim)
            %
            % ``axis image`` gives tight limits at 1:1 pixels, so a tall pair
            % (two tiles stacked vertically) drew as a narrow column with the
            % rest of the reserved grid cell empty - and zooming in only made
            % the column taller. This grows the SHORTER side of the requested
            % window until its aspect matches the axes rectangle on screen, so
            % the composite fills the whole cell; the extra span is context
            % around the tiles, never a distortion (the data aspect stays 1:1)
            % and never a crop (the window only ever grows).
            %
            % ``InnerPosition`` is the region available for the plot box - it
            % excludes the title but is NOT shrunk by the letterbox the aspect
            % constraint applies, so reading it here is not circular.
            %
            % The window is not re-fitted when the user resizes the inspector:
            % the next render, wheel zoom or ``F`` picks the new shape up.
            %
            % Input Arguments:
            %   - **xLim**, **yLim** - [1x2] window to widen; omitted = the
            %     axes' current limits
            %
            % Return Values:
            %   - **xLim**, **yLim** - [1x2] widened window; the caller writes
            %     it to the axes
            %
            if ~obj.hasWidget('pairAxes')
                if nargin < 3; xLim = []; yLim = []; end
                return;
            end
            pairAxes = obj.view.handles.pairAxes;
            if nargin < 3
                xLim = pairAxes.XLim;
                yLim = pairAxes.YLim;
            end
            box = pairAxes.InnerPosition;
            if numel(box) < 4 || box(3) <= 0 || box(4) <= 0; return; end
            xRange = diff(xLim);
            yRange = diff(yLim);
            if xRange <= 0 || yRange <= 0; return; end

            boxAspect = box(3) / box(4);
            if xRange / yRange < boxAspect
                xLim = mean(xLim) + [-0.5, 0.5] * yRange * boxAspect;
            else
                yLim = mean(yLim) + [-0.5, 0.5] * xRange / boxAspect;
            end
        end

        % ---------------------------------------------------------------
        function figureHandle = progressParent(obj)
            % PROGRESSPARENT - Figure to anchor a progress dialog to.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      figureHandle = obj.progressParent()
            %
            % The inspector window once it is VISIBLE (``uiprogressdlg``
            % refuses an invisible figure, which the window still is while the
            % constructor scores the seams), otherwise the parent Stitching
            % window, otherwise ``[]`` - headless, and the caller then skips
            % the progress bar entirely.
            %
            figureHandle = [];
            if ~isempty(obj.view) && ~isempty(obj.view.gui) && isvalid(obj.view.gui) ...
                    && strcmp(obj.view.gui.Visible, 'on')
                figureHandle = obj.view.gui;
            elseif ~isempty(obj.stitching) && isvalid(obj.stitching)
                figureHandle = obj.stitching.guiFigure();
            end
        end

        % ---------------------------------------------------------------
        function tf = dataValid(obj)
            % DATAVALID - True while the parent still holds a reviewable
            % edge/position set (a layout rebuild in the Stitching window
            % invalidates the inspector's session).
            tf = isvalid(obj.stitching) && ~isempty(obj.stitching.edges) && ...
                ~isempty(obj.stitching.positions) && ...
                numel(obj.ranking) == numel(obj.stitching.edges);
        end

        % ---------------------------------------------------------------
        function refreshExcludeButton(obj)
            % REFRESHEXCLUDEBUTTON - Show the current seam's exclusion state on
            % the Exclude button. The edge is the single source of truth (the
            % X key and a table reload change it too), so the button is always
            % pushed FROM the edge, never read from.
            %
            % Works with either widget type: an App Designer STATE button
            % (``uibutton(...,'state')``, has a ``Value``) shows the state as
            % pressed + red, a plain push button only as red - so the mlapp can
            % be upgraded without touching this code.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.refreshExcludeButton()
            %
            if ~obj.hasWidget('excludeBtn'); return; end
            excludeBtn = obj.view.handles.excludeBtn;
            if ~isvalid(excludeBtn); return; end

            isExcluded = false;
            if obj.dataValid() && ~isempty(obj.currentEdgeIdx)
                isExcluded = ~obj.stitching.edges(obj.currentEdgeIdx).valid;
            end

            if isprop(excludeBtn, 'Value')      % state button: pressed while excluded
                excludeBtn.Value = isExcluded;
            end
            % Excluded: pink with black text in both themes (the dark theme's auto
            % font is near-white). Included: both colors back on auto, so the
            % button follows the current theme, also after a theme switch
            if isExcluded
                excludeBtn.BackgroundColor = [1.0 0.72 0.72];
                excludeBtn.FontColor = [0 0 0];
                excludeBtn.Text = 'Excluded (X)';
            else
                excludeBtn.BackgroundColorMode = 'auto';
                excludeBtn.FontColorMode = 'auto';
                excludeBtn.Text = 'Exclude (X)';
            end
        end

        % ---------------------------------------------------------------
        function delta = currentOffsetYX(obj, edgeIdx)
            % CURRENTOFFSETYX - Current [dy dx] of an edge's pair. User-fixed
            % edges display at the offset the user set (``measured``), so a
            % fix is visible before (and independent of) the next re-solve;
            % everything else shows the solved position difference.
            edge = obj.stitching.edges(edgeIdx);
            if strcmp(edge.source, 'user')
                delta = edge.measured(1:2);
            else
                delta = obj.stitching.positions(edge.j, 1:2) - obj.stitching.positions(edge.i, 1:2);
            end
        end

        % ---------------------------------------------------------------
        function dz = currentDz(obj, edgeIdx)
            % CURRENTDZ - Current z-offset of an edge's pair (slices), same
            % display convention as currentOffsetYX: user-fixed edges show
            % the offset the user set, others the solved position difference.
            edge = obj.stitching.edges(edgeIdx);
            if strcmp(edge.source, 'user')
                dz = edge.measured(3);
            else
                dz = obj.stitching.positions(edge.j, 3) - obj.stitching.positions(edge.i, 3);
            end
        end

        % ---------------------------------------------------------------
        function tf = pairHasDepth(obj, edgeIdx)
            % PAIRHASDEPTH - True when a z-offset is meaningful for this pair:
            % a cross-layer edge, or either tile is a z-stack.
            edge = obj.stitching.edges(edgeIdx);
            tf = strcmp(edge.direction, 'z') || ...
                obj.stitching.layout(edge.i).tileSize(3) > 1 || ...
                obj.stitching.layout(edge.j).tileSize(3) > 1;
        end

        % ---------------------------------------------------------------
        function mode = fixMode(obj)
            % FIXMODE - What a fix edits on 3D pairs: 'xy' (default; the
            % in-plane offset at the aligned slices) or 'z' (match slices
            % across the Z boundary - fixModeDropdown, guarded).
            mode = 'xy';
            if obj.hasWidget('fixModeDropdown') && ...
                    contains(lower(obj.view.handles.fixModeDropdown.Value), 'z')
                mode = 'z';
            end
        end

        % ---------------------------------------------------------------
        function r = visibleRanking(obj)
            % VISIBLERANKING - obj.ranking filtered to the seams the current
            % fixMode edits: the IN-PLANE seams (x/y, tiles side by side or
            % stacked in the same Z-layer) in Fix XY, the CROSS-LAYER seams (z,
            % tiles in adjacent Z-layers) in Fix Z. The seam table and every
            % seam-to-seam navigation (table click, Up/Down, resolve, advance,
            % mini-map jump, the initial pick) follow this subset, so the table
            % never mixes in-plane and cross-layer rows - they read on different
            % axes and made the combined list confusing. A 2D dataset has only
            % in-plane seams, so Fix XY shows them all and Fix Z is empty.
            r = obj.ranking;
            if isempty(r); return; end
            isZ = strcmp({obj.stitching.edges(r).direction}, 'z');
            if strcmp(obj.fixMode(), 'z')
                r = r(isZ);
            else
                r = r(~isZ);
            end
        end

        % ---------------------------------------------------------------
        function tiles = currentLayerTiles(obj)
            % CURRENTLAYERTILES - Tile indices of the Z-layer the mini-map
            % currently draws: the current seam's layer (its lower tile for a
            % cross-layer pair), or the lowest layer before anything is
            % selected. Shared by renderMiniMap (what to draw) and jumpToTile
            % (what a mini-map click can land on) so the two never drift apart.
            layout = obj.stitching.layout;
            zLayers = arrayfun(@(t) t.zLayer, layout);
            if ~isempty(obj.currentEdgeIdx)
                currentLayer = layout(obj.stitching.edges(obj.currentEdgeIdx).i).zLayer;
            else
                currentLayer = min(zLayers);
            end
            tiles = find(zLayers == currentLayer);
        end

        % ---------------------------------------------------------------
        function k = edgeAtMiniMapPoint(obj, point)
            % EDGEATMINIMAPPOINT - Seam (edge index) nearest a mini-map click.
            %
            % A tile usually touches more than one seam (a grid tile has a
            % neighbour on two, three or four sides), so "jump to this tile's
            % worst seam" can only ever reach the single worst one - clicking
            % anywhere else on that tile, hoping to land on a DIFFERENT one of
            % its seams, always lands back on the same worst seam instead.
            % Fix: give every seam of the current layer (the subset
            % visibleRanking shows) a location - the midpoint of its two
            % tiles' overlap rectangle, i.e. where the shared image content
            % actually is - and return whichever seam's location is nearest
            % the click. Returns ``[]`` when there is nothing to match (no
            % seams in this fix mode, or none in the current layer).
            layout = obj.stitching.layout;
            positions = obj.stitching.positions;
            edges = obj.stitching.edges;
            drawTiles = obj.currentLayerTiles();

            k = [];
            bestDist = Inf;
            visibleRanking = obj.visibleRanking();
            for candidate = visibleRanking(:)'   % (:)' guarantees row orientation for the loop
                e = edges(candidate);
                if ~any(drawTiles == e.i) || ~any(drawTiles == e.j)
                    continue;   % not a seam of the currently-drawn layer
                end
                x0i = positions(e.i, 2); y0i = positions(e.i, 1);
                wi  = layout(e.i).tileSize(2); hi = layout(e.i).tileSize(1);
                x0j = positions(e.j, 2); y0j = positions(e.j, 1);
                wj  = layout(e.j).tileSize(2); hj = layout(e.j).tileSize(1);
                xOverlap = [max(x0i, x0j), min(x0i + wi, x0j + wj)];
                yOverlap = [max(y0i, y0j), min(y0i + hi, y0j + hj)];
                if diff(xOverlap) > 0 && diff(yOverlap) > 0
                    seamPoint = [mean(xOverlap), mean(yOverlap)];
                else
                    % No real overlap left at the solved placement (a weak or
                    % failed measurement) - fall back to the midpoint between
                    % the two tile centers so the seam still has a location.
                    seamPoint = ([x0i + wi / 2, y0i + hi / 2] + ...
                                 [x0j + wj / 2, y0j + hj / 2]) / 2;
                end
                seamDist = hypot(point(1) - seamPoint(1), point(2) - seamPoint(2));
                if seamDist < bestDist
                    bestDist = seamDist;
                    k = candidate;
                end
            end
        end

        % ---------------------------------------------------------------
        function tf = boundaryModeActive(obj)
            % BOUNDARYMODEACTIVE - True when the pair view shows a mosaic
            % Z BOUNDARY (Fix Z): the same tile at consecutive slices z-1
            % (cyan) vs z (magenta), fully overlapping - mostly white when
            % the mosaic is Z-aligned. Fixes then edit the per-slice mosaic
            % correction (applyZBoundaryFix), not a seam. renderPairView
            % engages it by storing viewSlice.boundaryTile.
            tf = strcmp(obj.fixMode(), 'z') && ~isempty(obj.viewSlice) && ...
                isfield(obj.viewSlice, 'boundaryTile') && ...
                ~isempty(obj.viewSlice.boundaryTile) && ...
                isequal(obj.viewSlice.edgeIdx, obj.currentEdgeIdx);
        end

        % ---------------------------------------------------------------
        function delta = boundaryDelta(obj, zBoundary)
            % BOUNDARYDELTA - Current [dy dx] mosaic correction at slice
            % boundary z (slices >= z relative to the ones below); [0 0]
            % when none is stored in the parent's zSliceFixes.
            delta = [0, 0];
            fixes = obj.stitching.zSliceFixes;
            if isempty(fixes); return; end
            row = find(round(fixes(:, 1)) == round(zBoundary), 1);
            if ~isempty(row); delta = fixes(row, 2:3); end
        end

        % ---------------------------------------------------------------
        function dz = fixDz(obj, edgeIdx)
            % FIXDZ - dz component written with any seam fix: always the
            % current dz - seam fixes never change the Z relation. (Z
            % corrections are per-slice mosaic shifts, applied through
            % applyZBoundaryFix in Fix-Z mode, not edge dz edits.)
            dz = obj.currentDz(edgeIdx);
        end

        % ---------------------------------------------------------------
        function tf = autoResolveEnabled(obj)
            % AUTORESOLVEENABLED - Re-solve automatically after each fix?
            % Defaults to ON (the solve is milliseconds at inspector sizes)
            % when the checkbox is absent from the mlapp.
            tf = true;
            if obj.hasWidget('autoResolveCheckbox')
                tf = logical(obj.view.handles.autoResolveCheckbox.Value);
            end
        end

        % ---------------------------------------------------------------
        function setStatus(obj, text)
            % SETSTATUS - Write to the status label (no-op without the widget).
            if obj.hasWidget('statusLabel')
                obj.view.handles.statusLabel.Text = text;
            end
        end
    end
end

% =========================================================================
function widgetFields = inspectorSessionFields()
% INSPECTORSESSIONFIELDS - {sessionSettings field, widget handle} of the sticky
% settings; one list shared by storeSessionSettings and restoreSessionSettings.
widgetFields = {
    'overlayMode',  'overlayModeDropdown'
    'fixMode',      'fixModeDropdown'
    'roiSize',      'ROIsizeSpinner'
    'searchRadius', 'SearchradiusSpinner'
    'autoResolve',  'autoResolveCheckbox'};
end
