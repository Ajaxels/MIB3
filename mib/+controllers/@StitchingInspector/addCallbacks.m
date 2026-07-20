function addCallbacks(obj)
% ADDCALLBACKS - Wire all view callbacks (called once from the constructor).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.addCallbacks()
%
% CloseRequestFcn is set first so the window can always be closed even if a
% later wiring line errors. Widgets that may not exist in the mlapp yet are
% guarded with ``isfield`` so the controller runs against a partial GUI.
%

handles = obj.view.handles;

obj.view.gui.CloseRequestFcn = @(~, ~) obj.closeWindow();
obj.view.gui.WindowKeyPressFcn = @(~, evnt) obj.keyPress_Callback(evnt);
obj.view.gui.WindowKeyReleaseFcn = @(~, evnt) obj.keyRelease_Callback(evnt);
obj.view.gui.WindowButtonMotionFcn = @(~, ~) obj.pairViewMotion();
obj.view.gui.WindowScrollWheelFcn = @(~, evnt) obj.scrollWheel_Callback(evnt);

if isfield(handles, 'seamTable')
    handles.seamTable.SelectionChangedFcn = @(src, evnt) obj.seamTableSelection_Callback(evnt);
end
if isfield(handles, 'overlayModeDropdown')
    handles.overlayModeDropdown.ValueChangedFcn = @(~, ~) obj.renderPairView();
end
if isfield(handles, 'fixModeDropdown')
    handles.fixModeDropdown.ValueChangedFcn = @(~, ~) fixModeChanged(obj);
end
if isfield(handles, 'confirmBtn')
    handles.confirmBtn.ButtonPushedFcn = @(~, ~) obj.confirmSeam_Callback();
end
if isfield(handles, 'excludeBtn')
    handles.excludeBtn.ButtonPushedFcn = @(~, ~) obj.excludeSeam_Callback();
end
if isfield(handles, 'resolveBtn')
    handles.resolveBtn.ButtonPushedFcn = @(~, ~) obj.resolveBtn_Callback();
end
if isfield(handles, 'twoClickBtn')
    handles.twoClickBtn.ButtonPushedFcn = @(~, ~) obj.twoClickBtn_Callback();
end
if isfield(handles, 'undoFixBtn')
    handles.undoFixBtn.ButtonPushedFcn = @(~, ~) obj.undoFix_Callback();
end
if isfield(handles, 'fitViewBtn')
    handles.fitViewBtn.ButtonPushedFcn = @(~, ~) obj.fitView_Callback();
end
if isfield(handles, 'refuseBtn')
    handles.refuseBtn.ButtonPushedFcn = @(~, ~) obj.refuseBtn_Callback();
end
if isfield(handles, 'saveProjectBtn')
    handles.saveProjectBtn.ButtonPushedFcn = @(~, ~) obj.stitching.saveProjectBtn_Callback();
end
if isfield(handles, 'closeButton')
    handles.closeButton.ButtonPushedFcn = @(~, ~) obj.closeWindow();
end
% roiSizeSpinner / searchRadiusSpinner / autoResolveCheckbox are read at the
% point of use — no callbacks needed.

% ---- tooltips (set here so the mlapp stays layout-only) --------------------
setTooltip(handles, 'seamTable', sprintf( ...
    ['Seams ranked worst-first by how well the pixels agree at the solved positions.\n' ...
     'The Seam column reads axis + the two tiles joined: X/Y (n-m) are in-plane\n' ...
     'seams, Z (n-m) cross-layer. Fix XY lists the in-plane seams, Fix Z the\n' ...
     'cross-layer ones. Click a row to review it.']));
setTooltip(handles, 'miniMapAxes', ...
    'Layout of the current seam''s Z-layer, tiles coloured by their worst seam (green = good, red = bad). Click a tile to jump to its worst seam.');
setTooltip(handles, 'pairAxes', sprintf( ...
    ['Both tiles composited at the current offset.\n' ...
     'Wheel: zoom at cursor (F fits) | drag: move tile j | Space: flicker\n' ...
     'Shift+hover: correlation box (Shift+wheel resizes it) | Shift+click: auto fine-tune\n' ...
     'Q/W or Up/Down: browse Z like the main MIB, always view-only\n' ...
     '(Fix XY: the aligned slice pair; Fix Z: the mosaic Z boundary)']));
setTooltip(handles, 'overlayModeDropdown', sprintf( ...
    ['How the pair is composited:\n' ...
     'Falsecolor — tile i cyan + tile j magenta, aligned structures WHITE\n' ...
     'Flicker — Space toggles the two tiles\nCheckerboard / Difference — imfuse views']));
setTooltip(handles, 'fixModeDropdown', sprintf( ...
    ['What a fix edits:\n' ...
     'Fix XY — the in-plane TILE offset of the current seam; Q/W browse the\n' ...
     'Z-aligned slices.\n' ...
     'Fix Z — align consecutive MOSAIC slices: one tile at slice z-1 (cyan)\n' ...
     'vs slice z (magenta), mostly white when aligned. Q/W moves the\n' ...
     'boundary; drag or Shift+click aligns slice z — the fix shifts that\n' ...
     'slice AND every slice above it across the whole mosaic (applied at\n' ...
     'Re-fuse / Stitch, saved in the project; Z removes it).']));
setTooltip(handles, 'offsetLabel', ...
    'Current pair offset vs the measured one, plus seam score, measurement quality and provenance.');
setTooltip(handles, 'confirmBtn', ...
    'Mark this seam as reviewed-OK and jump to the next worst unreviewed one (Enter).');
setTooltip(handles, 'excludeBtn', ...
    'Remove this seam''s measurement from the solve — the tiles are then held near their nominal positions. Press again to re-include (X).');
