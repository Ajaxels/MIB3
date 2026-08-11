% VERIFY_REMOTE_ZARR - Hands-on check of remote OME-Zarr support (steps 1-6).
%
% Run from the repo root:
%
%   cd C:\MATLAB\MIB3
%   addpath(fullfile(pwd,'mib')); addpath(genpath(fullfile(pwd,'tests')));
%   run('development/bigdata/verify_remote_zarr.m')
%
% Exercises the whole remote path against public Janelia OpenOrganelle data:
% URL parsing, S3 listing, zarr version detection, nested group resolution, a
% full BigData open through MibModel.loadImages, and real pixel reads at two
% pyramid levels.
%
% Needs network access and "aiohttp" + "requests" in the Python interpreter set
% at Preferences -> External directories -> Python installation path. Remote
% zarr v2 cannot be read without them; see plan_url_s3.md.
%
% NOTE: there is no GUI entry point yet. Home -> Import -> URL still opens a
% single image with imread; wiring it to this stack is step 8 of the plan.

storeRoot = ['https://janelia-cosem-datasets.s3.amazonaws.com/' ...
    'jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr'];

fprintf('\n=== 1. URL forms ==========================================\n');
fprintf('s3:// is rewritten to anonymous HTTPS, so no credentials are needed:\n  %s\n', ...
    io.RemoteStore.normalise('s3://janelia-cosem-datasets/jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr'));
storeInfo = io.RemoteStore.parse(storeRoot);
fprintf('bucket=%s  listable=%d  flavour=%s\n', storeInfo.bucket, storeInfo.listable, storeInfo.flavour);

fprintf('\n=== 2. Browsing one level at a time =======================\n');
fprintf('This is what the URL browser dialog will do, one S3 request per expand.\n');
io.RemoteStore.clearCache();
currentUrl = storeRoot;
for stepIndex = 1:3
    [~, childNames, fileNames] = io.RemoteStore.listChildren(currentUrl);
    fprintf('%-38s children={%s}  files={%s}\n', ...
        io.RemoteStore.relativePath(storeRoot, currentUrl), ...
        strjoin(childNames, ', '), strjoin(fileNames, ', '));
    if isempty(childNames); break; end
    currentUrl = io.RemoteStore.join(currentUrl, childNames{1});
end

fprintf('\n=== 3. Zarr version detection =============================\n');
fprintf('Used to be impossible for a URL, so every remote store was assumed v3\n');
fprintf('and handed to a loader that cannot read it.\n');
fprintf('  store root      -> "%s"\n', io.ExtensionRegistryLoad.probeRemoteZarr(storeRoot));
fprintf('  non-zarr prefix -> "%s"  (empty = correctly not claimed)\n', ...
    io.ExtensionRegistryLoad.probeRemoteZarr( ...
        'https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-liver-zon-1/neuroglancer'));

fprintf('\n=== 4. Finding the nested image group =====================\n');
io.RemoteStore.clearCache();
searchTimer = tic;
foundGroups = io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups(storeRoot, 2);
fprintf('%.1f s, %d match: %s\n', toc(searchTimer), numel(foundGroups), ...
    io.loaders.OmeZarrMetadataUtils.relativeGroupPath(storeRoot, foundGroups{1}));
fprintf('The 42-crop labels subtree below it is deliberately never walked.\n');

fprintf('\n=== 5. Full BigData open through MibModel =================\n');
if ~io.zarr.PyBackend.hasRemoteSupport()
    fprintf('SKIPPED: the Python environment cannot reach remote stores.\n');
    return;
end

mibModel = mibtest.helpers.buildSyntheticModel();
mibModel.preferences.System.DeveloperMode = false;
datasetId = mibModel.getActiveId();
placeholderFile = {fullfile(mibModel.mibPath, 'assets', 'images', 'default.h5')};
mibModel.I{datasetId}.switchDatasetMode(3, ...
    mibModel.preferences.System.EnableSelection, placeholderFile);   % 3 = BigData

loadOptions = struct();
loadOptions.Mode          = {'Combine datasets'};
loadOptions.Filenames     = {storeRoot};          % a URL, not a path
loadOptions.DirectoryName = {mibModel.currentDirectory};
loadOptions.Reader        = {'Default'};
loadOptions.showWaitbar   = false;
loadOptions.id            = datasetId;
% loadOptions.ZarrGroupPath = 'recon-1/em/fibsem-uint8';   % skips the search

openTimer = tic;
mibModel.loadImages('Combine datasets', loadOptions);
openSeconds = toc(openTimer);

image = mibModel.I{datasetId}.image;
fprintf('opened in %.1f s as %s\n', openSeconds, mibModel.I{datasetId}.datasetType);
fprintf('  dims [y x z c t] = %s   (%.1f teravoxels)\n', mat2str(image.dim_yxzct), ...
    prod(double(image.dim_yxzct(1:3))) / 1e12);
fprintf('  pyramid levels   = %d\n', numel(image.pyramid.levelNames));
fprintf('  voxel size       = %g x %g x %g %s\n', ...
    image.pixSize.x, image.pixSize.y, image.pixSize.z, image.pixSize.units);
fprintf('  resolved group   = %s\n', image.filePaths{1});
fprintf('  pixels in RAM    = %d bytes (BigData keeps none)\n', numel(image.data));

fprintf('\n=== 6. Reading pixels =====================================\n');
middleSlice = round(double(image.depth) / 2);

mibModel.I{datasetId}.magFactor = 32;             % zoomed out -> coarse level
readTimer = tic;
coarseBlocks = mibModel.getData2D('image', middleSlice, 3, 1, ...
    struct('id', datasetId, 'blockModeSwitch', 0));
fprintf('whole slice at magFactor 32 : %.1f s  %s  mean=%.1f\n', toc(readTimer), ...
    mat2str(size(coarseBlocks{1})), mean(double(coarseBlocks{1}(:))));

mibModel.I{datasetId}.magFactor = 1;              % full resolution sub-region
regionOptions = struct('id', datasetId, 'blockModeSwitch', 0, ...
    'y', [10000 10511], 'x', [12000 12511], 'z', [middleSlice middleSlice]);
readTimer = tic;
regionBlocks = mibModel.getData2D('image', middleSlice, 3, 1, regionOptions);
fprintf('512x512 at full resolution  : %.1f s  mean=%.1f\n', toc(readTimer), ...
    mean(double(regionBlocks{1}(:))));

figure('Name', 'Remote OME-Zarr: jrc_mus-liver-zon-1');
subplot(1, 2, 1); imshow(coarseBlocks{1}, []); title('whole slice, level s5');
subplot(1, 2, 2); imshow(regionBlocks{1}, []); title('512x512, full resolution');

fprintf('\nDone. There is no chunk cache yet, so re-reading a nearby slice\n');
fprintf('re-downloads the same chunks - see the caching note in plan_url_s3.md.\n');
