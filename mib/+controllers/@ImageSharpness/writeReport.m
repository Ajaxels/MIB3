function completed = writeReport(obj, baseFileName, formats, progressDialog)
% WRITEREPORT - Write a Word and/or PDF report with every measurement of the results table.
%
% Syntax:
%   .. code-block:: matlab
%
%      completed = obj.writeReport(baseFileName, {'docx', 'pdf'})
%      completed = obj.writeReport(baseFileName, {'docx', 'pdf'}, progressDialog)
%
% Report layout, A4 portrait:
%
%   - first page(s): title, date, number of measurements and a summary table
%     with one row per measurement (image, region, slice and the main
%     values), followed by a short legend of the columns;
%   - one page per measurement: heading and subtitle (image, region); the
%     analysed area and its power spectrum side by side; the radial
%     profile; the resolution per direction; a description block (image
%     name, region type, color channel, position, pixel size, settings);
%     and a table with the measured values only.
%
% The plots are drawn with :func:`controllers.ImageSharpness.drawResultPlot`
% into one invisible page figure per measurement. For Word that figure is
% saved as one PNG before any text is added (``exportgraphics`` crops it to
% the plots) and the description and values become native Word tables; for
% the PDF the heading and both tables are drawn into the same figure, which
% is then appended as a page (``exportgraphics(..., 'Append', true,
% 'Padding', 'figure')``), so every page is a full A4 page as laid out, not a
% crop of its content. One invisible A4 figure (21 x 29.7 cm) is cleared and
% reused for all pages: with a new figure per page, every second page came
% out 2-4 % larger than A4 (R2026a). The same drawing serves both formats;
% separate figures per plot took about twice as long.
%
% The Word file is written directly as Office Open XML: ``document.xml``,
% ``styles.xml`` (Calibri, title and heading styles), a footer with page
% numbers and the PNG files, zipped to ``.docx``. Neither MATLAB Report
% Generator nor Microsoft Word is needed, also in the compiled MIB. Both
% files are assembled in a temporary folder and moved to
% ``baseFileName.docx`` / ``.pdf`` only when complete.
%
% Input Arguments:
%   - **baseFileName** - [char] full path without extension
%   - **formats** - [cell] any of ``'docx'``, ``'pdf'``
%   - **progressDialog** *(optional)* - [uiprogressdlg] dialog to report in;
%     its ``Title`` is set to the report being written. A new cancelable
%     dialog is created when omitted.
%
% Output Arguments:
%   - **completed** - [logical] false when the user cancelled; nothing is
%     written then
%

% Updates
%

completed = false;
writeDocx = ismember('docx', formats);
writePdf = ismember('pdf', formats);
numberOfRows = numel(obj.results);
formatNames = {'Word', 'PDF'};
reportTitle = sprintf('Export: %s report', strjoin(formatNames([writeDocx writePdf]), ' and '));
if nargin < 4 || isempty(progressDialog) || ~isvalid(progressDialog)
    progressDialog = uiprogressdlg(obj.view.gui, 'Title', reportTitle, 'Cancelable', 'on');
    cleanupProgress = onCleanup(@() delete(progressDialog));
else
    progressDialog.Title = reportTitle;
end
progressDialog.Message = 'Writing the summary...';
progressDialog.Value = 0;

workFolder = tempname;
mkdir(workFolder);
cleanupFolder = onCleanup(@() rmdir(workFolder, 's'));
pdfTemporary = fullfile(workFolder, 'report.pdf');

style = reportStyle();
% one invisible A4 figure for all pages: exportgraphics keeps its full extent ('Padding', 'figure'),
% so every PDF page is A4 as laid out; a new figure per page gave every second page a few
% percent larger (R2026a)
pageFigure = figure('Visible', 'off', 'Color', 'w', 'Units', 'centimeters', 'Position', [1 1 21 29.7]);
cleanupFigure = onCleanup(@() close(pageFigure));
titleText = 'Sharpness and noise';
subtitleText = sprintf('Report of %s, %d measurements', char(datetime('now', 'Format', 'd MMMM yyyy, HH:mm')), numberOfRows);
[summaryHeader, summaryCells] = summaryTable(obj.results);
legendText = ['FFT res. - resolution from the power spectrum; Decorr. res. - resolution from the decorrelation ', ...
    'analysis; Astig. ratio - worst divided by best resolution (1 = no astigmatism); Astig. angle - most ', ...
    'blurred direction, counterclockwise from horizontal; SNR - signal-to-noise ratio of the area.'];

