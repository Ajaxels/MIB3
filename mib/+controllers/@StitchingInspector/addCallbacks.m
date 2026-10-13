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

handles.seamTable.SelectionChangedFcn = @(src, evnt) obj.seamTableSelection_Callback(evnt);
% The overlay list is owned HERE, not by the mlapp (whose Items are
% placeholders): renderPairView compares against these exact strings, and an
% mlapp still carrying an older list would otherwise offer modes it cannot draw.
% 'Preview final' heads the list in bold italics, set apart from the review modes
% below it (uidropdown has no Separator property, and a divider item would be
% selectable). The default stays 'Falsecolor (cyan/magenta)', the mode to
% review seams in.
overlayModes = {'Preview final', 'Falsecolor (cyan/magenta)', ...
    'Falsecolor (green/red)', 'Flicker', 'Checkerboard', 'Difference'};
defaultMode = 'Falsecolor (cyan/magenta)';
previousMode = handles.overlayModeDropdown.Value;
if strcmp(previousMode, 'Falsecolor'); previousMode = defaultMode; end
handles.overlayModeDropdown.Items = overlayModes;
if ismember(previousMode, overlayModes)
    handles.overlayModeDropdown.Value = previousMode;
else
    handles.overlayModeDropdown.Value = defaultMode;
end
addStyle(handles.overlayModeDropdown, uistyle('FontAngle', 'italic', 'FontWeight', 'bold'), ...
    'item', find(strcmp(overlayModes, 'Preview final')));
handles.overlayModeDropdown.ValueChangedFcn = @(~, ~) obj.renderPairView();
% Tile-order menu: a real ContextMenu, filled when it opens. Opening one by hand
% (open(menu, x, y)) from the right-button-up callback was tried first and never
% appears on screen - the window's own right-click handling dismisses it. A right
% DRAG pans the pair view; fillTileOrderMenu leaves the menu empty after a pan so
% nothing pops up. renderPairView attaches it to every image it draws.
obj.tileOrderMenu = uicontextmenu(obj.view.gui);
obj.tileOrderMenu.ContextMenuOpeningFcn = @(~, ~) obj.fillTileOrderMenu();
handles.pairAxes.ContextMenu = obj.tileOrderMenu;
handles.fixModeDropdown.ValueChangedFcn = @(~, ~) fixModeChanged(obj);
handles.confirmBtn.ButtonPushedFcn = @(~, ~) obj.confirmSeam_Callback();

% Exclude is a two-state action, so the mlapp may carry either an App
% Designer STATE button (has Value/ValueChangedFcn - shows the exclusion as
% pressed) or a plain push button. Wire whichever is there; the callback is
% the same and never reads the widget, so the X key stays equivalent.
if isprop(handles.excludeBtn, 'Value')
    handles.excludeBtn.ValueChangedFcn = @(~, ~) obj.excludeSeam_Callback();
else
    handles.excludeBtn.ButtonPushedFcn = @(~, ~) obj.excludeSeam_Callback();
end

handles.resolveBtn.ButtonPushedFcn = @(~, ~) obj.resolveBtn_Callback();
handles.twoClickBtn.ButtonPushedFcn = @(~, ~) obj.twoClickBtn_Callback();
handles.undoFixBtn.ButtonPushedFcn = @(~, ~) obj.undoFix_Callback();
handles.fitViewBtn.ButtonPushedFcn = @(~, ~) obj.fitView_Callback();
handles.helpButton.ButtonPushedFcn = @(~, ~) obj.helpBtn_Callback();
handles.keyShortcutsButton.ButtonPushedFcn = @(~, ~) obj.keyShortcutsBtn_Callback();
handles.closeButton.ButtonPushedFcn = @(~, ~) obj.closeWindow();
% ROIsizeSpinner / SearchradiusSpinner / autoResolveCheckbox are read at the
% point of use - no callbacks needed.

% ---- tooltips (set here so the mlapp stays layout-only) --------------------
setTooltip(handles, 'seamTable', sprintf( ...
    ['Seams ranked worst-first by how well the pixels agree at the solved positions.\n' ...
     'The Seam column reads axis + the two tiles joined: X/Y (n-m) are in-plane\n' ...
     'seams, Z (n-m) cross-layer. Fix XY lists the in-plane seams, Fix Z the\n' ...
     'cross-layer ones - or, when all tiles are on one layer, the slice\n' ...
     'boundaries (Z 1-2, Z 2-3, ...). Serial sections (Register slices): tiles\n' ...
     'are named by folder, and Fix Z shows one row per section boundary, opening\n' ...
     'its worst tile link. Click a row to review it.']));
