projectRoot = "E:\OneDrive - University of Helsinki\Matlab\MIB_OneDrive\MIB3";

% Create target build options object, set build properties and build.
buildOpts = compiler.build.StandaloneApplicationOptions(fullfile(projectRoot, "mib", "mib3.m"));
buildOpts.AdditionalFiles = [fullfile(projectRoot, "mib", "assets"), fullfile(projectRoot, "mib", "assets", "icons"), fullfile(projectRoot, "mib", "assets", "images")];
buildOpts.AutoDetectDataFiles = true;
buildOpts.OutputDir = fullfile(projectRoot, "deployed", "files");
buildOpts.ObfuscateArchive = false;
buildOpts.Verbose = true;
buildOpts.EmbedArchive = true;
buildOpts.ExecutableName = "MIB";
buildOpts.ExecutableVersion = "2025.11";
buildOpts.TreatInputsAsNumeric = false;
buildResult = compiler.build.standaloneApplication(buildOpts);


% Create package options object, set package properties and package.
packageOpts = compiler.package.InstallerOptions(buildResult);
packageOpts.ApplicationName = "My Desktop Application";
packageOpts.AuthorEmail = "ilya.belevich@helsinki.fi";
packageOpts.AuthorCompany = "University of Helsinki";
packageOpts.DefaultInstallationDir = "%ProgramFiles%/MIB3";
packageOpts.InstallerName = "MIB3_Win";
packageOpts.OutputDir = fullfile(projectRoot, "deployed", "installer");
packageOpts.Verbose = true;
packageOpts.Version = "2025.11";
packageOpts.AdditionalFiles = [fullfile(projectRoot, "mib", "assets"), fullfile(projectRoot, "mib", "assets", "icons"), fullfile(projectRoot, "mib", "assets", "images")];
compiler.package.installer(buildResult, "Options", packageOpts);