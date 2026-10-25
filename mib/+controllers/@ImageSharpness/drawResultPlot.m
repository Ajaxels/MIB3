function drawResultPlot(axesHandle, row, plotName)
% DRAWRESULTPLOT - Draw one plot of a results row into an axes.
%
% Syntax:
%   .. code-block:: matlab
%
%      controllers.ImageSharpness.drawResultPlot(axesHandle, row, plotName)
%
% Shared by the plot tabs (:func:`controllers.ImageSharpness.updatePlots`)
% and the report (:func:`controllers.ImageSharpness.writeReport`). Works on
% ``uiaxes`` and on ordinary ``axes``. The axes is not cleared here; the
% caller passes an empty axes (``cla(axesHandle, 'reset')``).
%
% Input Arguments:
%   - **axesHandle** - [axes or uiaxes] target axes
%   - **row** - [struct] one element of ``obj.results``, see
%     :func:`controllers.ImageSharpness.calculate`
%   - **plotName** - [char] which plot:
%
%     - ``'image'`` - the analysed region (``.thumbnail``) in physical
%       units; with FFT results, a line through the centre along the most
%       blurred direction, so that the reported angle can be checked
%       against the image
%     - ``'spectrum'`` - ``log10`` power spectrum, frequency in 1/units,
%       with the FFT cutoff circle and the fitted astigmatism ellipse;
%       limited to the Nyquist circle. The spectrum has the orientation of
%       the image (positive y frequency up): a direction at angle a on the
%       screen is at angle a in the spectrum too.
%     - ``'profile'`` - radially averaged power on a log scale, the noise
%       floor (its legend entry gives the noise SD and the SNR in dB; a
%       curve rather than a constant with the slow detector correction) and
%       the cutoff; when decorrelation was computed, its curves on the right
%       axis (pale: high-pass filtered curves, solid: unfiltered) and its
%       cutoff. Each quantity has its own colour (power blue, noise floor
%       grey, FFT cutoff orange-red, decorrelation green, decorrelation
%       cutoff purple) and each y axis the colour of its curve.
%     - ``'directions'`` - resolution per direction (markers, open markers
%       for directions limited by the pixel size) and the fitted ellipse as
%       resolution versus angle.
%
% A method that was switched off for the row leaves its plot with a short
% message.
%

% Updates
%

switch plotName
    case 'image'
        drawImage(axesHandle, row);
    case 'spectrum'
        drawSpectrum(axesHandle, row);
    case 'profile'
        drawProfile(axesHandle, row);
    case 'directions'
        drawDirections(axesHandle, row);
    otherwise
        error('MIB:ImageSharpness:WrongParameter', 'Unknown plot name: %s', plotName);
end
end

% -------------------------------------------------------------------------
function plotTitle = rowTitle(row)
plotTitle = sprintf('%s, %s', row.datasetName, row.regionName);
end

% -------------------------------------------------------------------------
function drawImage(imageAxes, row)
% analysed region in physical units with the most blurred direction
fftResult = row.analysis.fft;
regionWidth = row.regionSize(2) * row.pixelSize(1);
regionHeight = row.regionSize(1) * row.pixelSize(2);
imagesc(imageAxes, [0 regionWidth], [0 regionHeight], row.thumbnail);
colormap(imageAxes, gray);
clim(imageAxes, [0 255]);
axis(imageAxes, 'image');
imageAxes.YDir = 'reverse';
if ~isempty(fftResult) && ~isnan(fftResult.astigmatismRatio)
    % line through the centre; screen angle, rows grow downwards
    halfLength = 0.4 * min(regionWidth, regionHeight);
    worstAngle = fftResult.worstAngle * pi / 180;
    hold(imageAxes, 'on');
    lineHandle = plot(imageAxes, regionWidth/2 + halfLength*[-1 1]*cos(worstAngle), ...
        regionHeight/2 - halfLength*[-1 1]*sin(worstAngle), '-', 'Color', [1 0.6 0], 'LineWidth', 2);
    hold(imageAxes, 'off');
    legend(imageAxes, lineHandle, sprintf('Most blurred direction, ratio %.2f', fftResult.astigmatismRatio), ...
        'Location', 'southoutside', 'AutoUpdate', 'off');
end
xlabel(imageAxes, row.units);
ylabel(imageAxes, row.units);
title(imageAxes, rowTitle(row), 'Interpreter', 'none', 'FontWeight', 'normal');
end

