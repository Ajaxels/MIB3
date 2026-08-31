function mergeInstancesTo3D(obj)
% MERGEINSTANCESTO3D - merge predicted 2D instance models into a 3D instance model.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.mergeInstancesTo3D()
%
% Takes the instance models produced by 2D instance prediction
% (:func:`startPredictionInstances`, saved under
% ``ResultingImagesDir/PredictionImages/ResultsModels``) and stitches their slices
% into 3D instance models: objects overlapping between neighbouring slices are
% linked into one 3D instance with a consistent index through the whole stack
% (via :func:`utils.instances.stitch2Dto3D`).
%
% Two layouts of the prediction results are recognized automatically from the
% depth of the first model file:
%
%   - **2D models** (one Z-slice per file) - all files form a single stack, taken
%     in alphabetical order of their filenames, so the prediction images must be
%     named in their correct Z-order. One merged 3D model is written.
%   - **3D models** (a z-stack per file, produced when the prediction images were
%     themselves z-stacks) - every file is stitched independently and one merged
%     3D model is written per input file.
%
% The user is asked for the stitching settings, then for the destination: a
% filename and format for a single output, or a folder and format when several
% stacks are stitched. The merged model can be written as a single 3D file or as
% a sequence of 2D files depending on the selected format/policy.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%

% ------------------------------------------------------------------ %
%  Locate the predicted instance models                               %
% ------------------------------------------------------------------ %
resultsModelsDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
modelFiles = dir(fullfile(resultsModelsDir, '*.model'));
if isempty(modelFiles)
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf(['No predicted instance models (*.model) were found in\n\n%s\n\n' ...
        'Please run the 2D instance prediction first (Predict tab -> Predict)!'], resultsModelsDir), ...
        'No predictions found');
    return;
end
% dir() output is already alphabetical, but sort explicitly: the alphabetical
% order of the prediction filenames defines the Z-order of the merged stack
[~, sortIndices] = sort(lower({modelFiles.name}));
modelFiles = modelFiles(sortIndices);
numFiles = numel(modelFiles);

% peek at the first file to detect the layout of the prediction results; only
% its dimensions are needed, so read the header rather than the pixels
try
    firstLabelsSize = iPeekLabelsSize(fullfile(resultsModelsDir, modelFiles(1).name));
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Merge instances to 3D');
    return;
end
% more than one plane in the file, counting past any trailing singleton
% dimensions, which iLoadLabels squeezes away
stackPerFile = numel(firstLabelsSize) >= 3 && prod(firstLabelsSize(3:end)) > 1;

if stackPerFile
    numJobs = numFiles;
    note = sprintf(['%d predicted 3D instance models were found; each file is a complete z-stack\n' ...
        'and is stitched separately into its own 3D model.'], numFiles);
else
    numJobs = 1;
    note = sprintf(['%d predicted 2D instance models (Z-slices, ordered by filename) will be merged;\n' ...
        'objects overlapping between neighbouring slices are linked into one 3D instance.'], numFiles);
end

% ------------------------------------------------------------------ %
%  Stitching settings dialog                                          %
% ------------------------------------------------------------------ %
% Seed the dialog with the settings last used in this MIB session. The key is
% shared with models.MibModel.stitchModelInstances (Ribbon -> Model -> Stitch 2D
% instances to 3D): it is the same dialog driving the same algorithm, so a
% threshold trialled there is offered here and the other way round. The shared
% dialog falls back to its own defaults for anything missing and clamps a stored
% value that falls outside a widget's range, so a struct written by the other
% entry point is safe to hand over as-is. Its extra fields are ignored - the
% dialog seeds from its own field list, not from what it is given.
if isfield(obj.mibModel.sessionSettings, 'stitchInstances2Dto3D')
    dlgDefaults = obj.mibModel.sessionSettings.stitchInstances2Dto3D;
else
    dlgDefaults = struct();
end

% 'ratio' mode: raw prediction images carry no pixel size, so the Z anisotropy
% is asked for directly as a number instead of being read from a dataset
dlgSettings.anisotropyMode = 'ratio';
dlgSettings.dlgTitle = 'Merge 2D instances to 3D';
dlgSettings.mibPath = obj.mibModel.mibPath;
[stitchOptions, values] = utils.dlgs.stitchInstancesSettingsDlg(obj.view.gui, ...
    note, dlgDefaults, dlgSettings);
