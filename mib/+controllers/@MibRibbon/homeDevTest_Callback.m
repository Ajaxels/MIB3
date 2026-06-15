function homeDevTest_Callback(obj, hWidget, hData)
% HOMEDEVTEST_CALLBACK - Reserved for MIB developmental purposes.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.homeDevTest_Callback(hWidget, hData)
%
% Currently runs benchmarkGetSetData (below) — a correctness + performance
% benchmark of the getData2D/3D/4D and setData2D/3D/4D accessors.
% Can also be invoked from the MATLAB command line without widget arguments:
%
%   .. code-block:: matlab
%
%       mib.cRibbon.homeDevTest_Callback();

arguments (Input)
    obj controllers.MibRibbon
    hWidget = []    % matlab.ui.internal.toolstrip.base.Action when invoked from the ribbon
    hData = []      % matlab.ui.internal.toolstrip.base.ToolstripEventData when invoked from the ribbon
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeDevTest_Callback: pressed\n');
end

%io.zarr.Config.setSmoothing(true);

%benchmarkGetSetData(obj.mibModel);
end

%% =========================================================================
function benchmarkGetSetData(mibModel)
% Correctness + performance benchmark for MibModel getData2D/3D/4D and
% setData2D/3D/4D. Expects 3 loaded datasets with initialized model and mask:
%   id==1 — MibLabels63 model (labels/mask/selection packed into one uint8 array)
%   id==2 — 255-material model (uint8)
%   id==3 — 65535-material model (uint16)
% All writes are pure roundtrips (the data just read is written back), so the
% datasets are left unmodified; verified by per-dataset checksums at the end.

nIter2D = 100;      % iterations for per-slice (2D) calls
nIter3D = 5;        % iterations for full-volume (3D/4D) calls
nIterRGB = 20;      % iterations for the getRGBimage display-path benchmark
materialIndex = 1;  % material used for the material-extraction benchmarks

datasetIds = [];
for id = 1:min(3, numel(mibModel.I))
    if mibModel.I{id}.image.exists; datasetIds(end+1) = id; end %#ok<AGROW>
end
if numel(datasetIds) < 3
    fprintf('benchmarkGetSetData: WARNING — expected 3 loaded datasets, found %d\n', numel(datasetIds));
end

fprintf('\n=== getData/setData benchmark, %s, MATLAB R%s ===\n', ...
    char(datetime('now', 'Format', 'dd.MM.yyyy HH:mm:ss')), version('-release'));
columnLabels = {'', '', ''};
for id = datasetIds
    img = mibModel.I{id}.image;
    fprintf('ds%d: [h%d x w%d x z%d x c%d x t%d] %s, model maxMaterials=%d (%s)\n', id, ...
        img.height, img.width, img.depth, img.colors, img.time, img.dataClass, ...
        mibModel.I{id}.labels.maxMaterials, class(mibModel.I{id}.labels));
    columnLabels{id} = sprintf('ds%d:%d', id, mibModel.I{id}.labels.maxMaterials);
end

timings = struct('name', {}, 'ms', {});
checks = struct('name', {}, 'passed', {}, 'info', {});

