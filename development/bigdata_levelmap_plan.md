# BigData level-map manager — Implementation Plan

> **For agentic workers:** implement task-by-task. Steps use `- [ ]` checkboxes. **No git commits**
> (project rule: edit local files only). Each task ends with `check_matlab_code` (must be clean) + an
> MCP verification snippet (must pass) as its checkpoint. Spec: `development/bigdata_levelmap_spec.md`.

**Goal:** Make BigData (`core.MibBigDataLabels`) brush + selection ops (a/s/r/c/f) interactive and
correct at every zoom, with a Save that finalizes the full-res model — by tracking, per coarsest-grid
tile, the finest materialized pyramid level (`matLevel`) and recomputing finer levels lazily on read.

**Architecture:** Edits write the working level + coarser (eager downsample) and set `matLevel`. Reads
serve clean levels directly (no halo) and recompute dirty finer levels from `matLevel` (nearest clean
coarser level), materializing + caching them, viewport-bounded. Save materializes all tiles to level 1.
`matLevel` persists in a side-file (`<store>.levelmap.mat`).

**Tech Stack:** MATLAB R2026a, `io.zarr` facade (native zarrMex), MCP for run/verify.

## Global Constraints (verbatim)

- NEVER run git add/commit/push — edit local files only.
- Use descriptive variable names (no `vp`/`wb`/`fn`).
- `check_matlab_code` must be clean on every changed file (pre-existing warnings excepted).
- Verify via MCP on the real model: `C:\Matlab2\Data\FileFormats\czi\CMU-1.ndpi` opened as BigData.
- Finer = smaller level index; level 1 = full resolution; level N = coarsest. `matLevel(tile)` = finest
  materialized level (`0` = empty). Read rule: `L >= matLevel` → read level L directly; `L < matLevel`
  → recompute tile from `matLevel`, upsample to L, write L, set `matLevel = L`.
- Tile grid = the coarsest level's pixel grid (`[coarseY × coarseX × coarseZ]`).
- `io.zarr.Config.setSmoothing` stays the user default (false); recompute uses nearest resample.

---

## File structure

- `+core/@MibBigDataLabels/MibBigDataLabels.m` — `matLevel` property + helpers; remove dead queue code.
- `+core/@MibBigDataLabels/setData63.m` — write working+coarser, set `matLevel`.
- `+core/@MibBigDataLabels/getData63.m` — matLevel recompute-then-cache read.
- `+core/@MibBigDataLabels/private/` (optional) — none; keep helpers as methods.
- `+models/@MibModel/saveBigDataModel.m` — Save (materialize all → level 1).
- `+controllers/@MibRibbon/model_Callbacks.m` — wire Model→Save for BigData.
- `tests/test_MibBigDataLevelMap.m` — unit tests.

Shared MCP helper used by every verification step (paste inline each time):

```matlab
% --- build a fresh BigData model on CMU-1.ndpi; returns labels object `lb` + dims ---
addpath('C:\Matlab\MIB3\mib'); rehash; io.BioFormats.Config.setLibrary('mib'); io.zarr.Config.setSmoothing(false);
f='C:\Matlab2\Data\FileFormats\czi\CMU-1.ndpi';
o0=struct('datasetMode','BigData','readerFamily','BioFormats','silentMode',true,'ParentFigure',[],'mibPath','C:\Matlab\MIB3\mib');
Ld=io.loaders.BioFormatsVirtualSetupLoader(o0);[mi,fl]=Ld.loadMetadata({f},o0);[img,mi]=Ld.loadImages(fl,mi,o0);
io_=core.MibBigDataImage(img,mi);
sp=fullfile(tempdir,'lmtest.zarr3'); if isfolder(sp); rmdir(sp,'s'); end
if isfile([sp '.levelmap.mat']); delete([sp '.levelmap.mat']); end
bm=core.MibImage.initializeImgInfo('pixSize',io_.pixSize,'Height',io_.height,'Width',io_.width,'Depth',io_.depth,'Time',io_.time,'Colors',1);
lb=core.MibBigDataLabels([],bm); lb.createStore([io_.height,io_.width,io_.depth],sp,io_.pyramid);
H=lb.height; W=lb.width; N=size(lb.modelScaleFactors,1);
```

