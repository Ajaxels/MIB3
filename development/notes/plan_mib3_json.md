# Moving the preferences out of `mib3.mat` into JSON

MIB stores its preferences as a binary MAT file: `<USERPROFILE>\Matlab\mib3.mat` for the user's
own settings, and `mib3_prefs_override[_COMPUTERNAME].mat` next to `mib3.m` for site-wide
defaults. Neither can be read, checked, diffed or authored without a MATLAB licence, which makes
the override file in particular awkward to deploy - `mib/mib3_override_params.md` today instructs
an administrator to *run MIB, configure it by hand, exit, then copy and rename the binary*.

This note records what was measured before deciding whether JSON can replace it. Nothing here is
implemented yet.

Measured on R2026a Update 2, Windows 11, against the real `mib3.mat` of this workstation.

## What the file actually contains

9,363 bytes, 487 leaf values, and **only four MATLAB classes**:

| class | leaves |
|---|---|
| `double` | 278 |
| `logical` | 104 |
| `char` | 96 |
| `cell` | 9 |

No `datetime`, no function handles, no struct arrays, no integer types, no objects, no `string`.
The single `datetime` in the preferences tree (`Users.Tiers.logStartDate`) never reaches this file:
`MibController.exitProgram` strips `Users.Tiers` before saving and the statistics go to the
per-workstation `mib_user_<HOST>.mat` shard instead. That shard, if it is ever converted too,
*does* need an ISO-8601 convention for that one field.

Everything in `mib3.mat` is representable in JSON.

## Startup performance is not an argument against JSON

| | bytes | read, min | read, median |
|---|---|---|---|
| `load('mib3.mat')` | 9,363 | 1.91 ms | 1.96 ms |
| `jsondecode(fileread(...))`, pretty-printed | 27,341 | **1.33 ms** | **1.39 ms** |
| `jsonencode(P, 'PrettyPrint', true)` (exit path only) | - | 2.2 ms | - |

JSON reads ~0.6 ms *faster* despite being 2.9x larger - MAT-file header parsing and
decompression dominate at this size. Compact JSON is 16,976 bytes if size ever matters, but
readability is the entire point, so pretty-print is the right choice. Neither figure is
measurable next to MIB's overall startup (see [ports/plan_startup.md](../ports/plan_startup.md)).

## What breaks on a JSON round trip

The real preferences were encoded and decoded, then diffed leaf by leaf. **24 of 487 leaves come
back wrong**, in three classes.

### 1. Row vectors become column vectors (21 leaves)

`jsondecode` returns every 1-D array as a column, whatever orientation went in.

```
Colors.SelectionColor              double[1 3]   -> double[3 1]
Colors.MaskColor                   double[1 3]   -> double[3 1]
SegmTools.Annotations.Color        double[1 3]   -> double[3 1]
SegmTools.Presets.Annotations.Set1.Color (.Set2, .Set3)  double[1 3] -> double[3 1]
SegmTools.FavoriteTools            double[1 2]   -> double[2 1]
KeyShortcuts.Key                   cell[1 45]    -> cell[45 1]
KeyShortcuts.Action                cell[1 45]    -> cell[45 1]
KeyShortcuts.shift / .control / .alt             logical[1 45] -> logical[45 1]
KeyShortcuts.overrideShift / .overrideAlt        double[1 45]  -> double[45 1]
System.Dirs.RecentDirs             cell[1 14]    -> cell[14 1]
VolRen.Viewer.backgroundColor / .gradientColor / .lightColor  double[1 3] -> double[3 1]
VolRen.Volume.volumeAlphaCurve.x / .y            double[1 4]   -> double[4 1]
Deep.ImageFilenameExtension        cell[1 2]     -> cell[2 1]
Users.tierLevelRanks               cell[1 10]    -> cell[10 1]
```

This is the silent-bug class: `numel` and most arithmetic still work, indexing and concatenation
do not. `+controllers/@Stitching/applyProjectSettings.m:57` already carries a hand-written fixup
for exactly this, which is evidence that it bites in practice.

2-D matrices are **not** affected - `Colors.ModelMaterialColors` and `Colors.LUTColors` (both 6x3)
round-trip correctly. Only vectors.

### 2. `Inf` and `NaN` become `[]` (2 leaves)

`jsonencode(Inf)` emits `null`, and `jsondecode(null)` yields `0x0 double`.

```
Deep.TrainingOpt.GradientThreshold   Inf -> []
Deep.TrainingOpt.ValidationPatience  Inf -> []
```

Cheap workaround: store them as the JSON strings `"Inf"` / `"-Inf"` / `"NaN"`. Those round-trip
unchanged, and `str2double('Inf')` returns `Inf`.

### 3. Empty cell `{}` becomes `[]`

