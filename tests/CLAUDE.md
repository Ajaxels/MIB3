# MIB3 Test Conventions

## Running

```
buildtool             — code check + Unit tests (run before every commit)
buildtool testAll     — + Integration & Performance (network tests self-skip offline)
buildtool perf        — Performance vs committed baseline
                        set MIB3_UPDATE_PERF_BASELINE=1 to rewrite baseline for this machine
single file:          runtests('tests/models/GetSetDataCorrectnessTest.m')
```

## Adding a test when porting/changing a method

1. **Location** mirrors the source package: `core.MibImage` method → `tests/core/MibImageTest.m`.
2. **Data**: synthetic via `mibtest.helpers.buildSyntheticModel` (tag `Unit`). Use real cached data
   (`mibtest.fixtures.ExampleDataFixture`) ONLY if behavior is data-dependent — then tag
   `Integration` + `RequiresNetwork` and start with `assumeTrue(mibtest.helpers.hasTestData(...))`.
3. **Every test class**: `applyFixture(mibtest.fixtures.MibPathFixture)` in `TestClassSetup`.
4. **Build a FRESH model per test method** (MibModel/MibDataset are handles — never share live ones).
5. **Assert against raw-array ground truth**; for labels63 unpack bits explicitly:
   `material = bitand(x,63)`, `mask = bitand(x,64)/64`, `selection = bitand(x,128)/128`.
6. **Perf-sensitive method?** Add a `Performance`-tagged method using
   `mibtest.perf.timeCallSamples` + `PerfBaselineStore.verifyAgainstBaseline`, then commit the
   baseline (`MIB3_UPDATE_PERF_BASELINE=1` + `buildtool perf`).
7. **MATLAB rules apply**: `dictionary` not containers.Map; descriptive names; cache `.data` locally
   around pixel loops; plain hyphen `-` only, never `—`/`–` (see the dash rule in the root
   [`CLAUDE.md`](../CLAUDE.md)) - this holds for assertion messages and comments too, so the
   repo-wide check stays clean.

## Testing a controller (`tests/controllers/`)

Controllers are testable as `Unit` tests when they can be built **without a view** — no window
opens, nothing blocks, and the suite still exercises the real methods instead of re-implementing
their logic in the test. Two patterns, both used by `StitchingControllerTest` /
`StitchingInspectorControllerTest`:

1. **Build view-less.** The standard `NaN` constructor path returns a fully initialised controller
   with `view` empty: `controller = controllers.Stitching(mibModel, [], NaN)`. A controller with no
   such path needs an explicit opt-out (the inspector takes `struct('createView', false)`).
   Assert `isempty(controller.view)` in the helper so a future constructor change cannot silently
   start opening windows in the suite.
2. **Route UI through accessors.** Dialog parents and progress anchors belong behind a
   `guiFigure()`-style accessor returning `[]` headless, and widget writes behind a
   `hasWidget(name)` guard. This is what makes the workflow methods run unchanged — and it fixes
   batch mode at the same time, where `view` is empty for real.

When a test must assert on something the controller *renders*, hand it just that widget:

```matlab
rmseLabel = mibtest.helpers.FakeWidget();      % a HANDLE — a struct would take a copy
controller.view = struct('handles', struct('rmseLabel', rmseLabel), 'gui', []);
controller.refreshQualityChip();
testCase.verifySubstring(rmseLabel.Text, 'Seams disagree');
```

Keep `mibModel.preferences.System.DeveloperMode = false` — controllers print progress lines
otherwise. A model built with `Preferences = 'defaults'` (see below) already has it false, so the
explicit line in the fixture is only needed for stub models that are plain structs rather than a
real `MibModel`. Headless controllers must still **error** where the GUI shows a message box and
returns: a silent `return` reports success for work that never happened.

## Tags

| Tag | Meaning | Runs in `buildtool test`? |
|-----|---------|--------------------------|
| `Unit` | fast, synthetic, offline, headless | **yes** |
| `Integration` | multi-component and/or real cached data | no (`testAll`) |
| `Performance` | timing tests vs baseline | no (`perf`, `testAll`) |
| `RequiresNetwork` | needs download if cache absent — must self-skip offline | no |
| `RequiresGUI` | needs AppContainer UI | no (only with `MIB3_RUN_GUI_TESTS=1`) |

## Handle-safety rule (critical)

`MibModel` and `MibDataset` are handle objects. Every test method must build a **fresh model** via
`buildSyntheticModel` or `buildBenchmarkModel`. Sharing a live model between test methods causes
state from one test to corrupt the next.

## Path and MibModel construction

`MibPathFixture` adds `mib/` and `tests/` to the path. `buildSyntheticModel` derives the absolute
`mib/` path from `mfilename` and passes it to
`models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults')` — the explicit path is
required; an empty `mibPath` fails in clean sessions (Phase 0 finding).

**Always construct with both flags.** They default the other way so the real app is unaffected;
only tests opt out.

| Flag | Why tests need it |
|------|-------------------|
| `Verbose = false` | the constructor otherwise prints which preferences file and user statistics folder it picked up — once per model, i.e. once per test method. Warnings and errors still print. |
| `Preferences = 'defaults'` | without it the model loads the developer's real `mib3.mat`, so a preference last saved from the GUI can change what a test asserts. It also stops the statistics migration steps in `initializePreferences`, which `movefile` real user data, from ever running inside the suite. |

With `Preferences = 'defaults'` the preferences are exactly what `utils.defaults.generatePreferences`
produces, so assert against those values — not against whatever is in your own `mib3.mat`.
