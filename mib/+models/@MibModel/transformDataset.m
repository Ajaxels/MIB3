function status = transformDataset(obj, BatchOptIn)
% TRANSFORMDATASET - Dispatcher for dataset geometry transform operations.
%
% Syntax:
%   .. code-block:: matlab
%
%       status = obj.transformDataset(BatchOptIn)
%
% Orchestrates all dataset shape and orientation transforms for the active
% ``MibDataset``.  Validates preconditions (virtual mode, backup), then
% delegates to the appropriate ``MibDataset`` sub-method.  Fully
% batch-compatible.
%
% Input Arguments:
%   - **BatchOptIn** — *(optional)* structure for batch processing mode; when
%     ``NaN``, returns default options via the ``SyncBatch`` event.
%
%     - ``.Transform`` — [cell] transform to apply (default: ``{'Flip horizontally'}``).
%       Allowed values:
%       ``{'Flip horizontally','Flip vertically','Flip Z','Flip T'``
%       ``'Rotate 90 degrees','Rotate -90 degrees'``
%       ``'Transpose YX -> YZ','Transpose YX -> XZ','Transpose YX -> XY','Transpose YX -> ZX'``
%       ``'Transpose Z<->T','Transpose Z<->C'``
%       ``'Update with new width/height','Update with new dX/dY'}``
%     - ``.Position`` — [cell] image position for ``'Update with new width/height'``
%       (default: ``{'Center'}``). Allowed values: ``{'Center','Left-upper corner',``
%       ``'Center-top','Right-upper corner','Left-bottom corner',``
%       ``'Center-bottom','Right-bottom corner'}``
%     - ``.NewImageWidth`` — [numeric cell] new width in pixels for ``'Update with new width/height'``;
%       ``{1}`` value (default: ``0``), ``{2}`` limits ``[1, Inf]``, ``{3}`` ``'on'`` (integer)
%     - ``.NewImageHeight`` — [numeric cell] new height in pixels for ``'Update with new width/height'``;
%       ``{1}`` value (default: ``0``), ``{2}`` limits ``[1, Inf]``, ``{3}`` ``'on'`` (integer)
%     - ``.FrameColorIntensity`` — [numeric cell] fill pixel intensity for ``'Update with new width/height'``;
%       ``{1}`` value (default: ``0``), ``{2}`` limits ``[0, Inf]``, ``{3}`` ``'off'``
%     - ``.FrameWidth`` — [numeric cell] frame half-width in pixels for ``'Update with new dX/dY'``;
%       ``{1}`` value (default: ``0``), ``{2}`` limits ``[-Inf, Inf]``, ``{3}`` ``'on'`` (integer)
%     - ``.FrameHeight`` — [numeric cell] frame half-height in pixels for ``'Update with new dX/dY'``;
%       ``{1}`` value (default: ``0``), ``{2}`` limits ``[-Inf, Inf]``, ``{3}`` ``'on'`` (integer)
%     - ``.IntensityPadValue`` — [numeric cell] pad intensity for ``'Update with new dX/dY'``;
%       ``{1}`` value (default: ``0``), ``{2}`` limits ``[0, Inf]``, ``{3}`` ``'off'``
%     - ``.Method`` — [cell] pad method for ``'Update with new dX/dY'``
%       (default: ``{'use the pad value'}``). Allowed values:
%       ``{'use the pad value','replicate','circular','symmetric'}``
%     - ``.Direction`` — [cell] pad direction for ``'Update with new dX/dY'``
%       (default: ``{'both'}``). Allowed values: ``{'both','pre','post'}``
%     - ``.NumberOfColorChannels`` — [numeric cell] output color channels for ``'Transpose Z<->C'``;
%       ``{1}`` value (default: ``NaN`` = auto), ``{2}`` limits ``[0, Inf]``, ``{3}`` ``'on'`` (integer)
%     - ``.showWaitbar`` — [logical] show the progress dialog (default: ``true``)
%     - ``.id`` — *(optional)* dataset index 1–9, default = ``obj.getActiveId()``
%
% Output Arguments:
%   - **status** — ``1`` on success, ``0`` on failure or user cancel
%
% Usage:
%   **Example 1** — flip the current dataset horizontally
%
%   .. code-block:: matlab
%
%      obj.mibModel.transformDataset();
%
%   **Example 2** — rotate 90 degrees via batch call
%
%   .. code-block:: matlab
%
%      BatchOpt.Transform = {'Rotate 90 degrees'};
%      BatchOpt.showWaitbar = false;
%      obj.mibModel.transformDataset(BatchOpt);
%
%   **Example 3** — return default BatchOpt to the Batch Processing editor
%
%   .. code-block:: matlab
%
%      obj.mibModel.transformDataset(NaN);
%

