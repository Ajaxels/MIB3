function BatchOpt = updateBatchOptCombineFields_Shared(BatchOpt, BatchOptInput)
% UPDATEBATCHOPTCOMBINEFIELDS_SHARED - Merge BatchOpt fields from an input struct into a default struct.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      BatchOpt = updateBatchOptCombineFields_Shared(BatchOpt, BatchOptInput)
%
% Used by all tools that support Batch mode to merge caller-supplied options
% into the controller's full default BatchOpt.  Handles popup-menu cells
% (preserving the options list), numeric edit fields, and plain values.
%
% Input Arguments:
%   - **BatchOpt** — struct containing the full default BatchOpt for the controller
%   - **BatchOptInput** — struct supplied by the caller (may be a subset of fields)
%
% Output Arguments:
%   - **BatchOpt** — merged struct with caller values applied over defaults
%
% Usage:
%
%   **Example 1** — merge user-supplied options into controller defaults
%
%   .. code-block:: matlab
%
%      BatchOpt = utils.updateBatchOptCombineFields_Shared(BatchOpt, BatchOptInput);
%

BatchOptInputFields = fieldnames(BatchOptInput);
for i=1:numel(BatchOptInputFields)
    % check for popup menu, update only the first element, because the second element provides the list of options
    
%     if strcmp(BatchOptInputFields{i}, 'Architecture')
%         0;
%     end

    if iscell(BatchOptInput.(BatchOptInputFields{i})) || ...
            (isfield(BatchOpt, BatchOptInputFields{i}) && ...
             ~isempty(BatchOpt.(BatchOptInputFields{i})) && ...
             iscell(BatchOpt.(BatchOptInputFields{i})(1)))
        % convert to cell, this happens when the struct initialized as
        % "BatchOpt = struct('Mode', {'Add set'}, 'SetName', 'Set 1');"
        if ischar(BatchOptInput.(BatchOptInputFields{i})); BatchOptInput.(BatchOptInputFields{i}) = {BatchOptInput.(BatchOptInputFields{i})}; end 
        if isempty(BatchOptInput.(BatchOptInputFields{i}))
            BatchOpt.(BatchOptInputFields{i})(1) = {''};
        else
            if isfield(BatchOpt, BatchOptInputFields{i})
                % take only the first element
                %try
                BatchOpt.(BatchOptInputFields{i})(1) = BatchOptInput.(BatchOptInputFields{i})(1);
                %catch err
                %    0
                %end
            else    % take all elements
                for indexId = 1:numel(BatchOptInput.(BatchOptInputFields{i}))
                    BatchOpt.(BatchOptInputFields{i})(indexId) = BatchOptInput.(BatchOptInputFields{i})(indexId);
                end
            end
            % BatchOpt.(BatchOptInputFields{i})(1) = BatchOptInput.(BatchOptInputFields{i})(1);
        end
    else
        BatchOpt.(BatchOptInputFields{i}) = BatchOptInput.(BatchOptInputFields{i});
    end
end