if isempty(stitchOptions); return; end   % cancelled

% Store field by field rather than replacing the struct, so the ribbon entry
% point's 'UseAnisotropy' checkbox survives a run from here. That one parameter
% cannot be shared: here it is a raw ratio (values.Anisotropy), there a yes/no
% with the ratio taken from the dataset pixel size, so each side keeps its own.
sessionValues = dlgDefaults;
for sessionField = fieldnames(values)'
    sessionValues.(sessionField{1}) = values.(sessionField{1});
end
obj.mibModel.sessionSettings.stitchInstances2Dto3D = sessionValues;
% kept separately: it is also written into the saved model's pixSize.z below
anisotropyZ = values.Anisotropy;

% ------------------------------------------------------------------ %
%  Destination directory, filename and format                         %
% ------------------------------------------------------------------ %
% curated list of volume formats suitable for large instance models; the
% strings must exactly match io.SaverFactory registry entries
formats = { ...
    'Matlab format (*.model)'; ...
    'Matlab format 2D sequence (*.model)'; ...
    'Amira mesh binary (*.am)'; ...
    'Hierarchical Data Format (*.h5)'; ...
    'MRC Volume for IMOD (*.mrc)'; ...
    'NRRD for 3D Slicer (*.nrrd)'; ...
    'PNG format (*.png)'; ...
    'TIF format (*.tif)'};
extTokens = regexp(formats, '\(\*\.[\w.]+\)', 'match', 'once');
extTokens = strrep(strrep(extTokens, '(', ''), ')', '');   % '*.model', '*.am', ...
filterSpec = [extTokens, formats];

outputFilenames = cell(numJobs, 1);
if numJobs == 1
    defaultFilename = fullfile(fileparts(resultsModelsDir), 'Labels_stitched_3D.model');
    [fname, fpath, filterIndex] = uiputfile(filterSpec, 'Save 3D instance model', defaultFilename);
    if isequal(fname, 0); return; end   % user cancelled
    if filterIndex > size(filterSpec, 1)   % "All Files (*.*)" - no format selected
        dlgOpt.mibPath = obj.mibModel.mibPath;
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        utils.dlgs.inputUniversalDlg(obj.view.gui, 'The output format was not selected!', {}, {}, ...
            'Missing output format', dlgOpt);
        return;
    end

    % Fix filename extension to match the selected filter: uiputfile does not
    % always update the extension when the user changes the format filter
    % (platform-dependent bug, R2026a-pre, case 08552750)
    selectedExt = strrep(filterSpec{filterIndex, 1}, '*', '');
    [~, fbase] = fileparts(fname);
    outputFilenames{1} = fullfile(fpath, [fbase, selectedExt]);
    selectedFormat = filterSpec{filterIndex, 2};
    saverSilent = false;    % let the TIF/model savers ask 3D stack vs 2D sequence
