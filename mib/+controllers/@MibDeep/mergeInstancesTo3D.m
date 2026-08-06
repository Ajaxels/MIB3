function mergeInstancesTo3D(obj)
% MERGEINSTANCESTO3D - merge predicted 2D instance models into a 3D instance model.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.mergeInstancesTo3D()
%
% Takes the per-slice 2D instance models produced by 2D instance prediction
% (:func:`startPredictionInstances`, saved under
% ``ResultingImagesDir/PredictionImages/ResultsModels``) and stitches them into
% a single 3D instance model: objects overlapping between neighbouring slices
% are linked into one 3D instance with a consistent index through the whole
% stack (via :func:`utils.stitchInstances2Dto3D`).
%
% The files are taken in alphabetical order of their filenames, so the
% prediction images must be named in their correct Z-order. The user is asked
% for the stitching settings, then for the destination directory, filename and
% file format; the merged model can be written as a single 3D file or as a
% sequence of 2D files depending on the selected format/policy.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%

% ------------------------------------------------------------------ %
%  Locate the predicted 2D instance models                            %
% ------------------------------------------------------------------ %
resultsModelsDir = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels');
modelFiles = dir(fullfile(resultsModelsDir, '*.model'));
if isempty(modelFiles)
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf(['No predicted 2D instance models (*.model) were found in\n\n%s\n\n' ...
        'Please run the 2D instance prediction first (Predict tab -> Predict)!'], resultsModelsDir), ...
        'No predictions found');
    return;
end
% dir() output is already alphabetical, but sort explicitly: the alphabetical
% order of the prediction filenames defines the Z-order of the merged stack
[~, sortIndices] = sort(lower({modelFiles.name}));
modelFiles = modelFiles(sortIndices);
numSlices = numel(modelFiles);

% ------------------------------------------------------------------ %
%  Stitching settings dialog                                          %
% ------------------------------------------------------------------ %
note = sprintf(['%d predicted 2D instance models (Z-slices, ordered by filename) will be merged;\n' ...
    'objects overlapping between neighbouring slices are linked into one 3D instance.'], numSlices);

prompt = {...
    sprintf('Method:\n  "graph" links every overlapping pair and groups them by connected components\n  "hungarian" uses strict 1-to-1 matching per slice pair'), ...
    sprintf('IoU threshold (0-1):\n  join two objects when (overlap area)/(their union area) exceeds this;\nhigher = stricter, giving more but smaller 3D objects'), ...
    sprintf('Merge split objects (IoA):\n  also join when a smaller object is mostly contained in a neighbour,\n  reconnecting an object that breaks into pieces on one slice'), ...
    sprintf('Min overlap (pixels):\n  require at least this many overlapping pixels before linking, to block tiny spurious touches'), ...
    sprintf('Z lookback (slices):\n  also compare slices this many planes apart;\n  1 = adjacent slices only, higher bridges an object that briefly vanishes'), ...
    sprintf('Min object size (voxels):\n  after stitching, delete 3D objects smaller than this; 0 = keep all'), ...
    sprintf('Z anisotropy ratio (voxel Z-size / XY-size):\n  lower the IoU threshold by this ratio for thick sections,\n  so a real but displaced continuation still links; 1 = isotropic (off)'), ...
    sprintf('Max centroid shift (pixels):\n  reject a link when object centroids are farther apart than this;\n  0 = off. Pair with the anisotropy ratio to avoid fusing distant objects'), ...
    sprintf('Centroid link radius (pixels):\n  advanced gap bridging - link an object with no overlapping neighbour\n  to the mutually-nearest one within this distance; 0 = off')};

defAns = {{'graph', 'hungarian', 1}, ...
          struct('Spinner', true, 'Value', 0.25, 'Limits', [0, 1],    'Step', 0.05, 'Round', false), ...
          true, ...
          struct('Spinner', true, 'Value', 5,    'Limits', [0, 1e6],  'Step', 1,    'Round', true), ...
          struct('Spinner', true, 'Value', 1,    'Limits', [1, 100],  'Step', 1,    'Round', true), ...
          struct('Spinner', true, 'Value', 0,    'Limits', [0, 1e9],  'Step', 1,    'Round', true), ...
          struct('Spinner', true, 'Value', 1,    'Limits', [1, 1000], 'Step', 0.5,  'Round', false), ...
          struct('Spinner', true, 'Value', 0,    'Limits', [0, 1e6],  'Step', 1,    'Round', true), ...
          struct('Spinner', true, 'Value', 0,    'Limits', [0, 1e6],  'Step', 1,    'Round', true)};

dlgParams.mibPath = obj.mibModel.mibPath;
dlgParams.WindowWidth = 720;
dlgParams.WindowHeight = 560;
dlgParams.HeaderLines = 2;
dlgParams.LabelPosition = 'left';
answer = utils.dlgs.inputUniversalDlg(obj.view.gui, note, prompt, defAns, ...
    'Merge 2D instances to 3D', dlgParams);
if isempty(answer); return; end

% assemble the options for utils.stitchInstances2Dto3D; the IoA checkbox maps
% to a 0.5 containment threshold when enabled, Inf (never links) when disabled
stitchOptions = struct();
stitchOptions.method = answer{1};
stitchOptions.iouThreshold = answer{2};
if answer{3}
    stitchOptions.ioaThreshold = 0.5;
else
    stitchOptions.ioaThreshold = inf;
