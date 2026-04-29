function squeezeMaterialLabels(obj, wb)
% SQUEEZEMATERIALLABELS - Renumber all label indices to a contiguous range starting at 1.
%
% Syntax:
%   function squeezeMaterialLabels(obj, wb)
%
% Iterates over every time-point and replaces the sparse set of unique
% label values with consecutive integers 1, 2, 3, ...  Background (0) is
% preserved.  This is useful for large model types (255/65535/4294967295)
% where materials may have been deleted, leaving gaps in the index space.
%
% After squeezing, obj.materialsCount is updated to reflect the new
% highest index across all time-points.  The caller should typically invoke
% MibModel.addMaterial() to re-register the next available material index.
%
% Input Arguments:
%   - **wb** — *(optional)* handle to a uiprogressdlg used for progress display;
%     when empty no progress is reported.
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.labels.squeezeMaterialLabels();% squeeze without progress
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.labels.squeezeMaterialLabels(wb);% squeeze with progress bar
%

% Updates
%

if nargin < 2; wb = []; end

numT = obj.time;
maxLabel = 0;

for t = 1:numT
    img = obj.data{1}(:,:,:,1,t);
    [a, ~, c] = unique(img);
    if a(1) == 0; c = c - 1; end   % keep background at 0
    obj.data{1}(:,:,:,1,t) = reshape(cast(c, class(img)), size(img));

    % Track the highest label across all time-points
    nLabels = numel(a);
    if a(1) == 0; nLabels = nLabels - 1; end   % don't count background
    maxLabel = max(maxLabel, nLabels);

    if ~isempty(wb); wb.Value = t / numT; end
end

obj.materialsCount = maxLabel;
end