---

## Task 1 — Remove dead deferred-queue machinery  ·  **Model: Sonnet**

**Files:** Modify `+core/@MibBigDataLabels/MibBigDataLabels.m`, `setData63.m`, `getData63.m`.

**Interfaces:**
- Consumes: nothing.
- Produces: `propagateRegion(packed, fullY, fullX, fullZ, srcLevel, 'coarser')` remains (the only
  propagation kept); `closeStore` no longer references a queue.

- [ ] **Step 1:** In `MibBigDataLabels.m`, delete methods `enqueuePropagation`, `buildFinerJobs`,
  `drainPropagation`, `executeJob`, `refreshDirtyLevels`, `schedulePropagationFlush`,
  `onPropagationTimer`, `stopPropagationTimer`, and `flushPropagation`. Delete the Transient properties
  `deferPropagation`, `propagationDelay`, `drainJobsPerTick`, `drainTickDelay`, `propagationQueue`,
  `dirtyLevels`, `propagationTimer`.
- [ ] **Step 2:** In `closeStore`, remove the `flushPropagation()` and `stopPropagationTimer()` calls
  and the `propagationQueue = {}` line (will be replaced in Task 5). In `delete(obj)`, remove
  `stopPropagationTimer()` (leave the destructor body empty or `% no-op`).
- [ ] **Step 3:** In `setData63.m`, the propagation block currently calls only
  `obj.propagateRegion(subPacked, pfY, pfX, pfZ, levelIdx, 'coarser')` — keep it (already coarser-only
  from the prior change). Confirm no `enqueuePropagation`/`flushPropagation` references remain.
- [ ] **Step 4:** In `getData63.m`, leave the `reconstructFinerFill` call for now (replaced in Task 4);
  confirm no queue/`dirtyLevels` references remain (the earlier flush-on-read block was already removed).
- [ ] **Checkpoint:**
  - `check_matlab_code` on all three files → clean.
  - MCP: `methods('core.MibBigDataLabels')` does NOT contain `enqueuePropagation`/`drainPropagation`/
    `flushPropagation`; a fresh `core.MibBigDataLabels()` constructs without error.

```matlab
m=methods('core.MibBigDataLabels');
assert(~any(ismember({'enqueuePropagation','drainPropagation','flushPropagation','onPropagationTimer'},m)),'dead methods remain');
t=core.MibBigDataLabels(); clear t; disp('Task1 OK');
```

---

## Task 2 — `matLevel` property + tile helpers + side-file persistence  ·  **Model: Sonnet**

**Files:** Modify `+core/@MibBigDataLabels/MibBigDataLabels.m`.

**Interfaces:**
- Produces:
  - property `matLevel` (`uint8 [coarseY × coarseX × coarseZ]`, `0`=empty), Transient.
  - property `levelMapPath` (`char`) — `<storePath>.levelmap.mat`.
  - `[ty0,ty1,tx0,tx1,tz0,tz1] = obj.tilesForFullRegion(fullY, fullX, fullZ)` — full-res region →
    inclusive coarsest-tile index ranges (a tile = one coarsest pixel; map via `modelScaleFactors(N,:)`).
  - `obj.markTiles(fullY, fullX, fullZ, levelIdx)` — set `matLevel(tiles)=levelIdx` where currently
    `0` OR coarser-than/equal-handling: set to `levelIdx` (latest-edit-wins) for all covered tiles.
  - `obj.saveLevelMap()` / `obj.loadLevelMap()` — persist/restore `matLevel` (+ a version field) to
    `levelMapPath`; `loadLevelMap` returns false if missing.
  - `obj.initLevelMapEmpty()` — allocate `matLevel = zeros(coarsestSize,'uint8')`.

- [ ] **Step 1:** Add the two properties (Transient block) with doc comments.
- [ ] **Step 2:** Implement `initLevelMapEmpty`, `tilesForFullRegion`, `markTiles`,
  `saveLevelMap`, `loadLevelMap`:

```matlab
function initLevelMapEmpty(obj)
    cs = obj.modelLevelSizes(end, :);            % coarsest [y x z]
    obj.matLevel = zeros([cs(1), cs(2), max(1,cs(3))], 'uint8');
end

function [ty, tx, tz] = tilesForFullRegion(obj, fullY, fullX, fullZ)
    % full-res region -> inclusive tile (coarsest-pixel) index ranges
    sfN = obj.modelScaleFactors(end, :);         % [yScale xScale zScale] of coarsest
    cs  = obj.modelLevelSizes(end, :);
    ty = [max(1, ceil(fullY(1)/sfN(1))), min(cs(1), ceil(fullY(2)/sfN(1)))];
    tx = [max(1, ceil(fullX(1)/sfN(2))), min(cs(2), ceil(fullX(2)/sfN(2)))];
    tz = [max(1, ceil(fullZ(1)/sfN(3))), min(max(1,cs(3)), ceil(fullZ(2)/sfN(3)))];
end

function markTiles(obj, fullY, fullX, fullZ, levelIdx)
    if isempty(obj.matLevel); obj.initLevelMapEmpty(); end
    [ty, tx, tz] = obj.tilesForFullRegion(fullY, fullX, fullZ);
    obj.matLevel(ty(1):ty(2), tx(1):tx(2), tz(1):tz(2)) = uint8(levelIdx);
end

function saveLevelMap(obj)
    if isempty(obj.levelMapPath) || isempty(obj.matLevel); return; end
    matLevel = obj.matLevel; mapVersion = 1; %#ok<NASGU>
    coarsestSize = obj.modelLevelSizes(end, :); %#ok<NASGU>
    save(obj.levelMapPath, 'matLevel', 'mapVersion', 'coarsestSize', '-v7');
end

function tf = loadLevelMap(obj)
    tf = false;
    if isempty(obj.levelMapPath) || ~isfile(obj.levelMapPath); return; end
    S = load(obj.levelMapPath);
    if isfield(S, 'matLevel') && isequal(size(S.matLevel,1:2), obj.modelLevelSizes(end,1:2))
        obj.matLevel = uint8(S.matLevel); tf = true;
    end
end
```

- [ ] **Checkpoint:** `check_matlab_code` clean. MCP (using the shared helper; store created in Task 5
  not yet wired, so test helpers directly):

```matlab
% (shared helper block) then:
lb.initLevelMapEmpty();
assert(isequal(size(lb.matLevel,1:2), lb.modelLevelSizes(end,1:2)),'matLevel size');
lb.markTiles([1 H],[1 W],[1 1], 3); assert(all(lb.matLevel(:)==3),'markTiles');
lb.levelMapPath=[sp '.levelmap.mat']; lb.saveLevelMap();
lb.matLevel(:)=0; assert(lb.loadLevelMap() && all(lb.matLevel(:)==3),'roundtrip');
disp('Task2 OK'); lb.closeStore();
```

---

## Task 3 — `setData63`: set `matLevel` on write  ·  **Model: Sonnet**

**Files:** Modify `+core/@MibBigDataLabels/setData63.m`.

**Interfaces:** Consumes `markTiles`. Produces: after a write, `matLevel(touched tiles) = levelIdx`.

- [ ] **Step 1:** After the existing `obj.propagateRegion(subPacked, pfY, pfX, pfZ, levelIdx, 'coarser')`
  line, add: `obj.markTiles(pfY, pfX, pfZ, levelIdx);` (using the changed sub-region's full-res ranges
  `pfY/pfX/pfZ` already computed).
- [ ] **Checkpoint:** `check_matlab_code` clean. MCP:

```matlab
% (shared helper) then:
lb.initLevelMapEmpty();
o=struct('magFactor',64,'x',[1 W],'y',[1 H],'z',[1 1],'t',[1 1]); dl=round([H W]/64);
d=uint8(zeros(dl)); d(100:200,100:200)=1; lb.setData63(d,'selection',3,[],o);
% working level for mag 64 = N (coarsest); tiles under the stroke must be marked == that level
lvl=lb.pickLevel(o); tilesSet=nnz(lb.matLevel==lvl);
assert(tilesSet>0,'matLevel not set on write'); fprintf('Task3 OK: %d tiles at level %d\n',tilesSet,lvl);
lb.closeStore();
```