% ---- summary
docxBody = {};
imageFiles = {};
if writePdf
    pdfSummaryPages(pageFigure, pdfTemporary, style, titleText, subtitleText, summaryHeader, summaryCells, legendText);
end
if writeDocx
    docxBody{end+1} = docxParagraph(titleText, 'Title');
    docxBody{end+1} = docxParagraph(subtitleText, 'Subtitle');
    docxBody{end+1} = docxParagraph('Summary', 'Heading2');
    docxBody{end+1} = docxDataTable(summaryHeader, summaryCells, 15, 16);
    docxBody{end+1} = docxParagraph(legendText, 'Note');
end

% ---- one page per measurement
for rowId = 1:numberOfRows
    if progressDialog.CancelRequested; return; end
    progressDialog.Value = (rowId - 1) / numberOfRows;
    progressDialog.Message = sprintf('Measurement %d of %d', rowId, numberOfRows);
    row = obj.results(rowId);
    headingText = sprintf('Measurement %d of %d', rowId, numberOfRows);
    subheadingText = sprintf('%s, %s', row.datasetName, row.regionName);
    descriptionCells = measurementDescription(row);
    [valueHeader, valueCells] = measurementValues(row);

    drawPlotPage(pageFigure, row, style);
    if writeDocx
        % exportgraphics crops to the plots; heading and tables are Word text
        imageFiles{end+1} = fullfile(workFolder, sprintf('image%d.png', numel(imageFiles) + 1)); %#ok<AGROW>
        exportgraphics(pageFigure, imageFiles{end}, 'Resolution', 130, 'BackgroundColor', 'white');
        docxBody{end+1} = docxParagraph(headingText, 'Heading1'); %#ok<AGROW>
        docxBody{end+1} = docxParagraph(subheadingText, 'Subtitle'); %#ok<AGROW>
        docxBody{end+1} = docxImageParagraph(imageFiles, numel(imageFiles), 15); %#ok<AGROW>
        docxBody{end+1} = docxKeyValueTable(descriptionCells); %#ok<AGROW>
        docxBody{end+1} = docxDataTable(valueHeader, valueCells, 18, 18); %#ok<AGROW>
    end
    if writePdf
        pdfMeasurementText(pageFigure, style, headingText, subheadingText, descriptionCells, valueHeader, valueCells);
        exportgraphics(pageFigure, pdfTemporary, 'Append', true, 'ContentType', 'vector', 'Padding', 'figure');
    end
end
if progressDialog.CancelRequested; return; end

progressDialog.Message = 'Saving...';
progressDialog.Value = 1;
if writePdf
    movefile(pdfTemporary, [baseFileName '.pdf'], 'f');
end
if writeDocx
    writeDocxPackage([baseFileName '.docx'], docxBody, imageFiles, workFolder, titleText);
end
completed = true;
end

% =========================================================================
% content
function style = reportStyle()
% colours and fonts shared by the PDF pages
style.titleColor = [0.12 0.22 0.39];
style.accentColor = [0.18 0.46 0.71];
style.textColor = [0.13 0.13 0.13];
style.mutedColor = [0.40 0.40 0.40];
style.headerFill = [0.12 0.22 0.39];
style.stripeFill = [0.94 0.96 0.98];
style.gridColor = [0.80 0.82 0.86];
style.fontName = 'Helvetica';
end

function textValue = formatValue(value, unit)
% number with 3 significant digits and an optional unit; '' for no value
if nargin < 2; unit = ''; end
if isempty(value)
    textValue = '';
elseif isnan(value)
    textValue = 'no value';
elseif strcmp(unit, char(176))
    textValue = sprintf('%.3g%s', value, unit);
else
    textValue = strtrim(sprintf('%.3g %s', value, unit));
end
end

