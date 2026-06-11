# MIB3 Unit-Test & Performance-Benchmark System — Implementation Plan

> **Location:** this plan and its artifacts live in `tests\` (repo root), alongside the test code
> they describe (`plan_unittests.md`, `phase0_findings.md`, `phase0_spike.m`).
> **Status:** approved strategy. **Phase 0 complete (2026-06-11, all checks pass)** — see
> `phase0_findings.md`. Next: Phase 1.
> **Audience:** this document is written so that any model/developer can implement it phase by phase
> without re-deriving the design. Follow it literally; where a fact must be verified at runtime it is
> marked **[VERIFY]** with exact instructions.
>
> **Decisions recorded 2026-06-11 (do not re-ask):**
> 1. Perf regressions are detected automatically against **committed machine-keyed baselines** (JSON),
>    thresholds: ≤15 % slower = pass, 15–30 % = warning, >30 % = fail.
> 2. Downloaded demo datasets are cached in **`%LOCALAPPDATA%\MIB3\testData`**
>    (override with env var `MIB3_TEST_DATA_DIR`).
> 3. Phases are landed one at a time, each independently reviewable.

## 0. Model guidance — read this first

**Protocol: at the START of work on any phase, Claude must (a) state which model is recommended
for that phase (table below), (b) state which model is currently running, and (c) if the current
model is weaker than recommended, warn the user and ask whether to proceed or switch (`/model`).**

| Phase | Recommended model | Why |
|---|---|---|
| ~~0 — headless spike~~ | ~~Opus/Fable~~ | DONE (Fable 5) — open-ended debugging of unknowns |
| 1 — infra + get/set tests | **Sonnet** | transcription of complete skeletons + checklist-gated verification |
| 2 — real data + IO round-trips | **Sonnet**; escalate to Opus/Fable if stuck on loader/saver APIs | data fixture is fully specified; IO factory APIs need some discovery |
| 3 — core operations tests | **Sonnet** | same pattern as Phase 1, established conventions |
| 4 — porting-workflow tests | model doing the port (any) | tests land together with each ported method |
| 5 — GUI smoke + CI | **Sonnet** | small, well-bounded |
| Reviews | **Opus/Fable** | review each phase's diff (`/code-review`) before commit |

Quality is gated by each phase's **verification checklist** (incl. mutation tests), not by the
model: a phase is done only when its checklist passes in a fresh MATLAB session.

---

## 1. Goal

One `matlab.unittest`-based system that:

1. catches **correctness regressions** in headless-testable code (core, models, io, utils);
2. tracks **performance** of hot paths (e.g. `getData2D/3D/4D`, `setData2D/3D/4D`, `getRGBimage`)
   against committed baselines, so a slowdown shows up as a failing/warning test;
3. uses **real example datasets** (Trypanosoma + model, Huh7 + model) as integration/perf fixtures,
   downloaded once and cached;
4. **streamlines the MIB2→MIB3 port**: every newly ported method lands together with a test.

---

## 2. Verified background facts (do NOT re-explore, but [VERIFY] items in Phase 0)

- Repo root: `C:\MATLAB\MIB_CONVERSION\MIB3`; sources under `mib\` (packages `+core`, `+models`,
  `+controllers`, `+io`, `+utils`, `+views`; externals under `mib\external\`).
- There is currently **no** `buildfile.m`, **no** `tests\` folder, **no** MATLAB CI.
  The `buildtool check|test` commands mentioned in the root `CLAUDE.md` must be *created* by this plan.
- `models.MibModel(cpuParallelLimitMax, mibPath, mibVersion)` — all args optional, constructor calls
  `obj.initialize()` only. **VERIFIED headless-safe (Phase 0, 12/12 checks, 0 figures) — but
  `mibPath` MUST be the absolute path to `mib\`**, e.g. `models.MibModel(1, mibFolder)`; with empty
  `mibPath`, `datasetsSetsOps` fails to `imread` `assets\images\default.png` in a clean session.
  See `phase0_findings.md`.
- `core.MibDataset(img, meta, datasetType, modelType)` builds a dataset from a plain numeric array:
  - `img` — `[h, w, depth, colors, time]` numeric array (a `[h w z 1]` uint8 volume is fine);
  - `meta` — `dictionary()` is acceptable;
  - `datasetType` — `'Standard'` for tests;
  - `modelType` — `'imageOnly'` | `'labels'` (avoid in tests — see below) | `'labels63'`
    (packed uint8: **bits 1–6 = material (`bitand(x,63)`), bit 7 = mask (`bitand(x,64)/64`),
    bit 8 = selection (`bitand(x,128)/128`)**).
  - **VERIFIED (Phase 0):** build the layered 255/65535-material flavors with
    `core.MibDataset(img, dictionary(), 'Standard', 'labels63')` followed by
    `ds.createModel(255)` or `ds.createModel(65535)` — yields `core.MibLabels` with uint8/uint16
    data and separate mask/selection layers (uint16 roundtrips values >255). Do NOT use the
    `'labels'` constructor modelType (allocates labels shaped like the image incl. color dim,
    uint8 only).
- MibModel data accessors (the prime regression target):
  - `getData2D(type, sliceNumber, orient, colChannel, options)`,
    `getData3D(type, time, orient, colChannel, options)`, `getData4D(type, orient, colChannel, options)`
    — `type` ∈ `'image' | 'labels' | 'mask' | 'selection' | 'everything'` (`'everything'` only for
    labels63); `orient`: `1`=ZX, `2`=ZY, `3`=XY (native); `options.id` selects the dataset; results are
    returned as a cell array (`res{1}` is the array).
  - `setData2D(dataset, type, sliceNumber, orient, colChannel, options)` etc. — **dataset is the FIRST
    argument** in MIB3.
  - `colChannel`: `NaN` = all colors for `'image'`; `[]` = full model for `'labels'`; a numeric material
    index extracts a binary mask of that material.
- Reference implementations to copy logic from (both in this repo):
  - `mib\+controllers\@MibRibbon\homeDevTest_Callback.m` — function `benchmarkGetSetData` contains the
    complete correctness + timing harness: ground-truth comparison vs raw arrays (incl. labels63 bit
    unpacking), `stateChecksum`/`layerChecksum` state-preservation, `timeCall` (warm-up + N iterations,
    mean ms), `addTiming`/`addCheck` bookkeeping. **Port these checks; do not invent new ones.**
  - `mib\+controllers\@MibRibbon\homeExamples_Callback.m` — the exact download/reshape/build recipe for
    the real datasets (see §7 for the extracted specs).
- Existing matlab.unittest idiom to mirror: `mib\external\Zarr3Matlab\tests\ZarrArrayTest.m`
  (`matlab.unittest.TestCase`, `TestClassSetup` path handling, `TestMethodSetup/Teardown` temp dirs,
  `verifyEqual` / `verifyTrue` / `verifyError`).
- Path setup at app start: see `mib\mib3.m` (~lines 78–101) — it adds `mib\` and several
  `mib\external\*` folders to the path. The test path fixture must replicate this.
- MATLAB coding rules (root `CLAUDE.md`): use `dictionary` not `containers.Map`; descriptive variable
  names (`waitbar` not `wb`); cache `MibImage.data` into a local before tight pixel loops, write back once.

---

## 3. Folder layout (all new files)

```
buildfile.m                              % repo root — buildtool entry: check / test / testAll / perf
tests/
  plan_unittests.md                      % THIS PLAN (exists)
  phase0_findings.md                     % Phase 0 verified answers (exists)
  phase0_spike.m                         % re-runnable headless spike, not a test class (exists)
  CLAUDE.md                              % conventions: how to add a test (content in §10)
  +mibtest/                              % namespaced shared infrastructure (tests/ goes on path)
    +fixtures/
      MibPathFixture.m                   % adds mib/ + external dirs to path; auto-restored
      ExampleDataFixture.m               % SHARED fixture: download-and-cache real raw data (Phase 2)
    +helpers/
      buildSyntheticModel.m              % deterministic small headless MibModel (one dataset)
      buildBenchmarkModel.m              % 3-dataset model: labels63 / uint8-255 / uint16-65535
      datasetSpec.m                      % URLs, reshape dims, expected byte sizes, material names
      cachedRawDataset.m                 % cache-aware webread + manifest validation (Phase 2)
      hasTestData.m                      % cache valid OR network reachable (Phase 2)
    +perf/
      PerfBaselineStore.m                % load / compare / update baseline JSON
      timeCallSamples.m                  % warm-up + N iterations, returns per-iteration seconds
  core/
    MibDatasetTest.m                     % Phase 3
    MibImageTest.m                       % Phase 3
  models/
    GetSetDataCorrectnessTest.m          % Phase 1 — ported benchmarkGetSetData checks
    GetSetDataPerfTest.m                 % Phase 1 — fixed-iteration perf vs baseline
    BackupUndoTest.m                     % Phase 3
    ClearLayerTest.m                     % Phase 3
  io/
    RoundTripTest.m                      % Phase 2
  utils/
    PureUtilsTest.m                      % Phase 3 (grow over time)
  baselines/
    perf_<COMPUTERNAME>_<release>.json   % committed; created by buildtool perf
