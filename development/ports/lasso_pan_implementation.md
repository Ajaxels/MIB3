# Implementation Plan: Custom Polyline Vertex Placement for Lasso Tool

## Problem

MATLAB UIFigure's `drawpolygon` has 3 stages:
1. **Placement** — left-click adds vertices
2. **Adjustable** — vertices can be dragged, but no new vertices via clicking
3. **Accepted** — double-click finalizes

Right-click during Stage 1 causes `drawpolygon` to silently transition to Stage 2. MIB uses right-click for panning. Result: user can't pan during polygon vertex placement without losing the ability to add more points.

There is **no MATLAB API** to re-enter Stage 1 after it exits. `drawpolygon(axH, 'Position', verts)` always opens in Stage 2.

## Solution

Replace `drawpolygon(axH)` (Stage 1 only) for the **Polyline** lasso type with custom click-based vertex collection using `uiwait`/`uiresume` integrated into MIB's existing callback architecture. Since we never call `drawpolygon` during placement, right-click pan works normally. After custom placement, `drawpolygon(axH, 'Position', verts)` opens in Stage 2 for fine-tuning, then `wait(roi)` handles Stage 3 acceptance.

## How It Works

During custom placement, `segmentationLasso` calls `uiwait(hFig)` which blocks while processing MATLAB events via `drawnow`. When the user clicks:
- **Left-click** → `gui_WindowButtonDownFcn` fires → detects `placementMode` → adds vertex to `placementVertices` → updates line visual → returns
- **Right-click** → `gui_WindowButtonDownFcn` fires → `operation='pan'` path runs normally (lines 111–320) → pan gesture works → `gui_WindowButtonUpFcn` restores callbacks → placement continues
- **Double-click** → intercepted before operation determination → calls `uiresume(hFig)` → `uiwait` unblocks → `segmentationLasso` continues to Stage 2
- **Enter** → `gui_WindowKeyPressFcn` → calls `uiresume(hFig)`
- **Escape** → `gui_WindowKeyPressFcn` → clears vertices → calls `uiresume(hFig)` → cancellation

---

## Implementation Steps (7 files, implement in this order)

---

### Step 1: `mib/+controllers/@MibRoi/MibRoi.m`

**Goal:** Add new fields to `drawingROI` struct, remove `panRestartPending`.

**Line 60 — Replace the struct initialization:**

OLD:
```matlab
obj.drawingROI = struct('active', false, 'roi', [], 'type', '', 'dataPos', [], 'repositioning', false, 'panRestartPending', false);
```

NEW:
```matlab
obj.drawingROI = struct('active', false, 'roi', [], 'type', '', 'dataPos', [], ...
    'repositioning', false, 'placementMode', false, ...
    'placementVertices', [], 'placementLine', []);
```

**Lines 13–18 (property docblock) — Add documentation for new fields:**

Add to the `drawingROI` property comment:
```
%   .placementMode    - logical, true during custom Polyline Stage 1 vertex collection
%   .placementVertices - [Nx2 double] data-pixel vertices collected during custom placement
%   .placementLine    - handle to line object visualizing polygon outline during placement
```

**In the methods declaration block (around lines 28–35) — Add new method declaration:**

```matlab
updatePlacementLine(obj, axH)  % update polygon outline during custom Polyline placement
```

---

### Step 2: `mib/+controllers/@MibRoi/updatePlacementLine.m` — NEW FILE

Create this new external method file:

