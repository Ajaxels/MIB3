function initializeLibraries(obj, initList)
% INITIALIZELIBRARIES - Initialize external libraries and Java paths.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.initializeLibraries()
%      obj.initializeLibraries(initList)
%
% Initializes external libraries and adds Java paths needed for MIB.
% Can selectively initialize specific libraries or all libraries.
%
% Input Arguments:
%   - **initList** — *(optional)* cell array of library identifiers to initialize.
%     When empty or missing, all libraries are initialized.
%     Valid identifiers: ``'bm3d'``, ``'omero'``, ``'mij.jar'``, ``'bioformats'``,
%     ``'imageselection'``, ``'fiji'``, ``'poi'``, ``'imaris'``
%
% Output Arguments:
%   (none)
%
% **Example 1** — initialize all libraries:
%
%   .. code-block:: matlab
%
%      obj.initializeLibraries();
%
% **Example 2** — initialize only specific libraries:
%
%   .. code-block:: matlab
%
%      obj.initializeLibraries({'mij.jar', 'bioformats'});
%

arguments (Input)
    obj controllers.MibController
    initList cell = {}  % default empty cell array
end

% Store and disable warnings during initialization
warningState = warning('off');

% Get the Java classpath for checking existing libraries
javapath = javaclasspath('-all');

% ------------ add BM3D/BM4D to Matlab path ------------
if isempty(initList) || ismember('bm3d', initList)
    if ~isdeployed
        % Add BM3D path if available
        if isdir(obj.mibModel.preferences.ExternalDirs.bm3dInstallationPath) %#ok<*ISDIR>
            addpath(obj.mibModel.preferences.ExternalDirs.bm3dInstallationPath);
        end

        % Add BM4D path if available
        if isdir(obj.mibModel.preferences.ExternalDirs.bm4dInstallationPath)
            addpath(obj.mibModel.preferences.ExternalDirs.bm4dInstallationPath);
        end
    end
end

% ------------ add OMERO ------------
if isempty(initList) || ismember('omero', initList)
    if isdir(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath)
        if ~isdeployed
            % Load OMERO using its native loader
            if isfile(fullfile(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath, 'loadOmero.m'))
                addpath(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath);
                loadOmero();
            end
        else
            % In deployed mode, manually add OMERO libraries
            utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath, 'libs'));
            import omero.*;
        end
    else
        if ~isempty(obj.mibModel.preferences.ExternalDirs.OmeroInstallationPath)
            fprintf('Warning! Omero path is not correct!\nPlease fix it using MIB Preferences dialog (MIB->Home->Preferences->External dirs)\n');
        end
    end
end

% ------------ add Mij.jar to java class ------------
% This fixes compatibility issues with recent Fiji releases
if isempty(initList) || ismember('mij.jar', initList)
    if all(cellfun(@isempty, strfind(javapath, 'mij.jar')))
        cPath = fullfile(obj.mibPath, 'jars', 'mij.jar');
        javaaddpath(cPath, '-end');
        fprintf('MIB: adding "%s" to Matlab java path\n', cPath);
    end
end

% ------------ add Bio-formats java libraries ------------
if isempty(initList) || ismember('bioformats', initList)
    if all(cellfun(@isempty, strfind(javapath, 'bioformats_package.jar')))
        cPath = fullfile(obj.mibPath, 'jars', 'BioFormats', 'bioformats_package.jar');
        javaaddpath(cPath, '-end');
        fprintf('MIB: adding "%s" to Matlab java path\n', cPath);
    end

    % Initialize bio-formats logging to suppress warnings in newer MATLAB versions
    bfInitLogging();
end

% ------------ add ImageSelection.java for imclipboard ------------
if isempty(initList) || ismember('imageselection', initList)
    if all(cellfun(@isempty, strfind(javapath, 'ImageSelection')))
        cPath = fullfile(obj.mibPath, 'jars', 'ImageSelection');
        javaaddpath(cPath, '-end');
        fprintf('MIB: adding "%s" to Matlab java path\n', cPath);
    end
end

% ------------ Add Fiji.app ------------
if isempty(initList) || ismember('fiji', initList)
    if isdir(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath)
        fprintf('MIB: adding Fiji libraries from "%s" .', obj.mibModel.preferences.ExternalDirs.FijiInstallationPath);

        if ~isdeployed
            % Add Fiji scripts path
            addpath(fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'scripts'));
            fprintf('.');

            % Add Fiji JAR files
            utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'jars'));
            fprintf('.');

            % Add Fiji plugins
            utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'plugins'));
            fprintf('.');
            fprintf('done!\n');
        else
            % In deployed mode, add mij.jar if not already present
            if all(cellfun(@isempty, strfind(javapath, 'mij.jar')))
                % Important: during compiling include MIB/jars to the files 
                % installed for the end user and do not include it into the 
                % required files to run
                cPath = fullfile(obj.mibPath, 'jars', 'mij.jar');
                javaaddpath(cPath);
                fprintf('MIB: adding %s to Matlab java path\n', cPath);
            end

            % Add all libraries in jars/ and plugins/ to the classpath
            utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'jars'));
            utils.defaults.addToJavaClasspath(javapath, fullfile(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath, 'plugins'));

            % Set the Fiji directory (and plugins.dir which is not Fiji.app/plugins/)
            java.lang.System.setProperty('ij.dir', obj.mibModel.preferences.ExternalDirs.FijiInstallationPath);
            java.lang.System.setProperty('plugins.dir', obj.mibModel.preferences.ExternalDirs.FijiInstallationPath);
        end
    else
        if ~isempty(obj.mibModel.preferences.ExternalDirs.FijiInstallationPath)
            fprintf('Warning! Fiji path is not correct!\nPlease fix it using MIB Preferences dialog (MIB->Home->Preferences->External dirs)\n');
        end
    end
end

% ------------ add Apache POI java library for xlwrite ------------
% Only needed on non-Windows systems for Excel file operations
if isempty(initList) || ismember('poi', initList)
    if ~ispc && all(cellfun(@isempty, strfind(javapath, 'poi-3.8-20120326.jar')))
        poi_path = fullfile(obj.mibPath, 'jars', 'xlwrite');
        fprintf('MIB: adding "%s" to Matlab java path\n', poi_path);
        javaaddpath(fullfile(poi_path, 'poi-3.8-20120326.jar'));
        javaaddpath(fullfile(poi_path, 'poi-ooxml-3.8-20120326.jar'));
        javaaddpath(fullfile(poi_path, 'poi-ooxml-schemas-3.8-20120326.jar'));
        javaaddpath(fullfile(poi_path, 'xmlbeans-2.3.0.jar'));
        javaaddpath(fullfile(poi_path, 'dom4j-1.6.1.jar'));
        javaaddpath(fullfile(poi_path, 'stax-api-1.0.1.jar'));
    end
end

% ------------ set Imaris path ------------
if isempty(initList) || ismember('imaris', initList)
    loadImarisLib = 0;

    % Check if Imaris path is valid
    if isdir(fullfile(obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath, 'XT', 'matlab'))
        setenv('IMARISPATH', obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath);
        loadImarisLib = 1;
    else
        obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath = [];
    end

    % Add Imaris Java library if available
    if loadImarisLib && isdir(fullfile(obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath, 'XT', 'matlab'))
        if all(cellfun(@isempty, strfind(javapath, 'ImarisLib.jar')))
            javaaddpath(fullfile(obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath, 'XT', 'matlab', 'ImarisLib.jar'));
        end
    end
end

% Restore warning settings
warning(warningState);

end
