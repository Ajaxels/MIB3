function keyPress_Callback(obj, evnt)
% KEYPRESS_CALLBACK - Keyboard-first review loop.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.keyPress_Callback(evnt)
%
% Shortcuts:
%   - ``Space``  - flicker A/B (Flicker overlay mode)
%   - ``Enter``  - confirm current seam + jump to next worst unreviewed
%   - ``X``      - exclude / re-include current seam
%   - ``Down`` / ``Up`` - next / previous seam in the ranking, i.e. one row
%     down / up the seam table (next / previous slice boundary when the
%     table lists those - Fix Z with all tiles on one layer)
%   - ``Q`` / ``W`` - BROWSE Z, previous / next, exactly like the main MIB
%     (``Shift`` = ±5); ALWAYS view-only, in BOTH fix modes. Fix XY: the
%     dz-aligned slice pair; Fix Z: the mosaic Z boundary (both consecutive
%     slices step together). Keyboard nudging is disabled entirely - offsets
%     are edited by mouse only (drag / Shift+click / two-click)
%   - ``Z``      - undo the fix on the current seam (restore the auto edge);
%     in Fix Z, remove the boundary correction on screen
%   - ``Ctrl+Z`` - Fix Z: step back one Fix Z action (zFixHistory) - a
%     whole-stack correlation (Ctrl+Shift+click) returns every boundary to
%     its previous correction, a drag / Shift+click / Z the one boundary it
%     touched; repeatable. In Fix XY it is the same as ``Z``
%   - ``F``      - fit the pair view (reset the mouse-wheel zoom)
%   - ``Esc``    - cancel a tile drag in progress; nothing is applied
%   - ``Ctrl`` / ``Shift`` held - modifier state for the pair view: Shift+click
%     correlates one spot, Ctrl+Shift+click (Fix Z) every Z boundary there
%
% Input Arguments:
%   - **evnt** - KeyData from ``WindowKeyPressFcn``
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.keyPress_Callback: triggered\n');
end
if ~obj.dataValid(); return; end

switch evnt.Key
    case 'escape'
        % Abandon a left drag in progress (pairViewButtonDown): nothing applied.
        if ~isempty(obj.dragCancelFcn)
            obj.dragCancelFcn();
        end
    case 'space'
        % Flicker toggle: swap which strip is visible.
        if numel(obj.pairImageHandles) == 2 && all(isvalid(obj.pairImageHandles))
            obj.flickerState = 3 - obj.flickerState;
            obj.pairImageHandles(1).Visible = matlab.lang.OnOffSwitchState(obj.flickerState == 1);
            obj.pairImageHandles(2).Visible = matlab.lang.OnOffSwitchState(obj.flickerState == 2);
            if obj.hasWidget('pairAxes') && ~isempty(obj.currentEdgeIdx)
                % Replace only the first title line - line 2 (the slice pair
                % readout on 3D pairs) must survive the flicker toggle.
                titleHandle = obj.view.handles.pairAxes.Title;
                if obj.boundaryModeActive()
                    shown = [obj.viewSlice.sliceA, obj.viewSlice.sliceB];
                    flickerLine = sprintf('Flicker - showing slice %d (Space toggles)', ...
                        shown(obj.flickerState));
                else
                    edge = obj.stitching.edges(obj.currentEdgeIdx);
                    shown = [edge.i, edge.j];
                    flickerLine = sprintf('Flicker - showing tile %d (Space toggles)', ...
                        shown(obj.flickerState));
                end
                if iscell(titleHandle.String)
                    titleHandle.String{1} = flickerLine;
                else
                    titleHandle.String = flickerLine;
                end
            end
        end
    case 'return'
        obj.confirmSeam_Callback();
    case 'x'
        obj.excludeSeam_Callback();
    case {'uparrow', 'downarrow'}
        % The vertical arrows walk the seam TABLE, the way arrows walk any
        % list: Down = one row further down the worst-first ranking, Up =
        % back. Navigation stays inside the seams the current fix mode shows.
        %
        % Z browsing is on Q/W ALONE for this reason - while the arrows also
        % browsed Z they disagreed with the focused table, which reads Down as
        % "next row" itself. Rows are what the arrows point at here - so when
        % the rows are slice boundaries (Fix Z, one layer), a row is a Z step.
        if obj.listsSliceBoundaries()
            browseZ(obj, 1 - 2 * strcmp(evnt.Key, 'uparrow'), false);
            return;
        end
        visibleRanking = obj.visibleRanking();
        if isempty(obj.currentEdgeIdx) || isempty(visibleRanking); return; end
        rankPos = obj.rowOfEdge(obj.currentEdgeIdx);
        if isempty(rankPos); rankPos = 1; end
        if strcmp(evnt.Key, 'downarrow')
            rankPos = min(rankPos + 1, numel(visibleRanking));
        else
            rankPos = max(rankPos - 1, 1);
        end
        obj.selectSeam(visibleRanking(rankPos));
    case {'q', 'w'}
        % Slice browsing on the main-MIB keys: q = previous, w = next.
        step = 1;
        if any(strcmpi(evnt.Modifier, 'shift')); step = 5; end
        if strcmp(evnt.Key, 'q'); step = -step; end
        browseZ(obj, step, any(strcmpi(evnt.Modifier, 'control')));
    case 'z'
        if any(strcmpi(evnt.Modifier, 'control')) && strcmp(obj.fixMode(), 'z')
            obj.undoLastZFix();   % Ctrl+Z in Fix Z: step back one Fix Z action
        else
            obj.undoFix_Callback();
        end
    case 'f'
        obj.fitView_Callback();
    case 'control'
        obj.ctrlDown = true;   % with Shift: click correlates the whole stack
    case 'shift'
        % Shift held: the pair-view cursor becomes the correlation ROI box
        % (Shift+click = automated fine-tune within the box).
        obj.shiftDown = true;
        obj.view.gui.Pointer = 'crosshair';
        obj.pairViewMotion();
