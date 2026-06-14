function imgOut = applyFilter(obj, imgIn, maskIn)
% APPLYFILTER - Apply content-aware fill to a supplied image (preview) or to the dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       imgOut = obj.applyFilter(imgIn, maskIn)   % preview mode
%       obj.applyFilter()                          % full dataset mode
%
% Input Arguments:
%   - **imgIn** *(optional)* — [numeric] H×W or H×W×C image for preview mode.
%   - **maskIn** *(optional)* — [logical] H×W binary mask for preview mode.
%
% Output Arguments:
%   - **imgOut** — [numeric] filled image (preview mode only).
%

imgOut = [];

if nargin > 1 && ~isempty(imgIn)
    imgOut = applyInpaint(imgIn, maskIn, obj.BatchOpt);
    return;
end

id = obj.BatchOpt.id;

if any(obj.mibModel.I{id}.datasetType(1) == ['V' 'B'])
    utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), ...
        ['Content-aware fill is not available in virtual or BigData mode.' newline ...
         'Please switch to memory-resident mode and try again.'], ...
        'Not implemented');
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

%% Backup (single time point only; skip for 4D and batch mode)
if tRange(1) == tRange(2) && ~isempty(obj.view)
    backupOpt.z  = zRange;
    backupOpt.t  = tRange;
    backupOpt.id = id;
    obj.mibModel.backup('image', 1, backupOpt);
end

%% Process slices
colorChannels = 1:obj.mibModel.I{id}.image.colors;
nSteps = (tRange(2) - tRange(1) + 1) * (zRange(2) - zRange(1) + 1) * numel(colorChannels);

if obj.BatchOpt.showWaitbar
    waitbarHandle = uiprogressdlg(obj.mibModel.getProgressBarParent(), 'Value', 0, ...
        'Message', sprintf('Applying content-aware fill\nPlease wait...'), ...
        'Title', 'Content-aware fill', 'Cancelable', 'on');
    progressStep = max(1, floor(nSteps / 20));
end
stepIndex = 0;
getDataOptions.id = id;
cancelRequested = false;

for colCh = colorChannels
    if cancelRequested; break; end
    for t = tRange(1):tRange(2)
        if cancelRequested; break; end
        getDataOptions.t = [t, t];
        for z = zRange(1):zRange(2)
            imageData = obj.mibModel.getData2D('image',              z, [], colCh, getDataOptions);
            maskData  = obj.mibModel.getData2D(obj.BatchOpt.Mask{1}, z, [], 0,     getDataOptions);

            for roiIdx = 1:numel(imageData)
                mask = logical(maskData{roiIdx});
                if any(mask(:))
                    imageData{roiIdx} = applyInpaint(imageData{roiIdx}, mask, obj.BatchOpt);
                end
            end
            obj.mibModel.setData2D(imageData, 'image', z, [], colCh, getDataOptions);

            if obj.BatchOpt.showWaitbar && mod(stepIndex, progressStep) == 0
                waitbarHandle.Value = stepIndex / nSteps;
                waitbarHandle.Message = sprintf('Content-aware fill (slice %d of %d)\nPlease wait...', ...
                    stepIndex, nSteps);
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
obj.mibModel.sessionSettings.contentAwareFill.Method      = obj.BatchOpt.Method{1};
obj.mibModel.sessionSettings.contentAwareFill.Mask        = obj.BatchOpt.Mask{1};
obj.mibModel.sessionSettings.contentAwareFill.DatasetType = obj.BatchOpt.DatasetType{1};
obj.mibModel.sessionSettings.contentAwareFill.FillOrder   = obj.BatchOpt.FillOrder{1};

logText = sprintf('ContentAwareFill; Method: %s; Mask: %s; Radius: %d; SmoothingFactor: %d; FillOrder: %s', ...
    obj.BatchOpt.Method{1}, obj.BatchOpt.Mask{1}, ...
    obj.BatchOpt.Radius{1}, obj.BatchOpt.SmoothingFactor{1}, obj.BatchOpt.FillOrder{1});
obj.mibModel.I{id}.image.updateActionLog(logText);

obj.returnBatchOpt();
notify(obj.mibModel, 'ShowImage');
end

% -----------------------------------------------------------------------
function imgOut = applyInpaint(imgIn, mask, BatchOpt)
% APPLYINPAINT - Apply the selected inpaint function across all channels.
% Handles grayscale (H×W) and multi-channel (H×W×C) inputs.
radius          = BatchOpt.Radius{1};
smoothingFactor = BatchOpt.SmoothingFactor{1};
fillOrder       = BatchOpt.FillOrder{1};
method          = BatchOpt.Method{1};

nChannels = size(imgIn, 3);
imgOut = imgIn;
for channel = 1:nChannels
    if strcmp(method, 'inpaintCoherent')
        imgOut(:,:,channel) = inpaintCoherent(imgIn(:,:,channel), mask, ...
            'SmoothingFactor', smoothingFactor, 'Radius', radius);
    else
        imgOut(:,:,channel) = inpaintExemplar(imgIn(:,:,channel), mask, ...
            'FillOrder', fillOrder, 'PatchSize', radius);
    end
end
end
