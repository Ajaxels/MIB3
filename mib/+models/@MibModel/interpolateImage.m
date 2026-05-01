function interpolateImage(obj, imgType, intType, BatchOptIn)
% INTERPOLATEIMAGE - Interpolate the 'mask', 'selection', or 'labels' layer between slices.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.interpolateImage(imgType, intType, BatchOptIn)
%
% Applies either shape interpolation (suitable for filled blobs) or line
% interpolation (suitable for open-line / membrane annotations) to the
% binary representation of the chosen layer at the current time point.
% Intermediate slices between any two annotated slices are filled in.
%
% Input Arguments:
%   - **imgType** — *(optional)* string, layer to interpolate; default ``'selection'``:
%
%     - ``'selection'`` — smooth the Selection layer
%     - ``'mask'`` — smooth the Mask layer
%     - ``'labels'`` — smooth a material of the Labels (segmentation model) layer
%
%   - **intType** — *(optional)* string, interpolation algorithm; default from preferences:
%
%     - ``'shape'`` — contour-based interpolation, best for filled shapes/blobs
%     - ``'line'`` — endpoint-based interpolation, best for open lines/membranes
%
%   - **BatchOptIn** — *(optional)* structure for batch processing mode; when ``NaN``,
%     returns a structure with default options via the "SyncBatch" event:
%
%     - ``.Target`` — cell string, ``{'mask','selection','labels'}`` layer to interpolate
%     - ``.InterpolationType`` — cell string, ``{'shape','line'}`` algorithm
%     - ``.MaterialIndex`` — string [*only* for ``'labels'``], index of the material
%     - ``.showWaitbar`` — logical, show or not the waitbar
%     - ``.id`` — *(optional)* dataset index 1–9, default = ``obj.id``
%
% Output Arguments:
%   (none) — returns early on cancel, invalid input, or unsupported mode.
%
% Usage:
%   **Example 1** — shape-interpolate current selection
%
%   .. code-block:: matlab
%
%      obj.mibModel.interpolateImage('selection', 'shape');
%

% Updates
%

if nargin < 4; BatchOptIn = struct(); end
if nargin < 3; intType = []; end
if nargin < 2; imgType = []; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
if ~isempty(imgType)
    BatchOpt.Target = {imgType};
else
    BatchOpt.Target = {'selection'};
end
BatchOpt.Target{2} = {'mask', 'selection', 'labels'};

if ~isempty(intType)
    BatchOpt.InterpolationType = {intType};
else
    BatchOpt.InterpolationType = {obj.preferences.SegmTools.Interpolation.Type};
end
BatchOpt.InterpolationType{2} = {'shape', 'line'};

BatchOpt.MaterialIndex = '1';
BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();   % default dataset index

switch BatchOpt.Target{1}
    case 'selection'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Selection';
        BatchOpt.mibBatchActionName  = 'Interpolate selection';
    case 'mask'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Mask';
        BatchOpt.mibBatchActionName  = 'Interpolate mask';
    case 'labels'
        BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
        BatchOpt.mibBatchActionName  = 'Interpolate material';
end

% tooltips that will accompany the BatchOpt
BatchOpt.mibBatchTooltip.Target            = 'Layer to be interpolated';
BatchOpt.mibBatchTooltip.InterpolationType = 'Type of interpolation: "shape" is suitable for blobs, "line" for membranes';
BatchOpt.mibBatchTooltip.MaterialIndex     = '[Only for labels] index of the material in the model to be interpolated';
BatchOpt.mibBatchTooltip.showWaitbar       = 'Show or not the progress bar during execution';

