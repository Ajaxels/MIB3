%% UPDATE THE VERSION!
%% UPDATE THE PATH!

VERSION = "2026.06"; % <-- UPDATE THE VERSION!
PROJECT_ROOT = "/users/belevich/Desktop/MIB3";   % <-- UPDATE THE PATH
OS_ID = 'linux';
SHOW_TERMINAL = true;

% Plugin folders under mib/plugins that must not be shipped, e.g. personal
% or unreleased plugins. compiler.build.StandaloneApplicationOptions has no
% exclude property, so instead of pointing the build at mib/plugins directly
% a filtered copy of that folder is staged in tempdir and used both for the
% compiled archive and for the installer.
EXCLUDE_PLUGINS = "MyPlugins";

stagedPlugins = fullfile(tempdir, "MIB3_build_staging", "plugins");
if isfolder(stagedPlugins); rmdir(stagedPlugins, "s"); end
copyfile(fullfile(PROJECT_ROOT, "mib", "plugins"), stagedPlugins);
for pluginIndex = 1:numel(EXCLUDE_PLUGINS)
    excludedFolder = fullfile(stagedPlugins, EXCLUDE_PLUGINS(pluginIndex));
    if isfolder(excludedFolder); rmdir(excludedFolder, "s"); end
end

% The built user documentation ships next to the executable so that the Help
% buttons open local pages instead of mib.helsinki.fi. Both the installer and
% the copy loop at the end of this script name the destination folder after
% the basename of the source, so docs/html cannot be listed directly - a
% staged folder called "docs" holding "html" gives the wanted docs/html layout.
docsSource = fullfile(PROJECT_ROOT, "docs", "html");
if ~isfolder(docsSource)
    error('deploymentScript:noDocs', ...
        'Built documentation is missing in %s, build docs before packaging', docsSource);
end
stagedDocs = fullfile(tempdir, "MIB3_build_staging", "docs");
if isfolder(stagedDocs); rmdir(stagedDocs, "s"); end
copyfile(docsSource, fullfile(stagedDocs, "html"));

% Licenses of the third-party code sit next to that code in mib/external,
% which is compiled into the archive and not shipped as a folder, so they
% are gathered into licenses/external of a staged copy of mib/licenses.
% The file naming is not uniform (*_license.txt, LICENSE, license.txt,
% license_matGeom.txt, ...), so every file with "license" in its name is
% taken, and its subfolder under mib/external is kept so that, e.g.,
% export_fig/LICENSE and HistThresh/LICENSE do not overwrite each other.
externalRoot = fullfile(PROJECT_ROOT, "mib", "external");
stagedLicenses = fullfile(tempdir, "MIB3_build_staging", "licenses");
if isfolder(stagedLicenses); rmdir(stagedLicenses, "s"); end
copyfile(fullfile(PROJECT_ROOT, "mib", "licenses"), stagedLicenses);
licenseFiles = dir(fullfile(externalRoot, "**", "*"));
licenseFiles = licenseFiles(~[licenseFiles.isdir] & ...
    contains({licenseFiles.name}, "license", "IgnoreCase", true));
if isempty(licenseFiles)
    error('deploymentScript:noExternalLicenses', ...
        'No license files of external packages found in %s', externalRoot);
end
for fileIndex = 1:numel(licenseFiles)
    relativeFolder = extractAfter(string(licenseFiles(fileIndex).folder), strlength(externalRoot));
    targetFolder = fullfile(stagedLicenses, "external", relativeFolder);
    if ~isfolder(targetFolder); mkdir(targetFolder); end
    copyfile(fullfile(licenseFiles(fileIndex).folder, licenseFiles(fileIndex).name), targetFolder);
end

% Create target build options object, set build properties and build.
% buildOpts = compiler.build.StandaloneApplicationOptions(fullfile(PROJECT_ROOT, "mib", "mib3.m"));
buildOpts = compiler.build.StandaloneApplicationOptions(fullfile(PROJECT_ROOT, "mib", "mib3_deploy.m"));

buildOpts.AdditionalFiles = [
    fullfile(PROJECT_ROOT, "mib", "+controllers"), ...
    fullfile(PROJECT_ROOT, "mib", "+core"), ...
    fullfile(PROJECT_ROOT, "mib", "+deepmib"), ...
    fullfile(PROJECT_ROOT, "mib", "+io"), ...
    fullfile(PROJECT_ROOT, "mib", "+models"), ...
    fullfile(PROJECT_ROOT, "mib", "+utils"), ...
    fullfile(PROJECT_ROOT, "mib", "+views"), ...
    fullfile(PROJECT_ROOT, "mib", "assets"), ...
    fullfile(PROJECT_ROOT, "mib", "external"), ...
    fullfile(PROJECT_ROOT, "mib", "jars"), ...
    fullfile(PROJECT_ROOT, "mib", "legacy"), ...
    stagedPlugins, ...
    ];

