function img = Filter(obj, img, batchModeSwitch)
% FILTER - Apply the currently selected image filter to the dataset or a supplied image.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.Filter()              % reads data from model, applies filter, writes back
%       img = obj.Filter(img)     % applies filter to supplied image (used by preview/thumbnail)
%
% Input Arguments:
%   - **img** - *(optional)* image to filter; when empty the filter reads/writes via MibModel
%   - **batchModeSwitch** - *(optional)* ``1`` in batch mode (skips reading parameters from GUI)

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ImageFilters.Filter: triggered\n');
end
if nargin < 3; batchModeSwitch = 0; end
if nargin < 2; img = []; end

% build BatchOptOut - merge filter-specific parameters into a flat struct
BatchOptOut = obj.BatchOpt;

if batchModeSwitch == 0     % GUI mode: read current filter parameters
    ImageFiltersFields = fieldnames(obj.imageFiltersParams.(BatchOptOut.FilterName{1}));
    for i = 1:numel(ImageFiltersFields)
        if strcmp(ImageFiltersFields{i}, 'mibBatchTooltip'); continue; end
        BatchOptOut.(ImageFiltersFields{i}) = obj.imageFiltersParams.(BatchOptOut.FilterName{1}).(ImageFiltersFields{i});
    end
end

obj.imageFiltersParams.DesiredFilterName = BatchOptOut.FilterName{1};

% validate DistanceMap parameters
if strcmp(BatchOptOut.FilterName{1}, 'DistanceMap')
    errorMessage = [];
    if BatchOptOut.Mode3D == 1 && ~strcmp(BatchOptOut.Method{1}, 'euclidean')
        errorMessage = sprintf('DistanceMap in the 3D mode is implemented only for the "euclidean" method!\nPlease change the Method field to "euclidean" or switch off 3D and try again');
    end
    if strcmp(BatchOptOut.SourceLayer{1}, 'image')
        errorMessage = sprintf('The source layer for the DistanceMap filter should be one of these: "selection", "mask", or "labels"');
    end
    if ~isempty(errorMessage)
        utils.dlgs.showErrorDialog(obj.view.gui, errorMessage, 'Wrong parameters!');
        return;
    end
end

% define parent window
if isempty(obj.view)   % headless batch mode
    parentFigure = obj.mibModel.mibGUI;
else
    parentFigure = obj.view.gui;
end

returnBatchSettings = 0;
if isempty(img)
    % A BigData source image is read-only: the result goes to a new store
    if obj.mibModel.I{obj.BatchOpt.id}.datasetType(1) == 'B'
        localFilterBigData(obj, BatchOptOut, parentFigure);
        return;
    end
    % Virtual datasets are read on demand: getData3D would read the whole volume
    if obj.mibModel.I{obj.BatchOpt.id}.datasetType(1) == 'V'
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_warning';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', {''}, ...
            {sprintf('This tool is not compatible with the virtual mode!\nPlease switch to the memory-resident or BigData mode and try again')}, ...
            'Not implemented', dlgOpt);
        notify(obj.mibModel, 'StopProtocol');
        obj.closeWindow();
        return;
    end

    id = obj.BatchOpt.id;
    if obj.mibModel.I{id}.restrictToROI
        getDataOptions.roiId = 0;   % restrict to all ROIs
    else
        getDataOptions.roiId = -1;  % no ROI restriction
    end
    getDataOptions.id = id;

    if strcmp(BatchOptOut.FilterGroup{1}, 'Image Binarization')
        backupLayer = BatchOptOut.DestinationLayer{1};
    else
        backupLayer = BatchOptOut.SourceLayer{1};
    end

    if strcmp(BatchOptOut.FilterName{1}, 'ElasticDistortion') && BatchOptOut.DistortAllLAyers
        backupLayer = 'image';
    end
    if strcmp(BatchOptOut.FilterName{1}, 'DistanceMap')
        backupLayer = 'image';
    end

    switch obj.BatchOpt.DatasetType{1}
        case '2D, Slice'
            if batchModeSwitch == 0; obj.mibModel.backup(backupLayer, 0, getDataOptions); end
            timeVector = [obj.mibModel.I{obj.BatchOpt.id}.getCurrentTimePoint(), obj.mibModel.I{obj.BatchOpt.id}.getCurrentTimePoint()];
        case '3D, Stack'
            if batchModeSwitch == 0; obj.mibModel.backup(backupLayer, 1, getDataOptions); end
            timeVector = [obj.mibModel.I{obj.BatchOpt.id}.getCurrentTimePoint(), obj.mibModel.I{obj.BatchOpt.id}.getCurrentTimePoint()];
        case '4D, Dataset'
            timeVector = [1, obj.mibModel.I{obj.BatchOpt.id}.image.time];
    end
    returnBatchSettings = 1;
end

% validate 3D mode compatibility
if BatchOptOut.Mode3D == 1 && ~ismember(BatchOptOut.FilterName{1}, obj.Filters3D)
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf('The selected filter (%s) is only available in 2D mode!\nPlease change Mode3D parameter to false', BatchOptOut.FilterName{1}), ...
        'Error');
    return;
end