end
stitchOptions.minOverlapPixels = answer{4};
stitchOptions.zLookback = answer{5};
stitchOptions.minObjectVoxels = answer{6};
anisotropyZ = answer{7};
if anisotropyZ > 1; stitchOptions.anisotropyZ = anisotropyZ; end
if answer{8} > 0; stitchOptions.maxCentroidShift = answer{8}; end
if answer{9} > 0; stitchOptions.centroidLinkRadius = answer{9}; end

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
fname = [fbase, selectedExt];
outputFilename = fullfile(fpath, fname);
selectedFormat = filterSpec{filterIndex, 2};

% ------------------------------------------------------------------ %
%  Load the 2D instance models into a volume                          %
% ------------------------------------------------------------------ %
wb = uiprogressdlg(obj.view.gui, 'Title', 'Merge 2D instances to 3D', ...
    'Message', 'Loading 2D instance models...', 'Cancelable', 'on', 'Value', 0);

inputVol = [];
imgHeight = 0; imgWidth = 0;
try
    for sliceId = 1:numSlices
        if wb.CancelRequested; delete(wb); return; end
        sliceStruct = load(fullfile(resultsModelsDir, modelFiles(sliceId).name), '-mat');
        if isfield(sliceStruct, 'modelVariable') && isfield(sliceStruct, sliceStruct.modelVariable)
            sliceLabels = sliceStruct.(sliceStruct.modelVariable);
        elseif isfield(sliceStruct, 'outputLabels')
            sliceLabels = sliceStruct.outputLabels;
        elseif isfield(sliceStruct, 'mibModel')
            sliceLabels = sliceStruct.mibModel;
        else
            error('MibDeep:mergeInstancesTo3D:badModelFile', ...
                'The labels variable could not be identified in\n%s', modelFiles(sliceId).name);
        end
        sliceLabels = squeeze(sliceLabels);

        if sliceId == 1
            [imgHeight, imgWidth] = size(sliceLabels);
            inputVol = zeros(imgHeight, imgWidth, numSlices, class(sliceLabels));
        elseif size(sliceLabels, 1) ~= imgHeight || size(sliceLabels, 2) ~= imgWidth
            error('MibDeep:mergeInstancesTo3D:sizeMismatch', ...
                ['The slices have different dimensions!\n\n%s is %dx%d, while the first slice is %dx%d.\n\n' ...
                'All prediction images must have the same width and height to be merged into a 3D stack.'], ...
                modelFiles(sliceId).name, size(sliceLabels, 1), size(sliceLabels, 2), imgHeight, imgWidth);
        end

        % promote the volume class when a later slice uses a wider integer type
        if isa(sliceLabels, 'uint32') && ~isa(inputVol, 'uint32')
            inputVol = uint32(inputVol);
        end
        inputVol(:, :, sliceId) = sliceLabels;
        wb.Value = sliceId / numSlices * 0.5;
    end
catch err
    delete(wb);
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Merge instances to 3D');
    return;
end

% ------------------------------------------------------------------ %
%  Stitch                                                             %
% ------------------------------------------------------------------ %
if wb.CancelRequested; delete(wb); return; end
wb.Indeterminate = 'on';
wb.Message = 'Stitching 2D instances into 3D objects, please wait...';

try
    [labelVol, stats] = utils.stitchInstances2Dto3D(inputVol, stitchOptions);
catch err
    delete(wb);
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Merge instances to 3D');
    return;
end
clear inputVol;
delete(wb);   % the saver shows its own progress dialog

% ------------------------------------------------------------------ %
%  Save the merged 3D instance model                                  %
% ------------------------------------------------------------------ %
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

metadata.filename       = outputFilename;
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
% per-slice source stems (prediction image names) so that 2D-sequence saving
% with the "Use original filename" policy reproduces the input naming
sliceStems = cellfun(@(fn) regexprep(fn, '^Labels_|\.model$', ''), ...
    {modelFiles.name}', 'UniformOutput', false);
metadata.sliceName      = sliceStems;
metadata.sliceSize      = [];

saveOpts.Format         = selectedFormat;
saveOpts.layerType      = 'labels';
saveOpts.modelType      = modelType;
saveOpts.pixSize        = metadata.pixSize;
saveOpts.boundingBox    = metadata.boundingBox;
saveOpts.FilenamePrefix = 'Labels_';
saveOpts.silent         = false;    % let TIF/model savers ask 3D stack vs 2D sequence
saveOpts.showWaitbar    = true;
saveOpts.overwrite      = true;     % uiputfile has already confirmed overwriting
saveOpts.ParentFigure   = obj.view.gui;
saveOpts.mibPath        = obj.mibModel.mibPath;

try
    saver = io.SaverFactory.create(selectedFormat, saveOpts);
    data5D = reshape(labelVol, [imgHeight, imgWidth, numSlices, 1, 1]);
    fnOut = saver.save(data5D, metadata, outputFilename, saveOpts);
catch err
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Merge instances to 3D');
    return;
end
if isempty(fnOut); return; end   % user cancelled a saver dialog

fprintf('MibDeep.mergeInstancesTo3D: %d 2D objects -> %d 3D instances (method=%s), saved to %s\n', ...
    stats.numInput2DObjects, stats.numOutput3DObjects, stitchOptions.method, outputFilename);

dlgOpt.mibPath     = obj.mibModel.mibPath;
dlgOpt.MsgBoxOnly  = true;
dlgOpt.Icon        = 'puffin_info';
dlgOpt.HeaderLines = 1;
utils.dlgs.inputUniversalDlg(obj.view.gui, 'The merge is complete!', {''}, ...
    {sprintf('%d 2D objects from %d slices were stitched into %d 3D instances and saved to:\n%s', ...
    stats.numInput2DObjects, numSlices, stats.numOutput3DObjects, outputFilename)}, ...
    'Merge 2D instances to 3D', dlgOpt);
end
