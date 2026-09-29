# Java in MATLAB R2026b and newer

Implementation notes, 2026-09-29. User page: `docs/docs/getting-started/installation/java.md`
(Getting started -> Installation -> Enable Java).

## The problem

From R2026b MATLAB **and MATLAB Runtime** ship without a JRE. `usejava('jvm')` is false and any Java
call throws `MATLAB:Java:JavaNotFound` ("This feature is attempting to execute Java code, but no
runtime environment for Java applications has been found..."). MIB3 crashed at startup in
`utils.ensureJavaLibraries` -> `javaclasspath('-all')`.

A JVM can only be attached before MATLAB starts: `jenv`/`matlab_jenv` write a setting that the next
MATLAB (or Runtime) session reads. No in-session fix exists.

## What MIB uses Java for

| Feature | Java needed | Without Java |
|---------|-------------|--------------|
| Bio-Formats (`bioformats_package.jar` 8.3.0): loaders, OME-TIFF saver, stitching layout, batch series loop | yes | `MIB:javaNotFound` |
| Fiji (MIJ), Imaris (ImarisLib.jar), OMERO | yes | `MIB:javaNotFound` |
| xlwrite / Apache POI (non-Windows Excel export) | yes | `MIB:javaNotFound` |
| `imclipboard` (image copy/paste) | Windows: no (.NET fallback); macOS/Linux: yes | javachk error, caught and shown |
| BM3D/BM4D, HistThresh | no (plain MATLAB path) | works |

## Changes

### Java gateway - `mib/+utils/ensureJavaLibraries.m`

- `'bm3d'` runs before the first Java call.
- Without a JVM: `'imageselection'` is skipped silently (requested at startup, clipboard has the .NET
  fallback). Any other library throws `MIB:javaNotFound` naming the feature and pointing to
  Preferences -> External directories -> Java and the online help page.
- Reason for throwing rather than returning: returning silently let the failure surface later in
  code that replaced it with a misleading message ("Memoizer can not be initialized" in
  `BioFormatsStdLoader.loadMetadata`).

### Startup - `MibController.initialize`

`~usejava('jvm')` -> "Java is missing" dialog listing the Java features, with **Configure Java**
(OK button -> `utils.JavaSetup.configure`, see the three cases below), **Cancel** and
**Instructions** (help page, local copy first).
Shown on every start while Java is missing; there is no "do not show again" (offered to the author,
not decided).

### Error surfacing

- `MibModel.loadImages`: for `loaderId` starting with `BioFormats`, calls
  `ensureJavaLibraries({'bioformats'})` before `LoaderFactory.create` and shows the message via the
  `ShowErrorDialog` event + `StopProtocol`. `loadImages` is the only `LoaderFactory.create` caller
  that handles an empty loader, so the check was not put into the factory.
- `BioFormatsStdLoader.loadMetadata` Memoizer catch now passes `err` to `showErrorDialog` (the
  generic text becomes the prefix).
- `homeImport_Callback` (clipboard) and `Snapshot` (clipboard export) wrap `imclipboard` in
  try/catch -> MIB error dialog instead of "Error in executing callback".
- `exitProgram`: `unloadOmero` (calls `javarmpath`) only when `usejava('jvm')`; otherwise exit
  would fail before preferences are saved when OMERO is on the MATLAB path.

**Not yet covered**: stitching from Bio-Formats files, OME-TIFF save, batch series loop,
Fiji/Imaris/OMERO buttons. They throw `MIB:javaNotFound` with the clear message, but their callers
do not catch it, so it lands in the command window as a callback error (invisible in the compiled
app).

### Clipboard - `mib/external/imclipboard.m` (File Exchange, marked "MIB modification")

On Windows without Java: `System.Windows.Forms.Clipboard` via .NET. The image travels through a
temporary PNG (`imwrite` -> `System.Drawing.Bitmap(file)` -> `SetImage`; `GetImage().Save(png)` ->
`imread`); lossless. Bitmap disposed before the temp file is deleted (it locks the file).
MATLAB's main thread is STA, which the WinForms clipboard requires.

Verified in R2026b without Java: RGB uint8, grayscale uint8, RGB double, logical, grayscale uint16,
indexed + colormap all round-trip `isequal` to `im2uint8` of the input; empty clipboard -> `[]`;
no temp files left.

### Java setup - `mib/+utils/JavaSetup.m` (static methods)

First version was a function `utils.configureJava` behind **Home -> Preferences ▾ -> Configure
Java**. Replaced the same day (author's review): the dropdown item was hard to find from the
dialog's instructions, and Java belongs with the other external folders. Now:

- **Preferences -> External directories -> "Java path (R2026b or newer)"** (widgets added by the
  author in `PreferencesGUI.mlapp`): `JavaInstallationPath` edit field, `JavaDirSelectBtn` (`...`),
  `JavaFindBtn` ("Find Java...", `selectJava` -> fills the field, writes nothing),
  `JavaConfigureBtn` ("Configure Java...", `apply`). The two new buttons have no callback in the
  mlapp; `controllers.Preferences` sets their `ButtonPushedFcn` in the constructor.
  Apply/OK connects a path that was changed but not configured (`javaAppliedPath` tracks it; one
  attempt per change, so OK after a cancelled Apply does not ask again).
- **`preferences.ExternalDirs.JavaInstallationPath`** (default `[]`). `mib3.mat` is shared between
  MATLAB releases while the MATLAB Java setting is per release (assumed, not verified), so the stored
  folder lets the startup dialog re-apply it after an upgrade. When empty, opening Preferences fills it
  with the Java in use (`configuredHome`), so it is recorded once Java works.
- **Startup dialog** (`MibController.initialize`), three cases: MATLAB `jenv` already points to a
  folder (Java set, restart missing) -> just says restart; stored folder valid -> "connect it again"
  (`configure` with that folder); otherwise -> `configure` (search dialog + apply) and store the result.
  Edge case not handled: `jenv` points to a folder whose Java fails to load -> the "restart" message
  repeats.

1. **Detection** (`findInstallations`): subfolders of vendor folders (`Eclipse Adoptium`,
   `Amazon Corretto`, `Java`, `Microsoft`, `Zulu`, `BellSoft`, `Semeru`, `OpenJDK`,
   `Eclipse Foundation`) under `%ProgramFiles%`, `%ProgramW6432%`, `%LOCALAPPDATA%\Programs`,
   `%USERPROFILE%`; plus direct subfolders of `%USERPROFILE%`, `Documents`, `%USERPROFILE%\Java`
   (unzipped .zip without admin rights); plus `JAVA_HOME`. macOS:
   `/Library/Java/JavaVirtualMachines/*/Contents/Home` (+ user Library); Linux: `/usr/lib/jvm/*`,
   `/opt/java/*`, `~/java/*`.
2. **Validation** (`inspectFolder`): `bin/java(.exe)` and (`release` file or `lib/`); the
   Oracle `javapath` shim has `java.exe` but neither and is rejected. Accepts the `bin` folder or a
   folder with exactly one Java inside (what users pick in `uigetdir`). Version from `JAVA_VERSION`
   in `release`; `1.8.0_x` -> major 8.
3. **Dialog** (`selectJava`): dropdown of found installations + "Select the Java folder
   manually...", default = Java 21, else newest supported. With nothing found the default entry is
   "Search again (after installing Java)" and the OK button reads **Search**: the user downloads,
   installs and presses Search in the same dialog, which loops. **Download Java** opens
   `https://adoptium.net/temurin/releases/?version=21&package=jre&os=<os>&arch=<arch>`.
   Plain text in a `NaN` placeholder row: `inputUniversalDlg` renders `<html>` only in MsgBoxOnly
   mode (its docblock suggests otherwise).
   Compiled Windows app only (`apply`): question "Only for me" / "For all users".
4. **Supported versions** for R2026b: 8, 11, 17, 21, 25 (MathWorks OpenJDK table; Linux: 21 only up
   to 21.0.2). Anything else -> confirm dialog.
5. **Apply**:
   - MATLAB: `jenv(javaHome)`. `jenv` validates the folder itself
     (`MATLAB:Java:JavaDirectoryDoesNotExist`, config left unchanged - verified). After setting,
     only a non-empty `Configuration` is checked (exact format not verified, no Java installed here).
   - Compiled app: `matlab_jenv` of the running Runtime (`matlabroot` = Runtime root; candidates
     `bin/<arch>/matlab_jenv.exe`, `runtime/<arch>/matlab_jenv.exe`, `bin/matlab_jenv`), started via
     `System.Diagnostics.Process`: no cmd.exe quoting problems with two quoted paths, captures output,
     and `Verb = 'runas'` gives the UAC prompt for `-allusers`. Verified with MATLAB's own
     `matlab_jenv.exe` and a nonexistent folder with spaces: exit code 1, message captured, setting
     unchanged. macOS/Linux all-users: shows the `sudo` command instead.
6. Success dialog asks for a restart (MATLAB + MIB, or MIB for the standalone).

### `jenv("system")` finds Temurin 21 after all

The docs say the `system` search looks only for Java **8, 11, 17** (Windows: `java -version`, then
registry). Observed 2026-09-29 on this machine: after installing Temurin 21.0.12 JRE from the MSI
(defaults, Java added to PATH) and restarting, R2026b loaded it with
`jenv` -> `Configuration="system"`, `Status=loaded`,
`Home="C:\Program Files\Eclipse Adoptium\jre-21.0.12.101-hotspot\"`, no configuration by MIB.
Bio-Formats 8.3.0 on that Java opened `05_PLSNLS.zvi` (1388x1040x3, uint16). So the user page says
"install, restart, check" first; `JavaSetup` still writes the explicit folder because a .zip install
is not on PATH.

### Why Temurin 21 JRE

Supported by R2026b on all platforms (Linux caveat above), LTS, and current Fiji releases need
Java 21 (relevant for the MIJ connection, which loads Fiji jars into MATLAB's JVM). JRE rather than
JDK: smaller, sufficient. Linux docs recommend 17 because distro packages ship 21.0.x > 21.0.2.

## Facts about deployment (MathWorks docs, 2026-09)

- MATLAB Runtime R2026b has no JRE; `matlab_jenv` ships in `<Runtime>/bin`.
- The Java setting is not carried by the compiled app: an `-allusers` setting on the build machine is
  not included, and since R2023b a personal non-factory setting is stripped at compile time with a
  warning. The app uses the Runtime's setting on the target machine.
- Per-user `matlab_jenv <path>` (no `-allusers`) is shown in the Compiler docs example for the
  Runtime; not verified that the Runtime reads the per-user setting - hence the all-users option.

Sources: <https://www.mathworks.com/matlab-openjdk>,
<https://www.mathworks.com/support/requirements/openjdk.html>,
<https://www.mathworks.com/help/compiler/configure-matlab-runtime-to-use-java.html>,
<https://www.mathworks.com/matlabcentral/answers/2162010>,
<https://www.mathworks.com/help/matlab/ref/matlab_jenv.html>,
<https://www.mathworks.com/help/matlab/ref/jenv.html>.

## Still to verify (needs a real Java / Runtime)

- [x] MATLAB: Temurin 21 JRE msi -> restart -> loaded via "system" without configuration;
      Bio-Formats opens a ZVI (2026-09-29).
- [ ] MATLAB: `JavaSetup.apply` with a real folder -> what `jenv().Configuration` holds; restart
      loads it. Fiji connect on Java 21.
- [ ] Startup "connect it again" case after `jenv("-clear")` with a stored path.
- [ ] .zip install in `%USERPROFILE%\Java` is detected.
- [ ] Compiled app on R2026b Runtime: `matlab_jenv` location under `matlabroot`; per-user setting is
      honoured by the Runtime; `-allusers` + UAC works; UAC "No" gives a readable message.
- [ ] Temurin MSI default folder name (`jre-21.x.y.z-hotspot`) as written in the user page.
- [ ] Linux/macOS paths (untested).