```

Rationale:
- Test *classes* live in plain folders mirroring `mib\`'s package names (`core/`, `models/`, `io/`,
  `utils/`) — discovered via `runtests('tests', 'IncludeSubfolders', true)` without package-name friction.
- Shared *infrastructure* is namespaced (`mibtest.fixtures.*`, `mibtest.helpers.*`, `mibtest.perf.*`) so
  tests reference it unambiguously. `tests\` itself must be on the path (buildfile and the fixtures
  handle this).

### Test tags

Declared per test-method group: `methods (Test, TestTags = {'Unit'})` etc.

| Tag | Meaning | In default `buildtool test`? |
|---|---|---|
| `Unit` | fast, synthetic data, offline, headless | **yes** |
| `Integration` | multi-component and/or real cached data | no (in `testAll`) |
| `Performance` | timing tests compared to baseline | no (in `perf`, `testAll`) |
| `RequiresNetwork` | needs download if cache absent — must self-skip offline | no |
| `RequiresGUI` | needs AppContainer UI | no (only when env `MIB3_RUN_GUI_TESTS=1`) |

### Handle-safety rule (critical)

`MibModel` and `MibDataset` are handle objects. Fixtures hold only **immutable raw arrays**; every test
method builds a **fresh model** from them via the helpers. Never share a live model between test methods
— mutation in one test would corrupt the next.

---

## 4. Phase 0 — headless spike — **DONE (2026-06-11)**

**Completed. Results: 12/12 PASS in both an interactive session and a clean `matlab -batch`
session (0 figures created). See `tests\phase0_findings.md` for the full answers
and `tests\phase0_spike.m` for the re-runnable spike.** Key outcomes:
1. `models.MibModel(1, mibFolder)` is headless-safe — but the absolute `mib\` path MUST be passed
   (empty `mibPath` fails on `assets\images\default.png` in clean sessions).
2. `getActiveId()` works headlessly; `getRGBimage()` also works headlessly (keep it in the perf suite).
3. 255/65535-material models: `'labels63'` constructor + `ds.createModel(255|65535)`.
4. Only `mib\` itself is needed on the path for the model layer.

The original spike instructions below are kept for reference:

Run (adjust nothing else first):

```matlab
% --- Phase 0 spike -------------------------------------------------------
restoredefaultpath; rehash toolboxcache;        % clean state
repoRoot = 'C:\MATLAB\MIB_CONVERSION\MIB3';
addpath(fullfile(repoRoot, 'mib'));
% replicate the external-path additions found in mib\mib3.m (~lines 78-101);
% open that file and addpath the same external folders here.

