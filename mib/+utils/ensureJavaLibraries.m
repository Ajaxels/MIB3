function ensureJavaLibraries(libList, mibPath, externalDirs)
% ENSUREJAVALIBRARIES - Initialize external Java libraries on their first use.
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.ensureJavaLibraries(libList)
%      utils.ensureJavaLibraries(libList, mibPath, externalDirs)
%
% Adds the requested Java libraries to the dynamic Java class path. Each
% library is initialized only once per MATLAB session (kept in a persistent
% registry), so the function is cheap to call from any code path that is
% about to use a Java-dependent feature. Keeping the ``javaaddpath`` calls
% out of the MIB startup makes the startup faster and avoids the global
% variable clearing side effect of ``javaaddpath`` until a library is
% actually needed.
%
% When MATLAB runs without a Java runtime (``utils.JavaSetup.isAvailable`` is
% false, the default from MATLAB R2026b, which no longer bundles Java; also when
% the ``jenv`` setting points to an uninstalled Java), only the non-Java
% ``'bm3d'`` entry is processed and ``'imageselection'`` is skipped silently
% (it is requested at startup, and ``imclipboard`` falls back to the .NET
% clipboard on Windows). Any other requested library throws ``MIB:javaNotFound``
% with a message that names the feature (Bio-Formats, Fiji, ...) and points to
% Preferences -> External directories -> Java (``utils.JavaSetup``), which works
% both in MATLAB and in the compiled standalone, followed by a restart. Callers
% that catch errors should show ``err.message`` rather than a generic text, so
% the reason reaches the user.
%
% ``mibPath`` and ``externalDirs`` are cached in persistent variables on the
% first configured call (done from ``MibController.initializeLibraries``
% during startup), so later calls may provide only ``libList``.
%
% Input Arguments:
%   - **libList** - cell array of library identifiers to initialize.
%     Valid identifiers: ``'bm3d'``, ``'omero'``, ``'mij.jar'``, ``'bioformats'``,
%     ``'imageselection'``, ``'fiji'``, ``'poi'``, ``'imaris'``
%   - **mibPath** - *(optional)* char, MIB installation directory; cached
%     persistently; when never provided, resolved via ``utils.getInstallationPath``
%   - **externalDirs** - *(optional)* struct, copy of ``preferences.ExternalDirs``
%     with the Fiji/OMERO/Imaris/BM3D installation paths; cached persistently;
%     libraries that require it are skipped when it was never provided
%
% Output Arguments:
%   (none)
%
% **Example 1** - make sure Bio-Formats is available before reading a file:
%
%   .. code-block:: matlab
%
%      utils.ensureJavaLibraries({'bioformats'});
%      reader = bfGetReader(filename);
%

arguments (Input)
    libList cell = {}
    mibPath (1,:) char = ''
    externalDirs = []
end

persistent initializedLibs cachedMibPath cachedExternalDirs
if isempty(initializedLibs); initializedLibs = {}; end

% cache/refresh the configuration; refreshing externalDirs allows paths
% updated in the Preferences dialog to be picked up on the next ensure call
if ~isempty(mibPath); cachedMibPath = mibPath; end
if ~isempty(externalDirs); cachedExternalDirs = externalDirs; end
if isempty(cachedMibPath); cachedMibPath = utils.getInstallationPath('mib3'); end
mibPath = cachedMibPath;
externalDirs = cachedExternalDirs;

% skip libraries already initialized during this MATLAB session
libList = libList(~ismember(libList, initializedLibs));
if isempty(libList); return; end

% ------------ add BM3D/BM4D to Matlab path ------------
% plain MATLAB code, does not need Java
if ismember('bm3d', libList)
    if ~isdeployed && ~isempty(externalDirs)
        % Add BM3D path if available
        if isdir(externalDirs.bm3dInstallationPath) %#ok<*ISDIR>
            addpath(externalDirs.bm3dInstallationPath);
        end

        % Add BM4D path if available
        if isdir(externalDirs.bm4dInstallationPath)
            addpath(externalDirs.bm4dInstallationPath);
        end
    end
    initializedLibs{end+1} = 'bm3d';
