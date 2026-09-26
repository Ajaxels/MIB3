function mib3_compile_c_files()
% MIB3_COMPILE_C_FILES - Compile the C/C++ MEX files of MIB3 for the current platform.
%
% Syntax:
%   .. code-block:: matlab
%
%       mib3_compile_c_files
%
% Builds every MEX function that MIB3 ships as source, writing each binary
% next to its source with the extension of the running MATLAB (``mexext``:
% ``.mexw64`` Windows, ``.mexa64`` Linux, ``.mexmaci64`` Intel Mac,
% ``.mexmaca64`` Apple silicon Mac). The location of MIB3 is derived from this
% file (``<repo>/deployment`` -> ``<repo>/mib``), so ``mib3.m`` does not have to
% be on the path.
%
% Every target is compiled inside its own try/catch, so one failure never stops
% the rest; the script always runs to the end and prints a summary of what was
% built, what failed (with the compiler message) and what was skipped. The
% binaries that were built are also packed into
% ``deployment/mib3_mex_<mexext>.zip`` with paths relative to the repository
% root, so they can be sent back and unpacked over the repository.
%
% Special cases:
%   - **Random Forest classifier** (``RF_Class_C``) links a Fortran object
%     (``src/rfsub.f``). On Windows the precompiled
%     ``precompiled_rfsub/win64/rfsub.o`` is used with ``-DWIN64``; elsewhere
%     ``rfsub.o`` is compiled into ``tempdir`` with ``gfortran`` (searched on
%     the shell path, then ``/opt/homebrew/bin`` and ``/usr/local/bin``, because
%     MATLAB started from the macOS Dock does not inherit the shell PATH). The
%     Fortran code has no I/O, so the object links without ``-lgfortran`` and
%     the MEX file does not depend on the gfortran runtime. Without gfortran
%     the two targets are skipped.
%   - **NRRD reader** (``nrrdLoadWithMetadata``) needs the Teem library, see
%     ``mib/external/nrrd/compilethis.m``; it is always skipped. macOS does not
%     need it: ``io.loaders.NrrdLoader`` reads NRRD with ``nhdr_nrrd_read`` there.
%   - **Fast Marching** keeps ``-compatibleArrayDims``: the sources pass
%     ``mwSize`` arrays to helpers declared with ``int *``, which is only
%     correct when ``mwSize`` is 32-bit.
%
% Requirements: a C and a C++ compiler selected with ``mex -setup C`` and
% ``mex -setup C++``. On macOS this is Xcode or the Xcode Command Line Tools;
% see ``deployment/readme_mac.md`` for step-by-step instructions.

% Updates
% 26.09.2026, rewritten to run to the end on any platform, report a summary and
%             pack the results into a zip; added Random Forest targets

repoRoot = fileparts(fileparts(mfilename('fullpath')));
mibDir = fullfile(repoRoot, 'mib');
if ~isfolder(mibDir)
    error('mib3_compile_c_files: MIB3 folder was not found at %s', mibDir);
end

fprintf('\n=== Compiling MIB3 MEX files ===\n');
fprintf('MATLAB %s, platform %s, MEX extension .%s\n', version, computer('arch'), mexext);
fprintf('MIB3 folder: %s\n\n', mibDir);

if ismac && strcmp(computer('arch'), 'maci64')
    fprintf(2, ['Note: this is the Intel version of MATLAB. It builds .mexmaci64 files, which MIB3 already has.\n' ...
        'On an Apple silicon Mac install the "Apple silicon" version of MATLAB to build .mexmaca64 files.\n\n']);
end

% compilers must be configured before anything can be built
cCompiler = mex.getCompilerConfigurations('C', 'Selected');
cppCompiler = mex.getCompilerConfigurations('C++', 'Selected');
if isempty(cCompiler) || isempty(cppCompiler)
    fprintf(2, 'No C or C++ compiler is selected for MEX.\n');
    fprintf(2, 'Install a supported compiler, then run "mex -setup C" and "mex -setup C++" and start this script again.\n');
    if ismac
        fprintf(2, 'On macOS: run "xcode-select --install" in Terminal (see deployment/readme_mac.md).\n');
    end
    return;
end
fprintf('C compiler:   %s\nC++ compiler: %s\n\n', cCompiler.Name, cppCompiler.Name);

% unload MEX files, otherwise loaded binaries cannot be overwritten on Windows
clear mex; %#ok<CLMEX>

