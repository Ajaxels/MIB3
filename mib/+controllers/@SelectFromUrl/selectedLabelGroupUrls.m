function labelGroupUrls = selectedLabelGroupUrls(obj)
% SELECTEDLABELGROUPURLS - Absolute URLs of every label group currently picked.
%
% Syntax:
%   .. code-block:: matlab
%
%      labelGroupUrls = obj.selectedLabelGroupUrls()
%
% ``BatchOpt.LabelGroups`` holds the whole multi-selection as a semicolon-
% separated list of paths relative to the container root - text, so a recorded
% protocol replays without a network browse, and semicolons because a URL path
% can contain a comma but not one of these.
%
% **Order is the pick order and it is load-bearing**: where two classes overlap,
% the later pick wins, so the list must never be sorted on the way through.
%
% Falls back to the single ``GroupPath`` when no multi-selection was made, which
% is what makes a one-class crop work with no extra state.
%
% Output Arguments:
%   - **labelGroupUrls** - {1xN cell} absolute URLs, in pick order

labelGroupUrls = {};
if isempty(obj.rootUrl); return; end

relativePaths = strtrim(split(string(obj.BatchOpt.LabelGroups), ';'));
relativePaths(relativePaths == "") = [];

if isempty(relativePaths)
    if isempty(obj.BatchOpt.GroupPath); return; end
    relativePaths = string(obj.BatchOpt.GroupPath);
end

labelGroupUrls = cell(1, numel(relativePaths));
for pathIndex = 1:numel(relativePaths)
    labelGroupUrls{pathIndex} = io.RemoteStore.join(obj.rootUrl, char(relativePaths(pathIndex)));
end
end