end

% MATLAB R2026b and newer no longer bundle a Java runtime; without one every
% call below (starting with javaclasspath) throws MATLAB:Java:JavaNotFound.
% A Java runtime can only be attached (utils.JavaSetup) before MATLAB starts.
% 'imageselection' is skipped silently: it is requested at startup, and
% imclipboard falls back to the .NET clipboard on Windows. Any other Java
% library means the user started a Java feature, so stop it with an error
% that names the feature and the fix; without it the feature fails later
% with an error that its caller may replace by a misleading message
if ~utils.JavaSetup.isAvailable()
    libList = setdiff(libList, {'bm3d', 'imageselection'}, 'stable');
    if isempty(libList); return; end
    featureNames = dictionary(["omero", "mij.jar", "bioformats", "fiji", "poi", "imaris"], ...
        ["OMERO", "Fiji", "Bio-Formats", "Fiji", "Excel export", "Imaris"]);
    libList = string(libList);
    knownLibs = libList(isKey(featureNames, libList));
    featureList = strjoin(unique(featureNames(knownLibs), 'stable'), ', ');
    if strlength(featureList) == 0; featureList = "This feature"; end
    error('MIB:javaNotFound', ['%s needs Java, which is not available ' ...
        '(MATLAB R2026b and newer come without Java).\n\n' ...
        'To enable Java: Home -> Preferences -> External directories -> Java, press "Configure Java...", then restart MIB.\n\n' ...
        'Step-by-step instructions:\n' ...
        'http://mib.helsinki.fi/help/main3/getting-started/installation/java.html'], featureList);
end

% Store and disable warnings during initialization
warningState = warning('off');

% Get the Java classpath for checking existing libraries
javapath = javaclasspath('-all');

% ------------ add OMERO ------------
if ismember('omero', libList)
    if ~isempty(externalDirs) && isdir(externalDirs.OmeroInstallationPath)
        if ~isdeployed
            % Load OMERO using its native loader
            if isfile(fullfile(externalDirs.OmeroInstallationPath, 'loadOmero.m'))
                addpath(externalDirs.OmeroInstallationPath);
                loadOmero();
            end
        else
            % In deployed mode, manually add OMERO libraries
            utils.defaults.addToJavaClasspath(javapath, fullfile(externalDirs.OmeroInstallationPath, 'libs'));
            import omero.*;
        end
        initializedLibs{end+1} = 'omero';
    else
        if ~isempty(externalDirs) && ~isempty(externalDirs.OmeroInstallationPath)
            fprintf('Warning! Omero path is not correct!\nPlease fix it using MIB Preferences dialog (MIB->Home->Preferences->External dirs)\n');
        end
    end
end

% ------------ add Mij.jar to java class ------------
% This fixes compatibility issues with recent Fiji releases
if ismember('mij.jar', libList)
    if all(cellfun(@isempty, strfind(javapath, 'mij.jar')))
        cPath = fullfile(mibPath, 'jars', 'mij.jar');
        javaaddpath(cPath, '-end');
        fprintf('MIB: adding "%s" to Matlab java path\n', cPath);
    end
    initializedLibs{end+1} = 'mij.jar';
end

% ------------ add Bio-formats java libraries ------------
if ismember('bioformats', libList)
    if all(cellfun(@isempty, strfind(javapath, 'bioformats_package.jar')))
        cPath = fullfile(mibPath, 'jars', 'BioFormats', 'bioformats_package.jar');
        javaaddpath(cPath, '-end');
        fprintf('MIB: adding "%s" to Matlab java path\n', cPath);
    end

    % Initialize bio-formats logging to suppress warnings in newer MATLAB versions
    bfInitLogging();
    initializedLibs{end+1} = 'bioformats';
end

% ------------ add ImageSelection.java for imclipboard ------------
if ismember('imageselection', libList)
    if all(cellfun(@isempty, strfind(javapath, 'ImageSelection')))
        cPath = fullfile(mibPath, 'jars', 'ImageSelection');
        javaaddpath(cPath, '-end');
        fprintf('MIB: adding "%s" to Matlab java path\n', cPath);
    end
    initializedLibs{end+1} = 'imageselection';
