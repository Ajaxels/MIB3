function makeDocFigures(outputFolder, figureNames)
% MAKEDOCFIGURES - Figures for the Settings section of the Sharpness and noise user page.
%
% figureNames (optional) - cell array of the figures to write: 'snrThreshold',
% 'numberOfDirections', 'smoothingSigma', 'suppressScanLines', 'slowDetector'; all by default.
%
% Uses mib/assets/misc/sharpness_test_gold_on_carbon.tif (see makeSharpnessTestImage.m) and the
% static methods of controllers.ImageSharpness, so the figures show what the tool computes.
%
% Example (from the MIB3 folder, mib on the path):
%   makeDocFigures('docs\docs\user-interface\ribbon\image\images')
%   makeDocFigures('docs\docs\user-interface\ribbon\image\images', {'slowDetector'})

if nargin < 2
    figureNames = {'snrThreshold', 'numberOfDirections', 'smoothingSigma', 'suppressScanLines', 'slowDetector'};
end
testFile = fullfile(fileparts(mfilename('fullpath')), '..', '..', 'mib', 'assets', 'misc', 'sharpness_test_gold_on_carbon.tif');
pixelSize = 2;      % nm
focused = imread(testFile, 1);
astigmatic = imread(testFile, 3);
scanLines = imread(testFile, 5);
orange = [1 0.6 0];
blue = [0 0.45 0.74];

%% SNR threshold: radial profile with the cutoffs of three thresholds
if ismember('snrThreshold', figureNames)
    periodicImage = controllers.ImageSharpness.preprocessRegion(focused);
    thresholds = [0.3 1 4];
    figureHandle = newFigure([560 300]);
    axesHandle = axes(figureHandle);
    reference = controllers.ImageSharpness.computeFftResolution(periodicImage, pixelSize, struct('NumberOfSectors', 0));
    semilogy(axesHandle, reference.frequency, reference.radialPower, '-', 'Color', blue, 'LineWidth', 1.2);
    hold(axesHandle, 'on');
    yline(axesHandle, reference.noiseFloor, ':k', 'LineWidth', 1);
    lineStyles = {'--', '-', '-.'};
    legendText = {'Power', 'Noise floor'};
    for thresholdId = 1:numel(thresholds)
        result = controllers.ImageSharpness.computeFftResolution(periodicImage, pixelSize, ...
            struct('NumberOfSectors', 0, 'SnrThreshold', thresholds(thresholdId)));
        xline(axesHandle, result.cutoffFrequency, lineStyles{thresholdId}, 'Color', orange, 'LineWidth', 1.4);
        legendText{end+1} = sprintf('SNR threshold %g: %.1f nm', thresholds(thresholdId), result.resolution); %#ok<AGROW>
    end
    hold(axesHandle, 'off');
    xlim(axesHandle, [0 reference.nyquistFrequency]);
    xlabel(axesHandle, 'Frequency, 1/nm');
    ylabel(axesHandle, 'Power');
    legend(axesHandle, legendText, 'Location', 'northeast');
    grid(axesHandle, 'on');
    saveFigure(figureHandle, fullfile(outputFolder, 'imageSharpnessSnrThreshold.png'));
end

%% Number of directions: directional resolution of the astigmatic slice with 12 and 72 directions
if ismember('numberOfDirections', figureNames)
    periodicImage = controllers.ImageSharpness.preprocessRegion(astigmatic);
    figureHandle = newFigure([560 300]);
    axesHandle = axes(figureHandle);
    markers = {'o', '.'};
    markerSizes = [7 14];
    markerColors = [blue; orange];
    numberOfSectors = [12 72];
    legendText = {};
    for sectorId = 1:2
        result = controllers.ImageSharpness.computeFftResolution(periodicImage, pixelSize, ...
            struct('NumberOfSectors', numberOfSectors(sectorId)));
        plot(axesHandle, result.sectorAngles, result.sectorResolution, markers{sectorId}, ...
            'Color', markerColors(sectorId, :), 'MarkerSize', markerSizes(sectorId), 'LineWidth', 1.2);
        hold(axesHandle, 'on');
        legendText{end+1} = sprintf('%d directions: ratio %.2f at %.0f%s', numberOfSectors(sectorId), ...
            result.astigmatismRatio, mod(round(result.worstAngle), 180), char(176)); %#ok<AGROW>
    end
    hold(axesHandle, 'off');
    xlim(axesHandle, [0 180]);
    xticks(axesHandle, 0:30:180);
    xlabel(axesHandle, 'Direction, degrees');
    ylabel(axesHandle, 'Resolution, nm');
    legend(axesHandle, legendText, 'Location', 'north');
    grid(axesHandle, 'on');
    saveFigure(figureHandle, fullfile(outputFolder, 'imageSharpnessNumberOfDirections.png'));
end