for id = datasetIds
    ds = mibModel.I{id};
    is63 = (ds.labels.maxMaterials == 63);
    dsTag = sprintf('ds%d', id);
    opt = struct('id', id, 'blockModeSwitch', 0);
    midSlice = max(1, round(ds.image.depth/2));

    % ground truth taken directly from the raw arrays (bypassing the accessors)
    rawImage = ds.image.data;
    if is63
        rawPacked = ds.labels.data;
        gtLabels = bitand(rawPacked, 63);
        gtMask = bitand(rawPacked, 64)/64;
        gtSelection = bitand(rawPacked, 128)/128;
    else
        gtLabels = ds.labels.data;
        gtMask = ds.mask.data;
        gtSelection = ds.selection.data;
    end

    chkBefore = stateChecksum(ds, is63);

    try
        %% --- correctness: reads vs ground truth -------------------------
        res = mibModel.getData2D('image', midSlice, 3, NaN, opt);
        checks = addCheck(checks, [dsTag ' get2D image == raw'], ...
            isequal(res{1}, squeeze(rawImage(:, :, midSlice, :, 1))), '');

        res = mibModel.getData2D('labels', midSlice, 3, [], opt);
        checks = addCheck(checks, [dsTag ' get2D labels == raw'], ...
            isequal(squeeze(res{1}), squeeze(gtLabels(:, :, midSlice, 1, 1))), '');

        res = mibModel.getData3D('image', 1, 3, NaN, opt);
        checks = addCheck(checks, [dsTag ' get3D image == raw'], ...
            isequal(res{1}, rawImage(:, :, :, :, 1)), '');

        res = mibModel.getData3D('labels', 1, 3, [], opt);
        checks = addCheck(checks, [dsTag ' get3D labels == raw'], ...
            isequal(squeeze(res{1}), squeeze(gtLabels)), '');

        res = mibModel.getData3D('mask', 1, 3, [], opt);
        checks = addCheck(checks, [dsTag ' get3D mask == raw'], ...
            isequal(squeeze(res{1}), squeeze(gtMask)), '');

        res = mibModel.getData3D('selection', 1, 3, [], opt);
        checks = addCheck(checks, [dsTag ' get3D selection == raw'], ...
            isequal(squeeze(res{1}), squeeze(gtSelection)), '');

        res = mibModel.getData3D('labels', 1, 3, materialIndex, opt);
        checks = addCheck(checks, [dsTag ' get3D labels material'], ...
            isequal(squeeze(res{1}), squeeze(uint8(gtLabels == materialIndex))), '');

        res = mibModel.getData3D('image', 1, 1, NaN, opt);   % ZX orientation
        checks = addCheck(checks, [dsTag ' get3D image orient1'], ...
            isequal(res{1}, permute(rawImage(:, :, :, :, 1), [2 3 1 4 5])), '');

        res = mibModel.getData3D('image', 1, 2, NaN, opt);   % ZY orientation
        checks = addCheck(checks, [dsTag ' get3D image orient2'], ...
            isequal(res{1}, permute(rawImage(:, :, :, :, 1), [1 3 2 4 5])), '');

        res = mibModel.getData4D('image', 3, NaN, opt);
        checks = addCheck(checks, [dsTag ' get4D image == raw'], ...
            isequal(res{1}, rawImage), '');

        res = mibModel.getData4D('labels', 3, [], opt);
        checks = addCheck(checks, [dsTag ' get4D labels == raw'], ...
            isequal(squeeze(res{1}), squeeze(gtLabels)), '');

        if is63
            res = mibModel.getData3D('everything', 1, 3, [], opt);
            checks = addCheck(checks, [dsTag ' get3D everything == raw'], ...
                isequal(squeeze(res{1}), squeeze(rawPacked)), '');
        end
        clear res

        %% --- timings: 2D per-slice calls --------------------------------
        timings = addTiming(timings, 'get2D image', id, ...
            timeCall(@() mibModel.getData2D('image', midSlice, 3, NaN, opt), nIter2D));
        timings = addTiming(timings, 'get2D labels', id, ...
            timeCall(@() mibModel.getData2D('labels', midSlice, 3, [], opt), nIter2D));
        timings = addTiming(timings, 'get2D mask', id, ...
            timeCall(@() mibModel.getData2D('mask', midSlice, 3, [], opt), nIter2D));
        timings = addTiming(timings, 'get2D selection', id, ...
            timeCall(@() mibModel.getData2D('selection', midSlice, 3, [], opt), nIter2D));
        timings = addTiming(timings, 'get2D labels material', id, ...
            timeCall(@() mibModel.getData2D('labels', midSlice, 3, materialIndex, opt), nIter2D));

        imgSlice = mibModel.getData2D('image', midSlice, 3, NaN, opt); imgSlice = imgSlice{1};
        timings = addTiming(timings, 'set2D image', id, ...
            timeCall(@() mibModel.setData2D(imgSlice, 'image', midSlice, 3, NaN, opt), nIter2D));
        labSlice = mibModel.getData2D('labels', midSlice, 3, [], opt); labSlice = labSlice{1};
        timings = addTiming(timings, 'set2D labels', id, ...
            timeCall(@() mibModel.setData2D(labSlice, 'labels', midSlice, 3, [], opt), nIter2D));
        maskSlice = mibModel.getData2D('mask', midSlice, 3, [], opt); maskSlice = maskSlice{1};
        timings = addTiming(timings, 'set2D mask', id, ...
            timeCall(@() mibModel.setData2D(maskSlice, 'mask', midSlice, 3, [], opt), nIter2D));
        selSlice = mibModel.getData2D('selection', midSlice, 3, [], opt); selSlice = selSlice{1};
        timings = addTiming(timings, 'set2D selection', id, ...
            timeCall(@() mibModel.setData2D(selSlice, 'selection', midSlice, 3, [], opt), nIter2D));
        matSlice = mibModel.getData2D('labels', midSlice, 3, materialIndex, opt); matSlice = matSlice{1};
        timings = addTiming(timings, 'set2D labels material', id, ...
            timeCall(@() mibModel.setData2D(matSlice, 'labels', midSlice, 3, materialIndex, opt), nIter2D));
        clear imgSlice labSlice maskSlice selSlice matSlice

        %% --- timings: 3D full-volume calls ------------------------------
        timings = addTiming(timings, 'get3D image', id, ...
            timeCall(@() mibModel.getData3D('image', 1, 3, NaN, opt), nIter3D));
        timings = addTiming(timings, 'get3D labels', id, ...
            timeCall(@() mibModel.getData3D('labels', 1, 3, [], opt), nIter3D));
        timings = addTiming(timings, 'get3D mask', id, ...
            timeCall(@() mibModel.getData3D('mask', 1, 3, [], opt), nIter3D));
        timings = addTiming(timings, 'get3D selection', id, ...
            timeCall(@() mibModel.getData3D('selection', 1, 3, [], opt), nIter3D));
        timings = addTiming(timings, 'get3D labels material', id, ...
            timeCall(@() mibModel.getData3D('labels', 1, 3, materialIndex, opt), nIter3D));
        timings = addTiming(timings, 'get3D image orient1', id, ...
            timeCall(@() mibModel.getData3D('image', 1, 1, NaN, opt), nIter3D));

        imgVol = mibModel.getData3D('image', 1, 3, NaN, opt); imgVol = imgVol{1};
        timings = addTiming(timings, 'set3D image', id, ...
            timeCall(@() mibModel.setData3D(imgVol, 'image', 1, 3, NaN, opt), nIter3D));
        labVol = mibModel.getData3D('labels', 1, 3, [], opt); labVol = labVol{1};
        timings = addTiming(timings, 'set3D labels', id, ...
            timeCall(@() mibModel.setData3D(labVol, 'labels', 1, 3, [], opt), nIter3D));
        maskVol = mibModel.getData3D('mask', 1, 3, [], opt); maskVol = maskVol{1};
        timings = addTiming(timings, 'set3D mask', id, ...
            timeCall(@() mibModel.setData3D(maskVol, 'mask', 1, 3, [], opt), nIter3D));
        selVol = mibModel.getData3D('selection', 1, 3, [], opt); selVol = selVol{1};
        timings = addTiming(timings, 'set3D selection', id, ...
            timeCall(@() mibModel.setData3D(selVol, 'selection', 1, 3, [], opt), nIter3D));
        matVol = mibModel.getData3D('labels', 1, 3, materialIndex, opt); matVol = matVol{1};
        timings = addTiming(timings, 'set3D labels material', id, ...
            timeCall(@() mibModel.setData3D(matVol, 'labels', 1, 3, materialIndex, opt), nIter3D));
        clear imgVol labVol maskVol selVol matVol

        if is63
            allVol = mibModel.getData3D('everything', 1, 3, [], opt); allVol = allVol{1};
            timings = addTiming(timings, 'get3D everything', id, ...
                timeCall(@() mibModel.getData3D('everything', 1, 3, [], opt), nIter3D));
            timings = addTiming(timings, 'set3D everything', id, ...
                timeCall(@() mibModel.setData3D(allVol, 'everything', 1, 3, [], opt), nIter3D));
            clear allVol
        end

        %% --- timings: 4D calls ------------------------------------------
        timings = addTiming(timings, 'get4D image', id, ...
            timeCall(@() mibModel.getData4D('image', 3, NaN, opt), nIter3D));
        timings = addTiming(timings, 'get4D labels', id, ...
            timeCall(@() mibModel.getData4D('labels', 3, [], opt), nIter3D));

        imgVol4 = mibModel.getData4D('image', 3, NaN, opt); imgVol4 = imgVol4{1};
        timings = addTiming(timings, 'set4D image', id, ...
            timeCall(@() mibModel.setData4D(imgVol4, 'image', 3, NaN, opt), nIter3D));
        labVol4 = mibModel.getData4D('labels', 3, [], opt); labVol4 = labVol4{1};
        timings = addTiming(timings, 'set4D labels', id, ...
            timeCall(@() mibModel.setData4D(labVol4, 'labels', 3, [], opt), nIter3D));
        clear imgVol4 labVol4

        %% --- state preservation after all roundtrip writes --------------
        chkAfter = stateChecksum(ds, is63);
        checks = addCheck(checks, [dsTag ' state preserved'], isequal(chkBefore, chkAfter), '');
    catch err
        checks = addCheck(checks, [dsTag ' ERROR'], false, err.message);
    end
