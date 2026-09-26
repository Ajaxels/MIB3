# Compiling the MIB3 MEX files on a Mac with Apple silicon

MIB3 contains a few functions written in C/C++ (called MEX files) for speed. They must be compiled
separately for every type of computer, and MIB3 does not have them yet for Macs with Apple silicon
(M1, M2, M3, M4, ... processors). This guide explains how to compile them on such a Mac and send
them back. No programming knowledge is needed. It takes about 20-40 minutes, most of it waiting for
downloads.

You will need:

- a Mac with Apple silicon (Apple menu > **About This Mac** shows "Chip: Apple M...")
- MATLAB for Apple silicon, any recent version
- the MIB3 folder you were given. It contains the `mib` and `deployment` folders and this file.
- an administrator password for the Mac (to install Apple's compiler)
- an internet connection

## Step 1. Check that MATLAB is the Apple silicon version

MATLAB is available for Macs in two versions, one for Intel and one for Apple silicon, and the
Intel version also runs on Apple silicon Macs. Only the Apple silicon version can make the files we
need.

1. Start MATLAB.
2. In the **Command Window** (the panel with the `>>` prompt), type the following and press Return:

   ```matlab
   computer('arch')
   ```

3. The answer must be `'maca64'`.
   If it is `'maci64'`, this is the Intel version. Download and install **MATLAB for Apple silicon**
   from [mathworks.com/downloads](https://www.mathworks.com/downloads), then repeat this step.

## Step 2. Install Apple's compiler (Xcode Command Line Tools)

1. Open the **Terminal** app: press Cmd+Space, type `Terminal`, press Return.
2. Type (or paste) the following command and press Return:

   ```bash
   xcode-select --install
   ```

3. A window appears. Click **Install**, then **Agree** to the license. The download takes 5-20
   minutes.
   If Terminal instead replies `command line tools are already installed`, they are installed
   already. Continue with the next step.
4. When it has finished, check it in Terminal:

   ```bash
   clang --version
   ```

   It should print something like `Apple clang version 16.0.0`.

## Step 3 (optional). Install the Fortran compiler

One part of MIB3 (the Random Forest classifier, used by Membrane detection) also needs a Fortran
compiler. Everything else compiles without it, so skip this step if it causes trouble. The script
then reports those two files as "skipped".

1. Install **Homebrew**, a free installer for developer tools. Open [brew.sh](https://brew.sh),
   copy the command shown under "Install Homebrew", paste it into Terminal and press Return. Enter
   your Mac password when asked (nothing is shown while you type it, this is normal) and press
   Return again when asked to continue.
2. At the end Homebrew prints **"Next steps"** with two or three commands that start with `echo` or
   `eval`. Copy and run them in Terminal. They make the `brew` command available.
3. Install the GNU compilers, which include Fortran. This takes a few minutes:

   ```bash
   brew install gcc
   ```

4. Check it:

   ```bash
   gfortran --version
   ```

   It should print something like `GNU Fortran (Homebrew GCC 15.1.0) 15.1.0`.

## Step 4. Tell MATLAB to use the compiler

If MATLAB was open during Steps 2-3, quit and start it again first. Then type in the MATLAB
**Command Window**:

```matlab
mex -setup C
```

It should reply with a line that starts with `MEX configured to use` and mentions Xcode or Clang.

Then type:

```matlab
mex -setup C++
```

Again, the reply should start with `MEX configured to use`.

If you see `No supported compiler was found` instead, see [Troubleshooting](#troubleshooting).

## Step 5. Compile

1. In MATLAB, go to the `deployment` folder of MIB3. Replace the path with the location of your
   MIB3 folder. For example, if it is in your Downloads folder:

   ```matlab
   cd ~/Downloads/MIB3/deployment
   ```

   You can also use the **Current Folder** panel or the **Browse for folder** button above it.
2. Start the compilation:

   ```matlab
   mib3_compile_c_files
   ```

3. The script compiles 16 files one by one and prints `OK`, `FAILED` or `skipped` for each. This
   takes 1-3 minutes. It always continues to the end, even if some files fail.
4. At the end it prints a **Summary** with the lists of built, failed and skipped files. The last
   lines show where the results were packed:

   ```text
   The built files are packed into:
     /Users/<you>/Downloads/MIB3/deployment/mib3_mex_mexmaca64.zip
   ```

Note: `nrrdLoadWithMetadata` is always shown as skipped. This is expected, macOS does not need it.

## Step 6. Send the results back

Send back:

1. the file `deployment/mib3_mex_mexmaca64.zip`
2. if anything **FAILED**: all the text of the MATLAB Command Window from `=== Compiling MIB3 MEX
   files ===` down to `Done.` Select it with the mouse, copy (Cmd+C) and paste it into the email.

That is all, thank you!

## Files that will be created

All new files end with `.mexmaca64` and are written next to their source code inside the `mib`
folder:

| File | Used in MIB3 by |
|------|-----------------|
| `mib/external/Supervoxels/maxflowmex_v222.mexmaca64` | Graphcut segmentation |
| `mib/external/Supervoxels/slicmex.mexmaca64` | Graphcut, brush with superpixels, SLIC clustering filter (2D) |
| `mib/external/Supervoxels/slicomex.mexmaca64` | not used at the moment, built for completeness |
| `mib/external/Supervoxels/slicsupervoxelmex.mexmaca64` | not used at the moment, built for completeness |
| `mib/external/Supervoxels/slicsupervoxelmex_byte.mexmaca64` | Graphcut with supervoxels, SLIC clustering filter (3D) |
| `mib/external/RegionGrowing/RegionGrowing_mex.mexmaca64` | Region growing tool |
| `mib/external/FastMarching/functions/msfm2d.mexmaca64` | curve tracing (fast marching, 2D) |
| `mib/external/FastMarching/functions/msfm3d.mexmaca64` | curve tracing (fast marching, 3D) |
| `mib/external/FastMarching/shortestpath/rk4.mexmaca64` | curve tracing (shortest path) |
| `mib/external/RandomForest/MembraneDetection/meanvar.mexmaca64` | Membrane detection features |
| `mib/external/RandomForest/MembraneDetection/transformImageFast.mexmaca64` | Membrane detection features |
| `mib/external/RandomForest/RF_Class_C/mexClassRF_train.mexmaca64` | Membrane detection classifier (needs Step 3) |
| `mib/external/RandomForest/RF_Class_C/mexClassRF_predict.mexmaca64` | Membrane detection classifier (needs Step 3) |
| `mib/external/RandomForest/RF_Reg_C/mexRF_train.mexmaca64` | not used at the moment, built for completeness |
| `mib/external/RandomForest/RF_Reg_C/mexRF_predict.mexmaca64` | not used at the moment, built for completeness |
| `mib/+utils/GetExeLocation.mexmaca64` | locating the standalone MIB3 application |

In addition, the zip file `deployment/mib3_mex_mexmaca64.zip` contains all of the built files above.
Nothing else on the Mac is changed.

## Troubleshooting

**`No supported compiler was found` in Step 4, or the script says `No C or C++ compiler is selected`**

- Make sure Step 2 finished, then quit and restart MATLAB and repeat Step 4.
- Some MATLAB versions need the full **Xcode** app instead of the Command Line Tools:
  1. Install **Xcode** from the App Store (it is large, about 10 GB).
  2. Start Xcode once and accept the license, then quit it.
  3. In Terminal run the following (enter your Mac password when asked):

     ```bash
     sudo xcode-select --switch /Applications/Xcode.app
     sudo xcodebuild -license accept
     ```

  4. Restart MATLAB and repeat Step 4.

**`xcrun: error: invalid active developer path`**

The Command Line Tools are missing or were removed by a macOS update. Repeat Step 2.

**The two `mexClassRF_...` files are skipped with `needs the gfortran compiler`**

Step 3 was skipped or did not finish. Either complete Step 3 and run `mib3_compile_c_files` again,
or just send back what was built, the rest is still useful.

**One or more files FAILED**

Send the whole Command Window text as described in Step 6. The red message under each failed file
contains the compiler error needed to fix it.

**You want to run it again**

Just run `mib3_compile_c_files` again. It overwrites the previous results and the zip file.

## Notes for the MIB3 maintainer

- Unpack `mib3_mex_mexmaca64.zip` in the repository root: the paths inside start with `mib/`.
- Test in MIB3 on the Mac: Graphcut (Watershed and SLIC modes), Region growing, curve tracing and
  Membrane detection.
- Files downloaded from the internet get the macOS quarantine flag, and macOS may then refuse to load
  them ("cannot be opened because the developer cannot be verified"). If users see this, the flag is
  removed with `xattr -dr com.apple.quarantine <MIB3 folder>`.
- The script builds the files for whatever MATLAB runs it, so the same procedure makes `.mexa64` on
  Linux and `.mexmaci64` on an Intel Mac. Details are in the header of `mib3_compile_c_files.m`.