%% Batch mode check actions
if nargin == 4  % batch mode
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)    % when NaN return default options
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle      = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.interpolateImage';
            ErrorDlgOpt.err           = 'A structure as the 4th parameter is required!';
            ErrorDlgOpt.WindowHeight  = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        % combine fields from input and default structures
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%% Do nothing if selection is disabled
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    header       = 'The selection layer is switched off!';
    dlgOpt.HeaderLines = 1;
    dlgOpt.WindowHeight = 170;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, header, {''}, ...
        {'Please make sure that the "Enable selection" option in the Preferences dialog (Ribbon->Home->Preferences) is set to "yes" and try again...'}, ...
        'interpolateImages: The selection layer is disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Reject virtual stacking mode (not supported)
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly   = true;
    dlgOpt.Icon         = 'puffin_warning';
    dlgOpt.HeaderLines  = 1;
    dlgOpt.WindowHeight = 160;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'Ops!', {''}, ...
        {'The interpolation tool is not yet available in the virtual stacking mode. Please switch to the memory-resident mode and try again.'}, ...
        'interpolateImages: Not implemented', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Start the waitbar
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
        'Message', 'Please wait...', ...
        'Title', 'Interpolating...', 'Indeterminate', 'on');
end

%% Fetch layer data for the current time point
getDataOpt.id = BatchOpt.id;
t = obj.I{BatchOpt.id}.getCurrentTimePoint();

switch BatchOpt.Target{1}
    case {'mask', 'selection'}
        selection = cell2mat(obj.getData3D(BatchOpt.Target{1}, t, [], [], getDataOpt));
    case 'labels'
        MaterialIndex = str2double(BatchOpt.MaterialIndex);
        if MaterialIndex < 1
            if BatchOpt.showWaitbar; delete(wb); end
            notify(obj, 'StopProtocol');
            return;
        end
        selection = cell2mat(obj.getData3D(BatchOpt.Target{1}, t, [], MaterialIndex, getDataOpt));
end

%% Determine block-mode coordinate offsets (for partial-region backups)
if obj.I{BatchOpt.id}.blockModeSwitch == 0
    xShift = 0;
    yShift = 0;
    zShift = 0;
else
    [yMin, ~, xMin, ~, zMin, ~] = obj.I{BatchOpt.id}.getCoordinatesOfShownImage(1);
    xShift = xMin - 1;
    yShift = yMin - 1;
    zShift = zMin - 1;
end

storeOptions.id = BatchOpt.id;

%% Run the interpolation
if strcmp(BatchOpt.InterpolationType{1}, 'shape')   % shape interpolation
    [selection, bb] = utils.interpolateShapes(selection, obj.preferences.SegmTools.Interpolation.NoPoints);
    if isempty(bb)
        if BatchOpt.showWaitbar; delete(wb); end
        return;
    end

    % bb = [xMin, xMax, yMin, yMax, zMin, zMax] in the view coordinate system.
    % Map to dataset (x,y,z) depending on the current orientation.
    orient = obj.I{BatchOpt.id}.orientation;
    if orient == 1          % ZX plane
        storeOptions.y = [bb(5)+yShift, bb(6)+yShift];
        storeOptions.z = [bb(1)+zShift, bb(2)+zShift];
        storeOptions.x = [bb(3)+xShift, bb(4)+xShift];
    elseif orient == 2      % ZY plane
        storeOptions.y = [bb(3)+yShift, bb(4)+yShift];
        storeOptions.z = [bb(1)+zShift, bb(2)+zShift];
        storeOptions.x = [bb(5)+xShift, bb(6)+xShift];
    elseif orient == 3      % XY plane (default)
        storeOptions.y = [bb(3)+yShift, bb(4)+yShift];
        storeOptions.x = [bb(1)+xShift, bb(2)+xShift];
        storeOptions.z = [bb(5)+zShift, bb(6)+zShift];
    end
else                        % line interpolation
    selection = utils.interpolateLines(selection, ...
        obj.preferences.SegmTools.Interpolation.NoPoints, ...
        obj.preferences.SegmTools.Interpolation.LineWidth);
end

%% Back up the original state (done after interpolation so the backup reads
%  the unmodified data still in the dataset), then write the result
obj.backup(BatchOpt.Target{1}, 1, storeOptions);

switch BatchOpt.Target{1}
    case {'mask', 'selection'}
        obj.I{BatchOpt.id}.setData3D(selection, BatchOpt.Target{1}, t, [], [], getDataOpt);
    case 'labels'
        obj.I{BatchOpt.id}.setData3D(selection, BatchOpt.Target{1}, t, [], MaterialIndex, getDataOpt);
end

if BatchOpt.showWaitbar; delete(wb); end

%% Notify batch mode and redraw
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

notify(obj, 'ShowImage');
end
