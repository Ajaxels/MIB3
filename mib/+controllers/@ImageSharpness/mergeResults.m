function merged = mergeResults(firstResults, secondResults)
% MERGERESULTS - Concatenate two results struct arrays whose fields may differ.
%
% Syntax:
%   .. code-block:: matlab
%
%      merged = controllers.ImageSharpness.mergeResults(firstResults, secondResults)
%
% Rows calculated by different versions of the tool can have different
% fields (``regionSource`` was added later, for example), and MATLAB
% refuses to concatenate such struct arrays. Fields missing on one side are
% added there with ``[]``; code reading an optional field checks it with
% ``isempty`` or ``isfield``. Used when new rows are appended in
% :func:`controllers.ImageSharpness.calculate` and when a saved file is
% added to the table in :func:`controllers.ImageSharpness.loadResults`.
%
% Input Arguments:
%   - **firstResults**, **secondResults** - [struct array or []] rows of
%     ``obj.results``
%
% Output Arguments:
%   - **merged** - [struct column] first rows followed by second rows
%

% Updates
%

if isempty(firstResults)
    merged = secondResults(:);
    return;
end
if isempty(secondResults)
    merged = firstResults(:);
    return;
end
firstResults = addMissingFields(firstResults(:), fieldnames(secondResults));
secondResults = addMissingFields(secondResults(:), fieldnames(firstResults));
secondResults = orderfields(secondResults, firstResults);
merged = [firstResults; secondResults];
end

function results = addMissingFields(results, fieldList)
missingFields = setdiff(fieldList, fieldnames(results), 'stable');
for fieldId = 1:numel(missingFields)
    [results.(missingFields{fieldId})] = deal([]);
end
end