---

## Task 4 — `getData63`: matLevel recompute-then-cache read  ·  **Model: Opus**

**Files:** Modify `+core/@MibBigDataLabels/getData63.m`; delete `reconstructFinerFill` from
`MibBigDataLabels.m`.

**Interfaces:** Consumes `tilesForFullRegion`, `matLevel`, `readPackedLevel`, `writePackedLevel`,
`regionForLevel`, `resizeBlockNearest`. Produces: a read of level `L` over a window returns the model
with finer-dirty tiles recomputed from `matLevel` and cached.

- [ ] **Step 1:** Replace the `reconstructFinerFill` block in `getData63.m` (between the
  `packed = obj.readPackedLevel(...)` and the `packed = reshape(...)` lines) with a call:
  `obj.materializeForRead(levelIdx, physYlim, physXlim, physZlim);`  then re-read:
  `packed = obj.readPackedLevel(levelIdx, physYlim, physXlim, physZlim);`
  (Materialize writes any dirty tiles to `levelIdx` first; then the normal read returns correct data.)
- [ ] **Step 2:** Add `materializeForRead` to `MibBigDataLabels.m`:

```matlab
function materializeForRead(obj, L, Yl, Xl, Zl)
    % Ensure level L holds materialized data over [Yl Xl Zl] (level-L coords) for every
    % non-empty tile. Dirty tiles (matLevel > L) are recomputed by upsampling from their
    % matLevel source, written to L, and marked matLevel=L. Bounded to this window.
    if isempty(obj.matLevel); return; end
    sf = obj.modelScaleFactors(L, :);
    fullY = [(Yl(1)-1)*sf(1)+1, min(Yl(2)*sf(1), obj.height)];
    fullX = [(Xl(1)-1)*sf(2)+1, min(Xl(2)*sf(2), obj.width)];
    fullZ = [(Zl(1)-1)*sf(3)+1, min(Zl(2)*sf(3), obj.depth)];
    [ty, tx, tz] = obj.tilesForFullRegion(fullY, fullX, fullZ);
    win = obj.matLevel(ty(1):ty(2), tx(1):tx(2), tz(1):tz(2));
    srcLevels = unique(win(:));
    srcLevels = srcLevels(srcLevels > L);          % only tiles finer-than-materialized are dirty
    for A = reshape(double(srcLevels),1,[])
        % full-res extent of the dirty tiles with matLevel==A inside this window
        mask = win == A;
        [iy,ix,iz] = ind2sub(size(win), find(mask));
        % tile indices are offset by (ty(1)-1) etc.
        tY = [min(iy)+ty(1)-1, max(iy)+ty(1)-1];
        tX = [min(ix)+tx(1)-1, max(ix)+tx(1)-1];
        tZ = [min(iz)+tz(1)-1, max(iz)+tz(1)-1];
        sfN = obj.modelScaleFactors(end, :);       % coarsest scale = tile size in full-res px
        fY = [(tY(1)-1)*sfN(1)+1, min(tY(2)*sfN(1), obj.height)];
        fX = [(tX(1)-1)*sfN(2)+1, min(tX(2)*sfN(2), obj.width)];
        fZ = [(tZ(1)-1)*sfN(3)+1, min(tZ(2)*sfN(3), obj.depth)];
        % read source level A over fY/fX/fZ, upsample to level L, write L
        [aY,aX,aZ] = obj.regionForLevel(A, fY, fX, fZ);
        src = obj.readPackedLevel(A, aY, aX, aZ);
        [lY,lX,lZ] = obj.regionForLevel(L, fY, fX, fZ);
        tgtSize = [lY(2)-lY(1)+1, lX(2)-lX(1)+1, lZ(2)-lZ(1)+1];
        block = core.MibBigDataLabels.resizeBlockNearest(src, tgtSize);
        obj.writePackedLevel(L, block, lY, lX, lZ);
        % mark those tiles materialized at L
        obj.matLevel(tY(1):tY(2), tX(1):tX(2), tZ(1):tZ(2)) = ...
            min(obj.matLevel(tY(1):tY(2), tX(1):tX(2), tZ(1):tZ(2)), uint8(L));
    end
end
```

  Note: the per-`A` extent uses the tile bounding box (slightly over-materializes within the window;
  acceptable and bounded). `min(...)` preserves an already-finer materialization elsewhere in the box.
