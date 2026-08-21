function findings = phase0_spike()
% PHASE0_SPIKE - Phase 0 headless verification for the MIB3 unit-test plan.
% See tests\plan_unittests.md §4.
% Verifies:
%   1. models.MibModel constructs headlessly (no figures created)
%   2. labels63 dataset: image/labels/mask/selection/everything roundtrips
%   3. construction of 255-material (uint8) and 65535-material (uint16) models
%      via MibDataset.createModel
%   4. getActiveId() works headlessly
%   5. getRGBimage() headless behavior (informational)
% Returns a struct of pass/fail results and prints a report.

findings = struct('name', {}, 'passed', {}, 'info', {});

figuresBefore = numel(findall(0, 'Type', 'figure'));

% --- path setup (replicates mib3.m; only mib/ needed for the model layer) ---
repoRoot = fileparts(fileparts(mfilename('fullpath')));   % tests\ -> repo root
mibFolder = fullfile(repoRoot, 'mib');
addpath(mibFolder);

% --- 1. headless MibModel ------------------------------------------------
% mibPath MUST be passed: datasetsSetsOps.m resolves assets (default.png)
% via fullfile(obj.mibPath, 'assets', ...); empty mibPath only works when
% the assets happen to be resolvable from the MATLAB path or cwd.
try
    mibModel = models.MibModel(1, mibFolder, Verbose = false, Preferences = 'defaults');
    findings = addResult(findings, 'MibModel() constructs headlessly', true, ...
        sprintf('numel(I)=%d, id=%d', numel(mibModel.I), mibModel.id));
catch err
    findings = addResult(findings, 'MibModel() constructs headlessly', false, err.message);
    reportAndReturn(findings, figuresBefore); return;
end

% --- synthetic data ------------------------------------------------------
rng(0, 'twister');
volumeDims = [64 48 16];   % deliberately non-square to catch dim swaps
imageVolume = reshape(uint8(randi(255, volumeDims)), [volumeDims 1]);
labelVolume = uint8(randi([0 6], volumeDims));
maskVolume = uint8(rand(volumeDims) > 0.7);
selectionVolume = uint8(rand(volumeDims) > 0.9);

% --- 2. labels63 dataset + roundtrips ------------------------------------
try
    mibModel.I{1} = core.MibDataset(imageVolume, dictionary(), 'Standard', 'labels63');
    mibModel.I{1}.updateBoundingBox([], [0 0 0]);
    opt = struct('id', 1, 'blockModeSwitch', 0);
    mibModel.setData3D(labelVolume, 'labels', 1, 3, [], opt);
    mibModel.setData3D(maskVolume, 'mask', 1, 3, [], opt);
    mibModel.setData3D(selectionVolume, 'selection', 1, 3, [], opt);

    res = mibModel.getData3D('image', 1, 3, NaN, opt);
    findings = addResult(findings, 'labels63 image roundtrip', isequal(res{1}, imageVolume), '');
    res = mibModel.getData3D('labels', 1, 3, [], opt);
    findings = addResult(findings, 'labels63 labels roundtrip', ...
        isequal(squeeze(res{1}), labelVolume), '');
    res = mibModel.getData3D('mask', 1, 3, [], opt);
    findings = addResult(findings, 'labels63 mask roundtrip', ...
        isequal(squeeze(res{1}), maskVolume), '');
    res = mibModel.getData3D('selection', 1, 3, [], opt);
    findings = addResult(findings, 'labels63 selection roundtrip', ...
        isequal(squeeze(res{1}), selectionVolume), '');
    % verify packed bits directly
    packed = mibModel.I{1}.labels.data;
    bitsOk = isequal(squeeze(bitand(packed, 63)), labelVolume) && ...
        isequal(squeeze(bitand(packed, 64)/64), maskVolume) && ...
        isequal(squeeze(bitand(packed, 128)/128), selectionVolume);
    findings = addResult(findings, 'labels63 bit packing matches', bitsOk, ...
        sprintf('labels class=%s, maxMaterials=%d', ...
        class(mibModel.I{1}.labels), mibModel.I{1}.labels.maxMaterials));
    res = mibModel.getData3D('everything', 1, 3, [], opt);
    findings = addResult(findings, 'labels63 everything == packed', ...
        isequal(squeeze(res{1}), squeeze(packed)), '');
catch err
    findings = addResult(findings, 'labels63 roundtrips', false, ...
        sprintf('%s (%s)', err.message, err.identifier));
end

