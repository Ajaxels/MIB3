# Enable Java

**Java** is a free piece of software that other programs use to run parts of their code. It has nothing
to do with JavaScript used on web pages and does not need to be started or updated by hand, MIB uses
it in the background.

Starting from **MATLAB R2026b**, Java is no longer included with MATLAB or with the MATLAB Runtime used
by the standalone version of MIB. MIB starts and works without Java, but the following features need it:

- **Bio-Formats**: opening microscope formats such as CZI (Zeiss), LIF (Leica), ND2 (Nikon), ZVI, OIB,
  VSI and many others, and saving OME-TIFF
- connections to **Fiji**, **Imaris** and **OMERO**
- on macOS and Linux, copying images to and from the system clipboard

!!! tip "Do I need Java?"

    If you only work with TIF, PNG, JPG, AM, MRC, HDF5/XML, OME-Zarr or MIB's own formats, you can skip
    this page. You can always come back to it later: MIB tells you when a feature needs Java.

When Java is missing, MIB shows a <b>Java is missing</b> dialog at startup. Setting up Java takes about
five minutes and has to be done once per computer.

## Step 1: Download Java

MIB recommends **Eclipse Temurin 21**, a free Java distribution.

1. Press <span class="widget widget-button">Configure Java</span> in the <b>Java is missing</b> dialog
   and then <span class="widget widget-button">Download Java</span>, or open the
   [Eclipse Temurin download page](https://adoptium.net/temurin/releases/?version=21&package=jre)
   in a web browser.
2. Make sure the page shows **Version 21 - LTS**, **Package Type: JRE** and your operating system
   (for example **Windows**, **x64**).
3. Download one file:

    | Your computer | Download |
    |---------------|----------|
    | Windows, you can install programs (administrator rights) | the **.msi** file |
    | Windows, you **cannot** install programs (typical for computers managed by the IT department) | the **.zip** file |
    | macOS | the **.pkg** file; on Apple silicon (M1, M2, ...) choose **aarch64** |
    | Linux | see [Linux](#linux) below |

??? info "Can I use another Java version?"

    MATLAB R2026b works with Java versions **8, 11, 17, 21 and 25**, from Eclipse Temurin (Adoptium) or
    Amazon Corretto. MIB warns you when the selected Java is not one of those versions. If you do not
    have a reason to choose another one, use Temurin 21.

## Step 2: Install Java

### Windows with administrator rights (.msi file)

Double-click the downloaded **.msi** file and press **Next** until the installation finishes. Keep the
default settings. Java is installed to a folder like
`C:\Program Files\Eclipse Adoptium\jre-21.0.12.101-hotspot`.

### Windows without administrator rights (.zip file)

1. Open your user folder in File Explorer, for example `C:\Users\your-name`, and create a new folder
   called `Java`.
2. Right-click the downloaded **.zip** file, choose **Extract All...**, select the new `Java` folder
   and press **Extract**.

You now have a folder like `C:\Users\your-name\Java\jdk-21.0.12+101-jre`. MIB looks for Java in your
user folder, in `Documents` and in `Java` automatically.

!!! note

    Do not delete or move this folder later: MIB uses Java from where it is.

### macOS (.pkg file)

Double-click the downloaded **.pkg** file and follow the installer.

## Step 3: Restart and check

- **MIB for MATLAB**: close MIB **and MATLAB**, then start MATLAB and MIB again.
- **Standalone MIB**: close MIB and start it again.

After an installation with the **.msi** or **.pkg** file, MATLAB usually finds the new Java by itself.
If the <b>Java is missing</b> dialog no longer appears, Java works and you are done. Otherwise,
continue with Step 4. After an installation from the **.zip** file, Step 4 is always needed.

## Step 4: Connect MIB to Java

1. Open **Ribbon → Home → Preferences → External directories**, or press
   <span class="widget widget-button">Configure Java</span> in the <b>Java is missing</b> dialog,
   which does steps 2 and 3 for you.
2. In the **Java path** row press <span class="widget widget-button">Find Java...</span> and choose
   your Java from the list.
    - If you have just installed Java and the list is empty, press
      <span class="widget widget-button">Search</span> to look again.
    - If your Java is not in the list, choose **Select the Java folder manually...** and select the
      Java folder: the folder that contains the `bin` folder (for example
      `C:\Users\your-name\Java\jdk-21.0.12+101-jre`).
3. Press <span class="widget widget-button">Configure Java...</span>.
    - **Standalone MIB** asks whether to set Java **Only for me** or **For all users** of the computer.
      Choose **Only for me**; choose **For all users** when you set up a computer that several people
      use, or when Java is still missing after the restart. Windows then asks for an administrator
      password.
4. Press <span class="widget widget-button">OK</span> and restart as in Step 3.

Java now works: the <b>Java is missing</b> dialog no longer appears. Open one of your microscope files
to check.

!!! note "After installing a new version of MATLAB"

    A new MATLAB version, or a new MATLAB Runtime for standalone MIB, may not know about the Java that
    you set up before. MIB remembers the Java folder and offers to connect it again with one click in
    the <b>Java is missing</b> dialog.

## Troubleshooting

**The <b>Java is missing</b> dialog appears again after the restart**

- Make sure MATLAB was closed completely, not only MIB.
- Open **Preferences → External directories** and check that the **Java path** folder still exists,
  then press <span class="widget widget-button">Configure Java...</span> again.
- Standalone MIB: press <span class="widget widget-button">Configure Java...</span> again and choose
  **For all users**.

**"This is not a Java folder"**

The selected folder is not the Java folder itself. Select the folder that contains `bin`, `lib` and a
file called `release`.

**No administrator rights and no .zip file allowed**

Ask your IT department to install **Eclipse Temurin JRE 21** and to connect it to MATLAB as described
in the box below.

??? abstract "For IT administrators"

    Install Eclipse Temurin JRE 21 (or another OpenJDK version supported by MATLAB R2026b: 8, 11, 17,
    21, 25). With the default MSI options (Java added to `PATH`), MATLAB R2026b found Temurin 21 without
    further configuration. To set the folder explicitly for all users, run from an elevated command
    prompt:

    - **MATLAB**: `"<MATLAB folder>\bin\matlab_jenv" -allusers "<Java folder>"`
    - **MATLAB Runtime** (standalone MIB):
      `"<MATLAB Runtime folder>\R2026b\bin\matlab_jenv" -allusers "<Java folder>"`

    Run `matlab_jenv` without arguments to see the current setting. In MATLAB the same for the current
    user is `jenv("<Java folder>")` in the Command Window, followed by a MATLAB restart.
    More details: [MATLAB Support for OpenJDK](https://www.mathworks.com/matlab-openjdk) and
    [Use JRE with MATLAB Runtime](https://www.mathworks.com/help/compiler/configure-matlab-runtime-to-use-java.html).

### Linux

Install Java 17 with the package manager of your distribution, for example
`sudo apt install openjdk-17-jre` on Ubuntu, and connect it in Step 4 (Java installations in
`/usr/lib/jvm` are found automatically). Java 17 is recommended on Linux because MATLAB R2026b on
Linux supports Java 21 only up to version 21.0.2, older than what the package managers install.

---

*Back to [MIB](../../index.md) | [Getting started](../index.md) | [Installation](index.md)*