- [ ] **Step 3:** Delete the `reconstructFinerFill` static method from `MibBigDataLabels.m`.
- [ ] **Checkpoint (the critical one):** `check_matlab_code` clean. MCP — **halo = 0**, sharpness,
  caching, and durability:

```matlab
% (shared helper) then:
lb.initLevelMapEmpty();
mf=4; lvl=lb.pickLevel(struct('magFactor',mf)); o=struct('magFactor',mf,'x',[1 W],'y',[1 H],'z',[1 1],'t',[1 1]);
dyx=round([H W]/mf);[xx,yy]=meshgrid(1:dyx(2),1:dyx(1));disk=uint8((xx-dyx(2)/2).^2+(yy-dyx(1)/2).^2<=200^2);
lb.setData63(disk,'selection',3,[],o);
back=squeeze(lb.getData63('selection',3,[],o)); diskR=imresize(disk,size(back),'nearest');
halo=nnz(back & ~imdilate(diskR,strel('disk',2)));
fprintf('Task4: halo=%d (must be 0)  agreement=%.1f%%\n',halo,100*nnz(back&diskR)/max(nnz(back),nnz(diskR)));
assert(halo==0,'HALO present');
% zoom-in to full res materializes from working level (no halo), and caches (matLevel decreases)
o1=struct('magFactor',1,'y',[1 4096],'x',[1 4096],'z',[1 1],'t',[1 1]);
s1=squeeze(lb.getData63('selection',3,[],o1)); assert(any(s1(:)),'zoom-in lost the edit');
disp('Task4 OK'); lb.closeStore();
```

---

## Task 5 — Store lifecycle: init / load / save side-file  ·  **Model: Sonnet**

**Files:** Modify `+core/@MibBigDataLabels/MibBigDataLabels.m` (`createStore`, `openStore`,
`closeStore`).

**Interfaces:** Consumes `initLevelMapEmpty`/`loadLevelMap`/`saveLevelMap`. Produces: `levelMapPath`
set; `matLevel` valid after create/open; persisted on close.

- [ ] **Step 1:** In `createStore`, after the levels are built, set
  `obj.levelMapPath = [char(storePath) '.levelmap.mat'];` and `obj.initLevelMapEmpty();`.
- [ ] **Step 2:** In `openStore`, after attaching arrays/levels, set `obj.levelMapPath` and call
  `if ~obj.loadLevelMap(); obj.initLevelMapFallback(); end`. Add `initLevelMapFallback`:

```matlab
function initLevelMapFallback(obj)
    % Old store without a side-file: assume only the coarsest level is materialized
    % (finer levels recompute lazily). Mark tiles that have any data at the coarsest level.
    obj.initLevelMapEmpty();
    cs = obj.modelLevelSizes(end, :);
    coarse = obj.modelArrays{end}.read([1 cs(1)+1; 1 cs(2)+1; 1 max(1,cs(3))+1]);
    coarse = reshape(coarse, cs(1), cs(2), max(1,cs(3)));
    obj.matLevel(coarse ~= 0) = uint8(size(obj.modelLevelSizes,1));   % = N (coarsest)
end
```

- [ ] **Step 3:** In `closeStore`, before dropping handles, call `obj.saveLevelMap();` (replaces the
  removed queue flush).
- [ ] **Checkpoint:** `check_matlab_code` clean. MCP:

```matlab
% (shared helper) then:
o=struct('magFactor',64,'x',[1 W],'y',[1 H],'z',[1 1],'t',[1 1]); dl=round([H W]/64);
d=uint8(zeros(dl)); d(100:200,100:200)=1; lb.setData63(d,'selection',3,[],o);
lb.closeStore(); assert(isfile([sp '.levelmap.mat']),'side-file not written');
lb2=core.MibBigDataLabels([],bm); lb2.openStore(sp);
assert(~isempty(lb2.matLevel) && any(lb2.matLevel(:)>0),'matLevel not restored');
disp('Task5 OK'); lb2.closeStore();
```