model = models.MibModel();                       % must not open ANY figure
rng(0);
vol   = uint8(randi(255, [64 64 16]));           % [h w z]
vol   = reshape(vol, [64 64 16 1]);              % [h w z c]
label = uint8(randi([0 6], [64 64 16]));

model.I{1} = core.MibDataset(vol, dictionary(), 'Standard', 'labels63');
model.I{1}.updateBoundingBox([], [0 0 0]);
opt = struct('id', 1, 'blockModeSwitch', 0);
model.setData3D(label, 'labels', 1, 3, [], opt);

res = model.getData3D('labels', 1, 3, [], opt);
assert(isequal(squeeze(res{1}), label), 'labels roundtrip failed');
res = model.getData3D('image', 1, 3, NaN, opt);
assert(isequal(res{1}, vol), 'image roundtrip failed');
disp('headless OK');
```

Record the answers to these in a short note saved as `tests\phase0_findings.md`:

1. Does `models.MibModel()` construct with no figure side effects? If `initialize()` opens dialogs or
   needs `utils.getInstallationPath('mib3')`, document the minimal arguments/stubs needed
   (e.g. `models.MibModel(1, fullfile(repoRoot,'mib'), 'ver. test')`).
2. Does `getActiveId()` work headlessly (Sets struct initialized)? Tests always pass explicit
   `options.id`, but the helpers must not crash.
3. How to build the **uint8 / 255-material** and **uint16 / 65535-material** layered models headlessly.
   Read `mib\+core\@MibDataset\MibDataset.m` (modelType handling) and `mib\+core\@MibLabels\MibLabels.m`
   (`maxMaterials`). The benchmark in `homeDevTest_Callback.m` expects exactly:
   id1 → `MibLabels63` (`maxMaterials==63`), id2 → 255 (uint8 labels), id3 → 65535 (uint16 labels).
   Find the constructor/property sequence that produces id2 and id3 and write it into
   `buildBenchmarkModel.m` (§5.3).
4. Which `mib\external\*` folders are genuinely required on the path for the model layer (likely none
   beyond `mib\` itself for get/set tests; io tests will need more).

If headless construction fails irreparably, fall back: Phase 1 tests construct `core.MibDataset`
directly and call **`MibDataset`-level** get/set methods instead of going through `MibModel` — but try
the model layer first; that is where the regression value is.

---

## 5. Phase 1 — infrastructure + get/set regression suite

> **Recommended model: Sonnet** (report per §0 protocol before starting). The code skeletons below
> are near-complete; the work is transcription + iterating against the MATLAB MCP server until the
> Phase 1 verification checklist passes. Escalate to Opus/Fable only if the checklist cannot be made
> green after addressing the documented fallbacks.

Land everything below in one PR. After this phase `buildtool`, `buildtool check`, `buildtool test`,
`buildtool perf` all work, and the get/set data accessors are protected by correctness + perf tests.

### 5.1 `buildfile.m` (repo root)

```matlab
function plan = buildfile
% Build tasks for MIB3: buildtool [check|test|testAll|perf]
import matlab.buildtool.tasks.CodeIssuesTask
import matlab.buildtool.tasks.TestTask