function [header, cells] = summaryTable(results)
% one row per measurement with the main values
header = {'#', 'Image', 'Region', 'Slice', 'FFT res.', 'Decorr. res.', 'Astig. ratio', 'Astig. angle', 'SNR, dB'};
cells = cell(numel(results), numel(header));
for rowId = 1:numel(results)
    row = results(rowId);
    values = measurementNumbers(row);
    cells(rowId, :) = {sprintf('%d', rowId), row.datasetName, row.regionName, sprintf('%d', row.sliceNumber), ...
        formatValue(values.fftResolution, row.units), formatValue(values.decorrelationResolution, row.units), ...
        formatValue(values.astigmatismRatio), formatValue(values.astigmatismAngle, char(176)), ...
        formatValue(values.snrDecibels)};
end
end

function values = measurementNumbers(row)
% numbers of one measurement, [] where the method was off
names = {'fftResolution', 'bestResolution', 'worstResolution', 'astigmatismRatio', 'astigmatismAngle', ...
    'noiseSd', 'snrDecibels', 'decorrelationResolution', 'gradientEnergy', 'laplacianVariance'};
values = cell2struct(cell(numel(names), 1), names, 1);
values.notes = {};
fftResult = row.analysis.fft;
if ~isempty(fftResult)
    values.fftResolution = fftResult.resolution;
    if fftResult.pixelLimited; values.notes{end+1} = 'FFT resolution limited by the pixel size'; end
    slowDetector = isfield(row.options, 'SlowDetector') && row.options.SlowDetector;
    if isfield(fftResult, 'correlatedNoise') && fftResult.correlatedNoise && ~slowDetector
        values.notes{end+1} = 'noise smeared along the scan lines (slow detector): FFT values not valid';
    end
    if ~isnan(fftResult.astigmatismRatio)
        values.bestResolution = fftResult.bestResolution;
        values.worstResolution = fftResult.worstResolution;
        values.astigmatismRatio = fftResult.astigmatismRatio;
        values.astigmatismAngle = mod(round(fftResult.worstAngle), 180);
        if any(fftResult.sectorPixelLimited); values.notes{end+1} = 'some directions limited by the pixel size'; end
    end
    if isfield(fftResult, 'signalToNoise')
        values.noiseSd = fftResult.noiseSd;
        values.snrDecibels = round(10*log10(fftResult.signalToNoise), 1);
    end
end
decorrelationResult = row.analysis.decorrelation;
if ~isempty(decorrelationResult)
    values.decorrelationResolution = decorrelationResult.resolution;
    if isnan(decorrelationResult.resolution); values.notes{end+1} = 'decorrelation found no peak'; end
end
sharpnessResult = row.analysis.sharpness;
if ~isempty(sharpnessResult)
    values.gradientEnergy = sharpnessResult.gradientEnergy;
    values.laplacianVariance = sharpnessResult.laplacianVariance;
end
end

function cells = measurementDescription(row)
% label / value pairs that describe a measurement
orientationNames = {'ZX', 'ZY', 'XY'};
regionType = row.regionName;
if isfield(row, 'regionSource') && ~isempty(row.regionSource) && ~strcmp(row.regionSource, row.regionName)
    regionType = sprintf('%s: %s', row.regionSource, row.regionName);
end
if isempty(row.position)
    positionText = sprintf('slice %d, %s orientation', row.sliceNumber, orientationNames{row.orientation});
else
    positionText = sprintf('slice %d, %s orientation; x %d-%d, y %d-%d px (%d x %d px)', row.sliceNumber, ...
        orientationNames{row.orientation}, row.position(1), row.position(3), row.position(2), row.position(4), ...
        row.regionSize(2), row.regionSize(1));
end
if row.timePoint > 1; positionText = sprintf('%s; time point %d', positionText, row.timePoint); end
if abs(row.pixelSize(1) - row.pixelSize(2)) > 1e-6 * row.pixelSize(1)
    pixelText = sprintf('%.4g x %.4g %s', row.pixelSize(1), row.pixelSize(2), row.units);
else
    pixelText = sprintf('%.4g %s', row.pixelSize(1), row.units);
