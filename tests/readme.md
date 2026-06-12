# MIB3 Test Suite

## What the tests do

The tests verify that the core processing logic of MIB3 works correctly — things like reading and writing image data, manipulating labels and masks, geometric transforms, and I/O round-trips. They do **not** test the graphical interface; they run entirely in headless MATLAB without opening any windows.

Each test builds a small synthetic dataset (typically 16×24×4 pixels), calls one or more MIB methods on it, and checks that the output matches what is mathematically expected. If a method breaks during porting or refactoring, the relevant test will fail and pinpoint the problem.

---

## Quick start

Open MATLAB, make sure the working directory is `C:\MATLAB\MIB_CONVERSION\MIB3`, then run:

```matlab
buildtool
```

This runs a code quality check followed by the full unit test suite. You should see output like:

```
Running MibImageTest
.....
Done MibImageTest
...
Totals:
   284 Passed, 0 Failed, 0 Incomplete.
```

A clean build prints **0 Failed**. If any test fails, MATLAB prints the test name and the assertion that did not hold.

---

## Running options

| Command | What it does |
|---|---|
| `buildtool` | Code check + unit tests (fast, ~30 s) |
| `buildtool test` | Unit tests only |
| `buildtool testAll` | Unit + integration + performance tests (needs test data files) |
| `buildtool perf` | Performance tests only — compare against saved baseline |
| `buildtool check` | Code analysis only, no tests |
| `runtests('tests/models/RGBImageTest.m')` | Run a single test file |

---

## Performance baselines

A small number of tests are tagged **Performance**. They time hot-path methods (such as `getData2D`, `getData3D`, `getRGBimage`) against a committed baseline stored as a JSON file in `tests/+mibtest/+perf/baselines/`. Thresholds are:

| Change vs baseline | Result |
|---|---|
| ≤ 15 % slower | Pass |
| 15 – 30 % slower | Warning (printed, test still passes) |
| > 30 % slower | **Fail** |

**Recording a new baseline** — do this after intentional performance improvements, after a machine change, or when setting up on a new workstation:

```matlab
setenv('MIB3_UPDATE_PERF_BASELINE', '1')
buildtool perf
```

The env var tells the perf runner to write new JSON baselines instead of comparing against the old ones. Commit the updated JSON files alongside your code change so CI uses the new numbers.

After recording, clear the env var to return to comparison mode:

```matlab
setenv('MIB3_UPDATE_PERF_BASELINE', '')
```

Baselines are keyed per machine (using the hostname), so different developers' machines each have their own reference numbers in the same JSON file and do not interfere with each other.

---

## Test layout

Tests are organised to mirror the source packages:

```
tests/
  core/        — MibDataset and MibImage methods (pixel data, dims, layer ops)
  models/      — MibModel methods (the main application model layer)
  io/          — file format round-trips (save → reload → compare)
  utils/       — utility functions (unit conversions, batch helpers)
```

---

## What "Unit" vs "Integration" means

Most tests are tagged **Unit**: they create synthetic data on the fly, need no external files, and finish in under a second each. These are the tests that `buildtool` runs.

A small number are tagged **Integration**: they write and read real files (TIFF, HDF5, etc.) to a temporary folder. These run only with `buildtool testAll`.

---

## Temporary directories

The test suite uses two kinds of scratch space.

### Per-test temp folders (`%TEMP%`)

Integration tests (tagged `Integration`) write files — TIF stacks, `.model`, `.mask`, HDF5 — to a
temporary folder created by `matlab.unittest.fixtures.TemporaryFolderFixture`. MATLAB creates these
automatically under `%TEMP%` with a random hex name (e.g.
`C:\Users\...\AppData\Local\Temp\tp1e69c728_6a05_405d_8f65_d14b4c92da8a\`).

Each folder is **deleted automatically** when the test method that created it finishes. If a test
crashes hard enough to prevent cleanup, the leftover `tp…` folders can be removed manually — they
contain nothing important. Unit tests tagged `Unit` never write any files.

### Cached example datasets (`%LOCALAPPDATA%\MIB3\testData`)

Real microscopy datasets used by `RequiresNetwork` tests (currently not part of the default suite)
are downloaded once and cached in:

```
%LOCALAPPDATA%\MIB3\testData\
```

Override the location with the env var `MIB3_TEST_DATA_DIR` before starting MATLAB. The files
total roughly 140 MB. To force a fresh download, delete the folder — the next `buildtool testAll`
will re-fetch and re-validate them.

---

## What to expect on a healthy build

- All ~280 Unit tests pass in roughly 30 seconds.
- Four tests in `GetSetDataCorrectnessTest` are intentionally **skipped** (filtered) — they test a feature that only applies to one specific model type. Skipped tests are not failures.
- Integration tests may take a minute longer and require write access to `%TEMP%`.

If you see failures after pulling new code or switching MATLAB versions, the error message will tell you which method and which assertion failed — that is usually enough to identify what changed.

---

## Adding a test

When you port a method from MIB2 or change existing behaviour, add a test alongside the code change. Place it in the folder that matches the source package (`core/`, `models/`, etc.), name it `<MethodName>Test.m`, and tag it `Unit`. The file `tests/CLAUDE.md` has a step-by-step checklist.