%% Smoothing sigma: the same crop smoothed with sigma 0, 1 and 2
if ismember('smoothingSigma', figureNames)
    crop = double(focused(161:288, 161:288));
    sigmas = [0 1 2];
    figureHandle = newFigure([560 220]);
    layout = tiledlayout(figureHandle, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    for sigmaId = 1:numel(sigmas)
        axesHandle = nexttile(layout);
        shown = crop;
        if sigmas(sigmaId) > 0; shown = imgaussfilt(crop, sigmas(sigmaId)); end
        scores = controllers.ImageSharpness.computeSharpnessScores(focused, sigmas(sigmaId));
        imagesc(axesHandle, shown, [0 255]);
        colormap(axesHandle, gray);
        axis(axesHandle, 'image', 'off');
        title(axesHandle, sprintf('sigma %g: Grad. energy %.2f', sigmas(sigmaId), scores.gradientEnergy), 'FontWeight', 'normal', 'FontSize', 9);
    end
    saveFigure(figureHandle, fullfile(outputFolder, 'imageSharpnessSmoothingSigma.png'));
end

%% Suppress scan lines: spectrum and fitted ellipse of the scan-line slice, off and on
if ismember('suppressScanLines', figureNames)
    periodicImage = controllers.ImageSharpness.preprocessRegion(scanLines);
    figureHandle = newFigure([560 300]);
    layout = tiledlayout(figureHandle, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    states = [false true];
    stateNames = {'off', 'on'};
    circleAngles = linspace(0, 2*pi, 361);
    for stateId = 1:2
        result = controllers.ImageSharpness.computeFftResolution(periodicImage, pixelSize, ...
            struct('SuppressScanLines', states(stateId)));
        axesHandle = nexttile(layout);
        imagesc(axesHandle, result.spectrumFrequencyX, -result.spectrumFrequencyY, result.spectrumImage);
        axesHandle.YDir = 'normal';
        colormap(axesHandle, gray);
        axis(axesHandle, 'image');
        hold(axesHandle, 'on');
        coefficients = result.ellipseCoefficients;
        radius = 1 ./ sqrt(coefficients(1)*cos(circleAngles).^2 + coefficients(2)*sin(circleAngles).^2 + ...
            coefficients(3)*cos(circleAngles).*sin(circleAngles));
        plot(axesHandle, radius.*cos(circleAngles), radius.*sin(circleAngles), '-', 'Color', orange, 'LineWidth', 1.6);
        hold(axesHandle, 'off');
        limit = result.nyquistFrequency * 0.6;
        xlim(axesHandle, [-limit limit]);
        ylim(axesHandle, [-limit limit]);
        axesHandle.XTick = [];
        axesHandle.YTick = [];
        title(axesHandle, sprintf('Suppress scan lines %s: ratio %.2f', stateNames{stateId}, result.astigmatismRatio), ...
            'FontWeight', 'normal', 'FontSize', 9);
    end
    saveFigure(figureHandle, fullfile(outputFolder, 'imageSharpnessSuppressScanLines.png'));
end

%% Slow detector: radial profile of the focused slice recorded with a slow detector, off and on
if ismember('slowDetector', figureNames)
    % first-order detector response along the scan line, applied to signal
    % and noise alike; 0.5 = each pixel keeps half of the previous one
    detectorResponse = 0.5;
    slowImage = filter(1 - detectorResponse, [1 -detectorResponse], double(focused), [], 2);
    fastResult = controllers.ImageSharpness.computeFftResolution( ...
        controllers.ImageSharpness.preprocessRegion(focused), pixelSize);
    periodicImage = controllers.ImageSharpness.preprocessRegion(slowImage);
    figureHandle = newFigure([560 300]);
    layout = tiledlayout(figureHandle, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    states = [false true];
    stateNames = {'off', 'on'};
    for stateId = 1:2
        result = controllers.ImageSharpness.computeFftResolution(periodicImage, pixelSize, ...
            struct('SlowDetector', states(stateId)));
        axesHandle = nexttile(layout);
        semilogy(axesHandle, result.frequency, result.radialPower, '-', 'Color', blue, 'LineWidth', 1.2);
        hold(axesHandle, 'on');
        semilogy(axesHandle, result.frequency, result.radialNoise, ':k', 'LineWidth', 1.4);
        xline(axesHandle, result.cutoffFrequency, '--', 'Color', orange, 'LineWidth', 1.6);
        hold(axesHandle, 'off');
        xlim(axesHandle, [0 result.nyquistFrequency]);
        positivePower = result.radialPower(result.radialPower > 0);
        ylim(axesHandle, [10^floor(log10(min([positivePower(:); result.radialNoise(:)]))), 10^ceil(log10(max(positivePower)))]);
        xlabel(axesHandle, 'Frequency, 1/nm');
        if stateId == 1; ylabel(axesHandle, 'Power'); end
        grid(axesHandle, 'on');
        title(axesHandle, {sprintf('Slow detector %s', stateNames{stateId}), ...
            sprintf('FFT res. %.1f nm, SNR %.1f dB, ratio %.2f', result.resolution, ...
            10*log10(result.signalToNoise), result.astigmatismRatio)}, 'FontWeight', 'normal', 'FontSize', 9);
        if stateId == 2
            legend(axesHandle, {'Power', 'Noise floor', 'FFT cutoff'}, 'Location', 'northeast');
        end
    end
    title(layout, sprintf('Same image with a fast detector: FFT res. %.1f nm, ratio %.2f', ...
        fastResult.resolution, fastResult.astigmatismRatio), 'FontSize', 9);
    saveFigure(figureHandle, fullfile(outputFolder, 'imageSharpnessSlowDetector.png'));
end
end

% -------------------------------------------------------------------------
function figureHandle = newFigure(sizeInPixels)
figureHandle = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [100 100 sizeInPixels]);
end

function saveFigure(figureHandle, fileName)
exportgraphics(figureHandle, fileName, 'Resolution', 110, 'BackgroundColor', 'white');
close(figureHandle);
fprintf('saved %s\n', fileName);
end