plan = buildplan(localfunctions);

plan("check") = CodeIssuesTask("mib", IncludeSubfolders=true, ...
    WarningThreshold=Inf);   % start non-blocking on warnings; tighten later

plan("test") = TestTask("tests", IncludeSubfolders=true, Tag="Unit", ...
    SourceFiles="mib");

plan("testAll") = TestTask("tests", IncludeSubfolders=true, ...
    Tag=["Unit" "Integration" "Performance"], SourceFiles="mib");

plan.DefaultTasks = ["check" "test"];
end

function perfTask(context)
% PERF - run Performance-tagged tests and compare timings to the committed
% baseline. Set env MIB3_UPDATE_PERF_BASELINE=1 to (re)write the baseline
% for this machine instead of comparing.
testsFolder = fullfile(context.Plan.RootFolder, "tests");
addpath(testsFolder);                      % make +mibtest visible
results = runtests(testsFolder, IncludeSubfolders=true, Tag="Performance");
assertSuccess(results);
mibtest.perf.PerfBaselineStore.finalizeRun();   % compare/update + report (§5.6)
end
```

Notes for the implementer:
- `TestTask` requires R2023a+; the `Tag` name-value requires a recent release — **if it errors on this
  MATLAB version, replace the TestTask entries with custom function tasks that call
  `runtests(...,'Tag',...)` + `assertSuccess(results)`** (same pattern as `perfTask`).
- The perf measurements themselves are recorded by the perf test class into `PerfBaselineStore`'s
  session buffer (see §5.6) — `perfTask` only triggers the final compare/update step. This avoids
  parsing `runperf` result objects.

### 5.2 `tests\+mibtest\+fixtures\MibPathFixture.m`

```matlab
classdef MibPathFixture < matlab.unittest.fixtures.Fixture
    % Adds mib/ (+ required external folders) and tests/ to the MATLAB path.
    methods
        function setup(fixture)
            testsFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            repoRoot    = fileparts(testsFolder);
            mibFolder   = fullfile(repoRoot, 'mib');
            folders = {mibFolder, testsFolder};
            % append the external folders identified in Phase 0 / mib3.m here
            fixture.applyFixture(matlab.unittest.fixtures.PathFixture(folders));
            fixture.SetupDescription = 'Added mib/ and tests/ to path';
        end
        function tf = isCompatible(~, ~), tf = true; end
    end
end
```

### 5.3 Synthetic data helpers

`tests\+mibtest\+helpers\buildSyntheticModel.m` — one dataset, deterministic:

```matlab
function [mibModel, groundTruth] = buildSyntheticModel(options)
% BUILDSYNTHETICMODEL - headless MibModel with one synthetic dataset.
% options.modelType : 'labels63' (default) | 'labels255' | 'labels65535'
% options.dims      : [h w z] (default [64 64 16])
% groundTruth struct: .image [h w z 1], .labels, .mask, .selection (uint8/uint16)
arguments
    options.modelType (1,:) char = 'labels63'
    options.dims (1,3) double = [64 64 16]
end
rng(0, 'twister');                                  % determinism — never remove
h = options.dims(1); w = options.dims(2); z = options.dims(3);
groundTruth.image     = reshape(uint8(randi(255,[h w z])), [h w z 1]);
maxMat = 6;                                          % materials present in labels
groundTruth.labels    = uint8(randi([0 maxMat], [h w z]));
groundTruth.mask      = uint8(rand([h w z]) > 0.7);
groundTruth.selection = uint8(rand([h w z]) > 0.9);

testsFolder = ...;  % derive from mfilename('fullpath') as in MibPathFixture
mibFolder = fullfile(fileparts(testsFolder), 'mib');
mibModel = models.MibModel(1, mibFolder);   % mibPath REQUIRED (Phase 0 finding)
% all flavors start from 'labels63'; layered ones converted via createModel:
mibModel.I{1} = core.MibDataset(groundTruth.image, dictionary(), 'Standard', 'labels63');
mibModel.I{1}.updateBoundingBox([], [0 0 0]);
switch options.modelType
    case 'labels255',   mibModel.I{1}.createModel(255);    % uint8 labels expected
    case 'labels65535', mibModel.I{1}.createModel(65535);  % cast groundTruth.labels to uint16!