end

% ------------ Add Fiji.app ------------
if ismember('fiji', libList)
    if ~isempty(externalDirs) && isdir(externalDirs.FijiInstallationPath)
        fprintf('MIB: adding Fiji libraries from "%s" .', externalDirs.FijiInstallationPath);

        if ~isdeployed
            % Add Fiji scripts path
            addpath(fullfile(externalDirs.FijiInstallationPath, 'scripts'));
            fprintf('.');

            % Add Fiji JAR files
            utils.defaults.addToJavaClasspath(javapath, fullfile(externalDirs.FijiInstallationPath, 'jars'));
            fprintf('.');

            % Add Fiji plugins
            utils.defaults.addToJavaClasspath(javapath, fullfile(externalDirs.FijiInstallationPath, 'plugins'));
            fprintf('.');
            fprintf('done!\n');
        else
            % In deployed mode, add mij.jar if not already present
            if all(cellfun(@isempty, strfind(javapath, 'mij.jar')))
                % Important: during compiling include MIB/jars to the files
                % installed for the end user and do not include it into the
                % required files to run
                cPath = fullfile(mibPath, 'jars', 'mij.jar');
                javaaddpath(cPath);
                fprintf('MIB: adding %s to Matlab java path\n', cPath);
            end

            % Add all libraries in jars/ and plugins/ to the classpath
            utils.defaults.addToJavaClasspath(javapath, fullfile(externalDirs.FijiInstallationPath, 'jars'));
            utils.defaults.addToJavaClasspath(javapath, fullfile(externalDirs.FijiInstallationPath, 'plugins'));

            % Set the Fiji directory (and plugins.dir which is not Fiji.app/plugins/)
            java.lang.System.setProperty('ij.dir', externalDirs.FijiInstallationPath);
            java.lang.System.setProperty('plugins.dir', externalDirs.FijiInstallationPath);
        end
        initializedLibs{end+1} = 'fiji';
    else
        if ~isempty(externalDirs) && ~isempty(externalDirs.FijiInstallationPath)
            fprintf('Warning! Fiji path is not correct!\nPlease fix it using MIB Preferences dialog (MIB->Home->Preferences->External dirs)\n');
        end
    end
end

% ------------ add Apache POI java library for xlwrite ------------
% Only needed on non-Windows systems for Excel file operations
if ismember('poi', libList)
    if ~ispc && all(cellfun(@isempty, strfind(javapath, 'poi-3.8-20120326.jar')))
        poi_path = fullfile(mibPath, 'jars', 'xlwrite');
        fprintf('MIB: adding "%s" to Matlab java path\n', poi_path);
        javaaddpath(fullfile(poi_path, 'poi-3.8-20120326.jar'));
        javaaddpath(fullfile(poi_path, 'poi-ooxml-3.8-20120326.jar'));
        javaaddpath(fullfile(poi_path, 'poi-ooxml-schemas-3.8-20120326.jar'));
        javaaddpath(fullfile(poi_path, 'xmlbeans-2.3.0.jar'));
        javaaddpath(fullfile(poi_path, 'dom4j-1.6.1.jar'));
        javaaddpath(fullfile(poi_path, 'stax-api-1.0.1.jar'));
    end
    initializedLibs{end+1} = 'poi';
end

% ------------ set Imaris path ------------
if ismember('imaris', libList)
    loadImarisLib = 0;

    % Check if Imaris path is valid
    if ~isempty(externalDirs) && isdir(fullfile(externalDirs.ImarisInstallationPath, 'XT', 'matlab'))
        setenv('IMARISPATH', externalDirs.ImarisInstallationPath);
        loadImarisLib = 1;
    end

    % Add Imaris Java library if available
    if loadImarisLib
        if all(cellfun(@isempty, strfind(javapath, 'ImarisLib.jar')))
            javaaddpath(fullfile(externalDirs.ImarisInstallationPath, 'XT', 'matlab', 'ImarisLib.jar'));
        end
        initializedLibs{end+1} = 'imaris';
    end
end

% Restore warning settings
warning(warningState);

end