```matlab
function updatePlacementLine(obj, axH)
% UPDATEPLACEMENTLINE - Update polygon outline during custom Polyline placement.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updatePlacementLine(axH)
%
% Converts data-pixel vertices stored in ``obj.drawingROI.placementVertices``
% to current axes coordinates and creates or updates the placement line
% object on the given axes.
%
% Input Arguments:
%   - **axH** — handle to the image axes (``imViewAxes``)
%
% Output Arguments:
%   (none)
%

vertices = obj.drawingROI.placementVertices;
if isempty(vertices)
    if ~isempty(obj.drawingROI.placementLine) && isvalid(obj.drawingROI.placementLine)
        delete(obj.drawingROI.placementLine);
    end
    obj.drawingROI.placementLine = [];
    return;
end

[axX, axY] = obj.mibModel.convertDataToMouseCoordinates(vertices(:,1), vertices(:,2), 'shown');

% Close the polygon for display (connect last vertex back to first)
if size(axX, 1) >= 2
    plotX = [axX(:); axX(1)];
    plotY = [axY(:); axY(1)];
else
    plotX = axX(:);
    plotY = axY(:);
end

lineH = obj.drawingROI.placementLine;
if isempty(lineH) || ~isvalid(lineH)
    lineH = line(axH, plotX, plotY, ...
        'Color', [0 0.447 0.741], 'LineWidth', 1.5, 'LineStyle', '-', ...
        'Marker', 'o', 'MarkerSize', 6, 'MarkerFaceColor', [0 0.447 0.741], ...
        'Tag', 'polylinePlacement', 'HitTest', 'off', 'PickableParts', 'none');
    obj.drawingROI.placementLine = lineH;
else
    lineH.XData = plotX;
    lineH.YData = plotY;
end

end
```

---

### Step 3: `mib/+controllers/@MibImageDocument/segmentationLasso.m` — Major rewrite

**Goal:** Replace the broken `while true` restart loop (lines 73–150) with custom placement for Polyline and simple draw+wait for other types.

#### What to remove

Remove lines 73–150 (the `while true` loop + post-loop cleanup). This includes:
- The comment about pan-restart (lines 73–78)
- The `while true` loop (lines 78–145)
- Post-loop listener cleanup (lines 147–150)

#### What to replace with

Replace with this code (insert at line 73):

```matlab
if strcmp(type, 'Polyline')
    %% Custom Stage 1: collect vertices via clicks with right-click pan support
    % drawpolygon exits placement mode on right-click (UIFigure limitation).
    % Instead of using drawpolygon for Stage 1, we collect vertices manually
    % via gui_WindowButtonDownFcn (which handles left-click as vertex addition
    % when placementMode is true) and use uiwait/uiresume for synchronization.
    % Right-click pan works normally because we never call drawpolygon here.

    cRoi.drawingROI.type              = drawingROIType;  % 'Polygon'
    cRoi.drawingROI.active            = true;
    cRoi.drawingROI.placementMode     = true;
    cRoi.drawingROI.placementVertices = zeros(0, 2);
    cRoi.drawingROI.placementLine     = [];
    cRoi.drawingROI.dataPos           = [];
    cRoi.drawingROI.roi               = [];

    % Capture the initial click position as the first vertex
    pt = axH.CurrentPoint;
    [dataX, dataY] = obj.mibModel.convertMouseToDataCoordinates(pt(1,1), pt(1,2), 'shown');
    cRoi.drawingROI.placementVertices = [dataX, dataY];
    cRoi.drawingROI.dataPos           = cRoi.drawingROI.placementVertices;
    cRoi.updatePlacementLine(axH);

    % Block until double-click, Enter, or Escape calls uiresume
    uiwait(hFig);

    % Retrieve collected vertices and clean up placement state
    placementVertices = cRoi.drawingROI.placementVertices;
    if ~isempty(cRoi.drawingROI.placementLine) && isvalid(cRoi.drawingROI.placementLine)
        delete(cRoi.drawingROI.placementLine);
    end
    cRoi.drawingROI.placementLine     = [];
    cRoi.drawingROI.placementVertices = [];
    cRoi.drawingROI.placementMode     = false;

    % Check if cancelled or not enough vertices for a polygon
    if isempty(placementVertices) || size(placementVertices, 1) < 2
        cRoi.drawingROI.active = false;
        obj.mibModel.disableSegmentation = false;
        hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
        hFig.Pointer = 'crosshair';
        return;
    end

    %% Stage 2: create adjustable drawpolygon with collected vertices
    [axX, axY] = obj.mibModel.convertDataToMouseCoordinates( ...
        placementVertices(:,1), placementVertices(:,2), 'shown');
    roi = drawpolygon(axH, 'Position', [axX(:), axY(:)]);

    if isvalid(roi)
        captureF  = @() captureSegLassoDataPos(roi, drawingROIType, cRoi, obj.mibModel);
        movingLsn = addlistener(roi, 'MovingROI', @(~,~) captureF());
        movedLsn  = addlistener(roi, 'ROIMoved',  @(~,~) captureF());
        captureF();   % capture initial position
        cRoi.drawingROI.roi    = roi;
        cRoi.drawingROI.active = true;
    end

    %% Stage 3: wait for acceptance (double-click) or cancellation (Escape)
    try
        wait(roi);
    catch
        % user cancelled or error during Stage 2/3
    end

    if ~isempty(movingLsn); delete(movingLsn); end
    if ~isempty(movedLsn);  delete(movedLsn);  end
    cRoi.drawingROI.active = false;

else
    %% Non-Polyline types: use standard interactive draw + wait
    movingLsn = [];
    movedLsn  = [];
    try
        switch type
            case 'Lasso'
                roi = drawfreehand(axH, 'Closed', true);
            case 'Rectangle'
                roi = drawrectangle(axH);
            case 'Ellipse'
                roi = drawellipse(axH);
            otherwise
                roi = drawfreehand(axH, 'Closed', true);
        end
        if isvalid(roi)
            captureF  = @() captureSegLassoDataPos(roi, drawingROIType, cRoi, obj.mibModel);
            movingLsn = addlistener(roi, 'MovingROI', @(~,~) captureF());
            movedLsn  = addlistener(roi, 'ROIMoved',  @(~,~) captureF());
            captureF();   % capture initial position
            if ~isempty(cRoi)
                cRoi.drawingROI.roi    = roi;
                cRoi.drawingROI.active = true;
            end
        end
        wait(roi);
    catch
        % user cancelled or error during drawing
        if ~isempty(movingLsn); delete(movingLsn); end
        if ~isempty(movedLsn);  delete(movedLsn);  end
        if ~isempty(cRoi); cRoi.drawingROI.active = false; end
        obj.mibModel.disableSegmentation = false;
        hFig.WindowButtonDownFcn = @(~, ~) obj.gui_WindowButtonDownFcn();
        hFig.Pointer = 'crosshair';
        return;
    end

    if ~isempty(movingLsn); delete(movingLsn); end
    if ~isempty(movedLsn);  delete(movedLsn);  end
    if ~isempty(cRoi); cRoi.drawingROI.active = false; end
end
```

