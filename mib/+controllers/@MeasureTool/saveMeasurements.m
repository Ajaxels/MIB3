function saveMeasurements(obj)
% SAVEMEASUREMENTS - Save current measurements to a ``.measure`` or ``.xls`` file.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.saveMeasurements()
%
% Opens a save-file dialog.  Depending on the chosen extension:
%
% - ``*.measure`` — serialises ``hMeasure.Data`` to a MAT-file (variable ``measureData``).
% - ``*.xls``     — writes two sheets: **Sheet1** (summary table) and
%   **Sheet2** (intensity profiles).
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%

datasetId = obj.mibModel.getActiveId();
hMeasure  = obj.mibModel.I{datasetId}.measure;

if hMeasure.getNumberOfMeasurements() == 0
    utils.dlgs.showErrorDialog(obj.view.gui, 'No measurements to save.', 'Save measurements');
    return;
end

[filePath, templateFn] = fileparts(obj.mibModel.I{datasetId}.image.filename);
defaultFilename = fullfile(filePath, [templateFn '_measure']);
filters = {'*.measure', 'Matlab format (*.measure)'; ...
           '*.xls',     'Excel format (*.xls)'};
[filename, pathname] = uiputfile(filters, 'Save measurements', defaultFilename);
if isequal(filename, 0); return; end

fullPath = fullfile(pathname, filename);
[~, ~, fileExt] = fileparts(filename);

if strcmp(fileExt, '.measure')
    measureData = hMeasure.Data; %#ok<NASGU>
    save(fullPath, 'measureData', '-mat', '-v7.3');
    fprintf('MIB: saving measurements to %s -> done!\n', filename);
    return;
end

% --- Excel export ---
progressBar = core.PoolWaitbar(2, 'Please wait...', obj.view.gui, 'Generating Excel file...', true);

imageFilename = obj.mibModel.I{datasetId}.image.filename;
imageDepth    = obj.mibModel.I{datasetId}.image.depth;

sliceNames = obj.mibModel.I{datasetId}.image.sliceName;
if isempty(sliceNames) || numel(sliceNames) ~= imageDepth
    [~, baseName, baseExt] = fileparts(imageFilename);
    sliceNames = repmat({[baseName, baseExt]}, [imageDepth, 1]);
end

% --- Sheet 1: measurement summary ---
sheetData = {};
sheetData{1, 1} = sprintf('Measurements for %s', imageFilename);
sheetData(3, 1:11) = {'Filename', 'N', 'Type', 'Length', 'Info', ...
    'intensity', 'Integration width', '[tcoords]', '[zcoords]', '[xcoords]', '[ycoords]'};

currentRow = 5;
for measureIdx = 1:hMeasure.getNumberOfMeasurements()
    if progressBar.getCancelState(); progressBar.deletePoolWaitbar(); return; end
    entry = hMeasure.Data(measureIdx);

    if strcmp(entry.type, 'Circle (R)')
        xCoords = entry.circ.xc;
        yCoords = entry.circ.yc;
    elseif strcmp(entry.type, 'Distance (polyline)')
        xCoords = entry.spline.x;
        yCoords = entry.spline.y;
    else
        xCoords = entry.X;
        yCoords = entry.Y;
    end

    xStr = ['[' strjoin(arrayfun(@(v) sprintf('%.2f', v), xCoords(:)', 'UniformOutput', false), ' ; ') ']'];
    yStr = ['[' strjoin(arrayfun(@(v) sprintf('%.2f', v), yCoords(:)', 'UniformOutput', false), ' ; ') ']'];

    zSlice = entry.Z;
    if zSlice >= 1 && zSlice <= numel(sliceNames)
        sheetData(currentRow, 1) = sliceNames(zSlice);
    end
    sheetData{currentRow, 2}  = entry.n;
    sheetData{currentRow, 3}  = entry.type;
    sheetData{currentRow, 4}  = entry.value;
    sheetData{currentRow, 5}  = entry.info;
    sheetData{currentRow, 7}  = entry.integrateWidth;
    sheetData{currentRow, 8}  = entry.T;
    sheetData{currentRow, 9}  = entry.Z;
    sheetData{currentRow, 10} = xStr;
    sheetData{currentRow, 11} = yStr;

    intensityValues = entry.intensity;
    if ~isequal(intensityValues, NaN) && ~isempty(intensityValues)
        for intensityIdx = 1:numel(intensityValues)
            sheetData{currentRow + intensityIdx - 1, 6} = intensityValues(intensityIdx);
        end
        currentRow = currentRow + numel(intensityValues);
    else
        currentRow = currentRow + 1;
    end
end
writecell(sheetData, fullPath, 'Sheet', 'Sheet1', 'Range', 'A1');
progressBar.increment();
if progressBar.getCancelState(); progressBar.deletePoolWaitbar(); return; end

% --- Sheet 2: intensity profiles ---
profileSheetData = {};
profileSheetData{1, 1} = sprintf('Measurements for %s', imageFilename);
profileSheetData{2, 1} = 'Intensity profiles';

colShift = 1;
for measureIdx = 1:hMeasure.getNumberOfMeasurements()
    if progressBar.getCancelState(); progressBar.deletePoolWaitbar(); return; end
    entry = hMeasure.Data(measureIdx);
    profileSheetData{4, colShift + 1} = entry.n;

    if strcmp(entry.type, 'Circle (R)') || isequal(entry.profile, NaN) || isempty(entry.profile)
        profileSheetData{5, colShift + 1} = 'not implemented';
        colShift = colShift + 1;
    else
        nChannels = size(entry.profile, 1) - 1;
        nElements = size(entry.profile, 2);
        profileSheetData(5:5+nElements-1, colShift+1:colShift+nChannels) = ...
            num2cell(entry.profile(2:end, :)');
        colShift = colShift + nChannels;
    end
end
writecell(profileSheetData, fullPath, 'Sheet', 'Sheet2', 'Range', 'A1');
progressBar.increment();
progressBar.deletePoolWaitbar();
fprintf('MIB: saving measurements to %s -> done!\n', filename);
end