% -------------------------------------------------------------------------
function drawSpectrum(spectrumAxes, row)
% log power spectrum with the cutoff circle and the directional ellipse
fftResult = row.analysis.fft;
if isempty(fftResult)
    text(spectrumAxes, 0.5, 0.5, 'FFT resolution was not calculated', 'HorizontalAlignment', 'center', 'Units', 'normalized');
    axis(spectrumAxes, 'off');
    return;
end
nyquist = fftResult.nyquistFrequency;
% rows of the spectrum run from negative to positive y frequency, i.e.
% from up to down on the screen; negating the y data puts screen-up at
% the top of a normal y axis, so the spectrum has the image orientation
imagesc(spectrumAxes, fftResult.spectrumFrequencyX, -fftResult.spectrumFrequencyY, fftResult.spectrumImage);
spectrumAxes.YDir = 'normal';
colormap(spectrumAxes, gray);
axis(spectrumAxes, 'image');
hold(spectrumAxes, 'on');
circleAngles = linspace(0, 2*pi, 361);
lineHandles = plot(spectrumAxes, fftResult.cutoffFrequency*cos(circleAngles), fftResult.cutoffFrequency*sin(circleAngles), ...
    '--', 'Color', [0 0.75 1], 'LineWidth', 1);
if ~isempty(fftResult.ellipseCoefficients)
    ellipseRadius = ellipseFrequency(fftResult.ellipseCoefficients, circleAngles);
    lineHandles(2) = plot(spectrumAxes, ellipseRadius.*cos(circleAngles), ellipseRadius.*sin(circleAngles), ...
        '-', 'Color', [1 0.6 0], 'LineWidth', 1.5);
end
hold(spectrumAxes, 'off');
xlim(spectrumAxes, [-nyquist nyquist]);
ylim(spectrumAxes, [-nyquist nyquist]);
xlabel(spectrumAxes, sprintf('Frequency, 1/%s', row.units));
ylabel(spectrumAxes, sprintf('Frequency, 1/%s', row.units));
title(spectrumAxes, rowTitle(row), 'Interpreter', 'none', 'FontWeight', 'normal');
legendText = {'Cutoff', 'Directional cutoff'};
legend(spectrumAxes, lineHandles, legendText(1:numel(lineHandles)), ...
    'Location', 'southoutside', 'Orientation', 'horizontal', 'AutoUpdate', 'off');
end

% -------------------------------------------------------------------------
function drawProfile(profileAxes, row)
% radial power profile and decorrelation curves
fftResult = row.analysis.fft;
decorrelationResult = row.analysis.decorrelation;
if isempty(fftResult) && isempty(decorrelationResult)
    text(profileAxes, 0.5, 0.5, 'Fourier methods were not calculated', 'HorizontalAlignment', 'center', 'Units', 'normalized');
    axis(profileAxes, 'off');
    return;
end
units = row.units;
% one colour per quantity; each axis takes the colour of its curve
powerColor = [0 0.45 0.74];
noiseColor = [0.35 0.35 0.35];
fftCutoffColor = [0.85 0.33 0.10];
decorrelationColor = [0.20 0.60 0.20];
decorrelationCutoffColor = [0.49 0.18 0.56];
legendText = {};
if ~isempty(fftResult)
    yyaxis(profileAxes, 'left');
    semilogy(profileAxes, fftResult.frequency, fftResult.radialPower, '-', 'Color', powerColor, 'LineWidth', 1.5);
    hold(profileAxes, 'on');
    if isfield(fftResult, 'radialNoise')    % rows calculated before the slow detector correction have a constant floor
        semilogy(profileAxes, fftResult.frequency, fftResult.radialNoise, ':', 'Color', noiseColor, 'LineWidth', 2);
    else
        yline(profileAxes, fftResult.noiseFloor, ':', 'Color', noiseColor, 'LineWidth', 2);
    end
    xline(profileAxes, fftResult.cutoffFrequency, '--', 'Color', fftCutoffColor, 'LineWidth', 2);
    hold(profileAxes, 'off');
    ylabel(profileAxes, 'Power');
    profileAxes.YAxis(1).Color = powerColor;
    % explicit limits: with yyaxis and a log scale the automatic limits were
    % sometimes left at [0.1 1], hiding the power curve
    positivePower = fftResult.radialPower(fftResult.radialPower > 0);
    powerRange = [min([positivePower(:); fftResult.noiseFloor]), max(positivePower)];
    if isfield(fftResult, 'radialNoise'); powerRange(1) = min([powerRange(1); fftResult.radialNoise(:)]); end
    ylim(profileAxes, [10^floor(log10(powerRange(1))), 10^ceil(log10(powerRange(2)))]);
    noiseText = 'Noise floor';
    if isfield(fftResult, 'signalToNoise')    % rows calculated before SNR was added have no noise values
        noiseText = sprintf('Noise floor, SD %.3g, SNR %.1f dB', fftResult.noiseSd, 10*log10(fftResult.signalToNoise));
    end
    legendText = [legendText, {'Power', noiseText, sprintf('FFT cutoff, %.3g %s', fftResult.resolution, units)}];