**IMPORTANT:** The code AFTER this block (starting at the current line 152 `% check if ROI is valid...`) stays **unchanged**. It handles ROI vertex extraction, poly2mask, backup, and mask writing for all types.

---

### Step 4: `mib/+controllers/@MibImageDocument/gui_WindowButtonDownFcn.m` — Three changes

#### Change A: Double-click interception

**Insert after line 43** (`if ~obj.isInsideAxes; return; end`) and **before line 46** (the `if obj.mibModel.preferences.System.LeftMouseButton...` block):

```matlab
% Custom Polyline placement: double-click finishes vertex collection
if strcmp(seltype, 'open')
    if obj.mibModel.disableSegmentation
        cRoiCtrl = obj.mibController.cRoi;
        if ~isempty(cRoiCtrl) && cRoiCtrl.drawingROI.placementMode
            uiresume(hFig);
        end
    end
    return;
end
```

Then **remove** the `case 'open'` entries from both switch blocks:
- Remove lines 67–68: `case 'open' % double click` + `return`
- Remove lines 85–86: `case 'open' % double click` + `return`

(The new code above handles ALL double-clicks before the switch is reached.)

#### Change B: Left-click vertex addition

**Replace line 323:**

OLD:
```matlab
if obj.mibModel.disableSegmentation; return; end
```

NEW:
```matlab
if obj.mibModel.disableSegmentation
    % During custom Polyline placement, left-click adds a vertex
    cRoiCtrl = obj.mibController.cRoi;
    if ~isempty(cRoiCtrl) && cRoiCtrl.drawingROI.placementMode
        [dataX, dataY] = obj.mibModel.convertMouseToDataCoordinates(xy(1,1), xy(1,2), 'shown');
        cRoiCtrl.drawingROI.placementVertices(end+1, :) = [dataX, dataY];
        cRoiCtrl.drawingROI.dataPos = cRoiCtrl.drawingROI.placementVertices;
        cRoiCtrl.updatePlacementLine(obj.handles.imViewAxes);
    end
    return;
end
```