setTooltip(handles, 'miniMapAxes', ...
    'Layout of the current seam''s Z-layer, tiles coloured by their worst seam of the current Fix mode (green = good, red = bad). Click to jump to the review - selects whichever seam is nearest the click point; in Fix Z, shows the stitched mosaic around the clicked point at the same Z boundary.');
setTooltip(handles, 'pairAxes', sprintf( ...
    ['Both tiles composited at the current offset.\n' ...
     'Wheel: zoom at cursor - the level carries to the next seam (F fits) | drag: move tile j (Esc cancels) | Space: flicker\n' ...
     'Right-click drag: pan the view | Right-click: tile order (which tile Overwrite keeps)\n' ...
     'Shift+hover: correlation box (Shift+wheel resizes it) | Shift+click: auto fine-tune\n' ...
     'Ctrl+Shift+click (Fix Z): auto fine-tune every Z boundary of the stack at that spot\n' ...
     'Q/W: browse Z like the main MIB, always view-only | Up/Down: previous/next seam\n' ...
     '(Fix XY: the aligned slice pair; Fix Z: the mosaic Z boundary)']));
setTooltip(handles, 'overlayModeDropdown', sprintf([ ...
    'How the pair is composited:\n' ...
    '  - Preview final: the pair as Stitch will fuse it, with the current blend mode and tile order; right-click to change which tile is on top\n' ...
    '  - Falsecolor (cyan/magenta): the tile on top magenta, the one below cyan; aligned structures come out white (default)\n' ...
    '  - Falsecolor (green/red): the tile on top red, the one below green; aligned structures come out yellow\n' ...
    '  - Flicker: Space toggles the two tiles\n' ...
    '  - Checkerboard / Difference: the two tiles interleaved / subtracted']));
setTooltip(handles, 'fixModeDropdown', sprintf( ...
    ['What a fix edits:\n' ...
     'Fix XY - the in-plane TILE offset of the current seam; Q/W browse the\n' ...
     'Z-aligned slices.\n' ...
     'Fix Z - align consecutive MOSAIC slices: the stitched mosaic at slice\n' ...
     'z-1 (cyan) vs slice z (magenta), mostly white when aligned. A mini-map\n' ...
     'click picks where to look, Q/W moves the boundary; drag or Shift+click\n' ...
     'aligns slice z - the fix shifts that slice AND every slice above it as\n' ...
     'one block (applied by Stitch in the main window, saved in the project;\n' ...
     'Z removes it).']));
setTooltip(handles, 'offsetLabel', ...
    'Current pair offset vs the measured one, plus seam score, measurement quality and provenance.');
setTooltip(handles, 'confirmBtn', ...
    'Mark this seam as reviewed-OK and jump to the next worst unreviewed one (Enter).');
setTooltip(handles, 'excludeBtn', sprintf( ...
    ['Exclude this seam''s measurement from the solve - the tiles are then held\n' ...
     'near their nominal positions. The button stays pressed (red) while the seam\n' ...
     'is excluded; press it again to put the measurement back (X).']));
setTooltip(handles, 'resolveBtn', ...
    'Re-run the global solve with the edited seams, then re-score and re-rank the review.');
setTooltip(handles, 'twoClickBtn', ...
    'For tiles far out of place: shows both full tiles side by side - click the same landmark once in each to set the offset. Press again to cancel.');
setTooltip(handles, 'undoFixBtn', ...
    'Restore this seam''s original automatic measurement, undoing every fix applied to it this session (Z).');
setTooltip(handles, 'fitViewBtn', ...
    'Fit the whole tile pair in the view, resetting the mouse-wheel zoom (F).');
setTooltip(handles, 'ROIsizeSpinner', ...
    'Size (px) of the correlation box cut around a Shift+click. Hold Shift and scroll the mouse wheel to adjust. Keep it smaller than the overlap region.');
setTooltip(handles, 'SearchradiusSpinner', ...
    'How far (px per side) the box is searched around the current offset in the other tile.');
setTooltip(handles, 'autoResolveCheckbox', ...
    'Re-solve all positions (and re-rank the seams) automatically after each fix.');