end
scanLines = 'kept';
if row.options.SuppressScanLines; scanLines = 'suppressed'; end
settingsText = sprintf('SNR threshold %g; %d directions; scan lines %s; smoothing sigma %g px', ...
    row.options.SnrThreshold, row.options.NumberOfSectors, scanLines, row.options.SmoothingSigma);
if isfield(row.options, 'SlowDetector') && row.options.SlowDetector
    settingsText = [settingsText '; slow detector correction'];
end
cells = {'Image name', row.datasetName; 'Region type', regionType; ...
    'Color channel', sprintf('%d', row.colorChannel); 'Position', positionText; ...
    'Pixel size', pixelText; 'Settings', settingsText};
end

function [header, cells] = measurementValues(row)
% measured values as two label / value column pairs: resolution, then noise and focus
values = measurementNumbers(row);
units = row.units;
left = {'FFT resolution', formatValue(values.fftResolution, units); ...
    'Decorrelation resolution', formatValue(values.decorrelationResolution, units); ...
    'Best resolution', formatValue(values.bestResolution, units); ...
    'Worst resolution', formatValue(values.worstResolution, units); ...
    'Astigmatism ratio', formatValue(values.astigmatismRatio); ...
    'Astigmatism angle', formatValue(values.astigmatismAngle, char(176))};
notesText = strjoin(values.notes, '; ');
if isempty(notesText); notesText = '-'; end
right = {'Noise SD', formatValue(values.noiseSd, 'grey values'); ...
    'SNR', formatValue(values.snrDecibels, 'dB'); ...
    'Gradient energy', formatValue(values.gradientEnergy); ...
    'Laplacian variance', formatValue(values.laplacianVariance); ...
    'Notes', notesText; '', ''};
header = {'Resolution', '', 'Noise and focus', ''};
cells = [left, right];
end

% =========================================================================
% page figure shared by both formats
function drawPlotPage(pageFigure, row, style)
% A4 portrait figure with the four plots; the top and bottom stay free for text
clf(pageFigure);
plotSpecs = {'image', [0.08 0.680 0.37 0.220], 'Analysed area'; ...
    'spectrum', [0.57 0.680 0.37 0.220], 'Power spectrum'; ...
    'profile', [0.10 0.485 0.78 0.135], 'Radial profile'; ...
    'directions', [0.10 0.325 0.78 0.100], 'Resolution per direction'};
for plotId = 1:size(plotSpecs, 1)
    plotAxes = axes(pageFigure, 'Position', plotSpecs{plotId, 2}, 'FontName', style.fontName);
    controllers.ImageSharpness.drawResultPlot(plotAxes, row, plotSpecs{plotId, 1});
    set(findall(plotAxes, '-property', 'FontSize'), 'FontSize', 8);
    title(plotAxes, plotSpecs{plotId, 3}, 'FontSize', 10, 'FontWeight', 'bold', 'Color', style.titleColor);
    legendHandle = findobj(pageFigure, 'Type', 'legend', 'Axes', plotAxes);
    if ~isempty(legendHandle); legendHandle.FontSize = 7; end
end
end

% =========================================================================
% PDF helpers
function textAxes = overlayAxes(pageFigure)
textAxes = axes(pageFigure, 'Position', [0 0 1 1], 'Visible', 'off', 'XLim', [0 1], 'YLim', [0 1]);
uistack(textAxes, 'bottom');
end

function pdfMeasurementText(pageFigure, style, headingText, subheadingText, descriptionCells, valueHeader, valueCells)
% heading, description block and values table of a measurement page
textAxes = overlayAxes(pageFigure);
drawPageHeading(textAxes, style, headingText, subheadingText);
lineHeight = 0.016;
top = 0.270;
for lineId = 1:size(descriptionCells, 1)
    y = top - (lineId - 0.5) * lineHeight;
    text(textAxes, 0.06, y, descriptionCells{lineId, 1}, 'FontSize', 8, 'FontWeight', 'bold', ...
        'Color', style.mutedColor, 'FontName', style.fontName, 'Interpreter', 'none');
    text(textAxes, 0.21, y, descriptionCells{lineId, 2}, 'FontSize', 8, 'Color', style.textColor, ...
        'FontName', style.fontName, 'Interpreter', 'none');
