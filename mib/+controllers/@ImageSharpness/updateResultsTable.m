function updateResultsTable(obj)
% UPDATERESULTSTABLE - Fill the results table from obj.results.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateResultsTable()
%
% One row per element of ``obj.results``. Numbers are rounded to 3
% significant digits, angles to whole degrees in 0-179; a method that was
% switched off leaves its cells empty. The ``Note`` column flags FFT
% estimates limited by the pixel size (the true resolution may be finer than
% the 2 pixels reported), FFT results of images whose noise is smeared
% along the scan lines (``correlatedNoise``) calculated without
% ``SlowDetector`` - their FFT resolution, astigmatism, noise SD and SNR are
% not valid, see :func:`controllers.ImageSharpness.computeFftResolution` -
% images that look denoised (``denoised``, see
% :func:`controllers.ImageSharpness.analyseRegion`; FFT and decorrelation
% resolutions far too fine) and decorrelation curves without a peak (see
% :func:`controllers.ImageSharpness.computeDecorrelationResolution`). ``Noise
% SD`` (grey values) and ``SNR, dB`` come from the FFT noise floor and are
% empty when the FFT method was off; ``SNR, dB`` is
% ``10*log10(signalToNoise)`` to 0.1 dB, ``-Inf`` when no signal power is left
% above the noise. The table content is also what
% :func:`controllers.ImageSharpness.exportResults` writes to Excel or CSV.
%

% Updates
%

columnNames = {'Dataset', 'Region', 'Slice', 'Ch', 'Size, px', 'Pix. size', ...
    'FFT res.', 'Decorr. res.', 'Best res.', 'Worst res.', 'Astig. ratio', 'Astig. angle', ...
    'Grad. energy', 'Lapl. var.', 'Noise SD', 'SNR, dB', 'Units', 'Note'};
tableData = cell(numel(obj.results), numel(columnNames));
roundValue = @(value) round(value, 3, 'significant');
for rowId = 1:numel(obj.results)
    row = obj.results(rowId);
    notes = {};
    if abs(row.pixelSize(1) - row.pixelSize(2)) > 1e-6 * row.pixelSize(1)
        pixelText = sprintf('%.3g x %.3g', row.pixelSize(1), row.pixelSize(2));
    else
        pixelText = sprintf('%.3g', row.pixelSize(1));
    end
    tableData(rowId, 1:6) = {row.datasetName, row.regionName, row.sliceNumber, row.colorChannel, ...
        sprintf('%d x %d', row.regionSize(2), row.regionSize(1)), pixelText};

    fftResult = row.analysis.fft;
    if ~isempty(fftResult)
        tableData{rowId, 7} = roundValue(fftResult.resolution);
        if fftResult.pixelLimited; notes{end+1} = 'FFT: pixel-limited'; end %#ok<AGROW>
        % rows calculated before the slow detector check have no such fields
        slowDetector = isfield(row.options, 'SlowDetector') && row.options.SlowDetector;
        if isfield(fftResult, 'correlatedNoise') && fftResult.correlatedNoise && ~slowDetector
            notes{end+1} = 'FFT: slow detector, not valid'; %#ok<AGROW>
        end
        if isfield(fftResult, 'denoised') && fftResult.denoised
            notes{end+1} = 'denoised image: resolutions too fine'; %#ok<AGROW>
        end
        if ~isnan(fftResult.astigmatismRatio)
            tableData(rowId, 9:12) = {roundValue(fftResult.bestResolution), roundValue(fftResult.worstResolution), ...
                roundValue(fftResult.astigmatismRatio), mod(round(fftResult.worstAngle), 180)};
            if any(fftResult.sectorPixelLimited); notes{end+1} = 'some directions pixel-limited'; end %#ok<AGROW>
        end
        if isfield(fftResult, 'signalToNoise')    % rows calculated before SNR was added have no noise values
            tableData(rowId, 15:16) = {roundValue(fftResult.noiseSd), round(10*log10(fftResult.signalToNoise), 1)};
        end
    end
    decorrelationResult = row.analysis.decorrelation;
    if ~isempty(decorrelationResult)
        tableData{rowId, 8} = roundValue(decorrelationResult.resolution);
        if isnan(decorrelationResult.resolution)
            notes{end+1} = 'Decorr.: no peak'; %#ok<AGROW>
        end
    end
    sharpnessResult = row.analysis.sharpness;
    if ~isempty(sharpnessResult)
        tableData(rowId, 13:14) = {roundValue(sharpnessResult.gradientEnergy), ...
            roundValue(sharpnessResult.laplacianVariance)};
    end
    tableData{rowId, 17} = row.units;
    tableData{rowId, 18} = strjoin(notes, '; ');
end

resultsTable = obj.view.handles.resultsTable;
resultsTable.ColumnName = columnNames;
resultsTable.Data = tableData;
resultsTable.ColumnFormat = [{'char', 'char', 'shortG', 'shortG', 'char', 'char'}, repmat({'shortG'}, 1, 10), {'char', 'char'}];
resultsTable.ColumnWidth = 'fit';
resultsTable.ColumnEditable = false;
resultsTable.RowName = 'numbered';
obj.markActiveDatasetRows();
end
