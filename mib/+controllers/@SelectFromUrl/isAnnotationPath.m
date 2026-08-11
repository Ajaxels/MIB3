function tf = isAnnotationPath(obj, groupUrl)
% ISANNOTATIONPATH - Does this group live inside an OME-NGFF labels container?
%
% Syntax:
%   .. code-block:: matlab
%
%      tf = obj.isAnnotationPath(groupUrl)
%
% True when any component of the group's path below the container root is named
% ``labels``. OME-NGFF makes that name the container convention for annotations,
% so this is reading a declared structure rather than guessing from a name.
%
% Used to keep :meth:`resolveSiblingImageGroup` from offering an annotation as
% the image to load annotations onto. The case that forces it is ``crop1/all``,
% the merged ground truth: it is a genuine multiscales pyramid, it carries no
% ``cellmap`` annotation block, and it encloses the crop exactly, so nothing
% about its own content distinguishes it from the EM volume. Its path does.
%
% Input Arguments:
%   - **groupUrl** - [char] URL of the group to test
%
% Output Arguments:
%   - **tf** - [logical] true when the group is inside a labels container

tf = false;
if isempty(groupUrl) || isempty(obj.rootUrl); return; end

relativePath = io.RemoteStore.relativePath(obj.rootUrl, groupUrl);
parts = split(string(relativePath), '/');
tf = any(strcmpi(parts, "labels"));
end
