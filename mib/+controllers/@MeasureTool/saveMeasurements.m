function saveMeasurements(obj)
% SAVEMEASUREMENTS - Save current measurements to a file or export them to the MATLAB workspace.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.saveMeasurements()
%
% Asks whether to save to a file or export to MATLAB. **Export to Matlab**
% assigns a copy of ``hMeasure.Data`` (the in-memory struct array, ZX
% entries in the MIB3 frame) to a base-workspace variable named by the user
% (default ``mibMeasurements``), with one extra field, ``profileXY``: a
% [2 x N] matrix whose columns match the N columns of ``.profile``; row 1
% is the horizontal and row 2 the vertical coordinate of each profile
% sample in physical units (computed as for the Excel export below),
% ``NaN`` without a profile. ``profileXY`` is not kept in ``hMeasure.Data``
% or in ``.measure`` files, so ``.profile`` keeps its
% ``[distance; channel 1; channel 2; ...]`` layout for every reader.
% **Save to a file** opens a save-file dialog and,
% depending on the chosen extension:
%
% - ``*.measure`` - serialises ``hMeasure.Data`` to a MAT-file (variable ``Data``).
% - ``*.xls``     - writes two sheets: **Sheet1** (summary table) and
%   **Sheet2** (intensity profiles). Both sheets carry the voxel size
%   (x, y, z) under the title. Each profile takes a block of columns under
%   its measurement number: the two in-plane coordinates of every profile
%   sample in physical units (``x, y`` for YX, ``x, z`` for ZX, ``z, y``
%   for ZY measurements), the slice number (``.Z``, the index along the axis
%   normal to ``.orientation``, constant within the block), then one
%   intensity column per color channel. The sample coordinates are not
%   stored; they are recovered by interpolating the profiled path
%   (``.X``/``.Y``, or the perpendicular P3-P4 of a caliper) at the arc
%   lengths in profile row 1, and converted to units as
%   ``coordinate * pixSize + boundingBoxMin``, as in
%   :meth:`core.MibDataset.convertPixelsToUnits`.
%
% Input Arguments:
%   - **obj** - :class:`controllers.MeasureTool`
%

datasetId = obj.mibModel.getActiveId();
hMeasure  = obj.mibModel.I{datasetId}.measure;

if hMeasure.getNumberOfMeasurements() == 0
    utils.dlgs.showErrorDialog(obj.view.gui, 'No measurements to save.', 'Save measurements');
    return;
end

pixSize     = obj.mibModel.I{datasetId}.image.pixSize;
boundingBox = obj.mibModel.I{datasetId}.image.boundingBox;

button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
    'Would you like to save measurements to a file or export to the main Matlab workspace?', ...
    'Export/Save measurements', ...
    'Save to a file', 'Export to Matlab', 'Cancel', 'Save to a file');
if isempty(button) || strcmp(button, 'Cancel'); return; end

if strcmp(button, 'Export to Matlab')
    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
        {'A variable for the measurements structure:'}, {'mibMeasurements'}, 'Export to Matlab');
    if isempty(answer); return; end
    if ~isvarname(answer{1})
        utils.dlgs.showErrorDialog(obj.view.gui, ...
            sprintf('"%s" is not a valid MATLAB variable name.', answer{1}), 'Export to Matlab');
        return;
    end
    exportData = hMeasure.Data;
    for measureIdx = 1:numel(exportData)
        exportData(measureIdx).profileXY = profileSampleCoordinates(exportData(measureIdx), pixSize, boundingBox)';
    end
    assignin('base', answer{1}, exportData);
    fprintf('MIB: export measurements ("%s") to Matlab -> done!\n', answer{1});
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
    % keep ZX measurements in the legacy MIB2 frame, see core.Measurements.swapZXAxes
    Data = core.Measurements.swapZXAxes(hMeasure.Data); %#ok<NASGU>
    save(fullPath, 'Data', '-mat', '-v7.3');
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

voxelSizeRow = {sprintf('Voxel size (x, y, z), %s', pixSize.units), pixSize.x, pixSize.y, pixSize.z};

% --- Sheet 1: measurement summary ---
sheetData = {};
sheetData{1, 1} = sprintf('Measurements for %s', imageFilename);
sheetData(2, 1:4) = voxelSizeRow;
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
    % slice names belong to Z slices, .Z of a ZX/ZY measurement is a Y/X index
    if isequal(entry.orientation, 3) && zSlice >= 1 && zSlice <= numel(sliceNames)
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
    if ~isempty(intensityValues) && ~all(isnan(intensityValues(:)))
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
% each profile is a block of columns: the two in-plane coordinates of every
% sample in physical units and the slice number, followed by one intensity
% column per channel
profileSheetData = {};
profileSheetData{1, 1} = sprintf('Measurements for %s', imageFilename);
profileSheetData{2, 1} = 'Intensity profiles';
profileSheetData(3, 1:4) = voxelSizeRow;