end
end

% =====================================================================
function browseZ(obj, step, ~)
% BROWSEZ - Step the browsed z-slice(s) of the pair view. ALWAYS view-only.
% Fix XY: the dz-aligned pair browses synchronously (sliceB re-derived from
% sliceA - dz on render). Fix Z (boundary view): moves the boundary - both
% consecutive slices step together, clamped to [2, depth].
if isempty(obj.currentEdgeIdx); return; end
if ~obj.pairHasDepth(obj.currentEdgeIdx)
    obj.setStatus('2D pair - no Z slices here');
    return;
end
if isempty(obj.viewSlice) || ~isequal(obj.viewSlice.edgeIdx, obj.currentEdgeIdx)
    obj.renderPairView();   % establishes the slice state
end
if isempty(obj.viewSlice); return; end
if obj.boundaryModeActive()
    zBoundary = min(max(obj.viewSlice.sliceB + step, 2), obj.viewSlice.depthB);
    obj.viewSlice.sliceA = zBoundary - 1;
    obj.viewSlice.sliceB = zBoundary;
    % Serial sections list one row per section boundary: follow the browsed
    % boundary with the current row, so the highlight and Up / Down agree.
    if obj.isSectionLayout()
        viewCanvas = obj.zViewCanvas();
        visibleRanking = obj.visibleRanking();
        for rowEdge = visibleRanking(:)'
            if isequal(obj.zBoundaryOfEdge(rowEdge, viewCanvas), zBoundary)
                obj.currentEdgeIdx = rowEdge;
                obj.viewSlice.edgeIdx = rowEdge;
                if obj.hasWidget('seamTable')
                    try %#ok<TRYNC>
                        rankPos = obj.rowOfEdge(rowEdge);
                        obj.view.handles.seamTable.Selection = rankPos;
                        scroll(obj.view.handles.seamTable, 'row', rankPos);
                    end
                end
                break;
            end
        end
    end
else
    obj.viewSlice.sliceA = obj.viewSlice.sliceA + step;
end
obj.renderPairView();   % clamps and redraws
end