%% List of targets
% folder - relative to mibDir; output - MEX name without extension;
% sources - relative to folder; flags - extra mex arguments
targets = struct('group', {}, 'folder', {}, 'output', {}, 'sources', {}, 'flags', {});
targets(end+1) = makeTarget('Fast Marching', 'external/FastMarching/functions', 'msfm2d', {'msfm2d.c'}, {'-compatibleArrayDims'});
targets(end+1) = makeTarget('Fast Marching', 'external/FastMarching/functions', 'msfm3d', {'msfm3d.c'}, {'-compatibleArrayDims'});
targets(end+1) = makeTarget('Fast Marching', 'external/FastMarching/shortestpath', 'rk4', {'rk4.c'}, {'-compatibleArrayDims'});
targets(end+1) = makeTarget('Membrane Detection', 'external/RandomForest/MembraneDetection', 'meanvar', {'meanvar.c'}, {});
targets(end+1) = makeTarget('Membrane Detection', 'external/RandomForest/MembraneDetection', 'transformImageFast', {'transformImageFast.c'}, {});
targets(end+1) = makeTarget('Supervoxels', 'external/Supervoxels', 'slicmex', {'slicmex.c'}, {});
targets(end+1) = makeTarget('Supervoxels', 'external/Supervoxels', 'slicomex', {'slicomex.c'}, {});
targets(end+1) = makeTarget('Supervoxels', 'external/Supervoxels', 'slicsupervoxelmex', {'slicsupervoxelmex.c'}, {});
targets(end+1) = makeTarget('Supervoxels', 'external/Supervoxels', 'slicsupervoxelmex_byte', {'slicsupervoxelmex_byte.c'}, {});
targets(end+1) = makeTarget('Graphcut maxflow', 'external/Supervoxels', 'maxflowmex_v222', ...
    {'maxflowmex_v222.cpp', 'maxflow-v2.22/adjacency_list_new_interface/graph.cpp', ...
    'maxflow-v2.22/adjacency_list_new_interface/maxflow.cpp'}, {'-largeArrayDims'});
targets(end+1) = makeTarget('Utilities', '+utils', 'GetExeLocation', {'GetExeLocation.c'}, {});
targets(end+1) = makeTarget('Region Growing', 'external/RegionGrowing', 'RegionGrowing_mex', {'RegionGrowing_mex.cpp'}, {});
classRFSources = {'src/classRF.cpp', 'src/classTree.cpp', 'src/cokus.cpp', 'src/rfutils.cpp'};
targets(end+1) = makeTarget('Random Forest classifier', 'external/RandomForest/RF_Class_C', 'mexClassRF_train', ...
    [classRFSources, {'src/mex_ClassificationRF_train.cpp'}], {'-DMATLAB'});
targets(end+1) = makeTarget('Random Forest classifier', 'external/RandomForest/RF_Class_C', 'mexClassRF_predict', ...
    [classRFSources, {'src/mex_ClassificationRF_predict.cpp'}], {'-DMATLAB'});
targets(end+1) = makeTarget('Random Forest regression', 'external/RandomForest/RF_Reg_C', 'mexRF_train', ...
    {'src/cokus.cpp', 'src/reg_RF.cpp', 'src/mex_regressionRF_train.cpp'}, {'-DMATLAB'});
targets(end+1) = makeTarget('Random Forest regression', 'external/RandomForest/RF_Reg_C', 'mexRF_predict', ...
    {'src/cokus.cpp', 'src/reg_RF.cpp', 'src/mex_regressionRF_predict.cpp'}, {'-DMATLAB'});

%% Fortran object for the Random Forest classifier
[rfsubObject, rfsubFlags, rfsubSkipReason] = prepareRfsubObject(fullfile(mibDir, 'external', 'RandomForest', 'RF_Class_C'));

%% Compile
noTargets = numel(targets);
results = struct('group', {targets.group}, 'file', '', 'status', '', 'message', '');
for targetId = 1:noTargets
    target = targets(targetId);
    folderFull = fullfile(mibDir, target.folder);
    results(targetId).file = fullfile('mib', target.folder, [target.output '.' mexext]);
    fprintf('[%d/%d] %s: %s ... ', targetId, noTargets, target.group, target.output);

    sourcesFull = cellfun(@(source) fullfile(folderFull, source), target.sources, 'UniformOutput', false);
    extraFlags = {};
    if strcmp(target.output, 'mexClassRF_train') || strcmp(target.output, 'mexClassRF_predict')
        if isempty(rfsubObject)
            results(targetId).status = 'skipped';
            results(targetId).message = rfsubSkipReason;
            fprintf('skipped\n');
            continue;
        end
        sourcesFull{end+1} = rfsubObject; %#ok<AGROW>
        extraFlags = rfsubFlags;
    end

    try
        mex('-silent', '-outdir', folderFull, '-output', target.output, target.flags{:}, extraFlags{:}, sourcesFull{:});
        if ~isfile(fullfile(folderFull, [target.output '.' mexext]))
            error('mex finished without creating %s.%s', target.output, mexext);
        end
        results(targetId).status = 'built';
        fprintf('OK\n');
    catch err
        results(targetId).status = 'failed';
        results(targetId).message = err.message;
        fprintf(2, 'FAILED\n');
    end