setTooltip(handles, 'closeButton', 'Close the inspector.');
setTooltip(handles, 'keyShortcutsButton', ...
    'Show all mouse, Shift+mouse, and keyboard controls available in the pair view and seam table.');

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
% FIXMODECHANGED - Fix Z is the mosaic Z-BOUNDARY view: a crop of the FUSED
% mosaic at consecutive slices z-1 (cyan) vs z (magenta) - mostly white when
% the mosaic is Z-aligned; a fix shifts every mosaic slice >= z as one block
% (the tiles are taken as correctly stitched). It needs a mosaic with more
% than one slice and slices that belong together: a 2D mosaic, or unrelated
% slices (Register slices off - stitched one by one on purpose), flips the
% dropdown back to Fix XY - announced with a DIALOG, since the status line
% alone proved too easy to miss in live testing. Each mode starts from a
% fitted view, hence the pairZoom reset.
%
% Switching mode also re-filters the seam table (updateWidgets): Fix XY lists
% the in-plane x/y seams, Fix Z the cross-layer z seams (see
% StitchingInspector.visibleRanking) - so entering Fix Z lands on a z seam
% (its boundary) when one exists, keeping the table highlight and the view in
% step. Z-stacks on one layer have none; their table lists the slice
% boundaries instead (listsSliceBoundaries).
obj.viewSlice = [];
obj.pairZoom = [];
if strcmp(obj.fixMode(), 'z')
    edges = obj.stitching.edges;
    mosaicDepth = obj.zViewCanvas().size(3);
    unrelatedSlices = obj.isSectionLayout() && ~any(strcmp({edges.direction}, 'z'));
    if mosaicDepth < 2 || unrelatedSlices
        handles = obj.view.handles;
        if isfield(handles, 'fixModeDropdown')
            handles.fixModeDropdown.Value = handles.fixModeDropdown.Items{1};
        end
        obj.renderPairView();
        obj.updateWidgets();
        % Unrelated slices are split into sections with NO section-to-section
        % seams: there is Z, but nothing to align in it - say that rather than
        % call the dataset 2D.
        if unrelatedSlices
            statusText = 'Slices stitched independently - no Z alignment to fix. Staying in Fix XY.';
            dialogText = sprintf(['The slices were stitched independently (Register slices is off), so they\n' ...
                'are not aligned to each other and there is no Z alignment to fix. The mode\n' ...
                'stays at Fix XY. Tick Register slices to align them.']);
        else
            statusText = '2D dataset - no Z slices to align. Staying in Fix XY.';
            dialogText = sprintf(['This dataset is 2D - there are no Z slices to align, so the mode stays at Fix XY.\n' ...
                'Fix Z aligns mosaic slice z to slice z-1 and shifts everything above it.']);
        end
        obj.setStatus(statusText);
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_info';
        dlgOpt.HeaderLines = 1;
        dlgOpt.WindowHeight = 180;
        utils.dlgs.inputUniversalDlg(obj.view.gui, 'Fix Z needs Z slices', {''}, ...
            {dialogText}, 'Fix Z', dlgOpt);
        return;
    end
    zRanked = obj.visibleRanking();
    if ~isempty(zRanked) && (isempty(obj.currentEdgeIdx) || ~any(zRanked == obj.currentEdgeIdx))
        obj.selectSeam(zRanked(1));
    else
        obj.renderPairView();
    end
    obj.setStatus(['Fix Z: the stitched mosaic at slice z-1 (cyan) vs slice z (magenta) - mostly ' ...
        'white when aligned. Click the mini-map to look elsewhere, Q/W moves the boundary; ' ...
        'drag or Shift+click aligns slice z, shifting it AND every slice above; Z removes ' ...
        'the correction.']);
else
    obj.renderPairView();
    obj.setStatus(['Fix XY: drag or Shift+click edits the in-plane offset; ' ...
        'Q/W browses the Z-aligned slices; Up/Down steps through the seams.']);
end

% Rebuild the seam table for the new fix mode's filter, then restore the
% highlight on the current seam (cleared automatically if it is not a row of
% the newly shown set).
obj.updateWidgets();
% A slice-boundary table set its own highlight in updateWidgets.
if obj.hasWidget('seamTable') && ~obj.listsSliceBoundaries()
    rankPos = [];
    if ~isempty(obj.currentEdgeIdx)
        rankPos = obj.rowOfEdge(obj.currentEdgeIdx);
    end
    try %#ok<TRYNC>
        obj.view.handles.seamTable.Selection = rankPos;
        if ~isempty(rankPos)
            scroll(obj.view.handles.seamTable, 'row', rankPos);
        end
    end
end
end