buildOpts.AutoDetectDataFiles = true;
buildOpts.OutputDir = fullfile(PROJECT_ROOT, "deployed", OS_ID, "files");
buildOpts.ObfuscateArchive = false;
buildOpts.Verbose = true;
buildOpts.EmbedArchive = true;
buildOpts.ExecutableIcon = fullfile(PROJECT_ROOT, "mib", "assets", "icons", "mib_icon.png");
buildOpts.ExecutableName = "MIB3";
buildOpts.ExecutableSplashScreen = fullfile(PROJECT_ROOT, "mib", "assets", "images", "splashscreen.jpg");
buildOpts.ExecutableVersion = VERSION;
% buildOpts.RuntimeLogFile = fullfile(PROJECT_ROOT, "deployed", OS_ID, 'log_file.txt');
buildOpts.SupportPackages = "autodetect";  % none, autodetect
buildOpts.TreatInputsAsNumeric = false;

% On Linux there is no standaloneWindowsApplication - always use standaloneApplication
buildResult = compiler.build.standaloneApplication(buildOpts);

% Create package options object, set package properties and package.
packageOpts = compiler.package.InstallerOptions(buildResult);
packageOpts.ApplicationName = "MIB3";
packageOpts.AuthorEmail = "ilya.belevich@helsinki.fi";
packageOpts.AuthorCompany = "University of Helsinki";
packageOpts.DefaultInstallationDir = "/usr/local/MIB3";   % linux default install path
packageOpts.InstallerIcon = fullfile(PROJECT_ROOT, "mib", "assets", "icons", "mib_icon.png");
packageOpts.InstallerLogo = fullfile(PROJECT_ROOT, "mib", "assets", "images", "splashscreen_side.jpg");
packageOpts.InstallerName = "MIB3_Linux";   % renamed from MIB3_Win
packageOpts.InstallerSplash = fullfile(PROJECT_ROOT, "mib", "assets", "images", "splashscreen.jpg");
packageOpts.OutputDir = fullfile(PROJECT_ROOT, "deployed", OS_ID, "installer");
packageOpts.Verbose = true;
packageOpts.Version = VERSION;

packageOpts.Summary = "Image processing, segmentation and visualization of multidimensional microscopy datasets";
packageOpts.Description = join([ ...
    "Microscopy Image Browser (MIB) is a free open-source package for processing, segmentation, analysis and visualization of multidimensional (2D-4D) microscopy datasets.", ...
    "", ...
    "Key features: import and export of the most common microscopy and volume formats, alignment and stitching of image stacks, contrast and intensity adjustments, manual and automatic segmentation including deep learning (DeepMIB), quantification of 2D and 3D objects, direct 3D visualization and custom plugins.", ...
    "", ...
    "Developed at the Electron Microscopy Unit, Institute of Biotechnology, University of Helsinki.", ...
    "http://mib.helsinki.fi", ...
    "", ...
    "This standalone version is compiled under an academic MATLAB license, its use for commercial purposes is prohibited. See the licenses folder of the installation for the full terms."], newline);

% names of the folders as they appear next to the executable
AdditionalFolders = [...
    "assets", ...
    "jars", ...
    "licenses", ...
    "plugins", ...
    "docs"];

% sources for the folders above; licenses, plugins and docs are taken from
% the staged copies so that the external licenses are included,
% EXCLUDE_PLUGINS are missing from the installer as well and the
% documentation keeps its docs/html nesting
AdditionalFolderSources = [...
    fullfile(PROJECT_ROOT, "mib", "assets"), ...
    fullfile(PROJECT_ROOT, "mib", "jars"), ...
    stagedLicenses, ...
    stagedPlugins, ...
    stagedDocs];

AdditionalFiles = [...
    fullfile(PROJECT_ROOT, "mib", "mib3_override_params.md")];

packageAdditionalFiles = AdditionalFolderSources(:);

% append individual files
packageAdditionalFiles = [packageAdditionalFiles; AdditionalFiles(:)];

packageOpts.AdditionalFiles = packageAdditionalFiles;
compiler.package.installer(buildResult, "Options", packageOpts);

% copy folders
for i = 1:numel(AdditionalFolders)
    src = packageAdditionalFiles(i);
    dst = fullfile(PROJECT_ROOT, "deployed", OS_ID, "files", AdditionalFolders(i));
    copyfile(src, dst);
end

% copyfile only adds files, so drop excluded plugins left in the output
% folder by an earlier build
for pluginIndex = 1:numel(EXCLUDE_PLUGINS)
    excludedFolder = fullfile(PROJECT_ROOT, "deployed", OS_ID, "files", "plugins", EXCLUDE_PLUGINS(pluginIndex));
    if isfolder(excludedFolder); rmdir(excludedFolder, "s"); end
end

% copy individual files
for i = numel(AdditionalFolders)+1:numel(packageAdditionalFiles)
    src = packageAdditionalFiles(i);
    [~, fname, ext] = fileparts(src);
    dst = fullfile(PROJECT_ROOT, "deployed", OS_ID, "files", fname + ext);
    copyfile(src, dst);
end