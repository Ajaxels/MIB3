function generateKymograph(obj, datasetId, measurementIndex)
% GENERATEKYMOGRAPH - Generate a kymograph from a linear or polyline measurement.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.generateKymograph(datasetId, measurementIndex)
%
% Asks the user for output format, calls
% :meth:`core.Measurements.computeKymograph` with the 4-D image stack,
% then saves or previews the result.
%
% Input Arguments:
%   - **obj** — :class:`controllers.MeasureTool`
%   - **datasetId** — [double] index into ``mibModel.I``
%   - **measurementIndex** — [double] 1-based index in ``hMeasure.Data``
%

hMeasure    = obj.mibModel.I{datasetId}.measure;
measureType = hMeasure.Data(measurementIndex).type;

if ~ismember(measureType, {'Distance (linear)', 'Distance (polyline)', 'Caliper'})
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        'Kymograph requires a linear or polyline distance measurement.', ...
        'Kymograph');
    return;
end

% resolve colour channel
colChItems    = obj.view.handles.imageColChDropdown.Items;
colChSelected = obj.view.handles.imageColChDropdown.Value;
colChIndex    = find(strcmp(colChItems, colChSelected), 1);
colCh         = colChIndex - 1;

% options dialog
outputChoices = {'Preview', 'TIF', 'MAT', 'CSV'};
dlgAnswer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
    {'Output format:'}, ...
    {outputChoices, 1}, ...
    'Kymograph options', struct());
if isempty(dlgAnswer); return; end
outputFormat = dlgAnswer{1};

% get measurement line coords — use first two points for linear/caliper;
% use X/Y directly for polyline
X = hMeasure.Data(measurementIndex).X;
Y = hMeasure.Data(measurementIndex).Y;
if numel(X) > 2
    X = X([1, end]);
    Y = Y([1, end]);
end

% fetch 4-D stack (current time point, all Z slices)
imageStack = obj.mibModel.getData4D('image', [], colCh, struct('id', datasetId));
kymograph  = core.Measurements.computeKymograph(imageStack, X(1:2), Y(1:2));

% output
switch outputFormat
    case 'Preview'
        figHandle = figure(1951);
        clf(figHandle);
        imshow(kymograph(:, :, 1), [], 'Parent', axes(figHandle));
        title(figHandle.Children(end), sprintf('Kymograph — measurement %d', ...
            hMeasure.Data(measurementIndex).n));

    case 'TIF'
        [filename, pathname] = uiputfile({'*.tif', 'TIFF (*.tif)'}, ...
            'Save kymograph', obj.mibModel.myPath);
        if isequal(filename, 0); return; end
        imwrite(uint8(kymograph(:, :, 1)), fullfile(pathname, filename));

    case 'MAT'
        [filename, pathname] = uiputfile({'*.mat', 'MAT-file (*.mat)'}, ...
            'Save kymograph', obj.mibModel.myPath);
        if isequal(filename, 0); return; end
        save(fullfile(pathname, filename), 'kymograph');

    case 'CSV'
        [filename, pathname] = uiputfile({'*.csv', 'CSV (*.csv)'}, ...
            'Save kymograph', obj.mibModel.myPath);
        if isequal(filename, 0); return; end
        writematrix(double(kymograph(:, :, 1)), fullfile(pathname, filename));
end
end
