function [imageGroupUrl, imagePyramid] = resolveSiblingImageGroup(obj, labelGroupUrl, labelPyramid)
% RESOLVESIBLINGIMAGEGROUP - Find the image volume a label crop was cut from.
%
% Syntax:
%   .. code-block:: matlab
%
%      [imageGroupUrl, imagePyramid] = obj.resolveSiblingImageGroup(labelGroupUrl, labelPyramid)
%
% Walks up from the label group towards the container root, listing each level
% on the way, and takes the first multiscales group that is **not** an
% annotation and whose world box **contains** the crop.
%
% Two tests, and both are needed:
%
%   * **Not under a ``labels`` path.** OME-NGFF makes ``labels/`` the container
%     convention for annotations, so this is a rule rather than a guess about
%     names. It is also the only thing that rejects the merged ground truth:
%     ``crop1/all`` is a pyramid, carries no ``cellmap`` annotation block, and
%     encloses the crop exactly, so every content-based test accepts it. It is a
%     sibling annotation, not the image.
%   * **Containment.** A container can publish several volumes, and a group name
%     says nothing reliable about which one a crop came from, while the
%     coordinates say it exactly.
%
% The path test is applied **before** any metadata is fetched, which is what
% keeps the walk cheap: passing back up through ``groundtruth`` rejects all 26
% crops of the reference store on their paths alone, without a request each.
%
% Walking up rather than searching down from the root also bounds the cost - the
% sibling of a crop is a handful of levels away, whereas a search from the root
% would descend into the ground-truth subtree first.
%
% Returns empty when nothing qualifies; the caller then asks the user for the
% path rather than guessing.
%
% Input Arguments:
%   - **labelGroupUrl** - [char] URL of the selected label group
%   - **labelPyramid** - [struct] its :meth:`readGroupPyramid` result
%
% Output Arguments:
%   - **imageGroupUrl** - [char] URL of the image group, ``''`` when none found
%   - **imagePyramid** - [struct] its readGroupPyramid result, ``[]`` when none

imageGroupUrl = '';
imagePyramid  = [];

if ~labelPyramid.ok || isempty(obj.rootUrl); return; end

labelToUm = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(labelPyramid.unit);
cropBoxUm = io.loaders.OmeZarrMetadataUtils.outerBoundingBox( ...
    labelPyramid.levelWorldBoxes(1, :), labelPyramid.levelVoxelSizesXYZ(1, :)) * labelToUm;

relativePath = io.RemoteStore.relativePath(obj.rootUrl, labelGroupUrl);
parts = split(string(relativePath), '/');
parts(parts == "") = [];

visitedUrls = strings(0);

% Ancestors nearest first: the image is usually a short way up and across, so
% checking the closest ones first keeps the common case to a few requests.
for depth = numel(parts)-1 : -1 : 0
    if depth == 0
        ancestorUrl = obj.rootUrl;
    else
        ancestorUrl = io.RemoteStore.join(obj.rootUrl, char(join(parts(1:depth), '/')));
    end

    childUrls = io.RemoteStore.listChildren(ancestorUrl);
    for childIndex = 1:numel(childUrls)
        childUrl = childUrls{childIndex};
        if any(visitedUrls == string(childUrl)); continue; end
        visitedUrls(end+1) = string(childUrl); %#ok<AGROW>
        if obj.isAnnotationPath(childUrl); continue; end

        candidate = obj.readGroupPyramid(childUrl);
        if candidate.ok
            if obj.imageBoxContains(candidate, cropBoxUm)
                imageGroupUrl = childUrl;
                imagePyramid  = candidate;
                return;
            end
            continue;
        end

        % Not a pyramid itself: look one level inside, which is where the
        % OpenOrganelle layout keeps the image ('recon-1/em/fibsem-uint8').
        grandUrls = io.RemoteStore.listChildren(childUrl);
        for grandIndex = 1:numel(grandUrls)
            if obj.isAnnotationPath(grandUrls{grandIndex}); continue; end
            grandCandidate = obj.readGroupPyramid(grandUrls{grandIndex});
            if obj.imageBoxContains(grandCandidate, cropBoxUm)
                imageGroupUrl = grandUrls{grandIndex};
                imagePyramid  = grandCandidate;
                return;
            end
        end
    end
end
end