% Updates
%

status = 0;
if nargin < 2; BatchOptIn = struct(); end

%% Default BatchOpt
BatchOpt = struct();
BatchOpt.id = obj.getActiveId();

BatchOpt.Transform = {'Flip horizontally'};
BatchOpt.Transform{2} = {'Flip horizontally', 'Flip vertically', 'Flip Z', 'Flip T', ...
    'Rotate 90 degrees', 'Rotate -90 degrees', ...
    'Transpose YX -> YZ', 'Transpose YX -> XZ', 'Transpose YX -> XY', 'Transpose YX -> ZX', ...
    'Transpose Z<->T', 'Transpose Z<->C', ...
    'Update with new width/height', 'Update with new dX/dY'};

BatchOpt.Position = {'Center'};
BatchOpt.Position{2} = {'Center', 'Left-upper corner', 'Center-top', 'Right-upper corner', ...
    'Left-bottom corner', 'Center-bottom', 'Right-bottom corner'};

BatchOpt.NewImageWidth{1} = 0;
BatchOpt.NewImageWidth{2} = [0, Inf];
BatchOpt.NewImageWidth{3} = 'on';
BatchOpt.NewImageHeight{1} = 0;
BatchOpt.NewImageHeight{2} = [0, Inf];
BatchOpt.NewImageHeight{3} = 'on';
BatchOpt.FrameColorIntensity{1} = obj.I{BatchOpt.id}.image.maxInt;
BatchOpt.FrameColorIntensity{2} = [0, obj.I{BatchOpt.id}.image.maxInt];
BatchOpt.FrameColorIntensity{3} = 'on';

BatchOpt.FrameWidth{1} = 0;
BatchOpt.FrameWidth{2} = [-Inf, Inf];
BatchOpt.FrameWidth{3} = 'on';
BatchOpt.FrameHeight{1} = 0;
BatchOpt.FrameHeight{2} = [-Inf, Inf];
BatchOpt.FrameHeight{3} = 'on';
BatchOpt.IntensityPadValue{1} = obj.I{BatchOpt.id}.image.maxInt;
BatchOpt.IntensityPadValue{2} = [0, obj.I{BatchOpt.id}.image.maxInt];
BatchOpt.IntensityPadValue{3} = 'off';

BatchOpt.Method    = {'use the pad value'};
BatchOpt.Method{2} = {'use the pad value', 'replicate', 'circular', 'symmetric'};
BatchOpt.Direction    = {'both'};
BatchOpt.Direction{2} = {'both', 'pre', 'post'};

BatchOpt.NumberOfColorChannels{1} = NaN;
BatchOpt.NumberOfColorChannels{2} = [0, Inf];
BatchOpt.NumberOfColorChannels{3} = 'on';
BatchOpt.showWaitbar           = true;

BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
BatchOpt.mibBatchActionName  = 'Transform';
BatchOpt.mibBatchTooltip.Transform              = 'Select the transform operation';
BatchOpt.mibBatchTooltip.Position               = 'Image placement when adding a frame (width/height mode)';
BatchOpt.mibBatchTooltip.NewImageWidth          = 'New image width in pixels';
BatchOpt.mibBatchTooltip.NewImageHeight         = 'New image height in pixels';
BatchOpt.mibBatchTooltip.FrameColorIntensity    = 'Fill pixel intensity for the new frame region';
BatchOpt.mibBatchTooltip.FrameWidth             = 'Frame half-width in pixels (may be negative to trim)';
BatchOpt.mibBatchTooltip.FrameHeight            = 'Frame half-height in pixels (may be negative to trim)';
BatchOpt.mibBatchTooltip.IntensityPadValue      = 'Pad intensity when method is use the pad value';
BatchOpt.mibBatchTooltip.Method                 = 'Pad method for Update with new dX/dY';
BatchOpt.mibBatchTooltip.Direction              = 'Pad direction: both sides, pre (top/left) or post (bottom/right)';
BatchOpt.mibBatchTooltip.NumberOfColorChannels  = 'Number of output color channels for Transpose Z<->C (NaN = auto)';
BatchOpt.mibBatchTooltip.showWaitbar            = 'Show or not the progress dialog';