end
opt = struct('id', 1, 'blockModeSwitch', 0);
mibModel.setData3D(groundTruth.labels,    'labels',    1, 3, [], opt);
mibModel.setData3D(groundTruth.mask,      'mask',      1, 3, [], opt);
mibModel.setData3D(groundTruth.selection, 'selection', 1, 3, [], opt);
end
```

For `'labels65535'` cast labels to `uint16` and use the construction sequence found in Phase 0.

`tests\+mibtest\+helpers\buildBenchmarkModel.m` — the 3-dataset layout `benchmarkGetSetData` expects
(`id1` labels63, `id2` 255, `id3` 65535), built from given or synthetic arrays. Signature:

```matlab
function [mibModel, groundTruth] = buildBenchmarkModel(imageVolume, labelVolume)
% no-arg call -> synthetic [64 64 16]; with args -> real data (Phase 2)
```

### 5.4 `tests\models\GetSetDataCorrectnessTest.m`

Port the **checks** from `benchmarkGetSetData` 1:1 (same ground-truth math), parameterized over the
three model types. Skeleton:

```matlab
classdef GetSetDataCorrectnessTest < matlab.unittest.TestCase
    properties (TestParameter)
        modelType = {'labels63', 'labels255', 'labels65535'};
    end
    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end
    methods (Test, TestTags = {'Unit'})
        function get2DImageMatchesRaw(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3)/2);
            res = mibModel.getData2D('image', midSlice, 3, NaN, opt);
            testCase.verifyEqual(res{1}, squeeze(gt.image(:, :, midSlice, :, 1)));
        end
        % ... one focused method per check from benchmarkGetSetData:
        %  get2D labels / mask / selection / material extraction
        %  get3D image / labels / mask / selection / material / orient 1 / orient 2
        %  get4D image / labels
        %  'everything' (labels63 only — guard with assumeTrue(strcmp(modelType,'labels63')))
        %  setData2D/3D/4D roundtrips + state-preservation checksum (port stateChecksum/layerChecksum)
        %  orientation formulas (from benchmarkGetSetData lines 119-125):
        %    orient 1 (ZX): permute(raw, [2 3 1 4 5]);  orient 2 (ZY): permute(raw, [1 3 2 4 5])
    end
end
```

Implementation requirements:
- One **focused test method per check** (not one mega-method) so a failure pinpoints the broken path.
- Copy the ground-truth expressions from `homeDevTest_Callback.m` exactly (they are the verified spec):
  labels63 unpack `bitand(packed,63)`, mask `bitand(packed,64)/64`, selection `bitand(packed,128)/128`.
- Port `stateChecksum`/`layerChecksum` (sum-double, nnz, numel per layer) into a private helper method
  of the test class; verify state is identical after every set-roundtrip test.
- Material-extraction expected value: `uint8(gtLabels == materialIndex)` with `materialIndex = 1`.

### 5.5 `tests\+mibtest\+perf\timeCallSamples.m`

Lift `timeCall` from `homeDevTest_Callback.m`, returning raw samples:

```matlab
function secondsPerCall = timeCallSamples(fcn, nIterations)
% warm-up call excluded, then nIterations timed individually
fcn();
secondsPerCall = zeros(1, nIterations);
for k = 1:nIterations
    tStart = tic;
    fcn();
    secondsPerCall(k) = toc(tStart);
end
end
```

### 5.6 `tests\+mibtest\+perf\PerfBaselineStore.m`

A class with `Constant` thresholds and **static** methods (session state via `persistent` inside a
static accessor — simplest reliable pattern):

```matlab
classdef PerfBaselineStore
    properties (Constant)
        WarnRatio = 1.15;   % > this -> warning
        FailRatio = 1.30;   % > this -> failure
        DefaultIterations2D = 100;
        DefaultIterations3D = 5;
    end
    methods (Static)
        function record(measurementKey, secondsSamples)
            % store mean/min/n into a persistent session buffer
        end
        function verifyAgainstBaseline(testCase, measurementKey, secondsSamples)
            % record(...) then, if baseline exists for this key:
            %   ratio = mean(samples) / baseline.meanSeconds
            %   ratio > FailRatio -> testCase.verifyFail(diag with both values)
            %   ratio > WarnRatio -> fprintf warning line (do NOT fail)
            % if no baseline file or key: fprintf '[no baseline] key = X ms' (pass)
        end
        function finalizeRun()
            % if getenv('MIB3_UPDATE_PERF_BASELINE')=='1': write session buffer
            % to baselineFilePath() (jsonencode, PrettyPrint=true) and report.
            % else: print summary table of measured-vs-baseline.
        end
        function p = baselineFilePath()
            testsFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            p = fullfile(testsFolder, 'baselines', sprintf('perf_%s_R%s.json', ...
                getenv('COMPUTERNAME'), version('-release')));
        end
    end