% filter a supplied image directly (preview/thumbnail path)
t1 = tic;
if ~isempty(img)
    BatchOptOut.ColorChannel{1} = 1;
    BatchOptOut.Mode3D = false;
    if isfield(BatchOptOut, 'useRGB') && BatchOptOut.useRGB == 1
        if size(img,3) ~= 3; return; end
    end

    switch BatchOptOut.ActionToResult{1}
        case 'Fitler image'
            img = utils.doImageFiltering(img, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
        case 'Filter and add'
            imgOut = utils.doImageFiltering(img, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
            img = img + imgOut;
        case 'Filter and subtract'
            imgOut = utils.doImageFiltering(img, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
            img = img - imgOut;
    end
    if size(img, 4)+size(img, 3) > 2; toc; end
    return;
end

% resolve color channel
switch BatchOptOut.ColorChannel{1}
    case 'All';      colChannel = NaN;  % MIB3: NaN = all channels
    case 'Displayed'; colChannel = [];
    otherwise;       colChannel = str2double(BatchOptOut.ColorChannel{1});
end
if strcmp(BatchOptOut.SourceLayer{1}, 'labels')
    colChannel = str2double(BatchOptOut.MaterialIndex);
end

% determine which layers to process (ElasticDistortion can distort all)
if strcmp(BatchOptOut.FilterName{1}, 'ElasticDistortion') && BatchOptOut.DistortAllLAyers
    if isa(obj.mibModel.I{obj.BatchOpt.id}.labels, 'core.MibLabels63')
        sourceLayersList = {'image', 'everything'};
    else
        sourceLayersList = {'image', 'labels', 'mask'};
    end
else
    sourceLayersList = BatchOptOut.SourceLayer(1);
end

for sourceLayerId = 1:numel(sourceLayersList)
    BatchOptOut.SourceLayer(1) = sourceLayersList(sourceLayerId);
    for t = timeVector(1):timeVector(2)
        if ~strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
            img = obj.mibModel.getData3D(sourceLayersList{sourceLayerId}, t, [], colChannel, getDataOptions);
        else
            getDataOptions.t = [t t];
            img = obj.mibModel.getData2D(sourceLayersList{sourceLayerId}, obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], colChannel, getDataOptions);
        end

        if strcmp(BatchOptOut.FilterGroup{1}, 'Image Binarization') && size(img{1}, 4) > 1
            utils.dlgs.showErrorDialog(obj.view.gui, 'Please select a single color channel before binarization', 'Too many color channels');
            return;
        end

        for roi = 1:numel(img)
            % adjust image for SLIC/Watershed clustering (needs uint8)
            % img{roi} is in MIB3 format [H,W,Z,C] for 3D or [H,W,C] for 2D
            if ismember(BatchOptOut.FilterName{1}, {'SlicClustering', 'WatershedClustering'})
                id = obj.mibModel.getActiveId();
                viewPort = obj.mibModel.I{id}.image.viewPort;
                if isempty(colChannel)
                    col_channel = obj.mibModel.I{obj.BatchOpt.id}.slices{4};
                elseif isnan(colChannel)
                    col_channel = 1;
                else
                    col_channel = colChannel;
                end
                if isa(img{roi}, 'uint16')
                    if obj.mibModel.onFlyImageStretch
                        for sliceId = 1:size(img{roi}, 3)
                            img{roi}(:,:,sliceId,1) = imadjust(img{roi}(:,:,sliceId,1), stretchlim(img{roi}(:,:,sliceId,1),[0 1]),[]);
                        end
                    else
                        for sliceId = 1:size(img{roi}, 3)
                            img{roi}(:,:,sliceId,1) = imadjust(img{roi}(:,:,sliceId,1), [viewPort.min(col_channel)/65535 viewPort.max(col_channel)/65535],[0 1],viewPort.gamma(col_channel));
                        end
                    end
                    img{roi} = uint8(img{roi}/255);
                else
                    if viewPort.min(col_channel) > 1 || viewPort.max(col_channel) < 255
                        for sliceId = 1:size(img{roi}, 3)
                            img{roi}(:,:,sliceId,1) = imadjust(img{roi}(:,:,sliceId,1), [viewPort.min(col_channel)/255 viewPort.max(col_channel)/255],[0 1],viewPort.gamma(col_channel));
                        end
                    end
                end
            end

            switch BatchOptOut.ActionToResult{1}
                case 'Fitler image'
                    [img{roi}, log_text] = utils.doImageFiltering(img{roi}, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
                case 'Filter and add'
                    [imgOut, log_text] = utils.doImageFiltering(img{roi}, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
                    img{roi} = img{roi}+imgOut;
                case 'Filter and subtract'
                    [imgOut, log_text] = utils.doImageFiltering(img{roi}, BatchOptOut, obj.mibModel.preferences.System.cpuParallelLimit, parentFigure);
                    img{roi} = img{roi}-imgOut;
            end

            % Normalize output: doImageFiltering normalizes to [H,W,Z,C] internally.
            % For 2D-slice image data it adds a Z=1 dim ([H,W,C]→[H,W,1,C]); squeeze it back.
            % For non-image layers, squeeze [H,W,Z,1] → [H,W,Z] (or [H,W] for 2D).
            if strcmp(sourceLayersList{sourceLayerId}, 'image') && strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                img{roi} = squeeze(img{roi});  % [H,W,1,C] → [H,W,C] for setData2D
            elseif ~strcmp(sourceLayersList{sourceLayerId}, 'image') && ~ismember(BatchOptOut.FilterName{1}, {'DistanceMap'})
                img{roi} = squeeze(img{roi});  % [H,W,Z,1] → [H,W,Z] for setData3D non-image
            end
        end

        if ismember(BatchOptOut.FilterName{1}, {'DistanceMap'})
            % apply result to image layer; convert class if needed
            id = obj.mibModel.getActiveId();
            if ~strcmp(obj.mibModel.I{id}.image.dataClass, class(img{1}(1)))
                convertOpt.showWaitbar = true;
                obj.mibModel.I{id}.image.convertImage(class(img{1}(1)), convertOpt);
                notify(obj.mibModel, 'NewDataset');
            end
            if strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                obj.mibModel.setData2D(img, 'image', obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], 1, getDataOptions);
            else
                obj.mibModel.setData3D(img, 'image', t, [], 1, getDataOptions);
            end
        elseif ~ismember(BatchOptOut.FilterName{1}, obj.BinarizationFiltersList)
            id = obj.mibModel.getActiveId();
            if strcmp(BatchOptOut.FilterName{1}, 'MathOps')
                if ~strcmp(class(img{1}), obj.mibModel.I{id}.image.dataClass)
                    obj.mibModel.I{id}.image.convertImage(class(img{1}));
                end
            end
            if ~strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                obj.mibModel.setData3D(img, sourceLayersList{sourceLayerId}, t, [], colChannel, getDataOptions);
            else
                obj.mibModel.setData2D(img, sourceLayersList{sourceLayerId}, obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], colChannel, getDataOptions);
            end
        else    % binarization filters
            if strcmp(BatchOptOut.DestinationLayer{1}, 'labels')
                if isa(img{1}, 'uint16'); ModelType = 65535; else; ModelType = 4294967295; end
                if ~strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                    obj.mibModel.createModel(ModelType);
                    obj.mibModel.setData3D(img, BatchOptOut.DestinationLayer{1}, t, [], [], getDataOptions);
                else
                    id = obj.mibModel.getActiveId();
                    if obj.mibModel.I{id}.labels.maxMaterials ~= ModelType
                        obj.mibModel.createModel(ModelType);
                    end
                    obj.mibModel.setData2D(img, BatchOptOut.DestinationLayer{1}, obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], [], getDataOptions);
                end
                obj.mibModel.showModel = true;
                notify(obj.mibModel, 'ShowImage');
            else
                if ~strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
                    obj.mibModel.setData3D(img, BatchOptOut.DestinationLayer{1}, t, [], [], getDataOptions);
                else
                    obj.mibModel.setData2D(img, BatchOptOut.DestinationLayer{1}, obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber(), [], [], getDataOptions);
                end
                if strcmp(BatchOptOut.DestinationLayer{1}, 'mask')
                    obj.mibModel.showMask = true;
                    notify(obj.mibModel, 'ShowImage');
                end
            end
        end
    end
end

if strcmp(BatchOptOut.DatasetType{1}, '2D, Slice')
    log_text = [log_text ', slice=' num2str(obj.mibModel.I{obj.BatchOpt.id}.getCurrentSliceNumber())];
end
if isnan(log_text); return; end
if ~strcmp(BatchOptOut.FilterGroup{1}, 'Image Binarization') && ~ismember(BatchOptOut.SourceLayer{1}, {'selection', 'mask', 'labels'})
    obj.mibModel.I{obj.mibModel.getActiveId()}.image.updateActionLog(log_text);
end
toc(t1);

% count user points
obj.mibModel.preferences.Users.Tiers.numberOfImageFilterings = obj.mibModel.preferences.Users.Tiers.numberOfImageFilterings + 1;
eventdata = core.ToggleEventData(2);
notify(obj.mibModel, 'UpdateUserScore', eventdata);

% redraw image
notify(obj.mibModel, 'ShowImage');

% send BatchOpt to macro recorder
if returnBatchSettings; obj.returnBatchOpt(BatchOptOut); end
end

% ---------------------------------------------------------------------------
function localFilterBigData(obj, BatchOpt, parentFigure)
% LOCALFILTERBIGDATA - Filter a BigData image into a new OME-Zarr store.
%
% The source image of a BigData dataset is read-only, so the filtered image is
% written to the store ``BatchOpt.BigData_OutputPath`` and opened in
% ``BatchOpt.BigData_OpenIn`` (``controllers.BigDataOptions.run``). The whole
% dataset is filtered at level ``BatchOpt.BigData_PyramidLevel``, in bands of
% rows: ``DatasetType`` "3D, Stack" and "4D, Dataset" alike. "2D, Slice" is
% refused (``BigDataOptions.checkWholeDatasetType``), except with
% ``'Current overwrite (BigData)'``, which writes the shown slice into the store
% (``BigDataOptions.overwriteSlice``); a statistics pass still reads every slice.
%
% Only filters whose neighbourhood follows from their own size parameters are
% offered (``localFilterHalo``): a band then reads that many extra rows (and
% slices in 3D) and equals the whole-slice result. ``circular`` padding is
% refused, because a band cannot see the rows on the other side of the image.
% So are the settings that read the whole slice: *UnsharpMask* with a
% *Threshold* above 0 (relative to the strongest edge) and *MathOps* with
% another output class (the store keeps the class of the image). An empty
% *AdditiveNoise* of *Wiener* or *DegreeOfSmoothing* of *NonLocalMeans*, which
% MATLAB estimates from the whole slice, comes from a statistics pass per slice
% and channel (``localNoiseEstimates``).
%
% The filters whose result depends on the whole slice (*FlatfieldCorrection*,
% *LocalBrighten*, *ReduceHaze*, *LocalContrast*, *FastLocalLaplacian*) take that
% part from a coarser level of at most ``BigDataOptions.GuidePixels`` pixels
% and compute the rest in bands, see ``localPositionedPlan``; equal to the
% Standard result when the processed level itself fits that budget.
% *ElasticDistortion* and *BMxD* need the position of the band too: a random
% field generated per row, a block grid aligned to the slice.
% Only the image layer. The binarization filters write the mask or selection of
% the model instead (``localBinarizeBigData``).
%
% Errors are shown in a dialog, or raised when there is no window to show them
% in (headless batch), so a failed run never reports success.

filterName = BatchOpt.FilterName{1};
if ~strcmp(BatchOpt.SourceLayer{1}, 'image')
    localReportError(obj, parentFigure, sprintf(['On BigData datasets the filters are applied to the image ' ...
        'layer only; the "%s" filter with the "%s" layer is not available yet.'], filterName, BatchOpt.SourceLayer{1}));
    return;
end
if strcmp(BatchOpt.FilterGroup{1}, 'Image Binarization')
    localBinarizeBigData(obj, BatchOpt, parentFigure);
    return;
end
if controllers.BigDataOptions.checkWholeDatasetType(obj.mibModel, parentFigure, 'controllers:ImageFilters:bigData', ...
        BatchOpt, 'BigData filtering')
    return;
end
[haloYX, haloZ] = localFilterHalo(BatchOpt);
positioned = ismember(filterName, {'FlatfieldCorrection', 'LocalBrighten', 'ReduceHaze', 'LocalContrast', ...
    'FastLocalLaplacian', 'ElasticDistortion', 'BMxD'});
if isempty(haloYX) && ~positioned
    localReportError(obj, parentFigure, sprintf(['The "%s" filter is not available for BigData datasets: ' ...
        'its result depends on the whole image, so it cannot be computed in parts.'], filterName));
    return;
end
if isfield(BatchOpt, 'Padding') && strcmp(BatchOpt.Padding{1}, 'circular')
    localReportError(obj, parentFigure, ['The "circular" padding is not available for BigData datasets: ' ...
        'the image is filtered in bands of rows. Please select another padding.']);
    return;
end
if strcmp(filterName, 'UnsharpMask') && BatchOpt.Threshold{1} > 0
    % imsharpen compares the edges with the strongest edge of the whole image
    localReportError(obj, parentFigure, ['UnsharpMask with a Threshold above 0 is not available for BigData ' ...
        'datasets: the threshold is relative to the strongest edge of the whole image. Please set it to 0.']);
    return;
end
if strcmp(filterName, 'MathOps') && ~strcmp(BatchOpt.OutputImageClass{1}, 'Unchanged')
    localReportError(obj, parentFigure, ['MathOps with another output class is not available for BigData ' ...
        'datasets: the new store keeps the class of the image. Please select "Unchanged".']);
    return;
end
if ~BatchOpt.Mode3D; haloZ = 0; end

% channels to filter; the others are copied unchanged, as on a Standard dataset
dataset = obj.mibModel.I{BatchOpt.id};
switch BatchOpt.ColorChannel{1}
    case 'All'
        channels = 1:dataset.image.colors;
    case 'Displayed'
        channels = dataset.slices{4};
    otherwise
        channels = sscanf(BatchOpt.ColorChannel{1}, '%*[^0-9]%d');
        if isempty(channels); channels = sscanf(BatchOpt.ColorChannel{1}, '%d'); end
end

filterOptions = rmfield(BatchOpt, intersect(fieldnames(BatchOpt), {'mibBatchTooltip', 'id', ...
    'BigData_PyramidLevel', 'BigData_OutputPath', 'BigData_OpenIn'}));
filterOptions.showWaitbar = false;            % the store writer shows the progress
filterOptions.UseParallelComputing = false;
filterOptions.DatasetType = {'3D, Stack'};    % blocks arrive as [H W Z C]

% an empty noise parameter is estimated by MATLAB from the whole slice; here it
% comes from a statistics pass, one value per slice and channel
estimates = [];
guideLevel = [];
bandBytes = [];
confirmed = false;      % true once confirmRun asked before a statistics pass
statisticsNote = 'A pass over a sample of rows of every slice comes first, for the statistics; it is not in the estimate.';
estimateNoise = strcmp(filterName, 'Wiener') && isempty(str2num(BatchOpt.AdditiveNoise)); %#ok<ST2NM> as doImageFiltering reads it
estimateSmoothing = strcmp(filterName, 'NonLocalMeans') && isnan(str2double(BatchOpt.DegreeOfSmoothing));
if positioned
    % the band function needs its position: the part depending on the whole
    % slice comes from a coarser level (localPositionedPlan)
    try
        level = obj.bigDataOptions.resolveLevel(BatchOpt);
        plan = localPositionedPlan(obj, dataset, level, channels, BatchOpt);
    catch err
        localReportError(obj, parentFigure, err.message);
        return;
    end
    if plan.sampleLimits
        % asked before the statistics pass; the probe of the time runs without the limits
        confirmed = obj.bigDataOptions.confirmRun(BatchOpt, ...
            @(block, z, firstRow) localPositionedBlock(block, z, firstRow, plan, filterOptions, channels), ...
            HaloYX = plan.haloYX, BandBytes = obj.bigDataOptions.BandBytes / plan.bandDivisor, Note = statisticsNote);
        localGuideCache('');      % the probe's guide lacks the limits
        if ~confirmed; notify(obj.mibModel, 'StopProtocol'); return; end
        plan.limits = localSampledLimits(obj, dataset.image, level, channels, plan);
        if isempty(plan.limits)     % cancelled while collecting; nothing written
            notify(obj.mibModel, 'StopProtocol');
            return;
        end
    end
    haloYX = plan.haloYX;
    haloZ = 0;
    guideLevel = plan.guideLevel;
    bandBytes = obj.bigDataOptions.BandBytes / plan.bandDivisor;
    releaseGuide = onCleanup(@() localReleaseGuide(BatchOpt));    % frees the cached coarse slice when the run ends
    blockFunction = @(block, z, firstRow) localPositionedBlock(block, z, firstRow, plan, filterOptions, channels);
elseif estimateNoise || estimateSmoothing
    try
        level = obj.bigDataOptions.resolveLevel(BatchOpt);
    catch err
        localReportError(obj, parentFigure, err.message);
        return;
    end
    % asked before the statistics pass; the probe of the time uses a fixed noise value
    probeOptions = filterOptions;
    if estimateNoise; probeOptions.AdditiveNoise = '0.001'; else; probeOptions.DegreeOfSmoothing = '0.05'; end
    confirmed = obj.bigDataOptions.confirmRun(BatchOpt, ...
        @(block) localFilterBlock(block, probeOptions, channels, BatchOpt.Mode3D), ...
        HaloYX = haloYX, HaloZ = haloZ, Note = statisticsNote);
    if ~confirmed; notify(obj.mibModel, 'StopProtocol'); return; end
    estimates = localNoiseEstimates(obj, dataset.image, level, channels, BatchOpt);
    if isempty(estimates.values)      % cancelled while collecting; nothing written
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
    blockFunction = @(block, z) localFilterBlock(block, filterOptions, channels, BatchOpt.Mode3D, estimates, z);
else
    blockFunction = @(block) localFilterBlock(block, filterOptions, channels, BatchOpt.Mode3D);
end

try
    result = obj.bigDataOptions.run(BatchOpt, blockFunction, HaloYX = haloYX, HaloZ = haloZ, BandBytes = bandBytes, ...
        Fingerprint = jsonencode(struct('filterOptions', filterOptions, 'estimates', estimates, 'guideLevel', guideLevel)), ...
        Confirmed = confirmed);
catch err
    localReportError(obj, parentFigure, sprintf('Filtering of the BigData dataset failed:\n%s', err.message));
    return;
end
if isempty(result)      % cancelled; nothing is left on disk
    notify(obj.mibModel, 'StopProtocol');
    return;
end

obj.bigDataOptions.reportStoreResult(result, sprintf('%s filter of %s, level %s -> %s', filterName, ...
    dataset.image.filename, BatchOpt.BigData_PyramidLevel{1}, result.outputPath));

obj.mibModel.preferences.Users.Tiers.numberOfImageFilterings = obj.mibModel.preferences.Users.Tiers.numberOfImageFilterings + 1;
notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));
obj.returnBatchOpt(BatchOpt);
end