%% Batch mode check
batchModeSwitch = 0;
if isstruct(BatchOptIn) == 0
    if isnan(BatchOptIn)
        BatchOpt = rmfield(BatchOpt, 'id');
        notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
    else
        ErrorDlgOpt.Title  = 'BatchOpt Error';
        ErrorDlgOpt.String = 'A structure as the 1st parameter is required!';
        ErrorDlgOpt.Icon   = 'puffin_error';
        notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
    end
    return;
else
    BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    if isfield(BatchOptIn, 'mibBatchTooltip'); batchModeSwitch = 1; end
end

%% Guard: virtual stacking mode
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    if ~batchModeSwitch
        warnOpt.MsgBoxOnly  = true;
        warnOpt.Icon        = 'puffin_warning';
        utils.dlgs.inputUniversalDlg(obj.mibGUI, [], {}, ...
            {sprintf('The transform tools are not available in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again')}, 'Not implemented', warnOpt);
    end
    notify(obj, 'StopProtocol');
    return;
end

%% Backup
if ~batchModeSwitch
    backupOpt.id = BatchOpt.id;
    obj.backup('mibDataset', 1, backupOpt);
    % Note:
    % requires 'keepBackup'==true in NewDataset event below
    % here is the example: notify(obj, 'NewDataset', core.ToggleEventData(struct('index', BatchOpt.id, 'keepBackup', true)));
end

%% Number of color channels for Transpose Z<->C (interactive mode only)
noColorChannels = BatchOpt.NumberOfColorChannels{1};
if strcmp(BatchOpt.Transform{1}, 'Transpose Z<->C') && ~batchModeSwitch && isnan(noColorChannels)
    currentDepth  = obj.I{BatchOpt.id}.image.depth;
    currentColors = obj.I{BatchOpt.id}.image.colors;
    if currentColors == 1
        options.Type = 'spinner';
        options.WindowHeight = 130;
        defAns = struct('Value', currentDepth, 'Limits', [1 currentDepth], 'Step', 1, 'Round', true);
        answer = utils.dlgs.inputSingleDlg(obj.mibGUI, ...
            sprintf('Enter the number of color channels in the output image\n(enter %d to exchange all Z to C):', currentDepth), ...
            defAns, 'Transpose Z<->C', options);
        if isempty(answer); notify(obj, 'StopProtocol'); return; end
        noColorChannels = answer;
        BatchOpt.NumberOfColorChannels{1} = answer;
    else
        noColorChannels = NaN;
    end
end

%% Dispatch to MibDataset method
showWaitbar = BatchOpt.showWaitbar;
transformMode = BatchOpt.Transform{1};

