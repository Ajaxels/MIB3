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
   around pixel loops.

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
`mib/` path from `mfilename` and passes it to `models.MibModel(1, mibFolder)` — the explicit path
is required; an empty `mibPath` fails in clean sessions (Phase 0 finding).
