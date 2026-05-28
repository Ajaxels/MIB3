function convertModel(obj, ModelType, BatchOptIn)
% CONVERTMODEL - Convert the segmentation model to a different type.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.convertModel()
%       obj.convertModel(ModelType)
%       obj.convertModel(ModelType, BatchOptIn)
%
% Converts the segmentation model between capacity types (63, 255, 65535,
% 4294967295 materials) or generates a new model where each connected
% object receives a unique index (2D or 3D connectivity).
%
% Changing between integer types adjusts memory usage and the maximum
% number of materials.  Converting to an indexed-object type reruns
% connected-component labelling on all materials and replaces the model
% with per-object indices.
%
% Input Arguments:
%   - **ModelType** *(optional)* — numeric model type to convert to:
%
%     - ``63``         — packed uint8; mask and selection stored in bits 7–8
%     - ``255``        — separate uint8 labels layer
%     - ``65535``      — separate uint16 labels layer
%     - ``4294967295`` — separate uint32 labels layer
%     - ``2.4``        — detect 2D objects (connectivity 4) and index them
%     - ``2.8``        — detect 2D objects (connectivity 8) and index them
%     - ``3.6``        — detect 3D objects (connectivity 6) and index them
%     - ``3.26``       — detect 3D objects (connectivity 26) and index them
%
%   - **BatchOptIn** *(optional)* — structure for batch processing; pass
%     ``NaN`` to return default options via ``SyncBatch`` event
%
%     - ``.ModelType``    — cell string dropdown, first element is selected value
%     - ``.showWaitbar``  — logical, show or not the waitbar [*default* ``true``]
%     - ``.id``           — *(optional)* dataset index 1–9; default = active dataset
%
% Output Arguments:
%   (none)
%
% **Example 1** — convert current model to 255-material type
%
%   .. code-block:: matlab
%
%      obj.mibModel.convertModel(255);
%
% **Example 2** — batch call
%
%   .. code-block:: matlab
%
%      BatchOpt.ModelType = {'65535'};
%      obj.mibModel.convertModel([], BatchOpt);
%

% Updates
% Ported from MIB2 mibModel.convertModel

if nargin < 2; ModelType = []; end

%% Declaration of the BatchOpt structure
BatchOpt = struct();
if ~isempty(ModelType)
    switch ModelType
        case 2.4;  BatchOpt.ModelType = {'indexed objects 2D/4'};
        case 2.8;  BatchOpt.ModelType = {'indexed objects 2D/8'};
        case 3.6;  BatchOpt.ModelType = {'indexed objects 3D/6'};
        case 3.26; BatchOpt.ModelType = {'indexed objects 3D/26'};
        otherwise; BatchOpt.ModelType = {num2str(ModelType)};
    end
else
    BatchOpt.ModelType = {'63'};
end
BatchOpt.ModelType{2} = {'63', '255', '65535', '4294967295', ...
    'indexed objects 2D/4', 'indexed objects 2D/8', ...
    'indexed objects 3D/6', 'indexed objects 3D/26'};

BatchOpt.showWaitbar = true;
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Ribbon -> Model';
BatchOpt.mibBatchActionName  = 'Convert type';
BatchOpt.mibBatchTooltip.ModelType   = 'Type of model to convert to; higher capacity types use more memory';
BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not the progress bar during execution';

%% Batch mode check actions
if nargin == 3
    if isstruct(BatchOptIn) == 0
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.convertModel';
            ErrorDlgOpt.err = 'A structure as the 3rd parameter is required!';
            ErrorDlgOpt.WindowHeight = 150;
            eventdata = core.ToggleEventData(ErrorDlgOpt);
            notify(obj, 'ShowErrorDialog', eventdata);
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

dlgOpt.mibPath = obj.mibPath;

%% Virtual stacking guard
if strcmp(obj.I{BatchOpt.id}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'Not available in virtual stacking mode!', {''}, ...
        {'Model type conversion requires memory-resident mode. Please switch to standard mode and try again.'}, ...
        'Virtual mode', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Initial checks
if obj.I{BatchOpt.id}.enableSelection == 0
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'The models are switched off!', {''}, ...
        {'Please enable the "Enable selection" option in Preferences (Ribbon -> Home -> Preferences) and try again.'}, ...
        'Models are disabled', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

if ~obj.I{BatchOpt.id}.modelExist
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.mibGUI, 'No model exists!', {''}, ...
        {'Please create a model first (Ribbon -> Models -> New Model).'}, ...
        'No model', dlgOpt);
    notify(obj, 'StopProtocol');
    return;
end

%% Map string → numeric model type
switch BatchOpt.ModelType{1}
    case 'indexed objects 2D/4';  modelType = 2.4;
    case 'indexed objects 2D/8';  modelType = 2.8;
    case 'indexed objects 3D/6';  modelType = 3.6;
    case 'indexed objects 3D/26'; modelType = 3.26;
    otherwise;                    modelType = str2double(BatchOpt.ModelType{1});
end

%% Early-exit if already the requested type
if modelType == obj.I{BatchOpt.id}.labels.maxMaterials; return; end

%% Guard: indexed-object detection only works for 63/255-material models
if modelType < 4 && obj.I{BatchOpt.id}.labels.maxMaterials > 256
    utils.dlgs.showErrorDialog(obj.mibGUI, ...
        'Indexed-object detection is only supported for models with 63 or 255 materials.', ...
        'Wrong model type');
    notify(obj, 'StopProtocol');
    return;
end

%% Perform conversion
wb = [];
if BatchOpt.showWaitbar
    wb = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
        'Message', sprintf('Converting model to "%s", please wait...', BatchOpt.ModelType{1}), ...
        'Title', 'Convert model');
end

obj.I{BatchOpt.id}.convertModel(modelType, wb);

if BatchOpt.showWaitbar; wb.Value = 1; end

notify(obj, 'UpdateGuiWidgets', core.ToggleEventData({'ribbonModel', 'checkboxes'}));
notify(obj, 'ShowImage');

% Notify batch mode
BatchOpt = rmfield(BatchOpt, 'id');
eventdata = core.ToggleEventData(BatchOpt);
notify(obj, 'SyncBatch', eventdata);

if BatchOpt.showWaitbar; delete(wb); end
end
