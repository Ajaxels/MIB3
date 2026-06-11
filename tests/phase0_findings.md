# Phase 0 — Headless Spike Findings

Date: 2026-06-11. Spike script: `tests\phase0_spike.m` (re-runnable).
Answers the four [VERIFY] questions from `plan_unittests.md` §4.

## Verdict: headless testing is fully viable — all 12 spike checks PASS, 0 figures created.

Run 1: user's interactive MATLAB session (desktop, MIB paths pre-loaded) — 12/12 PASS.
Run 2: clean `matlab -batch` session, only `mib\` added to path — **12/12 PASS, 0 figures**.

## Answers to the [VERIFY] questions

### 1. Does `models.MibModel(...)` construct headlessly?

**Yes, but `mibPath` MUST be passed explicitly:**

```matlab
mibModel = models.MibModel(1, fullfile(repoRoot, 'mib'));
```

- With the no-arg default (`mibPath=''`), construction **fails in a clean session** with
  `Unable to find file "assets\images\default.png"`: `datasetsSetsOps.m` (line ~125-126) does
  `imread(fullfile(obj.mibPath, 'assets', 'images', 'default.png'))` for each of the 10 dummy
  datasets, and an empty `mibPath` yields a relative path that only resolves by accident in an
  interactive session. **`MibPathFixture`/`buildSyntheticModel` must always pass the absolute
  `mib\` folder as `mibPath`.** `utils.getInstallationPath` is NOT needed.
- `initialize()` → `initializePreferences()` loads prefs from `C:\Users\<user>\Matlab\mib3.mat`
  (prints `MIB parameters file: ...`); no dialogs in that code path.
- `datasetsSetsOps('Add set')` creates 10 dummy datasets (`numel(I)==10`) and fires `notify`
  events — harmless headless no-ops since no controllers/listeners exist. Dummy dataset creation
  reads `preferences.System.EnableSelection` and `preferences.Colors.*` — irrelevant for tests
  because tests replace `I{id}` with their own datasets.

### 2. Does `getActiveId()` work headlessly?

**Yes** — returns `1` right after construction (`Sets` struct fully initialized by
`datasetsSetsOps`). Tests should still always pass explicit `options.id`.

**Bonus:** `getRGBimage(struct('blockModeSwitch',0,'resizeToMagnification',true))` also works
headlessly (returned `[64 48 3]`), even with `axesX/axesY == NaN`. The display-path perf test can
stay in the suite — no GUI guard needed.

### 3. How to build the 255- and 65535-material models headlessly

**Use `MibDataset.createModel(modelTypeNumeric)`** — it reinitializes the labels layer with the
right class and auto-converts mask/selection between packed/separate representations:

```matlab
% labels63 (packed uint8: bits 1-6 material, 7 mask, 8 selection)
mibModel.I{id} = core.MibDataset(imageVolume, dictionary(), 'Standard', 'labels63');

% 255-material (separate layers, uint8) — verified: class core.MibLabels, data uint8, maxMaterials 255
mibModel.I{id} = core.MibDataset(imageVolume, dictionary(), 'Standard', 'labels63');
mibModel.I{id}.createModel(255);     % mask/selection become separate core.MibLabels layers

% 65535-material (separate layers, uint16) — verified: data uint16, maxMaterials 65535,
% roundtrips values > 255 (tested with 30000)
mibModel.I{id} = core.MibDataset(imageVolume, dictionary(), 'Standard', 'labels63');
mibModel.I{id}.createModel(65535);
```

After each: `updateBoundingBox([], [0 0 0])`, then
`mibModel.setData3D(labelVolume, 'labels', 1, 3, [], struct('id', id, 'blockModeSwitch', 0))`
(uint8 for ≤255, uint16 for 65535). All get/set roundtrips verified for image / labels / mask /
selection / 'everything' (labels63 only), including direct packed-bit verification.

Note: constructor `modelType='labels'` (`core.MibDataset(..., 'labels')`) allocates
`zeros(size(img),'uint8')` — i.e. labels shaped like the *image* including its color dim, and only
uint8. **Prefer the `'labels63'` + `createModel(N)` sequence above**; it is what the app itself
uses and produces correctly-shaped `[h w z 1 t]` label layers.

### 4. Which `mib\external\*` folders are needed on the path?

For the **model layer** (MibModel + core classes + get/set/getRGBimage): **only `mib\` itself** —
confirmed by the clean `matlab -batch` run, where the spike adds nothing but
`addpath(fullfile(repoRoot,'mib'))` and everything passes. IO round-trip tests (Phase 2) will
additionally need the loader-specific folders (`external\bioformats`, `external\nrrd`,
`external\Zarr3Matlab`, ...) — add to `MibPathFixture` when those tests land.

## Side observations for Phase 1

- `findall(0,'Type','figure')` before/after is a usable "no GUI side effects" assertion.
- Preferences are read from the *user's* `mib3.mat` — tests inherit user preferences
  (e.g. Undo settings). For determinism, tests that depend on preferences should set the relevant
  `mibModel.preferences.*` fields explicitly after construction.
- Non-square synthetic volumes (`[64 48 16]`) caught nothing this time but keep them — they would
  expose height/width swaps that square volumes hide.

## Clean-session run (matlab -batch)

Command: `matlab -batch "cd('...\tests'); phase0_spike();"` — exit code 0.
(Originally run from `development\unittests\`; files later moved to `tests\` and the spike's
repo-root derivation updated accordingly — re-verified from the new location.)

```
=== Phase 0 spike results ===
[PASS] MibModel() constructs headlessly              numel(I)=10, id=1
[PASS] labels63 image roundtrip
[PASS] labels63 labels roundtrip
[PASS] labels63 mask roundtrip
[PASS] labels63 selection roundtrip
[PASS] labels63 bit packing matches                  labels class=core.MibLabels63, maxMaterials=63
[PASS] labels63 everything == packed
[PASS] createModel(255) -> uint8 model roundtrip     class(labels)=core.MibLabels, data class=uint8, maxMaterials=255
[PASS] type-255 separate mask layer roundtrip        mask class=core.MibLabels
[PASS] createModel(65535) -> uint16 model roundtrip  class(labels)=core.MibLabels, data class=uint16, maxMaterials=65535
[PASS] getActiveId() works headlessly                activeId=1
[PASS] getRGBimage() headless                        size=[64 48 3]
Figures created during run: 0 (before=0, after=0)
```

(First clean-session attempt with `models.MibModel()` and empty `mibPath` failed at construction —
see question 1. The fix is baked into `phase0_spike.m`.)

## Conclusion for Phase 1

All four [VERIFY] questions are resolved; no blockers. Phase 1 can be implemented exactly as
planned (a Sonnet-class session is sufficient), with these two adjustments already known:
1. `buildSyntheticModel` must call `models.MibModel(1, mibFolder)` (absolute path to `mib\`).
2. Build the 3 model flavors as: `'labels63'` constructor; then `createModel(255)` or
   `createModel(65535)` for the layered variants (never the `'labels'` constructor modelType).
