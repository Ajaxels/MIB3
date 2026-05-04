function generateKymograph(obj, datasetId, measurementIndex)
% GENERATEKYMOGRAPH - Generate a kymograph from a linear or polyline measurement.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.generateKymograph(datasetId, measurementIndex)
%
% Asks the user for output format and whether to add a scale bar, calls
% :meth:`core.Measurements.computeKymograph` with the 4-D image stack,
% then saves or previews the result.  A ``.txt`` description file with
% physical step sizes is written alongside every TIF save.
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%   - **datasetId** — [double] index into ``mibModel.I``
%   - **measurementIndex** — [double] 1-based index in ``hMeasure.Data``
%

hMeasure    = obj.mibModel.I{datasetId}.measure;
measureType = hMeasure.Data(measurementIndex).type;

if ~ismember(measureType, {'Distance (linear)', 'Distance (polyline)', 'Distance (freehand)', 'Caliper'})
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'Kymograph requires a linear, polyline, freehand, or caliper measurement.', ...
        'Kymograph');
    return;
end

% resolve colour channel (0 = current shown channels → [] for getData4D)
colChItems    = obj.view.handles.imageColChDropdown.Items;
colChSelected = obj.view.handles.imageColChDropdown.Value;
colChIndex    = find(strcmp(colChItems, colChSelected), 1);
colCh         = colChIndex - 1;
colChData     = colCh;
if colCh == 0; colChData = []; end

% options dialog
dlgOpt.LabelPosition = 'left';
outputChoices = {'Preview', 'TIF', 'MAT', 'CSV'};
dlgAnswer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
    {'Output format:', 'Add scale bar:'}, ...
    {[outputChoices, {1}], true}, ...
    'Kymograph options', dlgOpt);
if isempty(dlgAnswer); return; end
outputFormat = dlgAnswer{1};
addScaleBarFlag = dlgAnswer{2};

% select path coordinates based on measurement type:
%   Caliper           — perpendicular segment P3-P4
%   polyline/freehand — dense stored path
%   linear            — two endpoints
storedX = hMeasure.Data(measurementIndex).X;
storedY = hMeasure.Data(measurementIndex).Y;
switch measureType
    case 'Caliper'
        kymX = storedX(3:4);
        kymY = storedY(3:4);
    case {'Distance (polyline)', 'Distance (freehand)'}
        kymX = storedX;
        kymY = storedY;
    otherwise
        kymX = storedX(1:2);
        kymY = storedY(1:2);
end

% fetch 4-D stack — getData4D returns {roi}[H x W x depth x colors x time]
getDataOptions = struct('id', datasetId, 'blockModeSwitch', false);
imageStackCell = obj.mibModel.getData4D('image', [], colChData, getDataOptions);
imageStackRaw  = imageStackCell{1};                              % [H x W x depth x colors x time]
imageStack     = permute(imageStackRaw(:,:,:,:,1), [1,2,4,3]);  % → [H x W x colors x depth]
kymograph      = core.Measurements.computeKymograph(imageStack, kymX, kymY);
% kymograph: [nSlices x nPoints x nChannels]

% physical step sizes for scale bar and export
pixSize        = obj.mibModel.I{datasetId}.image.pixSize;
nPoints        = size(kymograph, 2);
measureValue   = hMeasure.Data(measurementIndex).value;
resXvectorStep = measureValue / max(1, nPoints - 1);

imageDescription = sprintf( ...
    'Kymograph: X = profile length, Y = depth/time projection. X step: %f %s, Y step: %f %s or %f %s', ...
    resXvectorStep, pixSize.units, ...
    pixSize.z,      pixSize.units, ...
    pixSize.t,      pixSize.tunits);

% --- helper: build scale-bar-annotated RGB image from a 2-D kymograph slice ---
    function imgRGB = applyKymographScaleBar(kymoSlice)
        imgDouble = double(kymoSlice);
        imgMin    = min(imgDouble(:));
        imgMax    = max(imgDouble(:));
        if imgMax > imgMin
            imgNorm = (imgDouble - imgMin) / (imgMax - imgMin);
        else
            imgNorm = zeros(size(imgDouble));
        end
        imgRGB = repmat(uint8(imgNorm * 255), [1, 1, 3]);
        scaleBarPixSize.x     = resXvectorStep;
        scaleBarPixSize.y     = pixSize.z;
        scaleBarPixSize.units = pixSize.units;
        scaleBarOpt.textSuffix = sprintf(' dY=%.2f%s (%.2f%s)', ...
            pixSize.z, pixSize.units, pixSize.t, pixSize.tunits);
        scaleBarOpt.markerText = 'text';
        try
            imgRGB = utils.addScaleBar(imgRGB, scaleBarPixSize, 1, scaleBarOpt);
        catch
        end
    end

[filePath, templateFn] = fileparts(obj.mibModel.I{datasetId}.image.filename);
defaultFilename = fullfile(filePath, [templateFn '_kym']);

switch outputFormat
    case 'Preview'
        figHandle = figure(1951);
        clf(figHandle);
        axHandle = axes(figHandle);
        if addScaleBarFlag
            imgPreview = applyKymographScaleBar(kymograph(:, :, 1));
            imshow(imgPreview, 'Parent', axHandle);
        else
            imshow(kymograph(:, :, 1), [], 'Parent', axHandle);
        end
        title(axHandle, sprintf('Kymograph — measurement %d', hMeasure.Data(measurementIndex).n));

    case 'TIF'
        [filename, pathname] = uiputfile({'*.tif', 'TIFF (*.tif)'}, ...
            'Save kymograph', defaultFilename);
        if isequal(filename, 0); return; end
        fullPath = fullfile(pathname, filename);
        if addScaleBarFlag
            imgOut = applyKymographScaleBar(kymograph(:, :, 1));
            imwrite(imgOut, fullPath);
        else
            imwrite(kymograph(:, :, 1), fullPath);
        end
        fileID = fopen([fullPath(1:end-4) '.txt'], 'w');
        fprintf(fileID, '%s', imageDescription);
        fclose(fileID);

    case 'MAT'
        [filename, pathname] = uiputfile({'*.mat', 'MAT-file (*.mat)'}, ...
            'Save kymograph', defaultFilename);
        if isequal(filename, 0); return; end
        dataOut.x                = (0:nPoints-1) * resXvectorStep;
        dataOut.y                = kymograph;
        dataOut.imageDescription = imageDescription;
        save(fullfile(pathname, filename), 'dataOut');

    case 'CSV'
        [filename, pathname] = uiputfile({'*.csv', 'CSV (*.csv)'}, ...
            'Save kymograph', defaultFilename);
        if isequal(filename, 0); return; end
        xVec       = (0:nPoints-1) * resXvectorStep;
        kymoSlice  = double(kymograph(:, :, 1));   % [nSlices x nPoints]
        varNames   = [{'X_pos'}, arrayfun(@(i) sprintf('Z%d', i), 1:size(kymoSlice,1), 'UniformOutput', false)];
        tableData  = array2table([xVec(:), kymoSlice'], 'VariableNames', varNames);
        tableData.Properties.VariableUnits{1} = pixSize.units;
        writetable(tableData, fullfile(pathname, filename));
end
end