---

## Task 6 — Save path (materialize all → level 1) + button wiring  ·  **Model: Sonnet**

**Files:** Create `+models/@MibModel/saveBigDataModel.m`; declare it in `MibModel.m`; modify
`+controllers/@MibRibbon/model_Callbacks.m` (Model→Save case for BigData).

**Interfaces:** Consumes `materializeForRead` (reused to materialize) or a direct loop. Produces:
`obj.saveBigDataModel(id)` → all non-empty tiles materialized to level 1; side-file saved.

- [ ] **Step 1:** Add a `materializeAll` method to `MibBigDataLabels.m` that walks tiles with
  `matLevel > 1` in coarse-grid strips and calls the same recompute as `materializeForRead`, writing
  level 1 (and intermediate levels) so every level is consistent; set `matLevel(non-empty)=1`. Use a
  progress callback argument `pwbFcn` (function handle or `[]`).

```matlab
function materializeAll(obj, pwbFcn)
    if nargin<2; pwbFcn=[]; end
    if isempty(obj.matLevel); return; end
    nT = size(obj.matLevel,1);
    for r = 1:nT                                   % one coarse row of tiles per step (bounded)
        rowLevels = obj.matLevel(r, :, :);
        if all(rowLevels(:)<=1); continue; end
        sfN = obj.modelScaleFactors(end, :);
        fY = [(r-1)*sfN(1)+1, min(r*sfN(1), obj.height)];
        fX = [1, obj.width]; fZ = [1, obj.depth];
        for L = 1:1                                 % materialize down to level 1
            [lY,lX,lZ] = obj.regionForLevel(L, fY, fX, fZ);
            obj.materializeForRead(L, lY, lX, lZ);
        end
        if ~isempty(pwbFcn); pwbFcn(r/nT); end
    end
end
```

- [ ] **Step 2:** Create `+models/@MibModel/saveBigDataModel.m`:

```matlab
function saveBigDataModel(obj, id)
% SAVEBIGDATAMODEL - finalize a BigData model: materialize all pyramid levels + persist the level map.
    if nargin<2; id = obj.getActiveId(); end
    ds = obj.I{id};
    if ~strcmp(ds.datasetType,'BigData') || ~isa(ds.labels,'core.MibBigDataLabels') || ~ds.modelExist
        return;
    end
    wb = uiprogressdlg(obj.getProgressBarParent(),'Value',0,'Title','Save model', ...
        'Message','Finalizing all resolution levels...','Indeterminate','off'); drawnow;
    cleanupWb = onCleanup(@() delete(wb));
    ds.labels.materializeAll(@(p) set(wb,'Value',min(1,p)));
    ds.labels.saveLevelMap();
end
```

- [ ] **Step 3:** Declare `saveBigDataModel(obj, id)` in the methods list of `+models/@MibModel/MibModel.m`.
- [ ] **Step 4:** In `model_Callbacks.m`, the `Save\nmodel` case: when the active dataset is BigData,
  call `obj.mibModel.saveBigDataModel()` instead of the existing `saveLabels` overwrite path (keep the
  existing path for non-BigData). Place the branch at the top of the Save case.
- [ ] **Checkpoint:** `check_matlab_code` clean on all three. MCP (headless materializeAll):

```matlab
% (shared helper) then:
o=struct('magFactor',64,'x',[1 W],'y',[1 H],'z',[1 1],'t',[1 1]); dl=round([H W]/64);
d=uint8(zeros(dl)); d(100:300,100:300)=1; lb.setData63(d,'selection',3,[],o);
lb.materializeAll([]);
assert(all(lb.matLevel(lb.matLevel>0)==1),'not all materialized to level 1');
% level 1 now holds the edit directly (read without recompute path changing it)
s1=squeeze(lb.getData63('selection',3,[],struct('pyramidLevel',1,'y',[1 4096],'x',[1 4096],'z',[1 1],'t',[1 1])));
assert(any(s1(:)),'level1 empty after save'); disp('Task6 OK'); lb.closeStore();
```