end
tableTop = top - size(descriptionCells, 1) * lineHeight - 0.012;
tableHeight = (size(valueCells, 1) + 1) * lineHeight;
drawStyledTable(textAxes, style, [0.06 tableTop-tableHeight 0.88 tableHeight], valueHeader, valueCells, 8, [1.4 1 1.2 1.4]);
end

function drawPageHeading(textAxes, style, headingText, subheadingText)
text(textAxes, 0.06, 0.965, headingText, 'FontSize', 16, 'FontWeight', 'bold', 'Color', style.titleColor, ...
    'FontName', style.fontName, 'Interpreter', 'none');
text(textAxes, 0.06, 0.940, subheadingText, 'FontSize', 10, 'Color', style.mutedColor, ...
    'FontName', style.fontName, 'Interpreter', 'none');
line(textAxes, [0.06 0.94], [0.928 0.928], 'Color', style.accentColor, 'LineWidth', 1.5);
end

function pdfSummaryPages(pageFigure, pdfFile, style, titleText, subtitleText, header, cells, legendText)
% title and summary table, 40 rows per portrait page
rowsPerPage = 40;
numberOfRows = size(cells, 1);
rowHeight = 0.019;
for firstRow = 1:rowsPerPage:max(numberOfRows, 1)
    rows = firstRow:min(firstRow + rowsPerPage - 1, numberOfRows);
    clf(pageFigure);
    textAxes = overlayAxes(pageFigure);
    if firstRow == 1
        text(textAxes, 0.06, 0.955, titleText, 'FontSize', 22, 'FontWeight', 'bold', 'Color', style.titleColor, ...
            'FontName', style.fontName, 'Interpreter', 'none');
        text(textAxes, 0.06, 0.925, subtitleText, 'FontSize', 10, 'Color', style.mutedColor, ...
            'FontName', style.fontName, 'Interpreter', 'none');
        line(textAxes, [0.06 0.94], [0.91 0.91], 'Color', style.accentColor, 'LineWidth', 1.5);
        text(textAxes, 0.06, 0.885, 'Summary', 'FontSize', 12, 'FontWeight', 'bold', 'Color', style.accentColor, ...
            'FontName', style.fontName, 'Interpreter', 'none');
        tableTop = 0.865;
    else
        tableTop = 0.95;
    end
    tableHeight = (numel(rows) + 1) * rowHeight;
    drawStyledTable(textAxes, style, [0.06 tableTop-tableHeight 0.88 tableHeight], header, cells(rows, :), 7.5, []);
    if rows(end) == numberOfRows
        text(textAxes, 0.06, tableTop - tableHeight - 0.015, textwrap({legendText}, 160), 'FontSize', 7, ...
            'Color', style.mutedColor, 'FontName', style.fontName, 'Interpreter', 'none', 'VerticalAlignment', 'top');
    end
    exportgraphics(pageFigure, pdfFile, 'Append', true, 'ContentType', 'vector', 'Padding', 'figure');
end
end

function drawStyledTable(textAxes, style, box, header, cells, fontSize, columnWeights)
% table with a filled header row and striped body rows; box = [left bottom width height]
numberOfLines = size(cells, 1) + 1;
lineHeight = box(4) / numberOfLines;
if isempty(columnWeights)
    textLengths = cellfun(@numel, [header; cells]);
    columnWeights = max(max(textLengths, [], 1), 3) + 2;
end
columnEdges = box(1) + box(3) * [0, cumsum(columnWeights)] / sum(columnWeights);
top = box(2) + box(4);
rectangle(textAxes, 'Position', [box(1) top-lineHeight box(3) lineHeight], 'FaceColor', style.headerFill, 'EdgeColor', 'none');
for lineId = 2:numberOfLines
    if mod(lineId, 2) == 1
        rectangle(textAxes, 'Position', [box(1) top-lineId*lineHeight box(3) lineHeight], ...
            'FaceColor', style.stripeFill, 'EdgeColor', 'none');
    end