end
if ~isempty(decorrelationResult)
    if ~isempty(fftResult)
        yyaxis(profileAxes, 'right');
        nyquist = fftResult.nyquistFrequency;
    else
        nyquist = 1 / (2*max(row.pixelSize));
    end
    decorrelationFrequency = decorrelationResult.radii * nyquist;
    hold(profileAxes, 'on');
    plot(profileAxes, decorrelationFrequency, decorrelationResult.curves(2:end, :)', '-', ...
        'Color', [decorrelationColor 0.3], 'HandleVisibility', 'off');
    plot(profileAxes, decorrelationFrequency, decorrelationResult.curves(1, :), '-', ...
        'Color', decorrelationColor, 'LineWidth', 1.5);
    legendText = [legendText, {'Decorrelation'}];
    if decorrelationResult.cutoffNormalized > 0
        xline(profileAxes, decorrelationResult.cutoffNormalized * nyquist, '-.', ...
            'Color', decorrelationCutoffColor, 'LineWidth', 2);
        legendText = [legendText, {sprintf('Decorr. cutoff, %.3g %s', decorrelationResult.resolution, units)}];
    end
    hold(profileAxes, 'off');
    ylabel(profileAxes, 'Decorrelation d(r)');
    ylim(profileAxes, [0 max(1, max(decorrelationResult.curves(:)))]);
    if ~isempty(fftResult); profileAxes.YAxis(2).Color = decorrelationColor; end
end
xlim(profileAxes, [0 1/(2*max(row.pixelSize))]);
xlabel(profileAxes, sprintf('Frequency, 1/%s', units));
title(profileAxes, rowTitle(row), 'Interpreter', 'none', 'FontWeight', 'normal');
legend(profileAxes, legendText, 'Location', 'northeast');
grid(profileAxes, 'on');
end

% -------------------------------------------------------------------------
function drawDirections(directionAxes, row)
% resolution per direction with the fitted ellipse
fftResult = row.analysis.fft;
if isempty(fftResult) || isempty(fftResult.sectorAngles)
    text(directionAxes, 0.5, 0.5, 'Directional resolution was not calculated', 'HorizontalAlignment', 'center', 'Units', 'normalized');
    axis(directionAxes, 'off');
    return;
end
sectorAngles = fftResult.sectorAngles;
sectorResolution = fftResult.sectorResolution;
limited = fftResult.sectorPixelLimited;
plot(directionAxes, sectorAngles(~limited), sectorResolution(~limited), 'o', 'Color', [0 0.45 0.74], ...
    'MarkerFaceColor', [0 0.45 0.74]);
hold(directionAxes, 'on');
legendText = {'Measured'};
if any(limited)
    plot(directionAxes, sectorAngles(limited), sectorResolution(limited), 'o', 'Color', [0 0.45 0.74]);
    legendText{end+1} = 'Pixel-limited';
end
if ~isempty(fftResult.ellipseCoefficients)
    fitAngles = linspace(0, 180, 181);
    fitResolution = 1 ./ ellipseFrequency(fftResult.ellipseCoefficients, fitAngles*pi/180);
    plot(directionAxes, fitAngles, fitResolution, '-', 'Color', [1 0.6 0], 'LineWidth', 1.5);
    legendText{end+1} = sprintf('Fit, ratio %.2f, worst at %d%s', fftResult.astigmatismRatio, ...
        mod(round(fftResult.worstAngle), 180), char(176));
end
hold(directionAxes, 'off');
xlim(directionAxes, [0 180]);
xticks(directionAxes, 0:30:180);
xlabel(directionAxes, 'Direction, degrees (counterclockwise from horizontal)');
ylabel(directionAxes, sprintf('Resolution, %s', row.units));
title(directionAxes, rowTitle(row), 'Interpreter', 'none', 'FontWeight', 'normal');
legend(directionAxes, legendText, 'Location', 'best');
grid(directionAxes, 'on');
end

% -------------------------------------------------------------------------
function frequency = ellipseFrequency(coefficients, angles)
% radius of the ellipse A*x^2 + B*y^2 + C*x*y = 1 along the given screen angles
frequency = 1 ./ sqrt(coefficients(1)*cos(angles).^2 + coefficients(2)*sin(angles).^2 + ...
    coefficients(3)*cos(angles).*sin(angles));
end