---

## Task 7 — End-to-end MCP verification (halo, ops, save/reopen, bounded)  ·  **Model: Opus**

**Files:** Create `development/verify_levelmap.m` (an MCP-runnable script; not a unit test).

**Interfaces:** Consumes the full stack.

- [ ] **Step 1:** Write `verify_levelmap.m` asserting, on CMU-1.ndpi:
  1. Paint at a non-coarsest level → `halo == 0`; readback at the painting zoom == drawn (exact).
  2. Zoom-in materializes (matLevel decreases for the viewport) and a second read does NOT recompute
     (instrument: matLevel unchanged on the 2nd read).
  3. a/s/r/c/f sequence at low mag (mimic `moveLayers`): add material 1, read labels==material 1 only;
     paint selection over material → material unchanged; clear → selection 0.
  4. `materializeAll` then reopen via side-file → all levels read directly, edit preserved; delete the
     side-file → `openStore` falls back without error and the coarse edit still reads.
  5. Bounded cost: a 2% stroke `setData63` < 50 ms; peak `memory` delta < 50 MB.
- [ ] **Step 2:** Run it via MCP `run_matlab_file`; all asserts pass.
- [ ] **Checkpoint:** script prints `ALL LEVELMAP CHECKS PASSED`.

---

## Task 8 — Unit tests  ·  **Model: Sonnet**

**Files:** Create `tests/test_MibBigDataLevelMap.m` (MATLAB `matlab.unittest` style, mirroring existing
`tests/` patterns).

**Interfaces:** Consumes the full stack.

- [ ] **Step 1:** Test cases (each builds a small BigData model in `tempdir`, tears down in `TestMethodTeardown`):
  - `testWriteSetsMatLevel`, `testReadCleanLevelNoHalo`, `testZoomInRecomputeAndCache`,
    `testSaveMaterializesAll`, `testSideFileRoundTrip`, `testFallbackWhenSideFileMissing`,
    `testClearSelectionAtLowMag`, `testAddMaterialAtLowMag`.
  Use the assertions from Tasks 3–6 checkpoints as the test bodies (real code, not placeholders).
- [ ] **Step 2:** Run via MCP `run_matlab_test_file` on the file → all pass.
- [ ] **Checkpoint:** test summary shows 0 failed, 0 incomplete.

---

## Task 9 — Remove `reconstructFinerFill` remnants + docs  ·  **Model: Sonnet**

**Files:** `+core/@MibBigDataLabels/getData63.m` (confirm no `reconstructFinerFill` ref),
`+models/@MibModel/createModel.m` (explainer), `development/bigdata_brush_performance.md` +
`development/bigdata_levelmap_spec.md` (status).

- [ ] **Step 1:** Grep the repo for `reconstructFinerFill` → no references remain (method already
  deleted in Task 4; confirm).
- [ ] **Step 2:** Update the `createModel` BigData explainer to mention that lower zoom levels are
  reconstructed on demand and that **Save** finalizes the full-resolution model.
- [ ] **Step 3:** Mark `bigdata_levelmap_spec.md` status = IMPLEMENTED; add a one-line pointer + outcome
  to `bigdata_brush_performance.md`.
- [ ] **Checkpoint:** `check_matlab_code` clean; `grep -r reconstructFinerFill mib` empty.

---

## Self-review notes (done)

- **Spec coverage:** matLevel (T2), eager-coarse+mark (T3), recompute-then-cache read incl. halo=0 (T4),
  side-file + fallback (T2/T5), Save + button (T6), ops correctness (T7/T8), dead-code removal (T1/T9),
  model-type extensibility = out-of-scope per spec. All covered.
- **Placeholders:** none — code shown for every code step; assertions are real.
- **Type consistency:** `matLevel`, `markTiles`, `tilesForFullRegion`, `materializeForRead`,
  `materializeAll`, `saveLevelMap`/`loadLevelMap`, `initLevelMapEmpty`/`initLevelMapFallback`,
  `levelMapPath`, `saveBigDataModel(obj,id)` — names consistent across tasks.