end
line(textAxes, box(1) + [0 box(3)], [box(2) box(2)], 'Color', style.gridColor);
for lineId = 1:numberOfLines
    y = top - (lineId - 0.5) * lineHeight;
    if lineId == 1
        lineCells = header; textColor = [1 1 1]; fontWeight = 'bold';
    else
        lineCells = cells(lineId - 1, :); textColor = style.textColor; fontWeight = 'normal';
    end
    for columnId = 1:numel(lineCells)
        text(textAxes, columnEdges(columnId) + 0.006, y, lineCells{columnId}, 'FontSize', fontSize, ...
            'FontWeight', fontWeight, 'Color', textColor, 'FontName', style.fontName, ...
            'Interpreter', 'none', 'VerticalAlignment', 'middle');
    end
end
end

% =========================================================================
% Word (Office Open XML) helpers
function xml = docxParagraph(textValue, styleName)
xml = sprintf('<w:p><w:pPr><w:pStyle w:val="%s"/></w:pPr><w:r><w:t xml:space="preserve">%s</w:t></w:r></w:p>', ...
    styleName, xmlEscape(textValue));
end

function xml = docxSpacer(spacingAfter)
% empty paragraph after a table, 2 pt high: Word needs a paragraph between
% two tables, and a full-height one at the foot of a page spills onto a new
% page; measurement pages start with Heading1, whose style breaks the page
xml = sprintf(['<w:p><w:pPr><w:spacing w:before="0" w:after="%d" w:line="240" w:lineRule="auto"/>', ...
    '<w:rPr><w:sz w:val="4"/></w:rPr></w:pPr></w:p>'], spacingAfter);
end

function xml = docxCell(textValue, widthTwips, sizeHalfPoints, isBold, textColor, fillColor)
shading = '';
if ~isempty(fillColor); shading = sprintf('<w:shd w:val="clear" w:color="auto" w:fill="%s"/>', fillColor); end
boldTag = '';
if isBold; boldTag = '<w:b/>'; end
xml = sprintf(['<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/>%s<w:vAlign w:val="center"/></w:tcPr>', ...
    '<w:p><w:pPr><w:spacing w:before="20" w:after="20"/></w:pPr><w:r><w:rPr>%s<w:color w:val="%s"/>', ...
    '<w:sz w:val="%d"/></w:rPr><w:t xml:space="preserve">%s</w:t></w:r></w:p></w:tc>'], ...
    widthTwips, shading, boldTag, textColor, sizeHalfPoints, xmlEscape(textValue));
end

function xml = docxDataTable(header, cells, sizeHalfPoints, headerSizeHalfPoints)
% header row filled dark blue with white text, striped body rows, full text width
pageWidth = 10206;      % twips, A4 portrait minus 1.5 cm margins
textLengths = cellfun(@numel, [header; cells]);
columnWeights = max(max(textLengths, [], 1), 3) + 2;
columnWidths = round(pageWidth * columnWeights / sum(columnWeights));
border = 'w:val="single" w:sz="4" w:space="0" w:color="CBD2DC"';
parts = {sprintf(['<w:tbl><w:tblPr><w:tblW w:w="%d" w:type="dxa"/><w:tblLayout w:type="fixed"/>', ...
    '<w:tblBorders><w:top %s/><w:bottom %s/><w:insideH %s/></w:tblBorders>', ...
    '<w:tblCellMar><w:left w:w="70" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>'], ...
    sum(columnWidths), border, border, border)};
parts{end+1} = sprintf('<w:gridCol w:w="%d"/>', columnWidths);
parts{end+1} = '</w:tblGrid><w:tr><w:trPr><w:tblHeader/></w:trPr>';
for columnId = 1:numel(header)
    parts{end+1} = docxCell(header{columnId}, columnWidths(columnId), headerSizeHalfPoints, true, 'FFFFFF', '1F3864'); %#ok<AGROW>
end
parts{end+1} = '</w:tr>';
for rowId = 1:size(cells, 1)
    fillColor = '';
    if mod(rowId, 2) == 0; fillColor = 'EEF2F7'; end
    parts{end+1} = '<w:tr><w:trPr><w:cantSplit/></w:trPr>'; %#ok<AGROW>
    for columnId = 1:size(cells, 2)
        parts{end+1} = docxCell(cells{rowId, columnId}, columnWidths(columnId), sizeHalfPoints, false, '222222', fillColor); %#ok<AGROW>
    end
    parts{end+1} = '</w:tr>'; %#ok<AGROW>