end
```

Baseline JSON schema (committed to git):

```json
{
  "schemaVersion": 1,
  "host": "WS-NAME",
  "matlabRelease": "R2025b",
  "createdUtc": "2026-06-11T08:00:00Z",
  "measurements": {
    "GetSetDataPerf/get2D_image/labels63":      { "meanSeconds": 0.00118, "minSeconds": 0.00101, "samples": 100 },
    "GetSetDataPerf/set3D_everything/labels63": { "meanSeconds": 0.04210, "minSeconds": 0.04020, "samples": 5 }
  }
}
```

Measurement key convention: `<ClassShortName>/<operation>/<modelTypeOrDataset>`.

### 5.7 `tests\models\GetSetDataPerfTest.m`

```matlab
classdef GetSetDataPerfTest < matlab.unittest.TestCase
    properties (TestParameter)
        modelType = {'labels63', 'labels255', 'labels65535'};
    end
    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end
    methods (Test, TestTags = {'Performance'})
        function perfGet2DImage(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                modelType=modelType, dims=[256 256 32]);   % big enough to measure
            opt = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3)/2);
            samples = mibtest.perf.timeCallSamples( ...
                @() mibModel.getData2D('image', midSlice, 3, NaN, opt), ...
                mibtest.perf.PerfBaselineStore.DefaultIterations2D);
            mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, ...
                sprintf('GetSetDataPerf/get2D_image/%s', modelType), samples);
        end
        % mirror the timing list of benchmarkGetSetData:
        %  get/set 2D x {image, labels, mask, selection, labels-material}
        %  get/set 3D x {image, labels, mask, selection, labels-material, everything(63 only)}
        %  get3D image orient 1;  get/set 4D x {image, labels};  getRGBimage (headless-safe, Phase 0)
    end
end
```

Use plain `matlab.unittest.TestCase` + fixed iterations (NOT `matlab.perftest`/`runperf`) for this
default suite — deterministic and fast (<1 min). `runperf`-based statistical measurement on real data is
an optional Phase 2 extra.

### 5.8 `homeDevTest_Callback.m` shim (optional in Phase 1, required by Phase 2 end)

Refactor so the ribbon button keeps working but shares code: the button keeps its current behavior
(operates on GUI-loaded datasets, prints the table) but calls `mibtest.perf.timeCallSamples` and the
ported check helpers instead of its private copies. **Do not change its output format.** If `tests\` is
not on the deployed path, guard with `exist('mibtest.perf.timeCallSamples','file')` and keep local
fallbacks — simplest safe option: leave the button untouched until Phase 2 and only delete its local
duplicates once the shared versions are proven.

### 5.9 `.gitignore`

No entry needed for test data (cache lives in `%LOCALAPPDATA%`). Add `tests/**/*.asv`.

### Phase 1 verification checklist

1. Fresh MATLAB session, `cd C:\MATLAB\MIB_CONVERSION\MIB3`:
   - `buildtool` → check + Unit tests green.
   - `runtests('tests', 'IncludeSubfolders', true, 'Tag', 'Unit')` → green.
2. Mutation test: temporarily break a branch in `mib\+models\@MibModel\setData2D.m` (e.g. transpose the
   slice) → exactly the corresponding correctness tests fail with pinpoint names → revert.
3. `set MIB3_UPDATE_PERF_BASELINE=1` + `buildtool perf` → baseline JSON appears in `tests\baselines\`;
   unset, rerun `buildtool perf` → passes. Hand-edit one baseline `meanSeconds` down by 50 % → rerun →
   that one measurement fails; restore.
4. `buildtool check` runs codeIssues over `mib\` without erroring out.
5. Commit baseline JSON together with the code.

---

## 6. Phase 2 — real cached datasets + IO round-trips

> **Recommended model: Sonnet** (report per §0 protocol). §6.1–6.3 (data fixture) are fully
> specified. §6.4 (IO round-trips) requires discovering loader/saver factory APIs in `mib\+io\` —
> if a given format's round-trip cannot be made to pass after reasonable effort, leave it as a
> documented TODO and escalate that format to Opus/Fable rather than forcing it.

### 6.1 `tests\+mibtest\+helpers\datasetSpec.m`

Specs extracted from `homeExamples_Callback.m` (keep in one place):

```matlab
function spec = datasetSpec(name)
switch name
    case 'Trypanosoma'
        spec.imageUrl   = 'http://mib.helsinki.fi/tutorials/datasets/SBEM_Trypanosoma.raw';
        spec.labelsUrl  = 'http://mib.helsinki.fi/tutorials/datasets/Labels_SBEM_Trypanosoma.raw';
        spec.imageDims  = [887 813 171 1];     % uint8
        spec.labelsDims = [887 813 171];       % uint8, 6 materials
        spec.materialNames = {'Nuclei'; 'Mito'; 'Vesicles'; 'LD'; 'ER'; 'Cytoplasm'};
        spec.pixSize = struct('x', 0.0140193, 'y', 0.0140193, 'z', 0.03);
    case 'Huh7'
        spec.imageUrl   = 'http://mib.helsinki.fi/tutorials/datasets/SBEM_Huh7.raw';
        spec.labelsUrl  = 'http://mib.helsinki.fi/tutorials/datasets/Labels_SBEM_Huh7.raw';
        spec.imageDims  = [372 521 75 1];
        spec.labelsDims = [372 521 75];        % 4 materials
        spec.materialNames = {'LD'; 'NE'; 'ER'; 'Mito'};
        spec.pixSize = struct('x', 0.013, 'y', 0.013, 'z', 0.030);
