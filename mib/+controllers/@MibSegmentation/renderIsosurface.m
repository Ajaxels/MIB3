function renderIsosurface(obj)
% RENDERISOSURFACE - Render the currently selected material(s) as MATLAB isosurfaces.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.renderIsosurface()
%
% Prompts the user for mesh generation parameters (volume reduction, smoothing,
% face limit, orthoslice) and renders the selected material — or all materials
% when ``showAllMaterials`` is active — as a 3-D isosurface mesh in a dedicated
% MATLAB figure.  Delegates mesh computation to ``utils.isosurfaceMibRendering``.
%
% Entry points:
%   - Context menu: ``materialsTable_ContextMenu`` → ``'materialsTableContextRenMat'``
%   - Ribbon: ``model_Callbacks`` → ``'MATLAB isosurface'``
%
% Input Arguments:
%   (none beyond ``obj``)
%
% Output Arguments:
%   None
%

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};

contIndex = dataset.getSelectedMaterialIndex();

[height, width, depth] = dataset.getDatasetDimensions('image', 3);
if max(height, width) > 500
    defaultReduce = 500;
else
    defaultReduce = 0;
end

%% Parameter dialog
prompts = { ...
    'Reduce volume to width, pixels [0 = no reduction]:'; ...
    'Smoothing 3D kernel width [0 = no smoothing]:'; ...
    'Max number of faces [0 = no limit]:'; ...
    'Orthoslice number [0 = none]:'};
defAns = { ...
    struct('Spinner', true, 'Value', defaultReduce, 'Limits', [0 max(width, 1000)], 'Step', 1,    'Round', true, 'ValueDisplayFormat','%d'); ...
    struct('Spinner', true, 'Value', 5,             'Limits', [0 100],              'Step', 1,    'Round', true, 'ValueDisplayFormat','%d'); ...
    struct('Spinner', true, 'Value', 300000,        'Limits', [0 10000000],         'Step', 1000, 'Round', true, 'ValueDisplayFormat','%d'); ...
    struct('Spinner', true, 'Value', 1,             'Limits', [0 depth],            'Step', 1,    'Round', true, 'ValueDisplayFormat','%d')};
dlgOptions.WindowHeight = 230;
answer = utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, '', prompts, defAns, ...
    'Isosurface parameters', dlgOptions);
if isempty(answer); return; end

meshOpts.reduce   = answer{1};
meshOpts.smooth   = answer{2};
meshOpts.maxFaces = answer{3};
sliceNo           = answer{4};

%% ROI handling
getDataOptions = struct();
if dataset.roiShow
    getDataOptions.roiId = [];   % restrict to active ROI
end
getDataOptions.fillBg = 0;

%% Fetch volume and resolve material list
if contIndex == -1
    % Render mask layer
    if dataset.maskExist == 0
        utils.dlgs.showErrorDialog(obj.mibController.mibGUI, 'Mask was not found!', 'Missing mask');
        return;
    end
    modelData      = cell2mat(obj.mibModel.getData3D('mask', [], 3, NaN, getDataOptions));
    materialColors = obj.mibModel.preferences.Colors.MaskColor;   % [1×3]
    materialNames  = {'Mask'};
    materialIndices = 1;
else
    % Render labels layer
    rawData = obj.mibModel.getData3D('labels', [], 3, NaN, getDataOptions);
    if numel(rawData) > 1
        utils.dlgs.showErrorDialog(obj.mibController.mibGUI, ...
            'Please select which ROI you would like to render!', 'Multiple ROIs');
        return;
    end
    modelData      = cell2mat(rawData);
    materialNames  = dataset.labels.materialNames;
    materialColors = dataset.labels.materialColors;   % [M×3]

    if dataset.showAllMaterials
        prompts2 = {sprintf('Specify material indices to render\n(leave empty to render all)\nExample: 2,4,6:8')};
        defAns2  = {num2str(contIndex)};

        answer2 = utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, '', prompts2, defAns2, ...
            'Select materials');
        if isempty(answer2); return; end
        if isempty(strtrim(answer2{1}))
            materialIndices = 1:numel(materialNames);
        else
            materialIndices = str2num(answer2{1}); %#ok<ST2NM>
        end
    else
        if contIndex == 0
            materialIndices = 1:numel(materialNames);
        else
            materialIndices = contIndex;
        end
    end
end

%% Render
model_hwd = squeeze(modelData(:,:,:,1,1));   % [H, W, D]
pixSize   = dataset.image.pixSize;
bb        = dataset.image.boundingBox;       % [xmin xmax ymin ymax zmin zmax]

meshOpts.showRendering = true;

for k = 1:numel(materialIndices)
    matIdx = materialIndices(k);

    if contIndex == -1
        matColor = materialColors;           % mask: single [1×3] row
    else
        if matIdx >= 1 && matIdx <= size(materialColors, 1)
            matColor = materialColors(matIdx, :);
        else
            matColor = rand(1, 3);
        end
    end

    meshOpts.initFigure     = (k == 1);
    meshOpts.finalizeFigure = (k == numel(materialIndices));
    meshOpts.matColor       = matColor;

    utils.isosurfaceMibRendering(model_hwd, matIdx, pixSize, bb, meshOpts);
end

%% Optional orthoslice overlay
if sliceNo > 0
    depth   = dataset.image.depth;
    sliceNo = max(1, min(round(sliceNo), depth));

    getRGBOptions.mode    = 'full';
    getRGBOptions.resize  = 'no';
    getRGBOptions.sliceNo = sliceNo;
    rgbImage = obj.mibModel.getRGBimage(getRGBOptions);   % [H×W×3] uint8

    hFig = findall(0, 'Type', 'figure', 'Tag', 'isosurfaceMibRenderingFig');
    if ~isempty(hFig)
        hAx   = gca(hFig(1));
        zPhys = bb(5) + (sliceNo - 1) * pixSize.z;

        imgH = size(rgbImage, 1);
        imgW = size(rgbImage, 2);
        xGrid = linspace(bb(1), bb(2), imgW);
        yGrid = linspace(bb(3), bb(4), imgH)';

        surf(hAx, xGrid, yGrid, zPhys * ones(imgH, imgW), ...
            double(rgbImage) / 255, ...
            'EdgeColor', 'none', 'FaceAlpha', 0.6);
        drawnow;
    end
end

end
