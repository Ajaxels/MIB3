function calculate(obj)
% CALCULATE - Analyse the chosen regions of the current slice and append the results to the table.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.calculate()
%
% Reads the regions with :func:`controllers.ImageSharpness.getRegions`, runs
% :func:`controllers.ImageSharpness.analyseRegion` on each and appends one
% element per region to ``obj.results``. When ``Drawn rectangle`` is chosen
% and no rectangle exists yet, only the drawing starts:
% :func:`controllers.ImageSharpness.drawRectangle` calls ``calculate`` again
% once the rectangle is confirmed.
%
% Pixel sizes are taken from ``I{id}.image.pixSize`` for the shown
% orientation (XY: ``[x y]``; ZX, rows = Z: ``[x z]``; ZY, columns = Z:
% ``[z y]``). Lengths in m, mm, um or nm are converted to nm so rows of
% datasets with different units compare directly; any other unit is kept
% as it is, with scale 1.
%
% Regions with a side below 64 pixels, and regions above 8192 x 8192
% pixels (memory of the Fourier transforms), are skipped and listed in a
% warning. The same warning reports new rows whose FFT result has
% ``correlatedNoise`` set while ``SlowDetector`` is off, and asks to tick
% it (see :func:`controllers.ImageSharpness.computeFftResolution`), and
% new rows whose FFT result has ``denoised`` set (see
% :func:`controllers.ImageSharpness.analyseRegion`). The
% progress dialog can be cancelled before every region; on cancel no rows
% are added.
%
% Each element of ``obj.results`` has the fields:
%
%   - ``.datasetName`` - [char] file name of the dataset
%   - ``.regionSource`` - [char] the Region setting used, e.g. ``ROIs``
%   - ``.regionName`` - [char] see getRegions
%   - ``.position`` - [double] ``[x1 y1 x2 y2]`` or ``[]``
%   - ``.sliceNumber``, ``.timePoint``, ``.orientation``, ``.colorChannel`` - [double]
%   - ``.regionSize`` - [double] ``[height width]`` in pixels
%   - ``.pixelSize`` - [double] ``[x y]`` in ``.units``
%   - ``.units`` - [char] length unit of every value of the row
%   - ``.analysis`` - [struct] output of analyseRegion, lengths in ``.units``
%   - ``.options`` - [struct] the analysis options used
%   - ``.thumbnail`` - [uint8, 2D] the region for display in the Image tab,
%     with the display range and gamma of the channel in the image view
%     (``I{id}.image.viewPort``), so it looks as in MIB at the time of the
%     calculation; reduced to at most 512 pixels on the longer side; not
%     used for any measurement
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ImageSharpness.calculate: triggered\n');
end

obj.BatchOpt.id = obj.mibModel.getActiveId();
id = obj.BatchOpt.id;
dataset = obj.mibModel.I{id};

if ~obj.BatchOpt.UseFft && ~obj.BatchOpt.UseDecorrelation && ~obj.BatchOpt.UseSharpness
    utils.dlgs.showErrorDialog(obj.view.gui, 'Select at least one method.', 'Sharpness and noise');
    return;
end
if strcmp(obj.BatchOpt.RegionSource{1}, 'Drawn rectangle') && isempty(obj.drawnRectangle)
    obj.drawRectangle();    % analyses the rectangle itself once it is confirmed
    return;
end

progressDialog = uiprogressdlg(obj.view.gui, 'Message', 'Reading image...', ...
    'Title', 'Sharpness and noise', 'Cancelable', 'on');
try
    regions = obj.getRegions();
catch err
    delete(progressDialog);
    if strcmp(err.identifier, 'MIB:ImageSharpness:NoRegions')
        uialert(obj.view.gui, sprintf(err.message), 'Sharpness and noise', 'Icon', 'info');
    else
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Sharpness and noise');
    end
    return;
end

% pixel size of the shown orientation, converted to nm when possible
pixSize = dataset.image.pixSize;
switch dataset.orientation
    case 1      % zx: rows = z, columns = x
        pixelSize = [pixSize.x pixSize.z];
    case 2      % zy: rows = y, columns = z
        pixelSize = [pixSize.z pixSize.y];
    otherwise
        pixelSize = [pixSize.x pixSize.y];
end
switch lower(strtrim(pixSize.units))
    case 'm';                               unitScale = 1e9;
    case 'mm';                              unitScale = 1e6;
    case {'um', [char(181) 'm'], [char(956) 'm'], 'micron', 'microns'}; unitScale = 1e3;
    case 'nm';                              unitScale = 1;
    otherwise;                              unitScale = [];
end
if isempty(unitScale)
    units = pixSize.units;
    unitScale = 1;
else
    units = 'nm';
end
pixelSize = pixelSize * unitScale;

analysisOptions = struct('UseFft', obj.BatchOpt.UseFft, ...
    'UseDecorrelation', obj.BatchOpt.UseDecorrelation, ...
    'UseSharpness', obj.BatchOpt.UseSharpness, ...
    'SnrThreshold', obj.BatchOpt.SnrThreshold{1}, ...
    'NumberOfSectors', obj.BatchOpt.NumberOfSectors{1}, ...
    'SuppressScanLines', obj.BatchOpt.SuppressScanLines, ...
    'SlowDetector', obj.BatchOpt.SlowDetector, ...
    'SmoothingSigma', obj.BatchOpt.SmoothingSigma{1});