end
spec.cacheDir = getenv('MIB3_TEST_DATA_DIR');
if isempty(spec.cacheDir)
    spec.cacheDir = fullfile(getenv('LOCALAPPDATA'), 'MIB3', 'testData');
end
end
```

### 6.2 `cachedRawDataset.m` / `hasTestData.m`

- `cachedRawDataset(spec)`: for each of imageUrl/labelsUrl — if the cached file exists in
  `spec.cacheDir` **and** its byte size equals `prod(dims)` (uint8 ⇒ bytes == elements), load with
  `fread`; else download via `webread(url, weboptions('ContentType','raw'))`, write to cache, then
  reshape per spec and return `[imageVolume, labelVolume]`.
- `hasTestData(spec)`: true if both cached files exist with correct sizes; else attempt a cheap
  reachability probe (`webread` of the image URL inside try/catch with `weboptions('Timeout', 5)` is too
  heavy — instead probe `java.net.InetAddress.getByName('mib.helsinki.fi')` in try/catch, or simply
  return false on any error from a tiny `webread` of `http://mib.helsinki.fi` root). On false, callers
  skip.

### 6.3 `ExampleDataFixture.m` (shared fixture — download once per test run)

```matlab
classdef ExampleDataFixture < matlab.unittest.fixtures.Fixture
    properties (SetAccess = immutable), DatasetName, end
    properties (SetAccess = private), Image, Labels, MaterialNames, PixSize, end
    methods
        function fixture = ExampleDataFixture(datasetName)
            fixture.DatasetName = datasetName;
        end
        function setup(fixture)
            spec = mibtest.helpers.datasetSpec(fixture.DatasetName);
            [fixture.Image, fixture.Labels] = mibtest.helpers.cachedRawDataset(spec);
            fixture.MaterialNames = spec.materialNames;
            fixture.PixSize = spec.pixSize;
        end
        function tf = isCompatible(fixtureA, fixtureB)
            tf = strcmp(fixtureA.DatasetName, fixtureB.DatasetName);  % enables sharing
        end
    end
end
```

Usage in a test class:

```matlab
methods (TestClassSetup)
    function setupOnce(testCase)
        testCase.applyFixture(mibtest.fixtures.MibPathFixture);
    end
end
methods (Test, TestTags = {'Integration', 'Performance', 'RequiresNetwork'})
    function perfRealDataGet3DLabels(testCase)
        testCase.assumeTrue(mibtest.helpers.hasTestData( ...
            mibtest.helpers.datasetSpec('Trypanosoma')), 'no cache and offline');
        dataFixture = testCase.applyFixture(mibtest.fixtures.ExampleDataFixture('Trypanosoma'));
        [mibModel, ~] = mibtest.helpers.buildBenchmarkModel(dataFixture.Image, dataFixture.Labels);
        % ... timeCallSamples + verifyAgainstBaseline with keys '.../trypanosoma'
    end
end
```

### 6.4 `tests\io\RoundTripTest.m`

