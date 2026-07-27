classdef StitchingInspector < handle
    % STITCHINGINSPECTOR - Seam inspector: manual QC + fixing of a stitch.
    %
    % Reviews the measured tile-pair seams worst-first and lets the user
    % confirm, exclude, or (Phase C) fix them; fixes re-steer the global solve
    % through high-weight user edges. Launched from the Stitching tool
    % (``inspectSeamsBtn``) with the parent ``controllers.Stitching`` handle —
    % the parent's ``layout``/``edges``/``positions``/``tforms`` are the single
    % source of truth and are mutated in place. Design + phasing:
    % ``development/stitching/plan_inspector.md``.
    %
    % Seams are ranked by ``utils.stitch.scoreSeams`` (pixel NCC at the SOLVED
    % positions — catches confidently-wrong measurements that solver residuals
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
        % shared LRU tile reader (utils.stitch.makeTileReader)
        pairImageHandles
        % [2x1] image handles on pairAxes for the flicker overlay ([] otherwise)
        flickerState
        % which flicker image is visible (1 = tile i, 2 = tile j)
        autoBackup
        % cell (per edge) with the original automatic edge before the first
        % user fix — Z / undoFixBtn restores it (in-memory only, not persisted)
        pairStrip
        % struct with the current pair view geometry (.bboxA = tile-i strip
        % [rowStart rowEnd; colStart colEnd], .deltaYX) — maps clicks on the
        % strip back to tile-i pixels; [] when no overlap is rendered
        twoClick
        % two-click landmark match state: .active, .stage (1|2), .scale,
        % .leftWidth, .gap, .clickA ([x y] in tile-i full-res pixels)
        shiftDown
        % true while Shift is held over the inspector — the pair-view cursor
        % becomes the correlation ROI box and a click runs click-to-correlate
        roiBoxHandle
        % line handle of the hover ROI box on pairAxes ([] until first shown)
        pairZoom
        % wheel-zoom state of the pair view: struct .edgeIdx (the seam it
        % belongs to), .xLim, .yLim — re-applied across re-renders of the
        % same seam so nudges/drags keep the zoom; [] = fit to view
        tileThumbs
        % cell (per tile) of low-res greyscale thumbnails for the mini-map
        % fused preview, jointly normalised to [0 1]; built lazily once by
        % ensureTileThumbs ({} until then, {} forever if tiles are too big)
        thumbScale
        % full-res pixels per thumbnail pixel (NaN until thumbs are built)
        resolvePending
        % true when a user fix was applied WITHOUT the global re-solve
        % (auto-re-solve off / deferred). The parent's Stitch checks this and
        % re-solves before fusing, so the mosaic never comes from stale
        % positions no matter which window the user works in
        excludeBtnDefaultColor
        % BackgroundColor the exclude button had when the window opened, so the
        % "included" look can be restored without hardcoding a theme colour
        % ([] until addCallbacks captures it)
        viewSlice
        % browsed z-slices of the pair view: struct .edgeIdx, .sliceA
        % (tile-i slice), .sliceB (tile-j slice), .depthA, .depthB (stack
        % depths) and .boundaryTile — [] in Fix XY (sliceA/sliceB are the
        % dz-aligned pair of the seam's tiles), or the tile index in Fix Z,
        % where the view is the mosaic Z BOUNDARY: that ONE tile at slices
        % z-1 (sliceA, cyan) vs z (sliceB, magenta). Browsing is VIEW ONLY.
        % [] = defaults (central slice)
    end

    events
        CloseEvent
        % fired when the window is closed
        SeamsUpdated
        % fired after a re-solve / edge edit so the parent Stitching refreshes
    end

    methods

        % ---------------------------------------------------------------
        function obj = StitchingInspector(mibModel, stitchController)
            % STITCHINGINSPECTOR - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = controllers.StitchingInspector(mibModel, stitchController)
            %
            % Input Arguments:
            %   - **mibModel** — handle to MibModel
            %   - **stitchController** — handle to the launching
            %     ``controllers.Stitching``; must hold a measured ``edges`` set
            %     and solved ``positions``
            %

            obj.mibModel  = mibModel;
            obj.stitching = stitchController;
            obj.ranking = [];
            obj.currentEdgeIdx = [];
            obj.readerFcn = [];
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
            obj.resolvePending = false;
            obj.viewSlice = [];
            obj.excludeBtnDefaultColor = [];

            if isempty(obj.stitching.edges) || isempty(obj.stitching.positions)
                utils.dlgs.showErrorDialog(obj.stitching.view.gui, ...
                    'Measure overlaps and Optimize positions first — the inspector reviews seams at the SOLVED placement.', ...
                    'Seam inspector');
                notify(obj, 'CloseEvent');
                return;
            end

            % ---- GUI
            obj.view = core.ChildView(obj, 'views.StitchingInspectorGUI');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.closeButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'right');

            obj.addCallbacks();
            obj.scoreAndRank();
            obj.updateWidgets();
            initialRanking = obj.visibleRanking();
            if ~isempty(initialRanking)
                obj.selectSeam(initialRanking(1));
            end

            obj.view.gui.Visible = 'on';
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
            % pressed + red, a plain push button only as red — so the mlapp can
            % be upgraded without touching this code.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.refreshExcludeButton()
            %
            if isempty(obj.view) || ~isfield(obj.view.handles, 'excludeBtn'); return; end
            excludeBtn = obj.view.handles.excludeBtn;
            if ~isvalid(excludeBtn); return; end

            if isempty(obj.excludeBtnDefaultColor)
                obj.excludeBtnDefaultColor = excludeBtn.BackgroundColor;
            end

            isExcluded = false;
            if obj.dataValid() && ~isempty(obj.currentEdgeIdx)
                isExcluded = ~obj.stitching.edges(obj.currentEdgeIdx).valid;
            end

            if isprop(excludeBtn, 'Value')      % state button: pressed while excluded
                excludeBtn.Value = isExcluded;
            end
            if isExcluded
                excludeBtn.BackgroundColor = [1.0 0.72 0.72];
                excludeBtn.Text = 'Excluded (X)';
            else
                excludeBtn.BackgroundColor = obj.excludeBtnDefaultColor;
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
            % across the Z boundary — fixModeDropdown, guarded).
            mode = 'xy';
            if ~isempty(obj.view) && isfield(obj.view.handles, 'fixModeDropdown') && ...
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
            % seam-to-seam navigation (table click, N/P, resolve, advance,
            % mini-map jump, the initial pick) follow this subset, so the table
            % never mixes in-plane and cross-layer rows — they read on different
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
        function tf = boundaryModeActive(obj)
            % BOUNDARYMODEACTIVE - True when the pair view shows a mosaic
            % Z BOUNDARY (Fix Z): the same tile at consecutive slices z-1
            % (cyan) vs z (magenta), fully overlapping — mostly white when
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
            % current dz — seam fixes never change the Z relation. (Z
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
            if ~isempty(obj.view) && isfield(obj.view.handles, 'autoResolveCheckbox')
                tf = logical(obj.view.handles.autoResolveCheckbox.Value);
            end
        end

        % ---------------------------------------------------------------
        function setStatus(obj, text)
            % SETSTATUS - Write to the status label (no-op without the widget).
            if ~isempty(obj.view) && isfield(obj.view.handles, 'statusLabel')
                obj.view.handles.statusLabel.Text = text;
            end
        end
    end
end
