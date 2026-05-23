function imgOut = applyFilter(obj, imgIn)
% APPLYFILTER - Apply CLAHE to a supplied image (preview) or to the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       imgOut = obj.applyFilter(imgIn)   % preview mode: apply and return
%       obj.applyFilter()                 % full mode: read model, apply, write back
%
% Input Arguments:
%   - **imgIn** *(optional)* — [numeric] 2-D or H×W×C image to process in preview mode.
%     When omitted the filter is applied to the full dataset region defined by
%     ``BatchOpt.DatasetType``.
%
% Output Arguments:
%   - **imgOut** — [numeric] filtered image (only populated in preview mode).
%

imgOut = [];

if nargin > 1 && ~isempty(imgIn)
    % Preview mode: process the supplied image, return result
    imgOut = applyAdapthisteq(imgIn, obj.BatchOpt);
    return;
end

id = obj.BatchOpt.id;

% Virtual stacking guard
if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
    utils.dlgs.showErrorDialog(obj.mibGUI, ...
        ['CLAHE contrast adjustment is not available in virtual stacking mode.' newline ...
         'Please switch to memory-resident mode and try again.'], ...
        'Not implemented');
    return;
end

% Indexed color guard
if strcmp(obj.mibModel.I{id}.image.colorType, 'indexed')
    utils.dlgs.showErrorDialog(obj.mibGUI, ...
        ['Please convert the image to grayscale or multi-channel format first.' newline ...
         'Ribbon -> Image -> Mode'], 'Change format!');
    return;
end

%% Determine z / t ranges from DatasetType
maxZ = obj.mibModel.I{id}.image.depth;
maxT = obj.mibModel.I{id}.image.time;

switch obj.BatchOpt.DatasetType{1}
    case 'Shown slice (2D)'
        zRange = repmat(obj.mibModel.I{id}.slices{3}(1), 1, 2);
        tRange = repmat(obj.mibModel.I{id}.slices{5}(1), 1, 2);
    case 'Current stack (3D)'
        zRange = [1, maxZ];
        tRange = repmat(obj.mibModel.I{id}.slices{5}(1), 1, 2);
    case 'Complete volume (4D)'
        zRange = [1, maxZ];
        tRange = [1, maxT];
end

%% Backup (single time point only)
if tRange(1) == tRange(2)
    backupOpt.z  = zRange;
    backupOpt.t  = tRange;
    backupOpt.id = id;
    obj.mibModel.backup('image', 1, backupOpt);
end

%% Determine color channels
switch obj.BatchOpt.ColorChannel{1}
    case 'All'
        colorChannel = 1:obj.mibModel.I{id}.image.colors;
    case 'Displayed'
        colorChannel = obj.mibModel.I{id}.selectedColorChannel;
    otherwise
        colorChannel = str2double(obj.BatchOpt.ColorChannel{1}(7:end));
end

%% Process slices
nSteps = (tRange(2) - tRange(1) + 1) * (zRange(2) - zRange(1) + 1) * numel(colorChannel);
if obj.BatchOpt.showWaitbar
    waitbarHandle = uiprogressdlg(obj.mibGUI, 'Value', 0, ...
        'Message', sprintf('Applying CLAHE\nPlease wait...'), 'Title', 'CLAHE', ...
        'Cancelable', 'on');
    progressStep = floor(nSteps/20);
end
stepIndex = 0;
getDataOptions.id = id;
cancelRequested = false;

for colCh = colorChannel
    if cancelRequested; break; end
    for t = tRange(1):tRange(2)
        if cancelRequested; break; end
        getDataOptions.t = [t, t];
        for z = zRange(1):zRange(2)
            sliceData = obj.mibModel.getData2D('image', z, [], colCh, getDataOptions);
            for roiIdx = 1:numel(sliceData)
                sliceData{roiIdx} = applyAdapthisteq(sliceData{roiIdx}, obj.BatchOpt);
            end
            obj.mibModel.setData2D(sliceData, 'image', z, [], colCh, getDataOptions);

            if obj.BatchOpt.showWaitbar && mod(stepIndex, progressStep) == 0
                waitbarHandle.Value = stepIndex / nSteps;
                waitbarHandle.Message = sprintf('Applying CLAHE (slice %d of %d)\nPlease wait...', stepIndex, nSteps);
                if waitbarHandle.CancelRequested
                    cancelRequested = true;
                    break;
                end
            end
            stepIndex = stepIndex + 1;
        end
    end
end

if obj.BatchOpt.showWaitbar; delete(waitbarHandle); end
if cancelRequested; notify(obj.mibModel, 'ShowImage'); return; end

%% Persist parameters to session settings
obj.mibModel.sessionSettings.CLAHE.NumTiles     = [obj.BatchOpt.NumTilesY{1}, obj.BatchOpt.NumTilesX{1}];
obj.mibModel.sessionSettings.CLAHE.ClipLimit    = obj.BatchOpt.ClipLimit{1};
obj.mibModel.sessionSettings.CLAHE.NBins        = obj.BatchOpt.NBins{1};
obj.mibModel.sessionSettings.CLAHE.Distribution = obj.BatchOpt.Distribution{1};
obj.mibModel.sessionSettings.CLAHE.Alpha        = obj.BatchOpt.Alpha{1};

logText = sprintf('CLAHE; NumTiles: [%d %d]; ClipLimit: %.4f; NBins: %d; Distribution: %s; Alpha: %.3f; ColCh: %s', ...
    obj.BatchOpt.NumTilesY{1}, obj.BatchOpt.NumTilesX{1}, ...
    obj.BatchOpt.ClipLimit{1}, obj.BatchOpt.NBins{1}, ...
    obj.BatchOpt.Distribution{1}, obj.BatchOpt.Alpha{1}, ...
    obj.BatchOpt.ColorChannel{1});
obj.mibModel.I{id}.image.updateActionLog(logText);

obj.returnBatchOpt();
notify(obj.mibModel, 'ShowImage');
end

% -----------------------------------------------------------------------
function imgOut = applyAdapthisteq(imgIn, BatchOpt)
% APPLYADAPTHISTEQ - Apply adapthisteq to imgIn using the current BatchOpt.
% Handles multi-channel images by processing each channel independently.
% Supports 2-D and H×W×C inputs.
numTiles     = [BatchOpt.NumTilesY{1}, BatchOpt.NumTilesX{1}];
clipLimit    = BatchOpt.ClipLimit{1};
nBins        = BatchOpt.NBins{1};
distribution = BatchOpt.Distribution{1};
alpha        = BatchOpt.Alpha{1};

nChannels = size(imgIn, 3);
imgOut = imgIn;
for ch = 1:nChannels
    if strcmp(distribution, 'uniform')
        imgOut(:,:,ch) = adapthisteq(imgIn(:,:,ch), ...
            'NumTiles',    numTiles, ...
            'ClipLimit',   clipLimit, ...
            'NBins',       nBins, ...
            'Distribution', distribution);
    else
        imgOut(:,:,ch) = adapthisteq(imgIn(:,:,ch), ...
            'NumTiles',    numTiles, ...
            'ClipLimit',   clipLimit, ...
            'NBins',       nBins, ...
            'Distribution', distribution, ...
            'Alpha',       alpha);
    end
end
end