For each headless-capable saver/loader pair: save a small synthetic dataset to a
`TemporaryFolderFixture` dir → load through `io.LoaderFactory` → `verifyEqual` to original.
Start with the formats that need no external windows: TIF (Imread loader), NRRD, MatModel/MibImg,
AmiraMesh, HDF5. Look up factory entry points in `mib\+io\` (`LoaderFactory.create`,
`ExtensionRegistryLoad`, savers under `mib\+io\+savers\`). Tag `Unit` if fully offline+fast, else
`Integration`. BioFormats/Zarr round-trips: `Integration` (heavier path setup).

### Phase 2 verification

1. Delete `%LOCALAPPDATA%\MIB3\testData` → `buildtool testAll` downloads (~140 MB once), passes.
2. Re-run → no network traffic (verify by timing or by disabling network) → cached load, passes.
3. Disable network with empty cache → `RequiresNetwork` tests are **skipped (assumption-filtered)**,
   suite still green.
4. `set MIB3_UPDATE_PERF_BASELINE=1` + `buildtool perf` to add the real-data baseline entries; commit.

---

## 7. Phase 3 — core operations tests

> **Recommended model: Sonnet** (report per §0 protocol) — same pattern as Phase 1 with
> established conventions.

- `tests\core\MibImageTest.m` — construction from arrays (incl. `[h w c]→[h w 1 c]` auto-permute for
  color images), dims properties, `dataClass`.
- `tests\core\MibDatasetTest.m` — modelType variants, layer presence (labels63 ⇒ mask/selection are
  views into packed bits), `updateBoundingBox`, `clearLayer('selection','2D'/'3D'/'4D')`.
- `tests\models\BackupUndoTest.m` — `backup(type, switch3d, opts)` → mutate via setData → undo via
  `MibBackup` → state checksum equals pre-mutation. Check both 2D (switch3d=0) and 3D (switch3d=1)
  flavors and `enableSelection==0` early-return guard.
- `tests\models\ClearLayerTest.m` — clearing each layer at each scope leaves other layers intact
  (checksum the untouched layers).
- `tests\utils\PureUtilsTest.m` — start with `utils.updatePixSizeAndResolution`,
  `utils.updateBatchOptCombineFields_Shared` (incl. spinner 3-element-cell semantics from root
  CLAUDE.md), grow opportunistically.

All `Unit`-tagged, synthetic data only.

## 8. Phase 4 — porting-workflow integration (ongoing, no fixed end)

> **Recommended model: whichever model performs the port** — the test lands together with the
> ported method in the same session/PR (report per §0 protocol).

Rule added to the workflow: **every MIB2→MIB3 method port lands with at least one test at the
model/core layer** (not the controller layer). Where exact numeric output matters, capture the MIB2
result once (run `C:\Matlab\MIB2\`, save the output array as `.mat` under `tests\data\expected\` —
small arrays only, <1 MB) and `verifyEqual` against it. Update `tests\CLAUDE.md` and the root
`CLAUDE.md` porting-workflow section to state this rule.

## 9. Phase 5 (later, optional) — GUI smoke + CI

> **Recommended model: Sonnet** (report per §0 protocol) — small, well-bounded tasks.

- One `RequiresGUI` smoke test: construct `controllers.MibController(model, version)` + close, only when
  `getenv('MIB3_RUN_GUI_TESTS')=='1'` (assume-skip otherwise).
- GitHub Actions with `matlab-actions/setup-matlab` + `matlab-actions/run-build` running
  `buildtool check test` (Unit only; network tests self-skip). Not a blocker for anything above.

---

## 10. `tests\CLAUDE.md` content (write verbatim in Phase 1, adjust paths if needed)

```markdown
# MIB3 Test Conventions

## Running
- `buildtool`            — code check + Unit tests (run before every commit)
- `buildtool testAll`    — + Integration & Performance (network tests self-skip offline)
- `buildtool perf`       — Performance vs committed baseline; set MIB3_UPDATE_PERF_BASELINE=1 to rewrite
- single file:           `runtests('tests/models/GetSetDataCorrectnessTest.m')`

## Adding a test when porting/changing a method
1. Location mirrors the source package: `core.MibImage` method → `tests/core/MibImageTest.m`.
2. Data: synthetic via `mibtest.helpers.buildSyntheticModel` (tag `Unit`). Use real cached data
   (`mibtest.fixtures.ExampleDataFixture`) ONLY if behavior is data-dependent — then tag
   `Integration` + `RequiresNetwork` and start with `assumeTrue(mibtest.helpers.hasTestData(...))`.
3. Every test class: `applyFixture(mibtest.fixtures.MibPathFixture)` in `TestClassSetup`.
4. Build a FRESH model per test method (MibModel/MibDataset are handles — never share live ones).
5. Assert against raw-array ground truth; for labels63 unpack bits explicitly:
   material = bitand(x,63), mask = bitand(x,64)/64, selection = bitand(x,128)/128.
6. Perf-sensitive method? Add a `Performance`-tagged method using
   `mibtest.perf.timeCallSamples` + `PerfBaselineStore.verifyAgainstBaseline`, then commit the
   baseline (`MIB3_UPDATE_PERF_BASELINE=1` + `buildtool perf`).
7. MATLAB rules apply: `dictionary` not containers.Map; descriptive names; cache `.data` locally
   around pixel loops.
```

---

## 11. Risks & mitigations (read before starting each phase)

| Risk | Mitigation |
|---|---|
| ~~`MibModel.initialize()` touches GUI/preferences~~ | RESOLVED: headless-safe with explicit `mibPath` (Phase 0) |
| ~~65535-material construction unclear~~ | RESOLVED: `createModel(65535)` after `'labels63'` construction (Phase 0) |
| `TestTask`/`Tag` API not in this MATLAB release | replace with custom function tasks calling `runtests(...,'Tag',...)` |
| Baseline noise across machines | baselines keyed by COMPUTERNAME+release; 15 %/30 % warn/fail bands in one Constant block |
| 123 MB download flakiness | persistent LOCALAPPDATA cache + byte-size manifest check + assumption-skip offline; never fail the build for network |
| Handle-object state leaking between tests | fixtures expose immutable arrays only; fresh model per method (rule §3) |
| ~~`getRGBimage` may need GUI state~~ | RESOLVED: works headlessly (Phase 0) — keep in the perf suite |
| Perf tests slow | fixed iterations (100×2D / 5×3D, same as the ribbon benchmark), synthetic 256×256×32 default; real-data perf only in `testAll`/`perf` |
