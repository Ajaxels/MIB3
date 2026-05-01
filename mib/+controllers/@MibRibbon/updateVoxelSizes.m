function result = updateVoxelSizes(obj, pixSize, BatchOptIn)
% UPDATEVOXELSIZES - Update the physical voxel sizes of the currently shown dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.updateVoxelSizes(pixSize, BatchOptIn)
%
% Opens an interactive dialog when called without arguments, or accepts
% values programmatically via pixSize / BatchOptIn for scripting and
% batch-processing workflows.
% Replaces MIB2: mibController.menuDatasetParameters_Callback
%
% Input Arguments:
%   - **pixSize** — *(optional)* [struct] structure with new voxel parameters. When omitted or empty the user is prompted via an interactive dialog. Fields:
%
%     - **.x** — [numeric] physical voxel size in X
%     - **.y** — [numeric] physical voxel size in Y
%     - **.z** — [numeric] physical voxel size in Z
%     - **.t** — [numeric] time step between frames
%     - **.units** — [char] physical units: ``'m'``, ``'cm'``, ``'mm'``, ``'um'``, or ``'nm'``
%     - **.tunits** — [char] time units (e.g., ``'s'``, ``'m'``, ``'h'``)
%
%   - **BatchOptIn** — *(optional)* [struct] structure for batch-processing mode. Pass **NaN** to retrieve default options via the 'SyncBatch' event. Fields:
%
%     - **.VoxelX** — [char] physical voxel size in X
%     - **.VoxelY** — [char] physical voxel size in Y
%     - **.VoxelZ** — [char] physical voxel size in Z
%     - **.VoxelT** — [char] time step between frames
%     - **.Units** — [cell] ``{'m','cm','mm','um','nm'}`` with selected index as second element
%     - **.TimeUnits** — [char] time units
%     - **.id** — *(optional)* [numeric] dataset index 1-9; default = current dataset
%
% Output Arguments:
%   - **result** — **1** on success, **0** on cancel
%

% Updates
%

result = 0;

%% Build default BatchOpt from the currently active dataset
PossibleOptions = {'m', 'cm', 'mm', 'um', 'nm'};
pixSizeTemp = obj.mibModel.I{obj.mibModel.id}.image.pixSize;

BatchOpt = struct();
BatchOpt.VoxelX    = num2str(pixSizeTemp.x);
BatchOpt.VoxelY    = num2str(pixSizeTemp.y);
BatchOpt.VoxelZ    = num2str(pixSizeTemp.z);
BatchOpt.VoxelT    = num2str(pixSizeTemp.t);
BatchOpt.Units     = {pixSizeTemp.units};
BatchOpt.Units{2}  = PossibleOptions;
BatchOpt.TimeUnits = pixSizeTemp.tunits;
BatchOpt.id        = obj.mibModel.id;

BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
BatchOpt.mibBatchActionName  = 'Voxels';
BatchOpt.mibBatchTooltip.VoxelX    = 'Voxel size in the X-dimension';
BatchOpt.mibBatchTooltip.VoxelY    = 'Voxel size in the Y-dimension';
BatchOpt.mibBatchTooltip.VoxelZ    = 'Voxel size in the Z-dimension';
BatchOpt.mibBatchTooltip.VoxelT    = 'Time step for time-series datasets';
BatchOpt.mibBatchTooltip.Units     = 'Physical units for X/Y/Z calibration';
BatchOpt.mibBatchTooltip.TimeUnits = 'Time units';

%% Handle batch mode (3rd argument provided)
if nargin == 3
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)    % caller requests default options
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        else
            errorOpts.mibPath      = obj.mibModel.mibPath;
            errorOpts.WindowHeight = 150;
            utils.dlgs.showErrorDialog(obj.view.gui, ...
                'A structure is required as the 3rd parameter!', ...
                'BatchOpt Error', 'Error in MibRibbon.updateVoxelSizes', '', errorOpts);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%% Determine new pixSize — interactive dialog OR from arguments
if nargin < 2 || isempty(pixSize)
    if nargin < 2
        %% Interactive mode: delegate to utils.updatePixSizeAndResolution dialog
        dlgOpts.showDialog   = true;
        dlgOpts.ParentFigure = obj.view.gui;
        dlgOpts.mibPath      = obj.mibModel.mibPath;
        dlgOpts.HelpUrl      = fullfile(obj.mibModel.mibPath, ...
            'techdoc', 'html', 'user-interface', 'menu', 'dataset', 'index.html#parameters');

        [~, pixSize, dlgResult] = utils.updatePixSizeAndResolution([], pixSizeTemp, dlgOpts);
        if dlgResult == 0; return; end   % user cancelled dialog
    else
        % Batch mode without explicit pixSize: build from BatchOpt
        pixSize.x      = str2double(BatchOpt.VoxelX);
        pixSize.y      = str2double(BatchOpt.VoxelY);
        pixSize.z      = str2double(BatchOpt.VoxelZ);
        pixSize.t      = str2double(BatchOpt.VoxelT);
        pixSize.units  = BatchOpt.Units{1};
        pixSize.tunits = BatchOpt.TimeUnits;
    end
end

%% Apply new pixSize to the dataset
ds = obj.mibModel.I{BatchOpt.id};

newPixSize = ds.image.pixSize;
if isfield(pixSize, 'x');      newPixSize.x      = pixSize.x;      end
if isfield(pixSize, 'y');      newPixSize.y      = pixSize.y;      end
if isfield(pixSize, 'z');      newPixSize.z      = pixSize.z;      end
if isfield(pixSize, 't');      newPixSize.t      = pixSize.t;      end
if isfield(pixSize, 'units');  newPixSize.units  = pixSize.units;  end
if isfield(pixSize, 'tunits'); newPixSize.tunits = pixSize.tunits; end
ds.setPixSize(newPixSize);

% Recalculate bounding box extents from updated voxel sizes (origin unchanged)
ds.image.boundingBox(2) = ds.image.boundingBox(1) + (ds.image.width  - 1) * ds.image.pixSize.x;
ds.image.boundingBox(4) = ds.image.boundingBox(3) + (ds.image.height - 1) * ds.image.pixSize.y;
ds.image.boundingBox(6) = ds.image.boundingBox(5) + (ds.image.depth  - 1) * ds.image.pixSize.z;

%% Refresh view: update axes limits then redraw image
Options.mode  = 'resize';
Options.index = BatchOpt.id;
eventdata = core.ToggleEventData(Options);
notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);
notify(obj.mibModel, 'ShowImage');

%% Sync batch processing system with applied values
BatchOpt.VoxelX    = num2str(ds.image.pixSize.x);
BatchOpt.VoxelY    = num2str(ds.image.pixSize.y);
BatchOpt.VoxelZ    = num2str(ds.image.pixSize.z);
BatchOpt.VoxelT    = num2str(ds.image.pixSize.t);
BatchOpt.Units     = {ds.image.pixSize.units};
BatchOpt.Units{2}  = PossibleOptions;
BatchOpt.TimeUnits = ds.image.pixSize.tunits;

BatchOpt  = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj.mibModel, 'SyncBatch', eventdata);

result = 1;
end