Did not appear in the diff because `RecentDirs` is populated on this machine, but
`System.Dirs.RecentDirs` **defaults** to `{}`, so a fresh profile decodes it to a `0x0 double` and
the next `RecentDirs{end+1}` errors.

### What survives, contrary to expectation

- `''` -> `""` -> `''` - empty char is preserved, so the `[]` vs `''` distinction between
  `ExternalDirs.*InstallationPath` (empty double) and `Deep.SendReports.SMTP_password` (empty
  char) is **not** lost.
- `[]` -> `[]` - empty double is preserved.
- `struct()` -> `{}` -> `struct()` - empty structs survive, so `DoNotShowDialogs` and
  `VolRen.Animation.animationPath` are safe.
- The nested cell in `Deep.ImageFilenameExtension` (`{{'AM'},'TIF'}`) keeps its contents; only its
  orientation changes.
- Field names: every MIB preference name is a valid MATLAB identifier and therefore a valid JSON
  key, so the key sanitisation of `jsondecode` never fires.

## The generic fix

Do **not** build a per-field type table - it would need updating for every new preference and
would fail silently when someone forgets.

`utils.defaults.generatePreferences()` already runs first and produces the authoritative class and
shape for every leaf. Walk the decoded structure alongside those defaults and coerce each leaf to
its default's orientation and class. One recursive pass fixes all 21 orientation bugs and the `{}`
case at once, and it stays correct as preferences are added, because a new field needs no
registration anywhere.

Only `Inf`/`NaN` needs an explicit convention on top (class 2 above).

It composes correctly with the existing version-migration logic: coerce first, then hand the
result to `utils.concatenateStructures` unchanged, so `MibModel.initializePreferences` keeps its
older/same/newer-version branches as they are.

## Alternatives ruled out

| option | verdict |
|---|---|
| `writestruct` / `readstruct` (JSON or XML) | **Rejects the file outright**: `Input struct must contain scalar, vector, or empty values. Field "P.Colors.ModelMaterialColors" contains a matrix`. Would force reshaping the two colour tables, and it returns `string` rather than `char` throughout. |
| YAML | No builtin in R2026a - `yamlread`/`yamlwrite` do not exist. Would mean shipping a parser into the compiled app. |
| TOML | No builtin, same problem. |
| `readdictionary` / `writedictionary` | Exist, but are flat key-value - the wrong shape for a six-level-deep tree. |
| Read-only JSON mirror beside the `.mat` | **Actively bad.** Users will edit the mirror, nothing will happen, and that is worse than the present opacity. |

## The one genuine loss: no comments

`generatePreferences.m` documents the legal values inline (`'scroll'`/`'zoom'`,
`'native'`/`'python'`, `'quality'`/`'performance'`). `jsondecode` is strict - it rejects both `//`
comments and trailing commas (both verified). Someone hand-editing the file gets no hint what a
field accepts.

Mitigations: a `"_comment"` key convention, or an annotated reference page under `docs/` listing
the legal values per field.

## Plan

### Phase 1 - convert the override file only

`mib3_prefs_override.json` / `mib3_prefs_override_<COMPUTERNAME>.json`, read by
`MibModel.initializePreferences`. `mib3.mat` stays as it is.

This is where the pain actually lands, and it is the low-risk half: the override file is only read
when `mib3.mat` is absent, i.e. on a machine's first run.

It also unlocks **partial overrides**, which the current design cannot express.
`utils.concatenateStructures` already merges field by field with the second argument winning, so a
ten-line JSON naming only `ExternalDirs.PythonInstallationPath` and `IO.Zarr.Library` would simply
work. Today an administrator has to ship all 487 leaves, which is precisely why
`initializePreferences.m:74-86` has to hand-strip `Users` and patch up `KeyShortcuts` after
loading an override - a partial file makes both of those guards unnecessary.

`mib/mib3_override_params.md` and `docs/docs/getting-started/configuration/index.md` both describe
the copy-and-rename procedure and must be rewritten for this.

### Phase 2 - convert the user's own preferences

`mib3.mat` -> `mib3.json`, reusing the same coercion pass, and the parked `mib3_<version>.mat`
files along with it.

Migration is one-time and self-resolving: if `mib3.json` is absent but `mib3.mat` is present, read
the `.mat`, then write `.json` on exit. The top level keeps the existing shape,
`{"mibVersion": 2026.09, "preferences": {...}}`, so the version comparison in
`initializePreferences` is unchanged.

Wrap the decode in try/catch falling back to defaults - a hand-edited file will eventually be
malformed. That fallback is itself an argument for doing phase 1 first, where the blast radius is
a single machine's first startup.

`tests/models/PreferencesVersionTest.m` already redirects `USERPROFILE`/`APPDATA` to a sandbox and
writes preference files of a chosen version, so it is the natural home for round-trip and
coercion tests.