#### Change C: Placement line repositioning during pan

In the pan ROI-reposition section (lines 264–310), the code currently checks:

```matlab
if ~isempty(roiH) && isvalid(roiH) && ~isempty(dp)     % line 270
```

**Replace line 270 with:**
```matlab
hasStandardROI = ~isempty(roiH) && isvalid(roiH) && ~isempty(dp);
hasPlacementLine = ~isempty(drawInfo.placementLine) && isvalid(drawInfo.placementLine) && ~isempty(drawInfo.placementVertices);
if hasStandardROI || hasPlacementLine
```

Then **after line 305** (`roiH.Position = [Xax(:), Yax(:)];` in the `otherwise` case) and the corresponding `end` of the switch block, but **before** line 306 (`catch`), add:

```matlab
            % Reposition placement line for custom Polyline Stage 1
            if hasPlacementLine
                pverts = drawInfo.placementVertices;
                pX = toX(pverts(:,1));
                pY = toY(pverts(:,2));
                if numel(pX) >= 2
                    drawInfo.placementLine.XData = [pX(:); pX(1)];
                    drawInfo.placementLine.YData = [pY(:); pY(1)];
                else
                    drawInfo.placementLine.XData = pX(:);
                    drawInfo.placementLine.YData = pY(:);
                end
            end
```

**Note:** The `if hasStandardROI` guard should wrap the existing switch block (lines 285–305) so it only runs when there's a real ROI handle:

```matlab
if hasStandardROI || hasPlacementLine
    obj.mibController.cRoi.drawingROI.repositioning = true;
    try
        % ... existing toX/toY definitions (lines 273-283) ...
        if hasStandardROI
            switch drawInfo.type
                % ... existing Rectangle/Ellipse/otherwise cases (lines 285-305) ...
            end
        end
        if hasPlacementLine
            % ... new placement line repositioning code above ...
        end
    catch
    end
    obj.mibController.cRoi.drawingROI.repositioning = false;
end
```

---

### Step 5: `mib/+controllers/@MibController/gui_WindowKeyPressFcn.m` — Enter and Escape

In the `else` block (starting at line 376: `else % all other possible shortcuts`), there is a `switch char` statement. Add two cases.

#### Add `case 'return'` — insert BEFORE `case 'escape'` (before line 378):

```matlab
        case 'return'
            % Finish custom Polyline Stage 1 placement on Enter
            if obj.mibModel.disableSegmentation
                cRoiCtrl = obj.cRoi;
                if ~isempty(cRoiCtrl) && cRoiCtrl.drawingROI.placementMode
                    uiresume(cImageDoc.UIFigure);
                    return;
                end
            end
```

#### Modify `case 'escape'` (line 378) — add active code before the existing comments:

```matlab
        case 'escape'
            % Cancel custom Polyline Stage 1 placement on Escape
            if obj.mibModel.disableSegmentation
                cRoiCtrl = obj.cRoi;
                if ~isempty(cRoiCtrl) && cRoiCtrl.drawingROI.placementMode
                    cRoiCtrl.drawingROI.placementVertices = [];  % signal cancellation
                    uiresume(cImageDoc.UIFigure);
                    return;
                end
            end
            % % detect escape when modifying the measurements...  (existing comments stay)
```

---

### Step 6: `mib/+controllers/@MibImageDocument/gui_WindowButtonUpFcn.m` — Remove broken logic

**Delete the entire panRestartPending block** (lines 157–178). This is the block starting with the comment `% Polyline pan-restart: right-clicking to pan in UIFigure...` through the closing `end` of the outer `if obj.mibModel.disableSegmentation` block.