% ---------------------------------------------------------------------------
function localBinarizeBigData(obj, BatchOpt, parentFigure)
% LOCALBINARIZEBIGDATA - Edge detection of a BigData image into the mask or selection of its model.
%
% The whole dataset, or the shown slice for ``DatasetType`` ``'2D, Slice'``
% (``BigDataOptions.levelSlices``), is processed at level
% ``BatchOpt.BigData_PyramidLevel`` in bands of rows, and the destination layer
% is replaced there (``controllers.BigDataOptions.runToModel``, no undo). Offered only where a band
% with a halo gives the whole-slice result:
%
% - **Edge** with *Sobel*, *Prewitt*, *Roberts* (halo 3: the 3 x 3 / 2 x 2
%   kernel plus the thinning step's neighbours) or *LaplacianOfGaussian*
%   (halo ``ceil(3*Sigma) + 2``: ``edge`` uses a kernel of
%   ``2*ceil(3*Sigma) + 1``, plus the zero-crossing neighbours). An empty
%   **Threshold** is automatic: ``edge`` computes it from the whole image it
%   is given, so a band would get its own; instead one threshold per slice
%   comes from a statistics pass (``localEdgeThresholds``) and every band of
%   the slice uses it.
% - Not *Canny* / *approxcanny*: their hysteresis keeps a weak edge when it is
%   connected to a strong one at any distance, beyond any halo.
% - Not *SlicClustering* / *WatershedClustering*: the clusters depend on the
%   whole image, and their labels output needs more indices than a BigData
%   model holds.
%
% One color channel, as on a Standard dataset. Errors as ``localFilterBigData``.
filterName = BatchOpt.FilterName{1};
if ~strcmp(filterName, 'Edge')
    localReportError(obj, parentFigure, sprintf(['"%s" is not available for BigData datasets: its clusters depend ' ...
        'on the whole image, so they cannot be computed in parts.\nAvailable: Edge.'], filterName));
    return;
end
method = BatchOpt.Method{1};
sigma = max(str2num(BatchOpt.Sigma)); %#ok<ST2NM> entered as text
if isempty(sigma); sigma = 2; end      % the default of edge()
switch method
    case {'Sobel', 'Prewitt', 'Roberts'}
        haloYX = 3;
    case 'LaplacianOfGaussian'
        haloYX = ceil(3 * sigma) + 2;
    otherwise
        localReportError(obj, parentFigure, sprintf(['The "%s" edge method is not available for BigData datasets: ' ...
            'it links edges over any distance, so it cannot be computed in parts.\n' ...
            'Available: Sobel, Prewitt, Roberts, LaplacianOfGaussian.'], method));
        return;
end
dataset = obj.mibModel.I{BatchOpt.id};
switch BatchOpt.ColorChannel{1}
    case 'All'
        channel = 1:dataset.image.colors;
    case 'Displayed'
        channel = dataset.slices{4};
    otherwise
        channel = sscanf(BatchOpt.ColorChannel{1}, '%*[^0-9]%d');
        if isempty(channel); channel = sscanf(BatchOpt.ColorChannel{1}, '%d'); end
end
if numel(channel) ~= 1
    localReportError(obj, parentFigure, 'Please select a single color channel before binarization');
    return;
end
layer = BatchOpt.DestinationLayer{1};

filterOptions = rmfield(BatchOpt, intersect(fieldnames(BatchOpt), {'mibBatchTooltip', 'id', ...
    'BigData_PyramidLevel', 'BigData_OutputPath', 'BigData_OpenIn'}));
filterOptions.showWaitbar = false;
filterOptions.UseParallelComputing = false;
filterOptions.DatasetType = {'3D, Stack'};
% checked before any reading; "2D, Slice" processes the shown slice only
try
    level = obj.bigDataOptions.checkModelOutput(BatchOpt, layer);
    slices = obj.bigDataOptions.levelSlices(BatchOpt, level, BatchOpt.DatasetType{1});
catch err
    localReportError(obj, parentFigure, err.message);
    return;
end
thresholdText = BatchOpt.Threshold;
confirmed = false;      % true once confirmRun asked before the statistics pass
if isempty(str2num(BatchOpt.Threshold)) %#ok<ST2NM>
    % automatic threshold: edge() computes it from the whole image it is given,
    % so it is computed here from a statistics pass, one per slice; asked
    % before that pass, the probe of the time with a fixed threshold
    confirmed = obj.bigDataOptions.confirmRun(BatchOpt, ...
        @(block) localEdgeBlock(block, setfield(filterOptions, 'Threshold', '0.05')), ...
        Layer = layer, Slices = slices, HaloYX = haloYX, ColChannel = channel, ...
        Note = 'A pass over a sample of rows of every slice comes first, for the thresholds; it is not in the estimate.');
    if ~confirmed; notify(obj.mibModel, 'StopProtocol'); return; end
    [thresholds, fractionRead] = localEdgeThresholds(obj, dataset.image, level, channel, method, ...
        BatchOpt.Direction{1}, sigma, slices);
    if isempty(thresholds)      % cancelled while collecting; nothing written
        notify(obj.mibModel, 'StopProtocol');
        return;
    end
    blockFunction = @(block, z) localEdgeBlock(block, setfield(filterOptions, 'Threshold', ...
        sprintf('%.17g', thresholds(z))));
    thresholdText = sprintf('auto %.4g-%.4g from %.1f%% of the slices processed', min(thresholds), max(thresholds), ...
        100 * fractionRead);
else
    blockFunction = @(block) localEdgeBlock(block, filterOptions);
end

try
    result = obj.bigDataOptions.runToModel(BatchOpt, blockFunction, layer, HaloYX = haloYX, ColChannel = channel, ...
        Slices = slices, Confirmed = confirmed);
catch err
    localReportError(obj, parentFigure, sprintf('Binarization of the BigData dataset failed:\n%s', err.message));
    return;
end
if isempty(result)      % cancelled at the confirmation, nothing written
    notify(obj.mibModel, 'StopProtocol');
    return;
end
% shows the layer; a cancel during the write is reported (no undo), and a coarse
% level is explained (finer levels are filled by upsampling)
if ~obj.bigDataOptions.reportModelResult(result, layer); return; end
sliceText = '';
if ~isempty(slices); sliceText = sprintf(', level slice %d', slices); end
fprintf('Edge (%s, threshold %s) of %s, level %s%s -> %s\n', method, thresholdText, ...
    dataset.image.filename, BatchOpt.BigData_PyramidLevel{1}, sliceText, layer);
obj.mibModel.preferences.Users.Tiers.numberOfImageFilterings = obj.mibModel.preferences.Users.Tiers.numberOfImageFilterings + 1;
notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));
obj.returnBatchOpt(BatchOpt);
end