switch transformMode
    case {'Flip horizontally', 'Flip vertically', 'Flip Z', 'Flip T'}
        obj.I{BatchOpt.id}.flipDataset(transformMode, obj.mibGUI, showWaitbar);

    case {'Rotate 90 degrees', 'Rotate -90 degrees'}
        obj.I{BatchOpt.id}.rotateDataset(transformMode, obj.mibGUI, showWaitbar);

    case {'Transpose YX -> YZ', 'Transpose YX -> XZ', 'Transpose YX -> XY', 'Transpose YX -> ZX', ...
          'Transpose Z<->T', 'Transpose Z<->C'}
        obj.I{BatchOpt.id}.transposeDataset(transformMode, obj.mibGUI, showWaitbar, noColorChannels);

    case 'Update with new width/height'
        if ~batchModeSwitch && (BatchOpt.NewImageWidth{1} == 0 || BatchOpt.NewImageHeight{1} == 0)
            dlgOpt.WindowHeight = 240;
            currentWidth = obj.I{BatchOpt.id}.image.width;
            currentHeight = obj.I{BatchOpt.id}.image.height;
            BatchOpt.NewImageWidth{2} = [currentWidth Inf];
            BatchOpt.NewImageHeight{2} = [currentHeight Inf];
            answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', ...
                {'Position:', 'New image width (px):', 'New image height (px):', 'Fill color intensity:'}, ...
                {[BatchOpt.Position{2}, {find(strcmp(BatchOpt.Position{2}, BatchOpt.Position{1}))}], ...
                struct('Spinner',true,'Value',currentWidth,'Limits',BatchOpt.NewImageWidth{2},'Step',1, 'Round',true), ...
                struct('Spinner',true,'Value',currentHeight,'Limits',BatchOpt.NewImageHeight{2},'Step',1, 'Round',true), ...
                struct('Spinner',true,'Value',BatchOpt.FrameColorIntensity{1},'Limits',BatchOpt.FrameColorIntensity{2},'Step',1, 'Round',true)}, ...
                'Add frame (W/H)', dlgOpt);
            if isempty(answer); notify(obj, 'StopProtocol'); return; end
            
            BatchOpt.Position{1} = answer{1};
            BatchOpt.NewImageWidth{1} = answer{2};
            BatchOpt.NewImageHeight{1} = answer{3};
            BatchOpt.FrameColorIntensity{1} = answer{4};
            
        end
        obj.I{BatchOpt.id}.addFrameToImage(BatchOpt, obj.mibGUI);

    case 'Update with new dX/dY'
        if ~batchModeSwitch && (BatchOpt.FrameWidth{1} == 0 && BatchOpt.FrameHeight{1} == 0)
            dlgOpt.WindowHeight = 270;
            answer = utils.dlgs.inputUniversalDlg(obj.mibGUI, '', ...
                {'Frame width, dX (px; negative to trim):', 'Frame height, dY (px; negative to trim):', ...
                 'Fill intensity (for pad value method):', 'Pad method:', 'Direction:'}, ...
                {struct('Spinner',true,'Value',BatchOpt.FrameWidth{1},'Limits',BatchOpt.FrameWidth{2},'Step',1,'Round',true), ...
                 struct('Spinner',true,'Value',BatchOpt.FrameHeight{1},'Limits',BatchOpt.FrameHeight{2},'Step',1,'Round',true), ...
                 struct('Spinner',true,'Value',BatchOpt.IntensityPadValue{1},'Limits',BatchOpt.IntensityPadValue{2},'Step',1,'Round',false), ...
                 [BatchOpt.Method{2}, {find(strcmp(BatchOpt.Method{2}, BatchOpt.Method{1}))}], ...
                 [BatchOpt.Direction{2}, {find(strcmp(BatchOpt.Direction{2}, BatchOpt.Direction{1}))}]}, ...
                'Add frame (dX/dY)', dlgOpt);
            if isempty(answer); notify(obj, 'StopProtocol'); return; end
            BatchOpt.FrameWidth{1}        = answer{1};
            BatchOpt.FrameHeight{1}       = answer{2};
            BatchOpt.IntensityPadValue{1} = answer{3};
            BatchOpt.Method{1}            = answer{4};
            BatchOpt.Direction{1}         = answer{5};
        end
        obj.I{BatchOpt.id}.addFrame(BatchOpt, obj.mibGUI);

    otherwise
        utils.dlgs.showErrorDialog(obj.mibGUI, ...
            sprintf('Unknown transform mode: %s', transformMode), 'Transform dataset');
        notify(obj, 'StopProtocol');
        return;
end

%% Update display
dimChangingTransforms = {'Rotate 90 degrees', 'Rotate -90 degrees', ...
    'Transpose YX -> YZ', 'Transpose YX -> XZ', 'Transpose YX -> XY', 'Transpose YX -> ZX', ...
    'Transpose Z<->T', 'Transpose Z<->C', ...
    'Update with new width/height', 'Update with new dX/dY'};

if ismember(transformMode, dimChangingTransforms)
    notify(obj, 'NewDataset', core.ToggleEventData(struct('index', BatchOpt.id, 'keepBackup', true)));
end

BatchOpt = rmfield(BatchOpt, 'id');
notify(obj, 'SyncBatch', core.ToggleEventData(BatchOpt));
notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'ribbonDataset'}));
notify(obj, 'ShowImage');

status = 1;
end