end
parts{end+1} = ['</w:tbl>', docxSpacer(60)];
xml = [parts{:}];
end

function xml = docxKeyValueTable(cells)
% two columns without borders: grey bold labels, values
columnWidths = [2300 7906];
parts = {sprintf(['<w:tbl><w:tblPr><w:tblW w:w="%d" w:type="dxa"/><w:tblLayout w:type="fixed"/>', ...
    '<w:tblCellMar><w:left w:w="70" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr>', ...
    '<w:tblGrid><w:gridCol w:w="%d"/><w:gridCol w:w="%d"/></w:tblGrid>'], sum(columnWidths), columnWidths)};
for rowId = 1:size(cells, 1)
    parts{end+1} = ['<w:tr><w:trPr><w:cantSplit/></w:trPr>', ...
        docxCell(cells{rowId, 1}, columnWidths(1), 18, true, '595959', ''), ...
        docxCell(cells{rowId, 2}, columnWidths(2), 18, false, '222222', ''), '</w:tr>']; %#ok<AGROW>
end
parts{end+1} = ['</w:tbl>', docxSpacer(80)];
xml = [parts{:}];
end

function xml = docxImageParagraph(imageFiles, imageIndex, widthCm)
% one centred picture
imageInfo = imfinfo(imageFiles{imageIndex});
widthEmu = round(widthCm * 360000);
heightEmu = round(widthEmu * imageInfo.Height / imageInfo.Width);
xml = sprintf(['<w:p><w:pPr><w:jc w:val="center"/><w:spacing w:after="80"/></w:pPr><w:r><w:drawing>', ...
    '<wp:inline distT="0" distB="0" distL="0" distR="0">', ...
    '<wp:extent cx="%d" cy="%d"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:docPr id="%d" name="Picture %d"/>', ...
    '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>', ...
    '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>', ...
    '<pic:nvPicPr><pic:cNvPr id="%d" name="image%d.png"/><pic:cNvPicPr/></pic:nvPicPr>', ...
    '<pic:blipFill><a:blip r:embed="rIdImage%d"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>', ...
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>', ...
    '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'], ...
    widthEmu, heightEmu, imageIndex, imageIndex, imageIndex, imageIndex, imageIndex, widthEmu, heightEmu);
end

function writeDocxPackage(docxFile, bodyParts, imageFiles, workFolder, titleText)
% assemble the Office Open XML package and zip it to docxFile
packageFolder = fullfile(workFolder, 'docx');
mkdir(fullfile(packageFolder, '_rels'));
mkdir(fullfile(packageFolder, 'word', '_rels'));
mkdir(fullfile(packageFolder, 'word', 'media'));
mainNamespace = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

writeText(fullfile(packageFolder, '[Content_Types].xml'), ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', ...
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">', ...
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>', ...
    '<Default Extension="xml" ContentType="application/xml"/>', ...
    '<Default Extension="png" ContentType="image/png"/>', ...
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>', ...
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>', ...
    '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>', ...
    '</Types>']);
writeText(fullfile(packageFolder, '_rels', '.rels'), ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', ...
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">', ...
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>', ...
    '</Relationships>']);

% styles: Calibri 10 pt body, title, subtitle, headings, small note
writeText(fullfile(packageFolder, 'word', 'styles.xml'), ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', ...
    '<w:styles ', mainNamespace, '>', ...
    '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>', ...
    '<w:sz w:val="20"/><w:color w:val="222222"/></w:rPr></w:rPrDefault>', ...
    '<w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>', ...
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>', ...
    styleXml('Title', 'Title', '<w:spacing w:after="40"/>', '<w:b/><w:color w:val="1F3864"/><w:sz w:val="48"/>'), ...
    styleXml('Subtitle', 'Subtitle', '<w:spacing w:after="160"/><w:pBdr><w:bottom w:val="single" w:sz="12" w:space="6" w:color="2E75B6"/></w:pBdr>', ...
        '<w:color w:val="595959"/><w:sz w:val="22"/>'), ...
    styleXml('Heading1', 'heading 1', '<w:keepNext/><w:pageBreakBefore/><w:spacing w:before="0" w:after="20"/><w:outlineLvl w:val="0"/>', ...
        '<w:b/><w:color w:val="1F3864"/><w:sz w:val="32"/>'), ...
    styleXml('Heading2', 'heading 2', '<w:keepNext/><w:spacing w:before="120" w:after="60"/><w:outlineLvl w:val="1"/>', ...
        '<w:b/><w:color w:val="2E75B6"/><w:sz w:val="24"/>'), ...
    styleXml('Note', 'Note', '<w:spacing w:before="60" w:after="60"/>', '<w:color w:val="595959"/><w:sz w:val="16"/>'), ...
    '</w:styles>']);

