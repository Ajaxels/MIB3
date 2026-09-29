classdef JavaSetup
    % JAVASETUP - Find an installed Java and connect MATLAB or MATLAB Runtime to it.
    %
    % MATLAB R2026b and newer, and the matching MATLAB Runtime, no longer bundle
    % a Java runtime. MIB starts without Java, but Bio-Formats, Fiji, Imaris,
    % OMERO and (outside Windows) the image clipboard need it. The static
    % methods of this class automate the part of the setup that can be
    % automated; they are used by the "Java is missing" startup dialog
    % (``MibController.initialize``) and by the Java row of
    % Preferences -> External directories (``controllers.Preferences``).
    %
    % The chosen folder is written with ``jenv(javaHome)`` in MATLAB, or with the
    % ``matlab_jenv`` executable of the running MATLAB Runtime in the compiled
    % standalone. The setting is read when MATLAB/MATLAB Runtime starts, so it
    % takes effect only after a restart; a running MATLAB cannot load a JVM.
    % MIB also keeps the folder in ``preferences.ExternalDirs.JavaInstallationPath``
    % (``mib3.mat`` is shared between MATLAB releases while the MATLAB Java
    % setting is not), which lets the startup dialog re-apply it after a MATLAB
    % or MATLAB Runtime upgrade.
    %
    % The explicit folder is always written rather than ``jenv("system")``. The
    % default R2026b configuration already is "system", and in practice it found
    % Temurin 21 installed from the MSI (which adds Java to ``PATH``), even though
    % the MathWorks documentation says that search looks only for Java 8, 11 and
    % 17. A Java unpacked from a .zip is not on ``PATH`` and is never found that
    % way, so when the user reaches this class the folder has to be explicit.
    %
    % Static methods:
    %   - ``configure`` - pick a Java (dialog) when no folder is given, then ``apply``
    %   - ``selectJava`` - search dialog; returns the chosen Java, applies nothing
    %   - ``apply`` - validate a folder, confirm its version and write the setting
    %   - ``inspectFolder`` - check a folder and read its Java version
    %   - ``findInstallations`` - list Java installations in the usual folders
    %   - ``configuredHome`` - folder of the Java MATLAB uses or is set to use
    %
    % **Example 1** - full workflow from a callback:
    %
    %   .. code-block:: matlab
    %
    %      [status, javaHome] = utils.JavaSetup.configure(obj.view.gui, obj.mibModel.mibPath);
    %      if status; obj.mibModel.preferences.ExternalDirs.JavaInstallationPath = javaHome; end
    %

    properties (Constant)
        SupportedMajorVersions = [8 11 17 21 25]    % OpenJDK versions supported by MATLAB R2026b
        RecommendedMajorVersion = 21                % Eclipse Temurin version suggested to the user
    end

    methods (Static)
        function [status, javaHome] = configure(parentFigure, mibPath, javaHome)
            % CONFIGURE - Pick a Java when no folder is given, then connect it.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [status, javaHome] = utils.JavaSetup.configure(parentFigure, mibPath)
            %      [status, javaHome] = utils.JavaSetup.configure(parentFigure, mibPath, javaHome)
            %
            % Input Arguments:
            %   - **parentFigure** - parent window for the dialogs (AppContainer, uifigure or ``[]``)
            %   - **mibPath** - char, MIB installation path, used by the dialogs to locate their icons
            %   - **javaHome** - *(optional)* char, Java folder to connect; when empty, ``selectJava`` is shown
            %
            % Output Arguments:
            %   - **status** - logical, ``true`` when the setting was written
            %   - **javaHome** - char, the connected Java folder, ``''`` when cancelled
            arguments
                parentFigure = []
                mibPath char = ''
                javaHome char = ''
            end
            status = false;
            if isempty(javaHome)
                javaInfo = utils.JavaSetup.selectJava(parentFigure, mibPath);
                if isempty(javaInfo); return; end
                javaHome = javaInfo.home;
            end
            status = utils.JavaSetup.apply(parentFigure, javaHome, mibPath);
            if ~status; javaHome = ''; end
        end

        function javaInfo = selectJava(parentFigure, mibPath)
            % SELECTJAVA - Search dialog: choose an installed Java; nothing is written.
            %
            % Lists the installations found by ``findInstallations`` (default: the
            % recommended version, else the newest supported one) plus
            % "Select the Java folder manually...". When nothing was found, the
            % default entry is "Search again" so that a user who pressed
            % **Download Java** and installed it can simply press **Search** in the
            % same dialog; the dialog is then shown again with the new result.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      javaInfo = utils.JavaSetup.selectJava(parentFigure, mibPath)
            %
            % Output Arguments:
            %   - **javaInfo** - struct with fields ``home``, ``version``, ``major``
            %     (see ``inspectFolder``), or ``[]`` when cancelled
            arguments
                parentFigure = []
                mibPath char = ''
            end
            javaInfo = [];
            manualItem = 'Select the Java folder manually...';
            searchItem = 'Search again (after installing Java)';
            downloadUrl = javaDownloadUrl(utils.JavaSetup.RecommendedMajorVersion);

            dlgOptions = struct();
            dlgOptions.Icon = 'puffin_question';
            dlgOptions.WindowWidth = 620;
            dlgOptions.HeaderLines = 1;
            dlgOptions.LabelPosition = 'top';
            dlgOptions.HelpBtnText = 'Download Java';
            dlgOptions.HelpUrl = @() web(downloadUrl, '-browser');
            if ~isempty(mibPath); dlgOptions.mibPath = mibPath; end

            while true
                javaList = utils.JavaSetup.findInstallations();
                % plain text in a placeholder (NaN) row: inputUniversalDlg renders
                % <html> only in MsgBoxOnly mode
                if isempty(javaList)
                    bodyText = sprintf(['No Java was found on this computer.\n\n' ...
                        '1. Press "Download Java" and install Eclipse Temurin %d (the JRE .msi file)\n' ...
                        '2. When the installation is finished, press "Search"\n\n' ...
                        'If Java is already installed in another folder, choose "%s".'], ...
                        utils.JavaSetup.RecommendedMajorVersion, manualItem);
                    dropdownItems = {searchItem, manualItem};
                    defaultIndex = 1;
                    dlgOptions.OkBtnText = 'Search';
                else
                    bodyText = sprintf('Found %d Java installation(s). Choose the Java that MIB should use:', numel(javaList));
                    dropdownItems = [arrayfun(@(x) sprintf('Java %s   (%s)', x.version, x.home), ...
                        javaList, 'UniformOutput', false), {manualItem}];
                    % prefer the recommended version, then the newest supported one
                    majorVersions = [javaList.major];
                    rank = majorVersions + 1000 * (majorVersions == utils.JavaSetup.RecommendedMajorVersion) ...
                        - 1000 * ~ismember(majorVersions, utils.JavaSetup.SupportedMajorVersions);
                    [~, defaultIndex] = max(rank);
                    dlgOptions.OkBtnText = 'Select';
                end

                [answer, selectedIndices] = utils.dlgs.inputUniversalDlg(parentFigure, 'Find Java', ...
                    {bodyText; 'Java installation:'}, {NaN; [dropdownItems, {defaultIndex}]}, ...
                    'Find Java', dlgOptions);
                if isempty(answer); return; end

                switch answer{2}
                    case searchItem
                        continue;   % search again and show the dialog with the new result
                    case manualItem
                        javaInfo = utils.JavaSetup.browseForJava(parentFigure, mibPath, '');
                        return;
                    otherwise
                        javaInfo = javaList(selectedIndices(2));
                        return;
                end
            end
        end

        function javaInfo = browseForJava(parentFigure, mibPath, startFolder)
            % BROWSEFORJAVA - Folder browser for a Java folder, with validation.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      javaInfo = utils.JavaSetup.browseForJava(parentFigure, mibPath, startFolder)
            %
            % Output Arguments:
            %   - **javaInfo** - struct (see ``inspectFolder``) or ``[]`` when
            %     cancelled or when the folder is not Java (a message is shown)
            arguments
                parentFigure = []
                mibPath char = ''
                startFolder char = ''
            end
            javaInfo = [];
            if isempty(startFolder) || ~isfolder(startFolder); startFolder = defaultBrowseFolder(); end
            selectedFolder = uigetdir(startFolder, 'Select the Java folder (the folder that contains "bin")');
            if isequal(selectedFolder, 0); return; end
            javaInfo = utils.JavaSetup.inspectFolder(selectedFolder);
            if isempty(javaInfo)
                showMessage(parentFigure, mibPath, 'puffin_error', 'This is not a Java folder', ...
                    utils.JavaSetup.notJavaMessage(selectedFolder));
            end
        end

        function status = apply(parentFigure, javaHome, mibPath)
            % APPLY - Validate a Java folder, confirm its version and write the setting.
            %
            % - MATLAB: ``jenv(javaHome)`` (per user). ``jenv`` validates the folder
            %   itself and throws, e.g. ``MATLAB:Java:JavaDirectoryDoesNotExist``.
            % - Compiled standalone: ``matlab_jenv`` of the running MATLAB Runtime
            %   (``matlabroot`` is the Runtime folder in a compiled application).
            %   On Windows the user chooses "Only for me" or "For all users"; the
            %   latter runs elevated through the UAC prompt. It is offered because
            %   it is not verified that the Runtime reads the per-user setting.
            %
            % A version outside ``SupportedMajorVersions`` is confirmed first. On
            % success a message asks for a restart.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      status = utils.JavaSetup.apply(parentFigure, javaHome, mibPath)
            %
            % Output Arguments:
            %   - **status** - logical, ``true`` when the setting was written;
            %     ``false`` on cancel or error (errors are shown in a dialog)
            arguments
                parentFigure = []
                javaHome char = ''
                mibPath char = ''
            end
            status = false;
            javaInfo = utils.JavaSetup.inspectFolder(javaHome);
            if isempty(javaInfo)
                showMessage(parentFigure, mibPath, 'puffin_error', 'This is not a Java folder', ...
                    utils.JavaSetup.notJavaMessage(javaHome));
                return;
            end

            if ~ismember(javaInfo.major, utils.JavaSetup.SupportedMajorVersions)
                confirmAnswer = utils.dlgs.inputQuestDlg(parentFigure, ...
                    sprintf(['Java %s is not on the list of versions supported by MATLAB ' ...
                    '(%s).\n\nMIB may fail to start Java with it. We recommend Eclipse Temurin %d.\n\nUse it anyway?'], ...
                    javaInfo.version, strjoin(string(utils.JavaSetup.SupportedMajorVersions), ', '), ...
                    utils.JavaSetup.RecommendedMajorVersion), ...
                    'Unsupported Java version', 'Use anyway', 'Cancel', 'Cancel', ...
                    struct('Icon', 'puffin_warning', 'WindowWidth', 480, 'WindowHeight', 200, 'mibPath', mibPath));
                if ~strcmp(confirmAnswer, 'Use anyway'); return; end
            end

            allUsers = false;
            if isdeployed && ispc
                scopeAnswer = utils.dlgs.inputQuestDlg(parentFigure, ...
                    sprintf(['Connect MIB to Java %s only for you, or for everybody who uses this computer?\n\n' ...
                    '"For all users" asks for administrator rights. Use it also when Java is still ' ...
                    'missing after connecting it only for you and restarting MIB.'], javaInfo.version), ...
                    'Configure Java', 'Only for me', 'For all users', 'Cancel', 'Only for me', ...
                    struct('Icon', 'puffin_question', 'WindowWidth', 500, 'WindowHeight', 210, 'mibPath', mibPath));
                switch scopeAnswer
                    case 'Only for me'
                        allUsers = false;
                    case 'For all users'
                        allUsers = true;
                    otherwise
                        return;
                end
            end

            try
                if isdeployed
                    applyToMatlabRuntime(javaInfo.home, allUsers);
                else
                    jenv(string(javaInfo.home));
                    javaEnvironment = jenv;
                    if strlength(string(javaEnvironment.Configuration)) == 0
                        error('MIB:JavaSetup:notApplied', 'MATLAB did not store the Java folder.');
                    end
                end
            catch err
                showMessage(parentFigure, mibPath, 'puffin_error', 'Java was not configured', ...
                    sprintf('Java could not be connected:\n%s\n\n%s', javaInfo.home, err.message));
                return;
            end

            status = true;
            showMessage(parentFigure, mibPath, 'puffin_info', 'Java is configured', ...
                sprintf(['MIB will use Java %s from\n%s\n\n' ...
                'Please %s now. Java becomes available after the restart.'], ...
                javaInfo.version, javaInfo.home, utils.JavaSetup.restartText()));
        end

        function javaInfo = inspectFolder(folderName)
            % INSPECTFOLDER - Check that a folder holds Java and read its version.
            %
            % A Java folder has ``bin/java(.exe)`` and a ``release`` file or a
            % ``lib`` folder; the Oracle ``javapath`` shim folder has ``java.exe``
            % but neither, and is rejected. The ``bin`` folder itself, or a folder
            % with exactly one Java inside (e.g. ``C:\Program Files\Eclipse Adoptium``),
            % is accepted and resolved to the Java folder, since that is what users
            % often pick in the folder browser. The version comes from
            % ``JAVA_VERSION`` in ``release``; ``1.8.0_x`` gives major version 8.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      javaInfo = utils.JavaSetup.inspectFolder(folderName)
            %
            % Output Arguments:
            %   - **javaInfo** - struct with fields ``home`` (char, resolved Java
            %     folder), ``version`` (char, ``'unknown'`` without a release file),
            %     ``major`` (double, ``NaN`` when unknown); ``[]`` when not Java
            javaInfo = [];
            if isempty(folderName) || ~isfolder(folderName); return; end
            folderName = char(folderName);
            [parentFolder, lastName] = fileparts(strip(folderName, 'right', filesep));
            if strcmpi(lastName, 'bin'); folderName = parentFolder; end
            if ~hasJavaExecutable(folderName)
                innerFolders = subfolders(folderName);
                innerFolders = innerFolders(cellfun(@hasJavaExecutable, innerFolders));
                if isscalar(innerFolders)
                    folderName = innerFolders{1};
                else
                    return;
                end
            end
            if ~isfile(fullfile(folderName, 'release')) && ~isfolder(fullfile(folderName, 'lib')); return; end

            versionText = 'unknown';
            releaseFile = fullfile(folderName, 'release');
            if isfile(releaseFile)
                versionToken = regexp(fileread(releaseFile), 'JAVA_VERSION="([^"]+)"', 'tokens', 'once');
                if ~isempty(versionToken); versionText = versionToken{1}; end
            end
            javaInfo = struct('home', folderName, 'version', versionText, 'major', majorVersion(versionText));
        end

        function javaList = findInstallations()
            % FINDINSTALLATIONS - List Java installations in the usual folders.
            %
            % Windows: subfolders of the vendor folders (Eclipse Adoptium, Amazon
            % Corretto, Java, Microsoft, Zulu, BellSoft, Semeru, OpenJDK, Eclipse
            % Foundation) under ``%ProgramFiles%``, ``%ProgramW6432%``,
            % ``%LOCALAPPDATA%\Programs`` and ``%USERPROFILE%``; direct subfolders of
            % ``%USERPROFILE%``, ``Documents`` and ``%USERPROFILE%\Java`` (a Java
            % unpacked from a .zip without administrator rights). macOS:
            % ``/Library/Java/JavaVirtualMachines/*/Contents/Home`` (system and user
            % Library). Linux: ``/usr/lib/jvm``, ``/opt/java``, ``~/java``. Plus
            % ``JAVA_HOME`` on every platform. Takes well under a second.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      javaList = utils.JavaSetup.findInstallations()
            %
            % Output Arguments:
            %   - **javaList** - struct array (see ``inspectFolder``), empty when none
            candidateFolders = {};
            if ispc
                installRoots = unique({getenv('ProgramFiles'), getenv('ProgramW6432'), ...
                    fullfile(getenv('LOCALAPPDATA'), 'Programs'), getenv('USERPROFILE')});
                vendorFolders = {'Eclipse Adoptium', 'Amazon Corretto', 'Java', 'Microsoft', 'Zulu', ...
                    'BellSoft', 'Semeru', 'OpenJDK', 'Eclipse Foundation'};
                for rootIndex = 1:numel(installRoots)
                    if isempty(installRoots{rootIndex}); continue; end
                    for vendorIndex = 1:numel(vendorFolders)
                        candidateFolders = [candidateFolders, ...
                            subfolders(fullfile(installRoots{rootIndex}, vendorFolders{vendorIndex}))]; %#ok<AGROW>
                    end
                end
                candidateFolders = [candidateFolders, subfolders(getenv('USERPROFILE')), ...
                    subfolders(fullfile(getenv('USERPROFILE'), 'Documents')), ...
                    subfolders(fullfile(getenv('USERPROFILE'), 'Java'))];
            elseif ismac
                candidateFolders = [fullfile(subfolders('/Library/Java/JavaVirtualMachines'), 'Contents', 'Home'), ...
                    fullfile(subfolders(fullfile(getenv('HOME'), 'Library', 'Java', 'JavaVirtualMachines')), 'Contents', 'Home')];
            else
                candidateFolders = [subfolders('/usr/lib/jvm'), subfolders('/opt/java'), subfolders(fullfile(getenv('HOME'), 'java'))];
            end
            if ~isempty(getenv('JAVA_HOME')); candidateFolders{end+1} = getenv('JAVA_HOME'); end

            javaList = struct('home', {}, 'version', {}, 'major', {});
            knownHomes = {};
            for folderIndex = 1:numel(candidateFolders)
                javaInfo = utils.JavaSetup.inspectFolder(candidateFolders{folderIndex});
                if isempty(javaInfo) || any(strcmpi(knownHomes, javaInfo.home)); continue; end
                knownHomes{end+1} = javaInfo.home; %#ok<AGROW>
                javaList(end+1) = javaInfo; %#ok<AGROW>
            end
        end

        function javaHome = configuredHome()
            % CONFIGUREDHOME - Folder of the Java that MATLAB uses or is set to use.
            %
            % With a loaded JVM: the ``java.home`` system property (for a Java 8
            % JDK this is its ``jre`` subfolder). Without one, in MATLAB: the
            % ``jenv`` configuration when it is a folder (i.e. set but MATLAB not
            % restarted yet). Without one in the compiled standalone: ``''``, as
            % the MATLAB Runtime setting is not read back.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      javaHome = utils.JavaSetup.configuredHome()
            javaHome = '';
            if usejava('jvm')
                javaHome = char(java.lang.System.getProperty('java.home'));
            elseif ~isdeployed
                try
                    configuration = char(jenv().Configuration);
                    if isfolder(configuration); javaHome = configuration; end
                catch
                end
            end
        end

        function text = restartText()
            % RESTARTTEXT - What the user has to restart for a new Java setting.
            if isdeployed
                text = 'close MIB and start it again';
            else
                text = 'close MIB and MATLAB and start them again';
            end
        end

        function text = notJavaMessage(folderName)
            % NOTJAVAMESSAGE - Explanation shown for a folder that is not Java.
            text = sprintf(['The selected folder does not contain Java:\n%s\n\n' ...
                'Select the Java folder itself, the one that contains the "bin" folder, for example\n' ...
                'C:\\Program Files\\Eclipse Adoptium\\jre-21.0.5.11-hotspot'], folderName);
        end
    end
end

%% ------------------------------------------------------------------------
function tf = hasJavaExecutable(folderName)
if ispc
    tf = isfile(fullfile(folderName, 'bin', 'java.exe'));
else
    tf = isfile(fullfile(folderName, 'bin', 'java'));
end
end

function major = majorVersion(versionText)
% "1.8.0_432" -> 8, "21.0.5" -> 21, "unknown" -> NaN
numbers = sscanf(regexprep(versionText, '[^0-9.].*$', ''), '%d.');
if isempty(numbers)
    major = NaN;
elseif numbers(1) == 1 && numel(numbers) > 1
    major = numbers(2);
else
    major = numbers(1);
end
end

function folderList = subfolders(folderName)
folderList = {};
if isempty(folderName) || ~isfolder(folderName); return; end
listing = dir(folderName);
listing = listing([listing.isdir] & ~startsWith({listing.name}, '.'));
folderList = fullfile(folderName, {listing.name});
end

function folderName = defaultBrowseFolder()
if ispc
    folderName = getenv('ProgramFiles');
elseif ismac
    folderName = '/Library/Java/JavaVirtualMachines';
else
    folderName = '/usr/lib/jvm';
end
if ~isfolder(folderName); folderName = pwd; end
end

function url = javaDownloadUrl(majorVersion)
% Eclipse Temurin download page pre-filtered to the JRE for this computer
if ispc
    osName = 'windows';
elseif ismac
    osName = 'mac';
else
    osName = 'linux';
end
if contains(computer('arch'), 'maca64')
    archName = 'aarch64';
else
    archName = 'x64';
end
url = sprintf('https://adoptium.net/temurin/releases/?version=%d&package=jre&os=%s&arch=%s', ...
    majorVersion, osName, archName);
end

function applyToMatlabRuntime(javaHome, allUsers)
% run matlab_jenv of the MATLAB Runtime that runs this application; in a
% compiled application matlabroot is the MATLAB Runtime folder
jenvExecutable = '';
candidates = {fullfile(matlabroot, 'bin', computer('arch'), 'matlab_jenv.exe'), ...
    fullfile(matlabroot, 'runtime', computer('arch'), 'matlab_jenv.exe'), ...
    fullfile(matlabroot, 'bin', 'matlab_jenv')};
for candidateIndex = 1:numel(candidates)
    if isfile(candidates{candidateIndex})
        jenvExecutable = candidates{candidateIndex};
        break;
    end
end
if isempty(jenvExecutable)
    error('MIB:JavaSetup:noMatlabJenv', ...
        'matlab_jenv was not found in the MATLAB Runtime folder:\n%s', matlabroot);
end

if allUsers
    jenvArguments = sprintf('-allusers "%s"', javaHome);
else
    jenvArguments = sprintf('"%s"', javaHome);
end

if ispc
    % .NET Process instead of system(): no cmd.exe quoting of the two quoted
    % paths, and the Verb "runas" gives the UAC prompt for the all-users case
    startInfo = System.Diagnostics.ProcessStartInfo(jenvExecutable, jenvArguments);
    startInfo.CreateNoWindow = true;
    if allUsers
        startInfo.UseShellExecute = true;   % required for Verb
        startInfo.Verb = 'runas';
        startInfo.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;
    else
        startInfo.UseShellExecute = false;
        startInfo.RedirectStandardOutput = true;
        startInfo.RedirectStandardError = true;
    end
    try
        process = System.Diagnostics.Process.Start(startInfo);
    catch err
        % Win32 error 1223: the user answered "No" in the UAC prompt
        error('MIB:JavaSetup:elevationRefused', ...
            'matlab_jenv could not be started with administrator rights:\n%s', err.message);
    end
    commandOutput = '';
    if ~allUsers
        commandOutput = [char(process.StandardOutput.ReadToEnd()) char(process.StandardError.ReadToEnd())];
    end
    process.WaitForExit();
    exitCode = process.ExitCode;
else
    if allUsers
        error('MIB:JavaSetup:allUsersUnsupported', ...
            'To configure Java for all users, run in a terminal:\nsudo "%s" %s', jenvExecutable, jenvArguments);
    end
    [exitCode, commandOutput] = system(sprintf('"%s" %s', jenvExecutable, jenvArguments));
end
if exitCode ~= 0
    error('MIB:JavaSetup:matlabJenvFailed', ...
        'matlab_jenv finished with code %d:\n%s', exitCode, strtrim(commandOutput));
end
end

function showMessage(parentFigure, mibPath, icon, title, message)
dlgOptions = struct('MsgBoxOnly', true, 'Icon', icon, 'HeaderLines', 1, 'WindowWidth', 520);
if ~isempty(mibPath); dlgOptions.mibPath = mibPath; end
utils.dlgs.inputUniversalDlg(parentFigure, title, {''}, {message}, title, dlgOptions);
end
