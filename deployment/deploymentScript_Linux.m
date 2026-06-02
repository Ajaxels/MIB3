VERSION = "2026.06"; % <-- UPDATE THE VERSION!
projectRoot = "/nfs/home/456500414f5b2c6d/Matlab/MIB3";   % <-- update this path
os_id = 'linux';
showTerminal = true;

% Create target build options object, set build properties and build.
buildOpts = compiler.build.StandaloneApplicationOptions(fullfile(projectRoot, "mib", "mib3.m"));
buildOpts.AdditionalFiles = [
    fullfile(projectRoot, "mib", "+controllers"), ...
    fullfile(projectRoot, "mib", "+core"), ...
    fullfile(projectRoot, "mib", "+deepmib"), ...
    fullfile(projectRoot, "mib", "+io"), ...
    fullfile(projectRoot, "mib", "+models"), ...
    fullfile(projectRoot, "mib", "+utils"), ...
    fullfile(projectRoot, "mib", "+views"), ...
    fullfile(projectRoot, "mib", "assets"), ...
    fullfile(projectRoot, "mib", "external"), ...
    fullfile(projectRoot, "mib", "jars"), ...
    fullfile(projectRoot, "mib", "legacy"), ...
    fullfile(projectRoot, "mib", "plugins"), ...
    ];

buildOpts.AutoDetectDataFiles = true;
buildOpts.OutputDir = fullfile(projectRoot, "deployed", os_id, "files");
buildOpts.ObfuscateArchive = false;
buildOpts.Verbose = true;
buildOpts.EmbedArchive = true;
buildOpts.ExecutableIcon = fullfile(projectRoot, "mib", "assets", "icons", "mib_icon.png");
buildOpts.ExecutableName = "MIB3";
buildOpts.ExecutableSplashScreen = fullfile(projectRoot, "mib", "assets", "images", "splashscreen.jpg");
buildOpts.ExecutableVersion = VERSION;
% buildOpts.RuntimeLogFile = fullfile(projectRoot, "deployed", os_id, 'log_file.txt');
buildOpts.SupportPackages = "none";
buildOpts.TreatInputsAsNumeric = false;

% On Linux there is no standaloneWindowsApplication ? always use standaloneApplication
buildResult = compiler.build.standaloneApplication(buildOpts);

% Create package options object, set package properties and package.
packageOpts = compiler.package.InstallerOptions(buildResult);
packageOpts.ApplicationName = "MIB3";
packageOpts.AuthorEmail = "ilya.belevich@helsinki.fi";
packageOpts.AuthorCompany = "University of Helsinki";
packageOpts.DefaultInstallationDir = "/usr/local/MIB3";   % linux default install path
packageOpts.InstallerIcon = fullfile(projectRoot, "mib", "assets", "icons", "mib_icon.png");
packageOpts.InstallerLogo = fullfile(projectRoot, "mib", "assets", "images", "splashscreen_side.jpg");
packageOpts.InstallerName = "MIB3_Linux";   % renamed from MIB3_Win
packageOpts.InstallerSplash = fullfile(projectRoot, "mib", "assets", "images", "splashscreen.jpg");
packageOpts.OutputDir = fullfile(projectRoot, "deployed", os_id, "installer");
packageOpts.Verbose = true;
packageOpts.Version = VERSION;

packageOpts.Summary = "summary";
packageOpts.Description = "description";

AdditionalFolders = [...
    "assets", ...
    "jars", ...
    "plugins"];

% generate full paths as string array
AdditionalFiles = strings(numel(AdditionalFolders), 1);
for i = 1:numel(AdditionalFolders)
    AdditionalFiles(i) = fullfile(projectRoot, "mib", AdditionalFolders{i});
end
packageOpts.AdditionalFiles = AdditionalFiles;
compiler.package.installer(buildResult, "Options", packageOpts);

% manually copy required files to files distribution
for i = 1:numel(AdditionalFolders)
    src = packageOpts.AdditionalFiles{i};
    dst = fullfile(projectRoot, "deployed", os_id, "files", AdditionalFolders{i});
    copyfile(src, dst);
end