% footer with the report title and the page number
writeText(fullfile(packageFolder, 'word', 'footer1.xml'), ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', ...
    '<w:ftr ', mainNamespace, '><w:p><w:pPr><w:jc w:val="center"/></w:pPr>', ...
    '<w:r><w:rPr><w:color w:val="808080"/><w:sz w:val="16"/></w:rPr><w:t xml:space="preserve">', xmlEscape(titleText), ' - page </w:t></w:r>', ...
    '<w:r><w:rPr><w:color w:val="808080"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>', ...
    '<w:r><w:rPr><w:color w:val="808080"/><w:sz w:val="16"/></w:rPr><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>', ...
    '<w:r><w:rPr><w:color w:val="808080"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>', ...
    '<w:r><w:rPr><w:color w:val="808080"/><w:sz w:val="16"/></w:rPr><w:t>1</w:t></w:r>', ...
    '<w:r><w:rPr><w:color w:val="808080"/><w:sz w:val="16"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>', ...
    '</w:p></w:ftr>']);

relationships = cell(1, numel(imageFiles));
for imageIndex = 1:numel(imageFiles)
    copyfile(imageFiles{imageIndex}, fullfile(packageFolder, 'word', 'media', sprintf('image%d.png', imageIndex)));
    relationships{imageIndex} = sprintf(['<Relationship Id="rIdImage%d" ', ...
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image%d.png"/>'], ...
        imageIndex, imageIndex);
end
writeText(fullfile(packageFolder, 'word', '_rels', 'document.xml.rels'), ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', ...
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">', ...
    '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>', ...
    '<Relationship Id="rIdFooter1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>', ...
    relationships{:}, '</Relationships>']);

sectionProperties = ['<w:sectPr><w:footerReference w:type="default" r:id="rIdFooter1"/>', ...
    '<w:pgSz w:w="11906" w:h="16838"/>', ...
    '<w:pgMar w:top="850" w:right="850" w:bottom="850" w:left="850" w:header="425" w:footer="425" w:gutter="0"/></w:sectPr>'];
writeText(fullfile(packageFolder, 'word', 'document.xml'), ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>', ...
    '<w:document ', mainNamespace, ' ', ...
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ', ...
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" ', ...
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" ', ...
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body>', ...
    bodyParts{:}, sectionProperties, '</w:body></w:document>']);

zipFile = fullfile(workFolder, 'report.zip');
zip(zipFile, {'[Content_Types].xml', '_rels', 'word'}, packageFolder);
movefile(zipFile, docxFile, 'f');
end

function xml = styleXml(styleId, styleName, paragraphProperties, runProperties)
xml = sprintf(['<w:style w:type="paragraph" w:styleId="%s"><w:name w:val="%s"/><w:basedOn w:val="Normal"/>', ...
    '<w:next w:val="Normal"/><w:qFormat/><w:pPr>%s</w:pPr><w:rPr>%s</w:rPr></w:style>'], ...
    styleId, styleName, paragraphProperties, runProperties);
end

function writeText(fileName, content)
fileId = fopen(fileName, 'w', 'n', 'UTF-8');
fileCleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, unicode2native(content, 'UTF-8'));
end

function escaped = xmlEscape(textValue)
escaped = strrep(char(textValue), '&', '&amp;');
escaped = strrep(escaped, '<', '&lt;');
escaped = strrep(escaped, '>', '&gt;');
escaped = strrep(escaped, '"', '&quot;');
end