% --- 3a. 255-material model via createModel(255) --------------------------
try
    mibModel.I{2} = core.MibDataset(imageVolume, dictionary(), 'Standard', 'labels63');
    mibModel.I{2}.updateBoundingBox([], [0 0 0]);
    mibModel.I{2}.createModel(255);
    opt2 = struct('id', 2, 'blockModeSwitch', 0);
    mibModel.setData3D(labelVolume, 'labels', 1, 3, [], opt2);
    res = mibModel.getData3D('labels', 1, 3, [], opt2);
    labelsObj = mibModel.I{2}.labels;
    passed = isequal(squeeze(res{1}), labelVolume) && ...
        labelsObj.maxMaterials == 255 && strcmp(class(labelsObj.data), 'uint8');
    findings = addResult(findings, 'createModel(255) -> uint8 model roundtrip', passed, ...
        sprintf('class(labels)=%s, data class=%s, maxMaterials=%d', ...
        class(labelsObj), class(labelsObj.data), labelsObj.maxMaterials));
    % mask/selection must be separate layers now
    res = mibModel.getData3D('mask', 1, 3, [], opt2);
    mibModel.setData3D(maskVolume, 'mask', 1, 3, [], opt2);
    res = mibModel.getData3D('mask', 1, 3, [], opt2);
    findings = addResult(findings, 'type-255 separate mask layer roundtrip', ...
        isequal(squeeze(res{1}), maskVolume), ...
        sprintf('mask class=%s', class(mibModel.I{2}.mask)));
catch err
    findings = addResult(findings, 'createModel(255)', false, ...
        sprintf('%s (%s)', err.message, err.identifier));
end

% --- 3b. 65535-material model via createModel(65535) ----------------------
try
    mibModel.I{3} = core.MibDataset(imageVolume, dictionary(), 'Standard', 'labels63');
    mibModel.I{3}.updateBoundingBox([], [0 0 0]);
    mibModel.I{3}.createModel(65535);
    opt3 = struct('id', 3, 'blockModeSwitch', 0);
    labelVolume16 = uint16(labelVolume);
    labelVolume16(1, 1, 1) = 30000;   % force a value above uint8 range
    mibModel.setData3D(labelVolume16, 'labels', 1, 3, [], opt3);
    res = mibModel.getData3D('labels', 1, 3, [], opt3);
    labelsObj = mibModel.I{3}.labels;
    passed = isequal(squeeze(res{1}), labelVolume16) && ...
        labelsObj.maxMaterials == 65535 && strcmp(class(labelsObj.data), 'uint16');
    findings = addResult(findings, 'createModel(65535) -> uint16 model roundtrip', passed, ...
        sprintf('class(labels)=%s, data class=%s, maxMaterials=%d', ...
        class(labelsObj), class(labelsObj.data), labelsObj.maxMaterials));
catch err
    findings = addResult(findings, 'createModel(65535)', false, ...
        sprintf('%s (%s)', err.message, err.identifier));
end

% --- 4. getActiveId headless ----------------------------------------------
try
    activeId = mibModel.getActiveId();
    findings = addResult(findings, 'getActiveId() works headlessly', ...
        isnumeric(activeId) && activeId >= 1, sprintf('activeId=%d', activeId));
catch err
    findings = addResult(findings, 'getActiveId() works headlessly', false, err.message);
end

% --- 5. getRGBimage headless (informational) -------------------------------
try
    rgbOptions = struct('blockModeSwitch', 0, 'resizeToMagnification', true);
    imgRGB = mibModel.getRGBimage(rgbOptions);
    findings = addResult(findings, 'getRGBimage() headless', ...
        ~isempty(imgRGB), sprintf('size=%s', mat2str(size(imgRGB))));
catch err
    findings = addResult(findings, 'getRGBimage() headless', false, ...
        sprintf('%s (%s)', err.message, err.identifier));
end

reportAndReturn(findings, figuresBefore);
end

function findings = addResult(findings, name, passed, info)
findings(end+1).name = name;
findings(end).passed = passed;
findings(end).info = info;
end

function reportAndReturn(findings, figuresBefore)
figuresAfter = numel(findall(0, 'Type', 'figure'));
fprintf('\n=== Phase 0 spike results ===\n');
for k = 1:numel(findings)
    if findings(k).passed; status = 'PASS'; else; status = 'FAIL'; end
    fprintf('[%s] %-45s %s\n', status, findings(k).name, findings(k).info);
end
fprintf('Figures created during run: %d (before=%d, after=%d)\n', ...
    figuresAfter - figuresBefore, figuresBefore, figuresAfter);
fprintf('=== spike finished ===\n');
end