The block to remove (exact current content):
```matlab
% Polyline pan-restart: right-clicking to pan in UIFigure also causes
% drawpolygon to exit placement mode (can no longer click to add vertices).
% Detect this here (pan just ended, disableSegmentation is still true) and
% call uiresume so that wait(roi) returns in segmentationLasso, which then
% deletes the roi itself and re-opens drawpolygon with the saved vertices.
% IMPORTANT: do NOT call delete(roi) here. Deleting a roi inside a drawnow
% callback while wait(roi)/uiwait is blocking leaves the roi's WindowKeyRelease
% listener attached to the figure as a zombie; pressing Enter afterward
% fires that listener on the deleted roi and throws "Invalid or deleted object".
% Calling uiresume instead unblocks wait() cleanly so it can remove its own
% listeners before returning.
if obj.mibModel.disableSegmentation
    cRoiCtrl = obj.mibController.cRoi;
    if ~isempty(cRoiCtrl) && strcmp(cRoiCtrl.drawingROI.type, 'Polygon') && cRoiCtrl.drawingROI.active
        roiHandle = cRoiCtrl.drawingROI.roi;
        if ~isempty(roiHandle) && isvalid(roiHandle)
            cRoiCtrl.drawingROI.panRestartPending = true;
            cRoiCtrl.drawingROI.active = false;   % suppress repositionDrawingROI in showImage
            uiresume(obj.UIFigure);  % unblock wait(roi) without deleting it
        end
    end
end
```

---

### Step 7: `mib/+controllers/@MibRoi/repositionDrawingROI.m` — Handle placement line

**Replace lines 27–29:**

OLD:
```matlab
roi = obj.drawingROI.roi;
if isempty(roi) || ~isvalid(roi); return; end
if isempty(obj.drawingROI.dataPos); return; end
```

NEW:
```matlab
roi = obj.drawingROI.roi;
hasRoi = ~isempty(roi) && isvalid(roi) && ~isempty(obj.drawingROI.dataPos);
hasPlacement = ~isempty(obj.drawingROI.placementLine) && ...
    isvalid(obj.drawingROI.placementLine) && ~isempty(obj.drawingROI.placementVertices);
if ~hasRoi && ~hasPlacement; return; end
```

**Wrap the existing `switch` block (lines 36–66) in `if hasRoi`:**

```matlab
if hasRoi
    % (existing lines 36-66 go here, indented one level)
end
```

**Add placement line handling after the `if hasRoi` block, before the `catch` on line 67:**

```matlab
if hasPlacement
    axH = obj.drawingROI.placementLine.Parent;
    obj.updatePlacementLine(axH);
end
```

---

## Verification Checklist

1. **Basic Polyline**: Lasso/Polyline → click 4+ vertices → vertices displayed as polygon outline → double-click → adjustable polygon appears (Stage 2) → double-click to accept → selection mask created
2. **Enter to finish**: Place vertices → press Enter → Stage 2 → accept
3. **Escape to cancel**: Place vertices → press Escape → no selection, cursor restored to crosshair
4. **Pan during placement**: Place 2 vertices → right-click drag to pan → release → vertices still at correct positions → left-click to add more → accept
5. **Zoom during placement**: Place vertices → scroll wheel zoom → vertices reposition correctly → add more → accept
6. **Multiple pans**: Pan, add vertex, pan again, add vertex, accept — all vertices correct
7. **Other types unchanged**: Test Lasso (freehand), Rectangle, Ellipse — all work as before
8. **Stage 2 pan**: After placement, in adjustable mode → right-click pan → polygon repositions → double-click accept
9. **<2 vertices + finish**: Click once → double-click immediately → cancelled (needs ≥2 vertices)
10. **No `panRestartPending` errors**: Grep codebase for `panRestartPending` — should only appear in MibRoi.m struct comment (removed from all other files)

## Key Coordinate Systems

- **Data coordinates**: pixel positions in the full dataset (e.g., pixel 500,300 in a 1024x1024 image). Stored in `drawingROI.placementVertices` and `drawingROI.dataPos`.
- **Axes coordinates**: positions in the MATLAB axes space (affected by zoom, pan, aspect ratio). Used for display (line XData/YData, ROI Position).
- Convert: `mibModel.convertMouseToDataCoordinates(axX, axY, 'shown')` — axes → data
- Convert: `mibModel.convertDataToMouseCoordinates(dataX, dataY, 'shown')` — data → axes
- During pan, the axes coordinate system changes (image reloaded at different scale). Placement vertices are stored in DATA coordinates so they survive pan/zoom. The line visual is updated by converting data→axes after each coordinate system change.