end

results(end+1).group = 'NRRD reader';
results(end).file = fullfile('mib', 'external', 'nrrd', ['nrrdLoadWithMetadata.' mexext]);
results(end).status = 'skipped';
if ismac
    results(end).message = 'not needed on macOS, MIB3 reads NRRD files with MATLAB code there';
else
    results(end).message = 'needs the Teem library, see mib/external/nrrd/compilethis.m';
end

if ~isempty(rfsubObject) && startsWith(rfsubObject, tempdir)
    delete(rfsubObject);
end

%% Summary
isBuilt = strcmp({results.status}, 'built');
isFailed = strcmp({results.status}, 'failed');
isSkipped = strcmp({results.status}, 'skipped');

fprintf('\n=== Summary: %d built, %d failed, %d skipped ===\n', nnz(isBuilt), nnz(isFailed), nnz(isSkipped));
if any(isBuilt)
    fprintf('\nBuilt:\n');
    fprintf('  %s\n', results(isBuilt).file);
end
if any(isFailed)
    fprintf(2, '\nFailed:\n');
    for resultId = find(isFailed)
        fprintf(2, '  %s\n', results(resultId).file);
        fprintf(2, '      %s\n', strrep(strtrim(results(resultId).message), newline, [newline '      ']));
    end
end
if any(isSkipped)
    fprintf('\nSkipped:\n');
    for resultId = find(isSkipped)
        fprintf('  %s\n      %s\n', results(resultId).file, results(resultId).message);
    end
end

if any(isBuilt)
    zipFilename = fullfile(repoRoot, 'deployment', ['mib3_mex_' mexext '.zip']);
    builtFiles = strrep({results(isBuilt).file}, '\', '/');
    try
        zip(zipFilename, builtFiles, repoRoot);
        fprintf('\nThe built files are packed into:\n  %s\n', zipFilename);
    catch err
        fprintf(2, '\nThe zip file could not be created: %s\n', err.message);
    end
end
fprintf('\nDone.\n');
end

function target = makeTarget(group, folder, output, sources, flags)
% MAKETARGET - Describe one MEX file to build; folder is relative to mib/
target = struct('group', group, 'folder', strrep(folder, '/', filesep), 'output', output, ...
    'sources', {strrep(sources, '/', filesep)}, 'flags', {flags});
end

function [objectFile, mexFlags, skipReason] = prepareRfsubObject(classRFDir)
% PREPARERFSUBOBJECT - Get the Fortran object rfsub.o needed by the Random Forest classifier
%
% Returns the object path and extra mex flags, or an empty objectFile with a
% skipReason when the object cannot be made. On non-Windows platforms the
% object is compiled into tempdir and the caller deletes it afterwards.

objectFile = '';
mexFlags = {};
skipReason = '';

if ispc
    objectFile = fullfile(classRFDir, 'precompiled_rfsub', 'win64', 'rfsub.o');
    mexFlags = {'-DWIN64'};
    return;
end

gfortranPath = '';
[status, shellOutput] = system('command -v gfortran');
if status == 0 && ~isempty(strtrim(shellOutput))
    gfortranPath = strtrim(shellOutput);
else
    candidates = {'/opt/homebrew/bin/gfortran', '/usr/local/bin/gfortran'};
    for candidateId = 1:numel(candidates)
        if isfile(candidates{candidateId})
            gfortranPath = candidates{candidateId};
            break;
        end
    end
end
if isempty(gfortranPath)
    skipReason = 'needs the gfortran compiler (macOS: "brew install gcc", see deployment/readme_mac.md)';
    return;
end

objectFile = fullfile(tempdir, 'mib3_rfsub.o');
command = sprintf('"%s" -O2 -fPIC -c "%s" -o "%s"', gfortranPath, ...
    fullfile(classRFDir, 'src', 'rfsub.f'), objectFile);
[status, shellOutput] = system(command);
if status ~= 0 || ~isfile(objectFile)
    skipReason = sprintf('gfortran could not compile src/rfsub.f: %s', strtrim(shellOutput));
    objectFile = '';
end
end
