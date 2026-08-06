function deleteAnnotations(obj, BatchOptIn)
% DELETEANNOTATIONS - Delete all annotations from the active dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.deleteAnnotations(BatchOptIn)
%
% Backs up the current annotation state for undo, removes all annotations,
% and fires the UpdateAnnotations event so any listening views can refresh.
%
% Input Arguments:
%   - **BatchOptIn** - *(optional)* struct for batch processing mode; when NaN,
%     returns default options via the 'SyncBatch' event
%
%     - ``.id`` - *(optional)* dataset index 1-9, default = obj.getActiveId()
%
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** - delete all annotations from the active dataset
%
%   .. code-block:: matlab
%
%      obj.mibModel.deleteAnnotations();
%
%   **Example 2** - batch call on dataset 1
%
%   .. code-block:: matlab
%
%      BatchOpt.id = 1;
%      obj.mibModel.deleteAnnotations(BatchOpt);
%

% Updates
%

%% Declaration of the BatchOpt structure
BatchOpt = struct();
BatchOpt.id = obj.getActiveId();

BatchOpt.mibBatchSectionName = 'Panel -> Segmentation';
BatchOpt.mibBatchActionName  = 'Delete all annotations';

%%
if nargin == 2   % batch mode
    if ~isstruct(BatchOptIn)
        if isnan(BatchOptIn)
            BatchOpt = rmfield(BatchOpt, 'id');
            eventdata = core.ToggleEventData(BatchOpt);
            notify(obj, 'SyncBatch', eventdata);
        else
            ErrorDlgOpt.winTitle = 'BatchOpt Error';
            ErrorDlgOpt.optionalPrefix = 'Error in MibModel.deleteAnnotations';
            ErrorDlgOpt.err = 'A structure as the 2nd parameter is required!';
            ErrorDlgOpt.WindowHeight = 150;
            notify(obj, 'ShowErrorDialog', core.ToggleEventData(ErrorDlgOpt));
        end
        return;
    else
        BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptIn);
    end
end

%%
obj.backup('annotations', 0, struct('id', BatchOpt.id));
obj.I{BatchOpt.id}.annotations.removeLabels();
notify(obj, 'UpdateAnnotations');
notify(obj, 'ShowImage');
end