% ---------------------------------------------------------------------------
function [thresholds, fractionRead] = localEdgeThresholds(obj, image, level, channel, method, direction, sigma, slices)
% LOCALEDGETHRESHOLDS - The automatic threshold of edge() for every slice of a level, from a statistics pass.
%
% ``edge`` derives its automatic threshold from a mean over the image it is
% given (Pratt's RMS estimate of the noise):
%
% - *Sobel*, *Prewitt*: ``sqrt(4 * mean(b))``, *Roberts*: ``sqrt(6 * mean(b))``,
%   where ``b`` is the squared gradient magnitude of ``im2single(image)``:
%   ``gv.^2 + gh.^2`` for the direction *both*, ``gh.^2`` for *horizontal*,
%   ``gv.^2`` for *vertical* (the gradients ``edge`` returns; checked against
%   its threshold output in R2026a);
% - *LaplacianOfGaussian*: ``0.75 * mean(abs(b))``, ``b`` the image filtered by
%   the zero-sum ``fspecial('log', 2*ceil(3*sigma)+1, sigma)`` kernel with
%   replicated borders.
%
% The mean is taken per slice over stripes of rows (``utils.bigdata.sampleStripes``),
% each read with the halo of the kernel (1 row, ``ceil(3*sigma)`` for LoG) so
% ``b`` on a stripe equals ``b`` of the whole slice. When the level fits the
% sampling budget every row is read and the thresholds are those ``edge``
% computes for the whole slices.
%
% Only the level slices ``slices`` are sampled (``[]`` = all), so the budget
% goes to the slices that are processed.
%
% Output Arguments:
%   - **thresholds** - [1 x depth] double, NaN for a slice not sampled, ``[]`` when cancelled
%   - **fractionRead** - [double] share of the level read
switch method
    case {'Sobel', 'Prewitt', 'Roberts'}
        energyFunction = @(block) localGradientEnergy(block, lower(method), direction);
        haloYX = 1;
    case 'LaplacianOfGaussian'
        kernel = fspecial('log', ceil(sigma * 3) * 2 + 1, sigma);
        kernel = kernel - sum(kernel(:)) / numel(kernel);
        energyFunction = @(block) abs(imfilter(im2single(block), kernel, 'replicate'));
        haloYX = ceil(sigma * 3);
end
progressParent = [];
if ~isempty(obj.view) && isvalid(obj.view.gui); progressParent = obj.view.gui; end
[sums, info] = utils.bigdata.sampleStripes(image, level, @(values) [sum(values(:), 'double'); numel(values)], ...
    ColChannel = channel, BlockFunction = energyFunction, HaloYX = haloYX, ParentFigure = progressParent, ...
    Title = 'Collecting the statistics', Slices = slices);
thresholds = [];
fractionRead = 0;
if isempty(sums); return; end
meanEnergy = NaN(1, numel(sums));
sampled = ~cellfun(@isempty, sums);
meanEnergy(sampled) = cellfun(@(sliceSum) sliceSum(1) / sliceSum(2), sums(sampled));
switch method
    case {'Sobel', 'Prewitt'}
        thresholds = sqrt(4 * meanEnergy);
    case 'Roberts'
        thresholds = sqrt(6 * meanEnergy);
    case 'LaplacianOfGaussian'
        thresholds = 0.75 * meanEnergy;
end
fractionRead = info.fractionRead;
end

% ---------------------------------------------------------------------------
function energy = localGradientEnergy(block, method, direction)
% LOCALGRADIENTENERGY - Squared gradient magnitude of a band, as edge() sums it for its automatic threshold.
[~, ~, gradientV, gradientH] = edge(reshape(block, size(block, 1), size(block, 2)), method, [], direction);
switch direction
    case 'horizontal'
        energy = gradientH .* gradientH;
    case 'vertical'
        energy = gradientV .* gradientV;
    otherwise
        energy = gradientV .* gradientV + gradientH .* gradientH;
end
end

% ---------------------------------------------------------------------------
function [haloYX, haloZ] = localFilterHalo(BatchOpt)
% LOCALFILTERHALO - Rows (and slices) a filter reads around a pixel; [] for a filter not offered on BigData.
%
% The halo is half of the filter support, rounded up, so it covers the
% neighbourhood for an odd and an even size alike. A scalar size applies to every
% axis; a 2-element one gives Z the second value.
%
% ``[]`` also for the filters that need the position of the band
% (``localPositionedPlan`` gives their halo), and for those not offered:
% *DistanceMap* (distances of any length; a model layer as input) and
% *DNNdenoise* (a network of unknown reach, too slow for a whole slide).
haloYX = [];
haloZ = [];
switch BatchOpt.FilterName{1}
    case {'AddNoise', 'MathOps'}
        haloYX = 0;     % per pixel
        haloZ = 0;
        return;
    case {'Average', 'Gaussian', 'LoG'}
        support = str2num(BatchOpt.HSize); %#ok<ST2NM> sizes are entered as '3' or '3 3 5'
    case 'Disk'
        support = 2 * BatchOpt.Radius{1} + 1;
    case 'Motion'
        support = BatchOpt.Length{1} + 2;       % the kernel is up to Length wide at any angle, plus rounding
    case {'Median', 'Wiener'}
        support = str2num(BatchOpt.NeighborhoodSize); %#ok<ST2NM>
    case 'Mode'
        support = str2num(BatchOpt.FiltSize); %#ok<ST2NM>
    case 'SaltAndPepper'
        support = str2num(BatchOpt.HSize); %#ok<ST2NM>
    case {'Entropy', 'Range', 'Std'}
        support = str2num(BatchOpt.NeighborhoodSize); %#ok<ST2NM>
        if ~isempty(support) && strcmp(BatchOpt.StrelShape{1}, 'disk')
            diskElement = strel('disk', support(1), 0);     % as doImageFiltering builds it
            support = size(diskElement.Neighborhood);
        end
    case 'Bilateral'
        support = str2double(BatchOpt.NeighborhoodSize);
        if isnan(support); support = 2 * ceil(2 * BatchOpt.spatialSigma{1}) + 1; end   % the default of imbilatfilt
    case 'NonLocalMeans'
        % a pixel compares its window with the windows of its search area
        searchSize = str2double(BatchOpt.SearchWindowSize);
        comparisonSize = str2double(BatchOpt.ComparisonWindowSize);
        support = (searchSize - mod(searchSize, 2) + 1) + (comparisonSize - mod(comparisonSize, 2) + 1) - 1;
    case 'AnisotropicDiffusion'
        support = 2 * BatchOpt.NumberOfIterations{1} + 1;     % each iteration reaches one pixel further
    case 'UnsharpMask'
        support = 2 * ceil(2 * BatchOpt.Radius{1}) + 1;       % the Gaussian kernel of imsharpen
    case 'Frangi'
        % fibermetric smooths with a Gaussian of sigma = thickness / 6, size
        % 2*ceil(3*sigma) + 1, then takes the Hessian (two more rows each side)
        thickness = str2num(BatchOpt.ThicknessRange); %#ok<ST2NM>
        if isempty(thickness); return; end
        support = 2 * ceil(3 * max(thickness) / 6) + 1 + 4;
    case {'Prewitt', 'Sobel', 'Gradient'}
        support = 3;
    otherwise
        return;
end
if isempty(support); return; end
support(end+1:3) = support(end);
haloYX = ceil(max(support(1:2)) / 2);
haloZ = ceil(support(3) / 2);
end

% ---------------------------------------------------------------------------
function estimates = localNoiseEstimates(obj, image, level, channels, BatchOpt)
% LOCALNOISEESTIMATES - The noise value MATLAB estimates from a whole slice, for every slice and channel of a level.
%
% An empty noise parameter makes MATLAB estimate it from the image it is given,
% so a band would get its own value. Instead the value of every slice comes from
% a statistics pass over stripes of rows (``utils.bigdata.sampleStripes``),
% computed as MATLAB does it:
%
% - *Wiener*, empty *AdditiveNoise*: ``wiener2`` takes the mean of the local
%   variance, ``mean2(filter2(ones(n), g.^2)/prod(n) - localMean.^2)`` with
%   ``g = im2double(image)``; each stripe is read with the halo of the
%   neighbourhood, so its local variance equals that of the whole slice.
% - *NonLocalMeans*, empty *DegreeOfSmoothing*: ``imnlmfilt`` uses Immerkaer's
%   estimate, ``sum(abs(conv2(single(image), K))) * sqrt(pi/2) / (6*(W-2)*(H-2))``
%   with the full convolution by ``K = [1 -2 1; -2 4 -2; 1 -2 1]``. Each stripe
%   (halo 1 row) gives the rows of the full convolution centred on its rows; the
%   two outer rows of the full convolution, centred on the rows outside the
%   image, depend on the first and the last row alone and are read separately.
%   A sample is scaled to the height of the slice.
%
% When the level fits the sampling budget every row is read and the values are
% those MATLAB computes for the whole slices (up to the order of summation).
%
% Output Arguments:
%   - **estimates** - struct: ``field`` [char] the BatchOpt field to set,
%     ``values`` ``[depth x numel(channels)]`` double (``[]`` when cancelled),
%     ``fractionRead`` [double]
progressParent = [];
if ~isempty(obj.view) && isvalid(obj.view.gui); progressParent = obj.view.gui; end
if strcmp(BatchOpt.FilterName{1}, 'Wiener')
    neighborhood = str2num(BatchOpt.NeighborhoodSize); %#ok<ST2NM>
    if isscalar(neighborhood); neighborhood = [neighborhood, neighborhood]; end
    estimates = struct('field', 'AdditiveNoise', 'values', [], 'fractionRead', 0);
    [sums, info] = utils.bigdata.sampleStripes(image, level, ...
        @(variance) [sum(sum(variance, 1), 2, 'double'); repmat(size(variance, 1) * size(variance, 2), 1, 1, size(variance, 3))], ...
        ColChannel = channels, BlockFunction = @(block) localLocalVariance(block, neighborhood), ...
        HaloYX = ceil(max(neighborhood) / 2), ParentFigure = progressParent, Title = 'Estimating the noise');
    if isempty(sums); return; end
    estimates.values = cell2mat(cellfun(@(sliceSum) reshape(sliceSum(1, 1, :) ./ sliceSum(2, 1, :), 1, []), ...
        sums(:), 'UniformOutput', false));
else
    kernel = [1 -2 1; -2 4 -2; 1 -2 1];
    estimates = struct('field', 'DegreeOfSmoothing', 'values', [], 'fractionRead', 0);
    [sums, info] = utils.bigdata.sampleStripes(image, level, ...
        @(rowSums) [sum(sum(rowSums, 1), 2, 'double'); repmat(size(rowSums, 1), 1, 1, size(rowSums, 3))], ...
        ColChannel = channels, BlockFunction = @(block) localLaplacianRowSums(block, kernel), HaloYX = 1, ...
        ParentFigure = progressParent, Title = 'Estimating the noise');
    if isempty(sums); return; end
    levelSize = image.pyramid.levelImageSizes(level, :);    % [Y X Z]
    height = levelSize(1);
    width = levelSize(2);
    edgeRows = io.savers.FilteredSliceProvider(image, level, channels, @(block) block);
    values = zeros(levelSize(3), numel(channels));
    for z = 1:levelSize(3)
        % the full convolution's outer rows: the first and last image rows
        % against the kernel's outer row [1 -2 1]
        firstRow = single(edgeRows.getSliceRows(z, 1, 1));
        lastRow = single(edgeRows.getSliceRows(z, height, height));
        for channelIndex = 1:numel(channels)
            centred = sums{z}(1, 1, channelIndex) * height / sums{z}(2, 1, channelIndex);
            outer = sum(abs(conv2(firstRow(:, :, channelIndex), kernel(1, :))), 'double') + ...
                sum(abs(conv2(lastRow(:, :, channelIndex), kernel(3, :))), 'double');
            values(z, channelIndex) = (centred + outer) * sqrt(0.5 * pi) / (6 * (width - 2) * (height - 2));
        end
    end
    estimates.values = values;
end
estimates.fractionRead = info.fractionRead;
end

% ---------------------------------------------------------------------------
function variance = localLocalVariance(block, neighborhood)
% LOCALLOCALVARIANCE - The local variance of wiener2 for every channel of a band, [rows width channels].
variance = zeros(size(block));
for channel = 1:size(block, 3)
    image = im2double(block(:, :, channel));
    localMean = filter2(ones(neighborhood), image) / prod(neighborhood);
    variance(:, :, channel) = filter2(ones(neighborhood), image.^2) / prod(neighborhood) - localMean.^2;
end
end

% ---------------------------------------------------------------------------
function rowSums = localLaplacianRowSums(block, kernel)
% LOCALLAPLACIANROWSUMS - Per row, the sum of abs of the full convolution row centred on it, in column 1 of [rows width channels].
%
% The provider keeps the width of a block, so the sums go to the first column
% and the other columns are zero.
rowSums = zeros(size(block));
for channel = 1:size(block, 3)
    response = abs(conv2(single(block(:, :, channel)), kernel));     % full: rows 2..end-1 are centred on the block rows
    rowSums(:, 1, channel) = sum(response(2:end-1, :), 2, 'double');
end
end

% ---------------------------------------------------------------------------
function out = localFilterBlock(block, filterOptions, channels, mode3D, estimates, z)
% LOCALFILTERBLOCK - Apply the filter to the selected channels of one band.
%
% ``block`` is ``[rows width colors]`` (2D) or ``[rows width depth colors]``
% (3D), see io.savers.FilteredSliceProvider. ``ActionToResult`` is applied as in
% the Standard path: the result replaces, is added to, or subtracted from the
% channel, in the class of the image. With ``estimates`` (``localNoiseEstimates``)
% the band belongs to level slice ``z`` and each channel is filtered with its
% own value of ``estimates.field``, as MATLAB estimates it for each slice.
if mode3D
    data = block;
else
    data = reshape(block, size(block, 1), size(block, 2), 1, size(block, 3));
end
out = data;
% imnlmfilt refuses an image under 21 x 21; a short band (the provider's
% 8-row probe, a last band of a few rows) is padded symmetrically on both
% sides. The padding lies beyond the halo, so the kept rows do not reach it
padRows = 0;
if strcmp(filterOptions.FilterName{1}, 'NonLocalMeans') && size(data, 1) < 21
    padRows = ceil((21 - size(data, 1)) / 2);
    data = padarray(data, [padRows 0], 'symmetric', 'both');
end
if nargin < 5 || isempty(estimates)
    [filtered, ~] = utils.doImageFiltering(data(:,:,:,channels), filterOptions);   % two outputs: the log text is built only then
else
    filtered = zeros(size(data, 1), size(data, 2), size(data, 3), numel(channels), 'like', data);
    for channelIndex = 1:numel(channels)
        filterOptions.(estimates.field) = sprintf('%.17g', estimates.values(z, channelIndex));
        [filtered(:,:,:,channelIndex), ~] = utils.doImageFiltering(data(:,:,:,channels(channelIndex)), filterOptions);
    end
end
filtered = reshape(filtered, size(data, 1), size(data, 2), size(data, 3), numel(channels));
if padRows > 0
    filtered = filtered(padRows + 1:end - padRows, :, :, :);
    data = data(padRows + 1:end - padRows, :, :, :);
end
switch filterOptions.ActionToResult{1}
    case 'Filter and add'
        out(:,:,:,channels) = data(:,:,:,channels) + filtered;
    case 'Filter and subtract'
        out(:,:,:,channels) = data(:,:,:,channels) - filtered;
    otherwise
        out(:,:,:,channels) = filtered;
end
if ~mode3D
    out = reshape(out, size(out, 1), size(out, 2), size(out, 4));
end
end

% ---------------------------------------------------------------------------
function plan = localPositionedPlan(obj, dataset, level, channels, BatchOpt)
% LOCALPOSITIONEDPLAN - Parameters of a filter whose bands need their position in the slice.
%
% Every quantity a band needs besides its own rows is fixed here, so all bands
% of a slice compute the same thing (no seams):
%
% - *ElasticDistortion*: the random field comes from one random stream per row
%   (``localElasticBand``), smoothed and scaled as in
%   ``utils.elasticDistortionFilter`` (kernel ``2*ceil(2*Sigma)+1``). Halo:
%   the largest possible displacement, ``ScalingFactor`` (the smoothed noise
%   stays within [-1, 1]), plus the smoothing kernel and the interpolation. Only the image is
%   distorted, so *DistortAllLAyers* is refused when the dataset has a model
%   or a mask.
% - *BMxD*: a pixel depends on the blocks of its search window, and the Wiener
%   stage on the hard-thresholding estimate of its own search window, so the
%   halo is ``2*N1 + floor(Ns/2)`` for each stage (``BM3DProfile``: 70 rows
%   for *np*, 56 for *lc*). The reference blocks lie on a grid of
%   ``Nstep`` rows from the top of the image; a band is padded at the top to
%   that grid (``gridStep``). BM3D is not local to the last bit: its matching
%   thresholds scale with the intensity range of the image it gets (stage 1
%   the input, stage 2 the basic estimate), its noise spectrum is processed at
%   that image size, and its threads aggregate in any order. Bands therefore
%   differ from whole slices by a mean 0.1 grey levels (99th percentile 0.6-1.2
%   on a micrograph); rescaling the thresholds to the slice ranges or doubling
%   the halo changed that by under 0.01, so neither is done.
%
% The other filters take what depends on the whole slice from the *guide*: the
% same slice at the finest level ``guideLevel`` of at most
% ``BigDataOptions.GuidePixels`` pixels (``localGuideLevel``), read and
% processed once per slice (``localGuide``). ``ratio`` is the guide pixels per
% level pixel in Y and X; at ratio 1 (the level fits the budget) the result
% equals the Standard one:
%
% - *FlatfieldCorrection*: ``imflatfield`` divides by the Gaussian shading and
%   multiplies by the mean of the image. The mean comes from the guide, or
%   from ``localSampledLimits`` when the guide is coarser. The
%   shading is computed in the band (halo ``(FilterSize - 1) / 2``) up to a
%   halo of 256 rows, beyond that from the guide with the sigma scaled by
%   ``ratio`` and interpolated (a shading that wide is smooth on the guide).
% - *LocalBrighten*: ``imreducehaze`` of the complement, whose atmospheric light
%   ``imreducehaze`` estimates from the whole image; it comes from the guide,
%   the rest is the 5 x 5 guided filter of *simpledcp* (halo 5). From a coarser
%   guide the estimate differs (0.3-4 grey levels on sample images): it is the
%   pixel nearest to white in the brightest region, and averaging dims it;
%   picking the region on the guide and the pixel on the level was tried and
%   was worse on average (better in 2 of 6 cases, up to 4.9 off).
% - *ReduceHaze*: an empty *AtmosphericLight* comes from the guide. *simpledcp*
%   is local (halo 5). *approxdcp* sizes its minimum filter and guided filter
%   to the image (``min(H, W) / 400 * 15`` and ``/ 50``); it is offered when
%   the level fits the budget: the haze map of the whole slice, and the band
%   computes the radiance from it pixel by pixel as ``imreducehaze`` does
%   (``omega`` 0.95, ``t0`` 0.1). From a coarser level its minimum filter reads
%   higher minima (3-12 grey levels off on sample images; a dark channel
%   min-pooled from the full level would bring it to 0.1-1.5, at the price of
%   a full extra read). *ContrastEnhancement* *global* stretches by the
%   minimum, maximum and 0.1% / 99.9% limits of the whole dehazed slice
%   (``localSampledLimits`` when the guide is coarser); *boost* is local
%   (``BoostAmount`` 0.1, the default).
% - *LocalContrast*, *FastLocalLaplacian*: ``locallapfilt`` builds a pyramid of
%   ``floor(log2(min(H, W))) + 1`` levels and samples the intensities between
%   the minimum and the maximum of the image. Here the band runs the same fast
%   local Laplacian (``localLaplacianFilter``) with only ``numLevels`` levels,
%   on the intensity grid of the guide, and adds the contribution of the
%   coarser levels: the guide filtered with all its levels minus the guide
%   filtered with the levels the band covers, interpolated. Levels below
%   ``numLevels`` are the same for any number of levels above them, so at ratio
%   1 this is exact. The intensity samples span the range of the processed
%   level (``localSampledLimits`` when the guide is coarser). ``numLevels`` is
%   2 plus the levels the guide is coarser by; the band reaches ``2^(numLevels+1)`` rows (measured: 3, 11, 23, 55, 110,
%   236 rows for 2..7 levels) and is padded to the grid of its coarsest level.
%   A band keeps one pyramid per intensity level, so it gets a quarter of the
%   band budget (``bandDivisor``).
%
% With *useRGB* the three channels are processed together, as on a Standard
% dataset; otherwise each channel on its own, with a guide of its own.
filterName = BatchOpt.FilterName{1};
levelSize = dataset.image.pyramid.levelImageSizes(level, :);
plan = struct('filterName', filterName, 'haloYX', 0, 'bandDivisor', 1, 'levelSize', levelSize, ...
    'guideLevel', [], 'ratio', [1 1], 'sampleLimits', false);
plan.useRGB = isfield(BatchOpt, 'useRGB') && BatchOpt.useRGB;
if plan.useRGB && numel(channels) ~= 3
    error('controllers:ImageFilters:bigDataRGB', ['The "%s" filter with useRGB needs the 3 color channels ' ...
        'of an RGB image; %d are selected.'], filterName, numel(channels));
end
switch filterName
    case 'ElasticDistortion'
        if BatchOpt.DistortAllLAyers && (dataset.modelExist || dataset.maskExist)
            error('controllers:ImageFilters:bigDataLayers', ['On BigData datasets only the image is distorted; ' ...
                'please untick "DistortAllLAyers" to distort the image without its model and mask.']);
        end
        plan.sigma = BatchOpt.Sigma{1};
        plan.kernelSize = 2 * ceil(2 * plan.sigma) + 1;     % the imgaussfilt default, as utils.elasticDistortionFilter
        plan.scaling = BatchOpt.ScalingFactor{1};
        plan.haloYX = ceil(plan.scaling) + 1 + (plan.kernelSize - 1) / 2;
        return;
    case 'BMxD'
        if exist('BM3DProfile', 'file') ~= 2
            error('controllers:ImageFilters:bigDataBM3D', 'BM3D 4.x is not on the MATLAB path.');
        end
        profile = BM3DProfile(BatchOpt.Profile{1});
        plan.haloYX = 2 * profile.N1 + floor(profile.Ns / 2) + 2 * profile.N1_wiener + floor(profile.Ns_wiener / 2);
        plan.gridStep = lcm(profile.Nstep, profile.Nstep_wiener);
        return;
end

% the guide: the same slice at a level that fits the budget
plan.guideLevel = localGuideLevel(dataset.image, level, obj.bigDataOptions.GuidePixels);
guideSize = dataset.image.pyramid.levelImageSizes(plan.guideLevel, :);
plan.ratio = guideSize(1:2) ./ levelSize(1:2);
plan.guideDepth = guideSize(3);
plan.guideReader = io.savers.FilteredSliceProvider(dataset.image, plan.guideLevel, channels, @(block) block);
[~, plan.runKey] = fileparts(tempname);     % a guide cached by an earlier run is never reused
plan.unitIsRGB = plan.useRGB;
switch filterName
    case 'FlatfieldCorrection'
        plan.sigma = str2num(BatchOpt.Sigma); %#ok<ST2NM> as doImageFiltering reads them
        halfSize = str2num(BatchOpt.FilterHalfSize); %#ok<ST2NM>
        if isempty(halfSize)
            plan.filterSize = 2 * ceil(2 * plan.sigma) + 1;
        else
            plan.filterSize = 2 * halfSize + 1;
        end
        shadingHalo = max((plan.filterSize - 1) / 2);
        plan.shadingFromGuide = shadingHalo > 256 && any(plan.ratio < 1);
        if ~plan.shadingFromGuide; plan.haloYX = shadingHalo; end
        plan.sampleLimits = any(plan.ratio < 1);
    case 'LocalBrighten'
        plan.amount = BatchOpt.Amount{1};
        plan.alphaBlend = BatchOpt.AlphaBlend;
        plan.haloYX = 5;
    case 'ReduceHaze'
        plan.amount = BatchOpt.Amount{1};
        plan.method = BatchOpt.Method{1};
        plan.contrast = BatchOpt.ContrastEnhancement{1};
        plan.atmosphericLight = str2num(BatchOpt.AtmosphericLight); %#ok<ST2NM>
        if ~isempty(plan.atmosphericLight)
            if plan.useRGB
                if isscalar(plan.atmosphericLight); plan.atmosphericLight = repmat(plan.atmosphericLight, 1, 3); end
            else
                plan.atmosphericLight = plan.atmosphericLight(1);
            end
        end
        if strcmp(plan.method, 'approxdcp') && any(plan.ratio < 1)
            error('controllers:ImageFilters:bigDataApproxdcp', ['ReduceHaze with the "approxdcp" method sizes its ' ...
                'filters to the whole image, so on BigData it is available only for slices of at most %.0f Mpx; ' ...
                'this level has %.0f Mpx per slice. Please select "simpledcp" or a coarser level.'], ...
                obj.bigDataOptions.GuidePixels / 1e6, prod(levelSize(1:2)) / 1e6);
        end
        if strcmp(plan.method, 'simpledcp'); plan.haloYX = 5; end
        plan.sampleLimits = plan.amount > 0 && strcmp(plan.contrast, 'global') && any(plan.ratio < 1);
    case {'LocalContrast', 'FastLocalLaplacian'}
        if strcmp(filterName, 'LocalContrast')
            % localcontrast calls locallapfilt with these parameters
            plan.sigma = single(BatchOpt.EdgeThreshold{1});
            amount = BatchOpt.Amount{1};
            plan.beta = single(1);
            if amount > 0
                plan.alpha = single(1 - 0.99 * amount);
                colorMode = 'luminance';
            else
                plan.alpha = single(1 - 99 * amount);
                colorMode = 'separate';
            end
            plan.identity = plan.sigma == 0 || amount == 0;
            intensityLevels = NaN;
        else
            plan.sigma = single(BatchOpt.EdgeAmplitude{1});
            plan.alpha = single(BatchOpt.Smoothing{1});
            plan.beta = single(BatchOpt.DynamicRange{1});
            colorMode = BatchOpt.ColorMode{1};
            plan.identity = false;
            intensityLevels = str2double(BatchOpt.NumIntensityLevels);
        end
        plan.identity = plan.identity || (plan.alpha == 1 && plan.beta == 1) || (plan.sigma == 0 && plan.beta == 1);
        if isnan(intensityLevels)       % 'auto', as locallapfilt sets it
            if plan.alpha < 0.1
                intensityLevels = 50;
            elseif plan.alpha < 0.9
                intensityLevels = round(((50 * 0.9 - 16 * 0.1) - (50 - 16) * plan.alpha) / (0.9 - 0.1));
            else
                intensityLevels = 16;
            end
        end
        plan.intensityLevels = double(intensityLevels);
        plan.unitIsRGB = plan.useRGB && strcmp(colorMode, 'luminance');
        plan.guideOctaves = max(0, ceil(log2(1 / min(plan.ratio)) - 1e-9));   % levels the guide is coarser by
        plan.numLevels = 2 + plan.guideOctaves;
        plan.haloYX = 2^(plan.numLevels + 1);
        plan.bandDivisor = 4;
        plan.sampleLimits = ~plan.identity && any(plan.ratio < 1);
end
end

% ---------------------------------------------------------------------------
function limits = localSampledLimits(obj, image, level, channels, plan)
% LOCALSAMPLEDLIMITS - Per slice and unit, the limits a coarser level narrows, from a statistics pass of the processed level.
%
% A pyramid level averages its pixels, so its minimum and maximum lie inside
% those of the full level, and so do its percentiles and the mean of a channel
% maximum. Three filters depend on them:
%
% - *LocalContrast*, *FastLocalLaplacian*: ``locallapfilt`` samples the
%   intensities between the minimum and the maximum of the slice; taken from a
%   level of half the size, the shifted samples alone changed the result of a
%   micrograph by 4.5 grey levels on average, against 1 for all the rest.
%   ``range`` is ``[min max]`` of the luminance (RGB) or the channel.
% - *ReduceHaze* with *ContrastEnhancement* *global*: ``imreducehaze``
%   stretches ``deHazed.^0.75`` by its minimum and maximum (``mat2gray``), then
%   by the 0.1% and 99.9% limits of ``stretchlim`` (65536 bins for a floating
%   image) of the result, per plane. ``range`` and ``clipLimit`` are derived here
%   as ``imreducehaze`` derives them, from the dehazed stripes (halo 5).
% - *FlatfieldCorrection*: ``imflatfield`` divides by the mean of V
%   (``max(R, G, B)`` for RGB, the channel otherwise); the V of averaged pixels
%   is below the average of their V, so the mean comes from the level.
%   ``meanValue`` only.
%
% The values of every stripe go to a histogram of 2^18 bins over [0, 1]
% (``utils.bigdata.sampleStripes``), so a limit is within 4e-6 of the value
% on the rows read; when the level fits the sampling budget every row is
% read. The pass computes its own guides (another cache key), as the run's
% guides take these limits.
%
% Output Arguments:
%   - **limits** - {1 x depth} cell of {1 x units} structs with ``range`` and,
%     for ReduceHaze, ``clipLimit``; ``[]`` when cancelled
binCount = 2^18;
progressParent = [];
if ~isempty(obj.view) && isvalid(obj.view.gui); progressParent = obj.view.gui; end
limits = [];
if strcmp(plan.filterName, 'FlatfieldCorrection')
    % the mean of V = max(R, G, B) (or of the channel): the V of averaged
    % pixels is below the average of their V, so a coarser level biases it low
    sums = utils.bigdata.sampleStripes(image, level, ...
        @(value) [sum(sum(value, 1), 2, 'double'); repmat(size(value, 1) * size(value, 2), 1, 1, size(value, 3))], ...
        ColChannel = channels, BlockFunction = @(block) localFlatfieldValue(block, plan), ...
        ParentFigure = progressParent, Title = 'Collecting the mean intensity');
    if isempty(sums); return; end
    limits = cell(1, numel(sums));
    for z = 1:numel(sums)
        means = sums{z}(1, 1, :) ./ sums{z}(2, 1, :);
        limits{z} = arrayfun(@(meanValue) struct('meanValue', single(meanValue)), means(:)', 'UniformOutput', false);
    end
    return;
end
if strcmp(plan.filterName, 'ReduceHaze')
    passPlan = plan;
    passPlan.runKey = [plan.runKey '/statistics'];
    blockFunction = @(block, z) localDehazedPlanes(block, z, passPlan);
    haloYX = plan.haloYX;
else
    blockFunction = @(block) localUnitPlanes(block, plan);
    haloYX = 0;
end
sums = utils.bigdata.sampleStripes(image, level, @(values) localFineHistogram(values, binCount), ...
    ColChannel = channels, BlockFunction = blockFunction, HaloYX = haloYX, ...
    ParentFigure = progressParent, Title = 'Collecting the intensity range');
localGuideCache('');
if isempty(sums); return; end
binValues = (0:binCount - 1)' / (binCount - 1);
if plan.unitIsRGB
    unitPlanes = {1:size(sums{1}, 2)};
else
    unitPlanes = num2cell(1:size(sums{1}, 2));
end
limits = cell(1, numel(sums));
for z = 1:numel(sums)
    limits{z} = cell(1, numel(unitPlanes));
    for unitIndex = 1:numel(unitPlanes)
        counts = sums{z}(:, unitPlanes{unitIndex});
        occupied = find(any(counts > 0, 2));
        unitLimits = struct('range', binValues([occupied(1), occupied(end)])');
        if strcmp(plan.filterName, 'ReduceHaze')
            % stretchlim of mat2gray(values): 65536 bins of the normalized values
            lowHigh = repmat([0; 1], 1, size(counts, 2));
            if diff(unitLimits.range) > 0
                normalizedBins = round((binValues - unitLimits.range(1)) / diff(unitLimits.range) * 65535) + 1;
                normalizedBins = min(65536, max(1, normalizedBins));
                for planeIndex = 1:size(counts, 2)
                    cdf = cumsum(accumarray(normalizedBins, counts(:, planeIndex), [65536 1]));
                    cdf = cdf / cdf(end);
                    binLow = find(cdf > 0.001, 1, 'first');
                    binHigh = find(cdf >= 0.999, 1, 'first');
                    if binLow == binHigh; binLow = 1; binHigh = 65536; end
                    lowHigh(:, planeIndex) = ([binLow; binHigh] - 1) / 65535;
                end
            end
            unitLimits.clipLimit = lowHigh + 0.8 * (max(lowHigh, mean(lowHigh, 2)) - lowHigh);
        end
        limits{z}{unitIndex} = unitLimits;
    end
end
end

% ---------------------------------------------------------------------------
function value = localFlatfieldValue(block, plan)
% LOCALFLATFIELDVALUE - What imflatfield corrects: the V of rgb2hsv for an RGB unit, each channel otherwise, single [rows width planes].
value = im2single(block);
if plan.unitIsRGB; value = max(value, [], 3); end
end

% ---------------------------------------------------------------------------
function planes = localUnitPlanes(block, plan)
% LOCALUNITPLANES - The values the intensity range is taken from: the luminance of an RGB unit, or each channel, single [rows width planes].
image = im2single(block);
if plan.unitIsRGB
    planes = localLuminance(image);
else
    planes = image;
end
end

% ---------------------------------------------------------------------------
function planes = localDehazedPlanes(block, z, plan)
% LOCALDEHAZEDPLANES - ``deHazed.^0.75`` of every unit of a band (simpledcp, the atmospheric light of slice ``z``), single [rows width planes].
guide = localGuide(plan, z);
image = im2single(block);
planes = zeros(size(image), 'single');
if plan.unitIsRGB
    planes(:) = imreducehaze(image, plan.amount, 'method', 'simpledcp', ...
        'AtmosphericLight', guide{1}.atmosphericLight, 'ContrastEnhancement', 'none').^0.75;
    return;
end
for channelIndex = 1:size(image, 3)
    planes(:, :, channelIndex) = imreducehaze(image(:, :, channelIndex), plan.amount, 'method', 'simpledcp', ...
        'AtmosphericLight', guide{channelIndex}.atmosphericLight, 'ContrastEnhancement', 'none').^0.75;
end
end

% ---------------------------------------------------------------------------
function counts = localFineHistogram(values, binCount)
% LOCALFINEHISTOGRAM - Counts of the values of every plane in ``binCount`` bins over [0, 1], [binCount planes] double.
planeCount = size(values, 3);
counts = zeros(binCount, planeCount);
for planeIndex = 1:planeCount
    plane = values(:, :, planeIndex);
    bins = min(binCount, max(1, round(double(plane(:)) * (binCount - 1)) + 1));
    counts(:, planeIndex) = accumarray(bins, 1, [binCount 1]);
end
end

% ---------------------------------------------------------------------------
function guideLevel = localGuideLevel(image, level, guidePixels)
% LOCALGUIDELEVEL - The finest pyramid level from ``level`` down with at most ``guidePixels`` pixels per slice.
%
% A pyramid that stops above the budget gives its coarsest level, up to four
% times the budget; beyond that the whole-slice part would not fit in memory.
sizes = image.pyramid.levelImageSizes;
pixels = sizes(:, 1) .* sizes(:, 2);
levels = (1:size(sizes, 1))';
guideLevel = find(levels >= level & pixels <= guidePixels, 1);
if isempty(guideLevel)
    guideLevel = size(sizes, 1);
    if pixels(guideLevel) > 4 * guidePixels
        error('controllers:ImageFilters:bigDataGuide', ['This filter depends on the whole image, so it takes that ' ...
            'part from a coarser pyramid level, but the coarsest level of this image has %.0f Mpx per slice ' ...
            '(at most %.0f Mpx are used). Please save the image with more pyramid levels.'], ...
            pixels(guideLevel) / 1e6, 4 * guidePixels / 1e6);
    end
end
end

% ---------------------------------------------------------------------------
function value = localGuideCache(key, value)
% LOCALGUIDECACHE - The guide of the last slice processed: ``value = localGuideCache(key)`` ([] when not cached), ``localGuideCache(key, value)`` stores it, ``localGuideCache('')`` frees it.
persistent cachedKey cachedValue
if nargin == 2
    cachedKey = key;
    cachedValue = value;
    return;
end
if isempty(key)
    cachedKey = '';
    cachedValue = [];
    value = [];
elseif strcmp(cachedKey, key)
    value = cachedValue;
else
    value = [];
end
end

% ---------------------------------------------------------------------------
function localReleaseGuide(BatchOpt)
% LOCALRELEASEGUIDE - Free the cached guide on the client and, after a parallel run, on every worker of the pool.
%
% With ``UseParallelComputing`` every worker computes and caches the guide of
% the slices of its bands (``localGuide`` runs where the band is computed), up
% to ``GuidePixels`` per channel and the quantities derived from it; left there,
% it would hold that memory on each worker until the next positioned run.
localGuideCache('');
if isfield(BatchOpt, 'UseParallelComputing') && BatchOpt.UseParallelComputing
    pool = gcp('nocreate');
    if ~isempty(pool); parfevalOnAll(pool, @localGuideCache, 0, ''); end
end
end

% ---------------------------------------------------------------------------
function guide = localGuide(plan, z)
% LOCALGUIDE - The global part of level slice ``z``, one struct per unit (the RGB triplet or each channel), computed once per slice.
key = sprintf('%s/%d', plan.runKey, z);
guide = localGuideCache(key);
if ~isempty(guide); return; end
levelDepth = plan.levelSize(3);
guideSlice = min(plan.guideDepth, max(1, round((z - 0.5) * plan.guideDepth / levelDepth + 0.5)));
guideImage = im2single(plan.guideReader.getSlice(guideSlice));
if plan.unitIsRGB
    units = {guideImage};
else
    units = num2cell(guideImage, [1 2]);
end
guide = cell(1, numel(units));
for unitIndex = 1:numel(units)
    unitLimits = [];        % from the statistics pass of the level, when the guide is coarser
    if isfield(plan, 'limits'); unitLimits = plan.limits{z}{unitIndex}; end
    guide{unitIndex} = localGuideUnit(plan, units{unitIndex}, unitLimits);
end
localGuideCache(key, guide);
end

% ---------------------------------------------------------------------------
function unitGuide = localGuideUnit(plan, image, unitLimits)
% LOCALGUIDEUNIT - The whole-slice quantities of one unit of the guide, see localPositionedPlan.
%
% ``unitLimits`` (``localSampledLimits``, ``[]`` when the guide is the level
% itself) replaces the intensity range and the stretching limits, which a
% coarser level narrows.
unitGuide = struct();
switch plan.filterName
    case 'FlatfieldCorrection'
        value = max(image, [], 3);      % the V of rgb2hsv for RGB, as imflatfield uses it
        if isempty(unitLimits)
            unitGuide.meanValue = mean(value(:), 'omitnan');
        else
            unitGuide.meanValue = unitLimits.meanValue;
        end
        if plan.shadingFromGuide
            unitGuide.shading = imgaussfilt(value, plan.sigma .* plan.ratio, 'Padding', 'symmetric', ...
                'FilterSize', 2 * ceil((plan.filterSize - 1) / 2 .* plan.ratio) + 1);
        end
    case 'LocalBrighten'
        if plan.amount > 0
            [~, ~, unitGuide.atmosphericLight] = imreducehaze(1 - image, plan.amount, 'ContrastEnhancement', 'none');
        end
    case 'ReduceHaze'
        if plan.amount == 0; return; end
        unitGuide.atmosphericLight = plan.atmosphericLight;
        if isempty(unitGuide.atmosphericLight)
            [~, ~, unitGuide.atmosphericLight] = imreducehaze(image, plan.amount, 'method', plan.method, ...
                'ContrastEnhancement', 'none');
        end
        if ~isempty(unitLimits)
            unitGuide.range = unitLimits.range;
            unitGuide.clipLimit = unitLimits.clipLimit;
        end
        if strcmp(plan.method, 'approxdcp') || (strcmp(plan.contrast, 'global') && isempty(unitLimits))
            [deHazed, haze] = imreducehaze(image, plan.amount, 'method', plan.method, ...
                'AtmosphericLight', unitGuide.atmosphericLight, 'ContrastEnhancement', 'none');
            if strcmp(plan.method, 'approxdcp'); unitGuide.haze = single(haze); end
            if strcmp(plan.contrast, 'global') && isempty(unitLimits)
                % the limits of imreducehaze's global stretching, from the whole slice
                stretched = deHazed.^0.75;
                unitGuide.range = double([min(stretched(:)), max(stretched(:))]);
                clipLimit = stretchlim(mat2gray(stretched, unitGuide.range), [0.001, 0.999]);
                unitGuide.clipLimit = clipLimit + 0.8 * (max(clipLimit, mean(clipLimit, 2)) - clipLimit);
            end
        end
    case {'LocalContrast', 'FastLocalLaplacian'}
        if plan.identity; return; end
        gray = localLuminance(image);
        if isempty(unitLimits)
            minValue = min(gray(:));
            maxValue = max(gray(:));
        else
            minValue = single(unitLimits.range(1));
            maxValue = single(unitLimits.range(2));
        end
        unitGuide.flat = minValue == maxValue;
        unitGuide.middle = (minValue + maxValue) / 2;
        if unitGuide.flat || plan.intensityLevels == 1; return; end
        unitGuide.origin = minValue;
        unitGuide.step = (maxValue - minValue) / single(plan.intensityLevels - 1);
        allLevels = floor(log2(min(size(gray, 1:2)))) + 1;
        bandLevels = min(allLevels, plan.numLevels - plan.guideOctaves);
        unitGuide.coarse = localLaplacianFilter(gray, plan, unitGuide.origin, unitGuide.step, allLevels) - ...
            localLaplacianFilter(gray, plan, unitGuide.origin, unitGuide.step, bandLevels);
end
end

% ---------------------------------------------------------------------------
function out = localPositionedBlock(block, z, firstRow, plan, filterOptions, channels)
% LOCALPOSITIONEDBLOCK - Filter one band ``[rows width colors]`` of level slice ``z`` that starts at level row ``firstRow``, see localPositionedPlan.
[rows, width, ~] = size(block);
data = block(:, :, channels);
switch plan.filterName
    case 'ElasticDistortion'
        filtered = localElasticBand(data, z, firstRow, plan);
    case 'BMxD'
        pad = mod(firstRow - 1, plan.gridStep);      % the block grid of the whole slice
        padded = padarray(data, [pad 0], 'symmetric', 'pre');
        [filtered, ~] = utils.doImageFiltering(reshape(padded, rows + pad, width, 1, numel(channels)), filterOptions);
        filtered = reshape(filtered(pad + 1:end, :, :, :), rows, width, numel(channels));
    otherwise
        guide = localGuide(plan, z);
        bandRows = (firstRow:firstRow + rows - 1)';
        input = im2single(data);
        % each unit goes to the class of the image from the class its function
        % returns, as on a Standard dataset
        if plan.unitIsRGB
            filtered = localToClass(localPositionedUnit(input, guide{1}, bandRows, plan), class(block));
        else
            filtered = zeros(size(data), 'like', data);
            for channelIndex = 1:numel(channels)
                filtered(:, :, channelIndex) = localToClass(localPositionedUnit(input(:, :, channelIndex), ...
                    guide{channelIndex}, bandRows, plan), class(block));
            end
        end
end
out = block;
switch filterOptions.ActionToResult{1}
    case 'Filter and add'
        out(:, :, channels) = data + filtered;
    case 'Filter and subtract'
        out(:, :, channels) = data - filtered;
    otherwise
        out(:, :, channels) = filtered;
end
end

% ---------------------------------------------------------------------------
function result = localPositionedUnit(image, unitGuide, bandRows, plan)
% LOCALPOSITIONEDUNIT - One unit (the RGB triplet or a channel, single in [0, 1]) of a band, from its guide.
width = size(image, 2);
switch plan.filterName
    case 'FlatfieldCorrection'
        if size(image, 3) == 3
            hsv = rgb2hsv(image);
            value = hsv(:, :, 3);
        else
            value = image;
        end
        if plan.shadingFromGuide
            shading = localInterpolateGuide(unitGuide.shading, bandRows, width, plan.ratio);
        else
            shading = imgaussfilt(value, plan.sigma, 'Padding', 'symmetric', 'FilterSize', plan.filterSize);
        end
        corrected = value * unitGuide.meanValue ./ shading;
        corrected(isnan(corrected) | isinf(corrected)) = 0;
        if size(image, 3) == 3
            hsv(:, :, 3) = corrected;
            result = hsv2rgb(hsv);
        else
            result = corrected;
        end
    case 'LocalBrighten'
        if plan.amount == 0; result = image; return; end
        [inverted, haze] = imreducehaze(1 - image, plan.amount, 'ContrastEnhancement', 'none', ...
            'AtmosphericLight', unitGuide.atmosphericLight);
        result = 1 - inverted;
        if plan.alphaBlend; result = image .* (1 - haze) + result .* haze; end
    case 'ReduceHaze'
        if plan.amount == 0; result = image; return; end
        contrast = plan.contrast;
        if strcmp(contrast, 'global'); contrast = 'none'; end
        if strcmp(plan.method, 'simpledcp')
            result = imreducehaze(image, plan.amount, 'method', 'simpledcp', ...
                'AtmosphericLight', unitGuide.atmosphericLight, 'ContrastEnhancement', contrast);
        else
            % approxdcp from the haze map of the guide, as imreducehaze continues
            haze = localInterpolateGuide(unitGuide.haze, bandRows, width, plan.ratio);
            atmosphericLight = reshape(unitGuide.atmosphericLight, 1, 1, []);
            transmission = 1 - 0.95 * haze;
            radiance = min(1, max(0, atmosphericLight + (image - atmosphericLight) ./ max(transmission, 0.1)));
            newTransmission = min(1, transmission + plan.amount);
            result = radiance .* newTransmission + atmosphericLight .* (1 - newTransmission);
            if strcmp(contrast, 'boost'); result = result .* (1 + plan.amount * 0.1 * haze); end
        end
        if strcmp(plan.contrast, 'global')
            result = single(imadjust(mat2gray(result.^0.75, unitGuide.range), unitGuide.clipLimit));
        end
    case {'LocalContrast', 'FastLocalLaplacian'}
        if plan.identity || unitGuide.flat; result = image; return; end
        [gray, ratios] = localLuminance(image);
        if plan.intensityLevels == 1
            filtered = images.internal.builtins.llf.remap(gray, unitGuide.middle, plan.sigma, plan.alpha, plan.beta);
        else
            pad = mod(bandRows(1) - 1, 2^(plan.numLevels - 1));   % the grid of the coarsest band level
            padded = padarray(gray, [pad 0], 'symmetric', 'pre');
            numLevels = min(plan.numLevels, floor(log2(min(size(padded, 1:2)))) + 1);
            filtered = localLaplacianFilter(padded, plan, unitGuide.origin, unitGuide.step, numLevels);
            filtered = filtered(pad + 1:end, :) + localInterpolateGuide(unitGuide.coarse, bandRows, width, plan.ratio);
        end
        result = filtered .* ratios;
end
end

% ---------------------------------------------------------------------------
function [gray, ratios] = localLuminance(image)
% LOCALLUMINANCE - The luminance of an RGB triplet and the ratios that restore its colors, as locallapfilt; a channel is returned as is (ratios 1).
if size(image, 3) ~= 3
    gray = image;
    ratios = ones(1, 'like', image);
    return;
end
gray = single(0.298936021293776) * image(:, :, 1) + single(0.587043074451121) * image(:, :, 2) + ...
    single(0.114020904255103) * image(:, :, 3);
ratios = image ./ (gray + eps('single'));
end

% ---------------------------------------------------------------------------
function output = localLaplacianFilter(input, plan, origin, step, numLevels)
% LOCALLAPLACIANFILTER - Fast local Laplacian filter with ``numLevels`` levels and intensity samples ``origin + k*step``.
%
% The algorithm of ``locallapfilt`` (Aubry et al., 2014), built on its
% builtins: for each intensity sample the image is remapped around it, the
% Laplacian pyramid of the remapped image is formed, and each level of the
% output takes, at every pixel, the coefficients of the two samples nearest to
% the input's Gaussian pyramid there. ``locallapfilt`` samples from the
% minimum to the maximum of its input in its own number of levels; here the
% samples are fixed by the caller, extended over the range of ``input``, so
% bands of one slice share them. With the samples and levels of
% ``locallapfilt`` the result is equal to its one before the clipping to the
% class.
samples = floor((min(input(:)) - origin) / step):ceil((max(input(:)) - origin) / step - 1e-4);
inputPyramid = cell(numLevels, 1);
inputPyramid{1} = input;
for levelIndex = 2:numLevels
    inputPyramid{levelIndex} = images.internal.builtins.llf.pyrdownsample(inputPyramid{levelIndex - 1});
end
outputPyramid = cell(numLevels, 1);
outputPyramid{numLevels} = inputPyramid{numLevels};
for levelIndex = 1:numLevels - 1
    outputPyramid{levelIndex} = zeros(size(inputPyramid{levelIndex}), 'like', input);
end
remappedPyramid = cell(numLevels, 1);
for sample = samples
    referenceValue = origin + single(sample) * step;
    remappedPyramid{1} = images.internal.builtins.llf.remap(input, referenceValue, plan.sigma, plan.alpha, plan.beta);
    for levelIndex = 2:numLevels
        remappedPyramid{levelIndex} = images.internal.builtins.llf.pyrdownsample(remappedPyramid{levelIndex - 1});
    end
    for levelIndex = numLevels - 1:-1:1
        outputPyramid{levelIndex} = images.internal.builtins.llf.upSampleSubAddContribution(outputPyramid{levelIndex}, ...
            inputPyramid{levelIndex}, remappedPyramid{levelIndex}, remappedPyramid{levelIndex + 1}, referenceValue, step);
    end
end
for levelIndex = numLevels - 1:-1:1
    outputPyramid{levelIndex} = outputPyramid{levelIndex} + images.internal.builtins.llf.pyrupsample( ...
        outputPyramid{levelIndex + 1}, size(outputPyramid{levelIndex}, 1), size(outputPyramid{levelIndex}, 2));
end
output = outputPyramid{1};
end

% ---------------------------------------------------------------------------
function values = localInterpolateGuide(map, bandRows, width, ratio)
% LOCALINTERPOLATEGUIDE - A guide map at the rows ``bandRows`` and all columns of the level, linear between guide pixel centres.
if isequal(ratio, [1 1])
    values = map(bandRows, 1:width);      % 1:width: a probe of the run time passes a part of the columns
    return;
end
rowsAt = (bandRows - 0.5) * ratio(1) + 0.5;     % level pixel centres in guide pixels
columnsAt = ((1:width)' - 0.5) * ratio(2) + 0.5;
map = double(map);
if size(map, 1) == 1; map = [map; map]; end     % griddedInterpolant needs two samples per axis
if size(map, 2) == 1; map = [map, map]; end
interpolant = griddedInterpolant({1:size(map, 1), 1:size(map, 2)}, map, 'linear', 'nearest');
values = single(interpolant({rowsAt, columnsAt}));
end

% ---------------------------------------------------------------------------
function distorted = localElasticBand(data, z, firstRow, plan)
% LOCALELASTICBAND - Elastic distortion of a band, its random field generated row by row.
%
% As ``utils.elasticDistortionFilter``: uniform [-1, 1] displacements in X and
% Y, smoothed by a Gaussian of *Sigma* and scaled by *ScalingFactor*, one field
% for all channels of a slice. Each row of the field
% comes from its own substream of one random stream, so a row is the same
% whichever band generates it, and every slice gets its own field. The image is
% sampled at the displaced positions (linear), clamped to the band, as
% ``utils.elasticDistortionFilter`` clamps them to the image: the halo holds
% every position a kept row reaches, so the clamp acts only where the band ends
% at the image edge, whose pixels then repeat.
[rows, width, colors] = size(data);
stream = RandStream('threefry4x64_20', 'Seed', 0);
noise = zeros(rows, 2 * width);
for row = 1:rows
    stream.Substream = (z - 1) * plan.levelSize(1) + firstRow + row - 1;
    noise(row, :) = rand(stream, 1, 2 * width);
end
shiftX = plan.scaling * imgaussfilt(2 * noise(:, 1:width) - 1, plan.sigma, 'FilterSize', plan.kernelSize);
shiftY = plan.scaling * imgaussfilt(2 * noise(:, width + 1:end) - 1, plan.sigma, 'FilterSize', plan.kernelSize);
[gridY, gridX] = ndgrid(1:rows, 1:width);
sampleX = min(max(gridX + shiftX, 1), width);
sampleY = min(max(gridY + shiftY, 1), rows);
distorted = zeros(rows, width, colors, 'like', data);
for color = 1:colors
    distorted(:, :, color) = interp2(double(data(:, :, color)), sampleX, sampleY, 'linear');
end
end

% ---------------------------------------------------------------------------
function converted = localToClass(image, className)
% LOCALTOCLASS - A [0, 1] floating result in the class of the image, saturated as the image functions return it.
switch className
    case 'uint8'
        converted = im2uint8(image);
    case 'uint16'
        converted = im2uint16(image);
    case 'int16'
        converted = im2int16(image);
    case 'double'
        converted = double(image);
    otherwise
        converted = single(image);
end
end

% ---------------------------------------------------------------------------
function localReportError(obj, parentFigure, message)
% LOCALREPORTERROR - Show the error in a dialog, or raise it when headless.
controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, 'controllers:ImageFilters:bigData', ...
    message, 'BigData filtering');
end

% ---------------------------------------------------------------------------
function edges = localEdgeBlock(block, filterOptions)
% LOCALEDGEBLOCK - Edge detection of one band ``[rows width]`` of a single channel.
% Two outputs from doImageFiltering: its log text is built only then, and later
% steps append to it.
[edges, ~] = utils.doImageFiltering(reshape(block, size(block, 1), size(block, 2), 1, 1), filterOptions);
edges = reshape(edges, size(block, 1), size(block, 2));
end
