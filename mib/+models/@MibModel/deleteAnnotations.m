function deleteAnnotations(obj, BatchOptIn)
% function deleteAnnotations(obj, BatchOptIn)
% Delete all annotations from the active dataset
%
% Backs up the current annotation state for undo, removes all annotations,
% and fires the UpdateAnnotations event so any listening views can refresh.
%
% Parameters:
% BatchOptIn: [@em optional] struct for batch processing mode; when NaN,
%   returns default options via the 'SyncBatch' event
% @li .id -> [@em optional] dataset index 1-9,
%   default = obj.getActiveId()
%
% Return values:
%   (none)
%

%|
% @b Examples:
% @code obj.mibModel.deleteAnnotations();  // delete all annotations from the active dataset @endcode
% @code
% BatchOpt.id = 1;
% obj.mibModel.deleteAnnotations(BatchOpt);  // batch call on dataset 1
% @endcode

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