[~, datasetName, extension] = fileparts(dataset.image.filename);
rowTemplate = struct('datasetName', [datasetName extension], ...
    'regionSource', obj.BatchOpt.RegionSource{1}, 'regionName', '', 'position', [], ...
    'sliceNumber', dataset.getCurrentSliceNumber(), ...
    'timePoint', dataset.getCurrentTimePoint(), ...
    'orientation', dataset.orientation, ...
    'colorChannel', str2double(erase(obj.BatchOpt.ColorChannel{1}, 'Ch ')), ...
    'regionSize', [], 'pixelSize', pixelSize, 'units', units, ...
    'analysis', [], 'options', analysisOptions, 'thumbnail', []);

% display settings of the analysed channel, for the thumbnails
viewPort = dataset.image.viewPort;
displayRange = double([viewPort.min(rowTemplate.colorChannel), viewPort.max(rowTemplate.colorChannel)]);
displayGamma = viewPort.gamma(rowTemplate.colorChannel);

maxPixels = 8192^2;
newResults = repmat(rowTemplate, 0, 1);
skippedRegions = {};
numberOfRegions = numel(regions);
for regionId = 1:numberOfRegions
    if progressDialog.CancelRequested; break; end
    progressDialog.Value = (regionId-1) / numberOfRegions;
    progressDialog.Message = sprintf('Analysing %s (%d of %d)', regions(regionId).name, regionId, numberOfRegions);
    drawnow limitrate;

    regionImage = regions(regionId).image;
    if numel(regionImage) > maxPixels
        skippedRegions{end+1} = sprintf('%s: larger than 8192 x 8192 pixels', regions(regionId).name); %#ok<AGROW>
        continue;
    end
    try
        analysis = controllers.ImageSharpness.analyseRegion(regionImage, pixelSize, analysisOptions);
    catch err
        if strcmp(err.identifier, 'MIB:ImageSharpness:RegionTooSmall')
            skippedRegions{end+1} = sprintf('%s: %s', regions(regionId).name, err.message); %#ok<AGROW>
            continue;
        end
        delete(progressDialog);
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Sharpness and noise');
        return;
    end
    row = rowTemplate;
    row.regionName = regions(regionId).name;
    row.position = regions(regionId).position;
    row.regionSize = size(regionImage, [1 2]);
    row.analysis = analysis;
    % display copy with the contrast of the image view, at most 512 px
    displayImage = double(regionImage);
    if max(row.regionSize) > 512
        displayImage = imresize(displayImage, 512 / max(row.regionSize));
    end
    displayImage = (displayImage - displayRange(1)) / max(displayRange(2) - displayRange(1), eps);
    row.thumbnail = im2uint8(min(max(displayImage, 0), 1) .^ displayGamma);
    newResults(end+1, 1) = row; %#ok<AGROW>
end
cancelled = progressDialog.CancelRequested;
delete(progressDialog);

if cancelled
    uialert(obj.view.gui, 'Calculation was cancelled; no results were added.', 'Sharpness and noise', 'Icon', 'info');
    return;
end

if ~isempty(newResults)
    obj.results = controllers.ImageSharpness.mergeResults(obj.results, newResults);
    obj.storeSession();
    obj.updateResultsTable();
    obj.updatePlots(numel(obj.results));
end

% one alert for all warnings: a second uialert would replace the first
warnings = {};
if ~isempty(newResults) && analysisOptions.UseFft && ~analysisOptions.SlowDetector
    numberCorrelated = nnz(arrayfun(@(row) row.analysis.fft.correlatedNoise, newResults));
    if numberCorrelated > 0
        warnings{end+1} = sprintf(['The noise is smeared along the scan lines in %d of %d regions: the detector ' ...
            'is slow for this scan speed. FFT resolution, astigmatism, noise SD and SNR of these rows are not ' ...
            'valid.\nTick "Slow detector" in Settings and calculate again.'], numberCorrelated, numel(newResults));
    end
end
if ~isempty(newResults) && analysisOptions.UseFft
    numberDenoised = nnz(arrayfun(@(row) row.analysis.fft.denoised, newResults));
    if numberDenoised > 0
        warnings{end+1} = sprintf(['The noise is below one grey value in %d of %d regions: the image was probably ' ...
            'denoised or smoothed. Its FFT and decorrelation resolutions come out far too fine and do not compare ' ...
            'with those of raw images.\nAnalyse the image as it comes from the microscope.'], numberDenoised, numel(newResults));
    end
end
if ~isempty(skippedRegions)
    warnings{end+1} = sprintf('These regions were not analysed:\n%s', strjoin(skippedRegions, newline));
end
if ~isempty(warnings)
    uialert(obj.view.gui, strjoin(warnings, [newline newline]), 'Sharpness and noise', 'Icon', 'warning');
end
end
