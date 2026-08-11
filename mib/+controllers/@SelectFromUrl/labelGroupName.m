function groupName = labelGroupName(~, groupUrl, pyramidInfo)
% LABELGROUPNAME - Short, readable name for a label group.
%
% Syntax:
%   .. code-block:: matlab
%
%      groupName = obj.labelGroupName(groupUrl, pyramidInfo)
%
% Prefers the ``class_name`` the store declares, which is what a single-class
% COSEM group carries. Groups without a ``cellmap`` block - the merged ``all``
% of a crop - have no declared name, so the last path segment of the URL is
% used.
%
% That fallback used to be ``relativePath(join(url, '..'), url)``, which does not
% work: ``io.RemoteStore.join`` appends ``..`` rather than resolving it, so
% ``relativePath`` found no common prefix and returned the **whole URL** - which
% then became the material name shown in the Segmentation panel.
%
% Input Arguments:
%   - **groupUrl** - [char] URL of the group
%   - **pyramidInfo** - [struct] from :meth:`readGroupPyramid`
%
% Output Arguments:
%   - **groupName** - [char] e.g. ``'mito_mem'`` or ``'all'``

if ~isempty(pyramidInfo) && isstruct(pyramidInfo) && ~isempty(pyramidInfo.className)
    groupName = pyramidInfo.className;
    return;
end

segments = split(string(strip(char(groupUrl), 'right', '/')), '/');
groupName = char(segments(end));
if isempty(groupName); groupName = 'labels'; end
end
