function Calculate(obj, batchModeSwitch)
% CALCULATE - Apply morphological operations to the selection layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.Calculate()
%       obj.Calculate(batchModeSwitch)
%
% Input Arguments:
%   - **batchModeSwitch** — *(optional)* logical; when ``true`` skips backup
%     and ``returnBatchOpt`` call (default ``false``)
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MorphOps.Calculate: triggered\n');
end
if nargin < 2; batchModeSwitch = false; end

id    = obj.BatchOpt.id;
is2D  = ~obj.BatchOpt.Objects3D;

% define parent window
if isempty(obj.view)   % headless batch mode
    parentFigure = obj.mibModel.mibGUI;
else
    parentFigure = obj.view.gui;
end
if obj.BatchOpt.showWaitbar
    progressBar = uiprogressdlg(parentFigure, 'Value', 0, 'Cancelable', 'on', ...
        'Message', 'Please wait...', 'Title', 'Morphological operations');
end

if obj.mibModel.I{id}.enableSelection == 0
    if obj.BatchOpt.showWaitbar; delete(progressBar); end
    return;
end

depth = obj.mibModel.I{id}.image.depth;
time  = obj.mibModel.I{id}.image.time;

getDataOptions.roiId = -1;
getDataOptions.id    = id;

%% Backup — only for single time-frame datasets (too expensive for 4D)
if ~batchModeSwitch && time == 1
    datasetSwitch = strcmp(obj.BatchOpt.ApplyTo{1}, 'Stack') || ~is2D;
    backupOptions.id = id;
    obj.mibModel.backup('selection', datasetSwitch, backupOptions);
end

%% Processing loop
for t = 1:time
    getDataOptions.t = [t t];

    if is2D
        datasetSwitch = strcmp(obj.BatchOpt.ApplyTo{1}, 'Stack');

        if datasetSwitch
            % Whole stack: process each Z slice
            for z = 1:depth
                selSlice   = cell2mat(obj.mibModel.getData2D('selection', z, [], [], getDataOptions));
                morphedSel = obj.applyMorphOp2D(selSlice);
                obj.mibModel.setData2D(morphedSel, 'selection', z, [], [], getDataOptions);

                if obj.BatchOpt.showWaitbar && mod(z, 10) == 0
                    if progressBar.CancelRequested
                        delete(progressBar);
                        return;
                    end
                    progressBar.Value = ((t - 1) * depth + z) / (time * depth);
                end
            end
        else
            % Current slice only
            selSlice   = cell2mat(obj.mibModel.getData2D('selection', [], [], [], getDataOptions));
            morphedSel = obj.applyMorphOp2D(selSlice);
            obj.mibModel.setData2D(morphedSel, 'selection', [], [], [], getDataOptions);
        end

        if obj.BatchOpt.showWaitbar && ~datasetSwitch
            if progressBar.CancelRequested; delete(progressBar); return; end
            progressBar.Value = t / time;
        end

    else
        % 3D mode: operate on the full 3D volume
        operation = obj.BatchOpt.MorphOperation{1};
        iterNo    = obj.BatchOpt.Iterations{1};

        selection = obj.mibModel.getData3D('selection', t, 3, [], getDataOptions);
        for roiId = 1:numel(selection)
            if strcmp(operation, 'skel')
                selection{roiId} = uint8(bwskel(logical(selection{roiId}), 'MinBranchLength', iterNo));
            else
                selection{roiId} = uint8(bwmorph3(selection{roiId}, operation));
            end
        end
        obj.mibModel.setData3D(selection, 'selection', t, 3, [], getDataOptions);

        if obj.BatchOpt.showWaitbar
            if progressBar.CancelRequested; delete(progressBar); return; end
            progressBar.Value = t / time;
        end
    end
end

if obj.BatchOpt.showWaitbar; delete(progressBar); end
notify(obj.mibModel, 'ShowImage');
if ~batchModeSwitch; obj.returnBatchOpt(); end

end