colShift = 1;
for measureIdx = 1:hMeasure.getNumberOfMeasurements()
    if progressBar.getCancelState(); progressBar.deletePoolWaitbar(); return; end
    entry = hMeasure.Data(measureIdx);
    profileSheetData{4, colShift + 1} = entry.n;

    if isempty(entry.profile) || all(isnan(entry.profile(:)))
        profileSheetData{5, colShift + 1} = 'no profile';
        colShift = colShift + 1;
    else
        [coordinates, axisNames] = profileSampleCoordinates(entry, pixSize, boundingBox);
        coordinates(:, 3) = entry.Z;   % slice number along the axis normal to the plane

        nChannels = size(entry.profile, 1) - 1;
        nElements = size(entry.profile, 2);
        profileSheetData(5, colShift+1:colShift+3) = {sprintf('%s, %s', axisNames{1}, pixSize.units), ...
            sprintf('%s, %s', axisNames{2}, pixSize.units), sprintf('slice (%s)', axisNames{3})};
        for channelIdx = 1:nChannels
            profileSheetData{5, colShift + 3 + channelIdx} = sprintf('intensity %d', channelIdx);
        end
        profileSheetData(6:6+nElements-1, colShift+1:colShift+3+nChannels) = ...
            num2cell([coordinates, entry.profile(2:end, :)']);
        colShift = colShift + 3 + nChannels;
    end
end
writecell(profileSheetData, fullPath, 'Sheet', 'Sheet2', 'Range', 'A1');
progressBar.increment();
progressBar.deletePoolWaitbar();
fprintf('MIB: saving measurements to %s -> done!\n', filename);
end

function [coordinates, axisNames] = profileSampleCoordinates(entry, pixSize, boundingBox)
% PROFILESAMPLECOORDINATES - Physical in-plane coordinates of the samples of a measurement's intensity profile.
%
% Profile row 1 holds the arc length in pixels of each sample along the
% profiled path, sampled linearly as in core.Measurements.computeProfile
% and utils.imageProfileIntegrate, so interpolating the path at those arc
% lengths gives the sample positions. The caliper profile runs along its
% perpendicular P3-P4, the circle profile along the 60-point arc stored in
% .X/.Y. The horizontal/vertical axes of the measurement plane (see
% core.Measurements.resample) are converted to units as in
% core.MibDataset.convertPixelsToUnits.
%
% Input Arguments:
%   - **entry** - [struct] one element of ``core.Measurements.Data``
%   - **pixSize** - [struct] voxel size, ``.x``, ``.y``, ``.z``
%   - **boundingBox** - [double 1x6] ``[xMin xMax yMin yMax zMin zMax]``
%
% Output Arguments:
%   - **coordinates** - [double Nx2] horizontal and vertical coordinate of
%     each of the N profile samples, in units; ``NaN`` when the measurement
%     has no profile
%   - **axisNames** - [cell 1x3] names of the horizontal, vertical and
%     slice axes: ``{'x','y','z'}`` for YX, ``{'x','z','y'}`` for ZX,
%     ``{'z','y','x'}`` for ZY

switch entry.orientation
    case 1;    axisNames = {'x', 'z', 'y'};   % zx: horizontal = X, vertical = Z, slice = Y
    case 2;    axisNames = {'z', 'y', 'x'};   % zy: horizontal = Z, vertical = Y, slice = X
    otherwise; axisNames = {'x', 'y', 'z'};   % yx: slice = Z
end
if isempty(entry.profile) || all(isnan(entry.profile(:)))
    coordinates = NaN;
    return;
end

if strcmp(entry.type, 'Caliper')
    pathX = entry.X(3:4);
    pathY = entry.Y(3:4);
else
    pathX = entry.X;
    pathY = entry.Y;
end
sampleArcLengths = entry.profile(1, :)';
[pathArcLengths, uniqueIdx] = unique([0; cumsum(hypot(diff(pathX(:)), diff(pathY(:))))]);
if numel(pathArcLengths) < 2    % a point
    sampleX = repmat(pathX(1), size(sampleArcLengths));
    sampleY = repmat(pathY(1), size(sampleArcLengths));
else
    sampleX = interp1(pathArcLengths, pathX(uniqueIdx), sampleArcLengths);
    sampleY = interp1(pathArcLengths, pathY(uniqueIdx), sampleArcLengths);
end

axisOffset  = struct('x', boundingBox(1), 'y', boundingBox(3), 'z', boundingBox(5));
coordinates = [sampleX * pixSize.(axisNames{1}) + axisOffset.(axisNames{1}), ...
    sampleY * pixSize.(axisNames{2}) + axisOffset.(axisNames{2})];
end