setTooltip(handles, 'resolveBtn', ...
    'Re-run the global solve with the edited seams, then re-score and re-rank the review.');
setTooltip(handles, 'twoClickBtn', ...
    'For tiles far out of place: shows both full tiles side by side — click the same landmark once in each to set the offset. Press again to cancel.');
setTooltip(handles, 'undoFixBtn', ...
    'Restore this seam''s original automatic measurement, undoing every fix applied to it this session (Z).');
setTooltip(handles, 'fitViewBtn', ...
    'Fit the whole tile pair in the view, resetting the mouse-wheel zoom (F).');
setTooltip(handles, 'refuseBtn', ...
    'Fuse the mosaic with the corrected positions — same as Stitch in the main window (both output modes; a pending re-solve runs first).');
setTooltip(handles, 'roiSizeSpinner', ...
    'Size (px) of the correlation box cut around a Shift+click. Hold Shift and scroll the mouse wheel to adjust. Keep it smaller than the overlap region.');
setTooltip(handles, 'searchRadiusSpinner', ...
    'How far (px per side) the box is searched around the current offset in the other tile.');
setTooltip(handles, 'autoResolveCheckbox', ...
    'Re-solve all positions (and re-rank the seams) automatically after each fix.');
setTooltip(handles, 'saveProjectBtn', ...
    'Save the stitch project sidecar — review decisions and fixes are stored with it.');
setTooltip(handles, 'closeButton', 'Close the inspector.');

end

% =====================================================================
function setTooltip(handles, widgetName, text)
% SETTOOLTIP - Guarded: skip absent widgets and ones without a Tooltip property.
if isfield(handles, widgetName) && isprop(handles.(widgetName), 'Tooltip')
    handles.(widgetName).Tooltip = text;
end
end

% =====================================================================
function fixModeChanged(obj)
% FIXMODECHANGED - Fix Z is the mosaic Z-BOUNDARY view: one tile at
% consecutive slices z-1 (cyan) vs z (magenta), fully overlapping — mostly
% white when the mosaic is Z-aligned; a fix shifts every mosaic slice >= z.
% It needs a tile with Z slices: when the current seam is between 2D tiles
% it jumps to a seam that has one (worst-first); a fully-2D dataset flips
% the dropdown back to Fix XY — announced with a DIALOG, since the status
% line alone proved too easy to miss in live testing. Each mode starts
% from a fitted view, hence the pairZoom reset.
%
% Switching mode also re-filters the seam table (updateWidgets): Fix XY lists
% the in-plane x/y seams, Fix Z the cross-layer z seams (see
% StitchingInspector.visibleRanking) — so entering Fix Z lands on a z seam
% when one exists, keeping the table highlight and the boundary view in step.
obj.viewSlice = [];
obj.pairZoom = [];
if strcmp(obj.fixMode(), 'z')
    edges = obj.stitching.edges;
    layout = obj.stitching.layout;
    hasDepthTile = @(k) layout(edges(k).i).tileSize(3) > 1 || ...
                        layout(edges(k).j).tileSize(3) > 1;
    % Land on a cross-layer z seam (a visible Fix Z table row) when any exist,
    % so the table highlight matches the boundary view. Single-layer Z-stacks
    % (depth>1 but no z edges) have an empty Fix Z table — fall back to any
    % seam touching a Z-stack tile so the boundary view still engages.
    zRanked = obj.visibleRanking();
    if isempty(zRanked)
        candidateRanked = obj.ranking(arrayfun(hasDepthTile, obj.ranking));
    else
        candidateRanked = zRanked;
    end
    currentOk = ~isempty(obj.currentEdgeIdx) && hasDepthTile(obj.currentEdgeIdx) && ...
        (isempty(zRanked) || any(zRanked == obj.currentEdgeIdx));
    if ~currentOk
        if isempty(candidateRanked)
            handles = obj.view.handles;
            if isfield(handles, 'fixModeDropdown')
                handles.fixModeDropdown.Value = handles.fixModeDropdown.Items{1};
            end
            obj.renderPairView();
            obj.updateWidgets();
            obj.setStatus('2D dataset — no Z slices to align. Staying in Fix XY.');
            dlgOpt.MsgBoxOnly = true;
            dlgOpt.Icon = 'puffin_info';
            utils.dlgs.inputUniversalDlg(obj.view.gui, 'Fix Z needs Z slices', {''}, ...
                {['This dataset is 2D — there are no Z slices to align, so the mode ' ...
                  'stays at Fix XY. Fix Z aligns mosaic slice z to slice z-1 and ' ...
                  'shifts everything above it.']}, 'Fix Z', dlgOpt);
            return;
        end
        obj.selectSeam(candidateRanked(1));
    else
        obj.renderPairView();
    end
    obj.setStatus(['Fix Z: slice z-1 (cyan) vs slice z (magenta) of one tile — mostly ' ...
        'white when the mosaic is Z-aligned. Q/W moves the boundary; drag or ' ...
        'Shift+click aligns slice z, shifting it AND every slice above; Z removes ' ...
        'the correction.']);
else
    obj.renderPairView();
    obj.setStatus(['Fix XY: drag or Shift+click edits the in-plane offset; ' ...
        'Q/W or Up/Down browses the Z-aligned slices.']);
end

% Rebuild the seam table for the new fix mode's filter, then restore the
% highlight on the current seam (cleared automatically if it is not a row of
% the newly shown set).
obj.updateWidgets();
if ~isempty(obj.view) && isfield(obj.view.handles, 'seamTable')
    rankPos = [];
    if ~isempty(obj.currentEdgeIdx)
        rankPos = find(obj.visibleRanking() == obj.currentEdgeIdx, 1);
    end
    try %#ok<TRYNC>
        obj.view.handles.seamTable.Selection = rankPos;
    end
end
end