else
    % several independent stacks: ask once for the destination folder and the
    % format, then derive one output filename per input model
    outputDir = uigetdir(fileparts(resultsModelsDir), 'Select a folder for the merged 3D instance models');
    if isequal(outputDir, 0); return; end   % user cancelled

    fmtParams.mibPath = obj.mibModel.mibPath;
    fmtParams.WindowWidth = 560;
    fmtParams.HeaderLines = 2;
    fmtAnswer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
        sprintf('%d merged 3D instance models will be written to\n%s', numJobs, outputDir), ...
        {'Output format:'}, {[formats(:)', {1}]}, 'Select output format', fmtParams);
    if isempty(fmtAnswer); return; end
    selectedFormat = fmtAnswer{1};
    selectedExt = strrep(filterSpec{strcmp(formats, selectedFormat), 1}, '*', '');
    for jobId = 1:numJobs
        [~, inputBase] = fileparts(modelFiles(jobId).name);
        outputFilenames{jobId} = fullfile(outputDir, [inputBase '_stitched3D' selectedExt]);
    end
    saverSilent = true;     % avoid one 3D-stack / 2D-sequence dialog per file
end

% ------------------------------------------------------------------ %
%  Stitch and save every job                                          %
% ------------------------------------------------------------------ %
wb = uiprogressdlg(obj.view.gui, 'Title', 'Merge 2D instances to 3D', ...
    'Message', 'Loading instance models...', 'Cancelable', 'on', 'Value', 0);

totalInput2DObjects = 0;
totalOutput3DObjects = 0;
for jobId = 1:numJobs
    if wb.CancelRequested
        delete(wb);
        iReportCancelled(obj, jobId, numJobs, outputFilenames);
        return;
    end
    jobProgressBase = (jobId-1)/numJobs;

    % --- assemble the input volume ---
    try
        if stackPerFile
            wb.Message = sprintf('Loading %s (%d of %d)...', modelFiles(jobId).name, jobId, numJobs);
            inputVol = iLoadLabels(fullfile(resultsModelsDir, modelFiles(jobId).name));
            [~, inputBase] = fileparts(modelFiles(jobId).name);
            numSlices = size(inputVol, 3);
            if numSlices == 1
                error('MibDeep:mergeInstancesTo3D:mixedDimensions', ...
                    ['%s is a 2D model (a single slice) while the first model file is a 3D z-stack.\n\n' ...
                    'The results folder must contain either 2D models only (one per Z-slice) ' ...
                    'or 3D models only (one z-stack per file).'], modelFiles(jobId).name);
            end
            % a stack stored in one file carries no per-slice source names; generate
            % them so that 2D-sequence saving still produces predictable filenames
            sliceStems = arrayfun(@(z) sprintf('%s_%05d', inputBase, z), (1:numSlices)', ...
                'UniformOutput', false);
        else
            % every file is one Z-slice of a single stack
            numSlices = numFiles;
            inputVol = [];
            for sliceId = 1:numSlices
                if wb.CancelRequested
                    delete(wb);
                    iReportCancelled(obj, jobId, numJobs, outputFilenames);
                    return;
                end
                if mod(sliceId, 10) == 0
                    wb.Message = sprintf('Loading instance models: %d of %d...', sliceId, numSlices);
                end
                sliceLabels = iLoadLabels(fullfile(resultsModelsDir, modelFiles(sliceId).name));
                if size(sliceLabels, 3) > 1
                    error('MibDeep:mergeInstancesTo3D:mixedDimensions', ...
                        ['%s is a 3D model (%d slices) while the first model file is 2D.\n\n' ...
                        'The results folder must contain either 2D models only (one per Z-slice) ' ...
                        'or 3D models only (one z-stack per file).'], ...
                        modelFiles(sliceId).name, size(sliceLabels, 3));
                end

                if sliceId == 1
                    inputVol = zeros(size(sliceLabels, 1), size(sliceLabels, 2), numSlices, class(sliceLabels));
                elseif size(sliceLabels, 1) ~= size(inputVol, 1) || size(sliceLabels, 2) ~= size(inputVol, 2)
                    error('MibDeep:mergeInstancesTo3D:sizeMismatch', ...
                        ['The slices have different dimensions!\n\n%s is %dx%d, while the first slice is %dx%d.\n\n' ...
                        'All prediction images must have the same width and height to be merged into a 3D stack.'], ...
                        modelFiles(sliceId).name, size(sliceLabels, 1), size(sliceLabels, 2), ...
                        size(inputVol, 1), size(inputVol, 2));
                end

                % promote the volume class when a later slice uses a wider integer type
                if isa(sliceLabels, 'uint32') && ~isa(inputVol, 'uint32')
                    inputVol = uint32(inputVol);
                end
                inputVol(:, :, sliceId) = sliceLabels;
                wb.Value = sliceId/numSlices * 0.5;
            end
            % per-slice source stems (prediction image names) so that 2D-sequence saving
            % with the "Use original filename" policy reproduces the input naming
            sliceStems = cellfun(@(fn) regexprep(fn, '^Labels_|\.model$', ''), ...
                {modelFiles.name}', 'UniformOutput', false);
        end
    catch err
        delete(wb);
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Merge instances to 3D');
        return;
    end
    [imgHeight, imgWidth, ~] = size(inputVol);

    % --- stitch ---
    if wb.CancelRequested
        delete(wb);
        iReportCancelled(obj, jobId, numJobs, outputFilenames);
        return;
    end
    wb.Indeterminate = 'on';
    wb.Message = sprintf('Stitching 2D instances into 3D objects (%d of %d), please wait...', jobId, numJobs);
    try
        [labelVol, stats] = utils.instances.stitch2Dto3D(inputVol, stitchOptions, wb);
    catch err
        delete(wb);
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Merge instances to 3D');
        return;
    end
    % Cancelled during the stitch: nothing has been written to disk for this job,
    % and the jobs already finished keep the files they saved (reported below).
    if stats.cancelled
        delete(wb);
        iReportCancelled(obj, jobId, numJobs, outputFilenames);
        return;
    end
    clear inputVol;
    wb.Indeterminate = 'off';
    wb.Value = jobProgressBase + 0.75/numJobs;

    % --- save ---
    numInstances = stats.numOutput3DObjects;
    % Instance models always use a large model type (>= 65535); numeric material
    % names carry the index itself. Always provide at least 2 materials: MIB's
    % materials table renders two representative rows for >255 models and indexes
    % materialNames{1:2}, so an empty result must still carry >= 2 entries.
    numMaterials = max(2, numInstances);
    if numInstances <= 65535
        modelType = 65535;
    else
        modelType = 4294967295;
    end

    metadata.filename       = outputFilenames{jobId};
    metadata.colorType      = 'indexed';
    metadata.lutColors      = [];
    metadata.dataClass      = class(labelVol);
    metadata.maxInt         = double(intmax(class(labelVol)));
    metadata.materialNames  = arrayfun(@(x) num2str(x), (1:numMaterials)', 'UniformOutput', false);
    metadata.materialColors = obj.colormap255(mod((0:numMaterials-1), size(obj.colormap255, 1))+1, :);
    metadata.labelsVariable = 'mibModel';
    metadata.modelType      = modelType;
    metadata.layerType      = 'labels';
    % voxel size is unknown for raw prediction images: default to 1x1x1 um, with Z
    % scaled by the user-provided anisotropy ratio when one was given
    metadata.pixSize        = struct('x', 1, 'y', 1, 'z', anisotropyZ, 't', 1, 'units', 'um', 'tunits', 's');
    metadata.boundingBox    = [0, imgWidth, 0, imgHeight, 0, numSlices];
    metadata.sliceName      = sliceStems;
    metadata.sliceSize      = [];

    saveOpts.Format         = selectedFormat;
    saveOpts.layerType      = 'labels';
    saveOpts.modelType      = modelType;
    saveOpts.pixSize        = metadata.pixSize;
    saveOpts.boundingBox    = metadata.boundingBox;
    saveOpts.FilenamePrefix = 'Labels_';
    saveOpts.silent         = saverSilent;
    saveOpts.showWaitbar    = true;
    saveOpts.overwrite      = true;     % uiputfile / the folder selection have confirmed the destination
    saveOpts.ParentFigure   = obj.view.gui;
    saveOpts.mibPath        = obj.mibModel.mibPath;

    try
        saver = io.SaverFactory.create(selectedFormat, saveOpts);
        data5D = reshape(labelVol, [imgHeight, imgWidth, numSlices, 1, 1]);
        fnOut = saver.save(data5D, metadata, outputFilenames{jobId}, saveOpts);
    catch err
        delete(wb);
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Merge instances to 3D');
        return;
    end
    if isempty(fnOut); delete(wb); return; end   % user cancelled a saver dialog
    clear labelVol;

    totalInput2DObjects = totalInput2DObjects + stats.numInput2DObjects;
    totalOutput3DObjects = totalOutput3DObjects + stats.numOutput3DObjects;
    fprintf('MibDeep.mergeInstancesTo3D: %d 2D objects -> %d 3D instances (method=%s), saved to %s\n', ...
        stats.numInput2DObjects, stats.numOutput3DObjects, stitchOptions.method, outputFilenames{jobId});
    wb.Value = jobId/numJobs;
end
delete(wb);

% ------------------------------------------------------------------ %
%  Report                                                             %
% ------------------------------------------------------------------ %
if numJobs == 1
    resultText = sprintf('%d 2D objects from %d slices were stitched into %d 3D instances and saved to:\n%s', ...
        totalInput2DObjects, numSlices, totalOutput3DObjects, outputFilenames{1});
else
    resultText = sprintf('%d 2D objects from %d z-stacks were stitched into %d 3D instances and saved to:\n%s', ...
        totalInput2DObjects, numJobs, totalOutput3DObjects, fileparts(outputFilenames{1}));
end
dlgOpt.mibPath     = obj.mibModel.mibPath;
dlgOpt.MsgBoxOnly  = true;
dlgOpt.Icon        = 'puffin_info';
dlgOpt.HeaderLines = 1;
utils.dlgs.inputUniversalDlg(obj.view.gui, 'The merge is complete!', {''}, {resultText}, ...
    'Merge 2D instances to 3D', dlgOpt);
end

function iReportCancelled(obj, jobId, numJobs, outputFilenames)
% Tell the user where the merge stopped. The jobs that finished before the
% cancel have already written their files and those stay on disk, so saying
% only "cancelled" would leave the output folder in an unexplained state.
completedJobs = jobId - 1;
if numJobs == 1 || completedJobs == 0
    resultText = 'No merged 3D model was written.';
else
    resultText = sprintf(['%d of %d merged 3D models were written before the cancel and are kept in\n%s\n\n' ...
        'The remaining %d were not processed.'], ...
        completedJobs, numJobs, fileparts(outputFilenames{1}), numJobs - completedJobs);
end
fprintf('MibDeep.mergeInstancesTo3D: cancelled by the user after %d of %d jobs\n', completedJobs, numJobs);

dlgOpt.mibPath     = obj.mibModel.mibPath;
dlgOpt.MsgBoxOnly  = true;
dlgOpt.Icon        = 'puffin_info';
dlgOpt.HeaderLines = 1;
utils.dlgs.inputUniversalDlg(obj.view.gui, 'The merge was cancelled', {''}, {resultText}, ...
    'Merge 2D instances to 3D', dlgOpt);
end

function labelsSize = iPeekLabelsSize(filename)
% Dimensions of the labels array in a *.model file, taken from the MAT-file
% header instead of loading it. Only the layout (2D slices vs 3D stacks) is
% needed before the settings dialog opens, and a prediction stack can be
% several GB - loading one just to read size(...,3) is what used to keep the
% dialog off screen for a long time on large results.
info = whos('-file', filename);
if isempty(info)
    error('MibDeep:mergeInstancesTo3D:badModelFile', ...
        'The file is empty:\n%s', filename);
end
names = {info.name};

% mirrors the variable resolution of iLoadLabels below; modelVariable is a short
% char array, so loading that one variable to learn the name is still cheap
labelsName = '';
if ismember('modelVariable', names)
    % '-mat' is required: without it the .model extension makes load() try to
    % parse the file as ASCII and error out
    stored = load(filename, '-mat', 'modelVariable');
    if ismember(stored.modelVariable, names); labelsName = stored.modelVariable; end
end
if isempty(labelsName)
    for candidate = {'outputLabels', 'mibModel'}
        if ismember(candidate{1}, names); labelsName = candidate{1}; break; end
    end
end
if isempty(labelsName)
    [~, fn, ext] = fileparts(filename);
    error('MibDeep:mergeInstancesTo3D:badModelFile', ...
        'The labels variable could not be identified in\n%s', [fn ext]);
end
labelsSize = info(strcmp(names, labelsName)).size;
end

function labels = iLoadLabels(filename)
% load the label array out of a MIB *.model file saved by the instance prediction
modelStruct = load(filename, '-mat');
if isfield(modelStruct, 'modelVariable') && isfield(modelStruct, modelStruct.modelVariable)
    labels = modelStruct.(modelStruct.modelVariable);
elseif isfield(modelStruct, 'outputLabels')
    labels = modelStruct.outputLabels;
elseif isfield(modelStruct, 'mibModel')
    labels = modelStruct.mibModel;
else
    [~, fn, ext] = fileparts(filename);
    error('MibDeep:mergeInstancesTo3D:badModelFile', ...
        'The labels variable could not be identified in\n%s', [fn ext]);
end
% models are stored as [height, width] or [height, width, depth], possibly with
% trailing singleton dimensions
labels = squeeze(labels);
end
