function connectBtn_Callback(obj, autoOpenPlainImage)
% CONNECTBTN_CALLBACK - Inspect the URL and prepare the dialog for it.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.connectBtn_Callback()
%      obj.connectBtn_Callback(true)   % Enter was pressed in the dialog
%
% Decides between the three cases the dialog has to handle, cheaply and in this
% order:
%
%   1. **a listable OME-Zarr container** - seed the tree with the root node, the
%      user expands from there, one request per level;
%   2. **an OME-Zarr container on a host with no directory listing** - hide the
%      tree and let the group path be typed instead. Most non-AWS OME-Zarr hosts
%      are in this category, so this path is not a corner case;
%   3. **anything else** - if ``imfinfo`` recognises it, fall back to the plain
%      image import this menu item has always done.
%
% Before any of that, an N5 container URL is redirected to the OME-Zarr copy
% published beside it - see :meth:`resolveN5Sibling`, which exists because the
% OpenOrganelle dataset pages hand out the N5 form of every volume.
%
% Input Arguments:
%   - **autoOpenPlainImage** - *(optional)* [logical] true when Enter was pressed
%     rather than the Connect button. Case 3 then imports straight away instead
%     of waiting for Open, because a plain image has nothing to browse or
%     configure. Default: false

if nargin < 2; autoOpenPlainImage = false; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.SelectFromUrl.connectBtn_Callback: triggered\n');
end

urlText = strtrim(obj.BatchOpt.Url);
if isempty(urlText) && obj.hasView(); urlText = strtrim(obj.view.handles.Url.Value); end
if isempty(urlText)
    obj.setStatus('Enter a URL first.');
    return;
end

if ~io.RemoteStore.isRemote(urlText)
    obj.setStatus('Not a URL - expected http://, https:// or s3://');
    return;
end

% Enter already connects, so pressing the button afterwards would repeat the
% whole probe for no gain. Only a *successful* connect is recorded here, which
% leaves the button able to retry after a network failure.
if ~autoOpenPlainImage && ~isempty(obj.connectedUrl) && ...
        strcmp(io.RemoteStore.normalise(urlText), obj.connectedUrl)
    return;
end

obj.rootUrl = io.RemoteStore.normalise(urlText);

obj.setStatus('Contacting the server...');
if obj.hasView(); drawnow limitrate; end

io.RemoteStore.clearCache();
io.ExtensionRegistryLoad.clearRemoteProbeCache();
obj.probeCache = configureDictionary("string", "cell");

% An OpenOrganelle dataset page hands out the N5 form of the volume, which
% MIB cannot read; the OME-Zarr copy sits beside it. Resolved before anything
% else looks at the URL, so the rest of the connect never sees the N5 form.
[obj.rootUrl, swappedFromN5] = obj.resolveN5Sibling(obj.rootUrl);
sourceNote = '';
if swappedFromN5; sourceNote = ' (switched from the N5 container)'; end

% Show the URL actually connected to, so the s3:// rewrite and the N5 swap are
% both visible rather than silently applied behind the user's back.
obj.BatchOpt.Url = obj.rootUrl;
if obj.hasView(); obj.view.handles.Url.Value = obj.rootUrl; end

storeInfo = io.RemoteStore.parse(obj.rootUrl);
obj.isListable = storeInfo.listable;

obj.zarrFormat = io.ExtensionRegistryLoad.probeRemoteZarr(obj.rootUrl);

if obj.hasView()
    delete(obj.view.handles.groupTree.Children);
    obj.view.handles.infoTextArea.Value = {''};
    obj.view.handles.openButton.Enable = 'off';
end

% ---- case 3: not a zarr store --------------------------------------------
if isempty(obj.zarrFormat)
    try
        imageInfo = imfinfo(obj.rootUrl);
    catch
        imageInfo = [];
    end
    if isempty(imageInfo)
        if contains(obj.rootUrl, '.n5', 'IgnoreCase', true)
            obj.setStatus(['N5 container - MIB cannot read N5, and no OME-Zarr copy ' ...
                'was found beside it.']);
        else
            obj.setStatus('No OME-Zarr metadata here, and the URL is not a readable image.');
        end
        return;
    end
    obj.connectedUrl = obj.rootUrl;
    obj.setStatus(sprintf('Ordinary image (%s, %d page(s)) - will be opened with imread as a Standard dataset.', ...
        imageInfo(1).Format, numel(imageInfo)));
    if obj.hasView()
        obj.view.handles.openButton.Enable = 'on';
        obj.view.handles.infoTextArea.Value = { ...
            sprintf('Format : %s', imageInfo(1).Format), ...
            sprintf('Size   : %d x %d', imageInfo(1).Width, imageInfo(1).Height), ...
            sprintf('Pages  : %d', numel(imageInfo))};
    end
    % Nothing left to choose - a plain image has no groups and no dataset mode -
    % so Enter goes straight to the import and closes the dialog.
    if autoOpenPlainImage; obj.openBtn_Callback(); end
    return;
end

obj.connectedUrl = obj.rootUrl;

% Only the AWS spellings are *known* to answer ListObjectsV2; every other host
% is read as path style on the assumption that it might, so confirm it before
% offering a tree that could never fill. This costs nothing: the listing is
% cached, so the zarr-version probe above already paid for it and the root fill
% below reuses it.
if obj.isListable && ~strcmp(storeInfo.flavour, 's3')
    [rootChildUrls, ~, rootFileNames] = io.RemoteStore.listChildren(obj.rootUrl);
    obj.isListable = ~isempty(rootChildUrls) || ~isempty(rootFileNames);
end

% ---- case 2: a zarr store on a host that cannot be listed ----------------
if ~obj.isListable
    obj.setStatus(sprintf(['OME-Zarr %s%s. This host cannot be listed - type the group path ' ...
        'below and press Enter.'], obj.zarrFormat, sourceNote));
    obj.probeGroup(io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.GroupPath));
    return;
end

% ---- case 1: browsable container -----------------------------------------
if ~obj.hasView()
    obj.setStatus(sprintf('OME-Zarr %s%s.', obj.zarrFormat, sourceNote));
    obj.probeGroup(io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.GroupPath));
    return;
end

rootNode = uitreenode(obj.view.handles.groupTree, ...
    'Text', obj.nodeLabel(obj.rootUrl, '/'), ...
    'NodeData', struct('url', obj.rootUrl, 'expanded', false));

% Fill the root here instead of giving it a placeholder and letting the expand
% event do it. NodeExpandedFcn fires only when the user clicks the arrow - a
% programmatic expand() raises nothing - so the root would sit on "loading..."
% forever. Every deeper node is still filled lazily on the real event.
obj.treeNodeExpanded_Callback(struct('Node', rootNode));
expand(rootNode);

obj.view.handles.groupTree.SelectedNodes = rootNode;
obj.probeGroup(obj.rootUrl);

% Last, because filling the root and probing it both write their own progress
% into the status line on the way past.
obj.setStatus(sprintf('OME-Zarr %s%s. Expand the tree to choose a group.', ...
    obj.zarrFormat, sourceNote));
end