end

% display pipeline end-to-end benchmark for the currently active dataset
activeId = mibModel.getActiveId();
if ismember(activeId, datasetIds)
    rgbOptions.blockModeSwitch = 0;
    rgbOptions.resizeToMagnification = true;
    timings = addTiming(timings, 'getRGBimage (active ds)', activeId, ...
        timeCall(@() mibModel.getRGBimage(rgbOptions), nIterRGB));
end

%% --- report -------------------------------------------------------------
fprintf('\n%-26s %12s %12s %12s\n', 'ms/call', columnLabels{1}, columnLabels{2}, columnLabels{3});
for k = 1:numel(timings)
    fprintf('%-26s %12.3f %12.3f %12.3f\n', timings(k).name, ...
        timings(k).ms(1), timings(k).ms(2), timings(k).ms(3));
end

nPassed = nnz([checks.passed]);
fprintf('\nCorrectness: %d/%d checks passed\n', nPassed, numel(checks));
for k = 1:numel(checks)
    if ~checks(k).passed
        fprintf('[FAIL] %s %s\n', checks(k).name, checks(k).info);
    end
end
fprintf('=== benchmark finished ===\n');
end

%% =========================================================================
function ms = timeCall(fcn, nIter)
% Return mean ms per call.  Delegates to the shared mibtest.perf.timeCallSamples
% when tests\ is on the path; falls back to a loop-level timer otherwise
% (e.g. compiled / deployed build where tests\ is excluded).
if exist('mibtest.perf.timeCallSamples', 'file')
    ms = mean(mibtest.perf.timeCallSamples(fcn, nIter)) * 1000;
else
    fcn();   % warm-up
    tStart = tic;
    for k = 1:nIter
        fcn();
    end
    ms = toc(tStart) / nIter * 1000;
end
end

function timings = addTiming(timings, name, id, ms)
% store a timing value into the row with the given name, column id
idx = find(strcmp({timings.name}, name), 1);
if isempty(idx)
    idx = numel(timings) + 1;
    timings(idx).name = name;
    timings(idx).ms = nan(1, 3);
end
timings(idx).ms(id) = ms;
end

function checks = addCheck(checks, name, passed, info)
% store a named pass/fail correctness result
checks(end+1).name = name;
checks(end).passed = passed;
checks(end).info = info;
end

function chk = stateChecksum(ds, is63)
% lightweight checksum of all data layers to detect accidental modification
chk = layerChecksum(ds.image.data);
if is63
    chk = [chk, layerChecksum(ds.labels.data)];
else
    chk = [chk, layerChecksum(ds.labels.data), ...
        layerChecksum(ds.mask.data), layerChecksum(ds.selection.data)];
end
end

function chk = layerChecksum(dataArray)
chk = [sum(dataArray(:), 'double'), nnz(dataArray), numel(dataArray)];
end
