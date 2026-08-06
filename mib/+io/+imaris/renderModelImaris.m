% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi
% Date: 25.04.2023
% Written with a help of an old code SurfacesFromSegmentationImage.m by
% Igor Beati, Bitplane.

function connImaris = renderModelImaris(mibDataset, connImaris, options)
% RENDERMODELIMARIS - Render model materials as surfaces in Imaris.
%
% Syntax:
%   .. code-block:: matlab
%
%      connImaris = io.imaris.renderModelImaris(mibDataset, connImaris)
%      connImaris = io.imaris.renderModelImaris(mibDataset, connImaris, options)
%
% Input Arguments:
%   - **mibDataset** - instance of ``core.MibDataset`` with the model to render
%   - **connImaris** - *(optional)* handle to an existing Imaris connection
%   - **options** - *(optional)* struct with additional settings:
%
%     - ``.materialIndex`` - [integer] index of material to render; ``0`` = all materials (default: ``0``)
%     - ``.mibGUI`` - *(optional)* handle to the main MIB UIFigure for modal dialogs
%
% Output Arguments:
%   - **connImaris** - handle to the Imaris connection
%
% .. note::
%    Uses IceImarisConnector bindings. Requires:
%
%    1. Set system environment variable ``IMARISPATH`` to the Imaris installation directory
%    2. Restart MATLAB
%
% **Example** - render all model materials as Imaris surfaces:
%
%   .. code-block:: matlab
%
%      opts.mibGUI = obj.mibController.view.gui;
%      obj.connImaris = io.imaris.renderModelImaris(obj.mibModel.I{obj.mibModel.id}, obj.connImaris, opts);

if nargin < 3; options = struct(); end
if nargin < 2; connImaris = []; end

if ~isfield(options, 'materialIndex'); options.materialIndex = 0; end
if ~isfield(options, 'mibGUI'); options.mibGUI = []; end

pixSize = mibDataset.image.pixSize;

% prompt for smoothing factor
if ~isempty(options.mibGUI)
    answer = utils.dlgs.inputUniversalDlg(options.mibGUI, ...
        sprintf('Currently open in Imaris volume will be removed!\nYou can preserve it by importing it into MIB and exporting it back to Imaris after the surface is generated.'), ...
        {sprintf('Smoothing factor (IN IMAGE UNITS); voxel size: %.4f x %.4f x %.4f:', pixSize.x, pixSize.y, pixSize.z)}, ...
        {'0'}, 'Smoothing factor', struct('HeaderLines', 3, 'WindowHeight', 200));
else
    answer = inputdlg(sprintf('Currently open in Imaris volume will be removed!\nYou can preserve it by importing it into MIB and exporting it back to Imaris after the surface is generated.\n\nSmoothing factor (IN IMAGE UNITS); voxel size: %.4f x %.4f x %.4f:', ...
        pixSize.x, pixSize.y, pixSize.z), 'Smoothing factor', 1, {'0'});
end
if isempty(answer); return; end
smoothingFactor = str2double(answer{1});

% establish connection to Imaris
connImaris = io.imaris.connectToImaris(connImaris, options.mibGUI);
if isempty(connImaris); return; end

% define range of materials to render
if options.materialIndex == 0
    materialStart = 1;
    materialEnd = numel(mibDataset.labels.materialNames);
    numberOfMaterials = numel(mibDataset.labels.materialNames);
else
    materialStart = options.materialIndex;
    materialEnd = options.materialIndex;
    numberOfMaterials = 1;
end

if mibDataset.image.time > 1
    if ~isempty(options.mibGUI)
        mode = utils.dlgs.inputQuestDlg(options.mibGUI, ...
            'Export currently shown 3D (W×H×C×Z) stack or complete 4D (W×H×C×Z×T) dataset?', ...
            'Export to Imaris', '3D', '4D', '3D');
    else
        mode = questdlg('Export currently shown 3D (W×H×C×Z) stack or complete 4D (W×H×C×Z×T) dataset?', ...
            'Export to Imaris', '3D', '4D', 'Cancel', '3D');
    end
    if isempty(mode) || strcmp(mode, 'Cancel'); return; end
else
    mode = '3D';
end

imarisOptions = struct();
if ~isempty(connImaris.mImarisApplication.GetDataSet) && strcmp(mode, '3D')
    [~, ~, imarisDepth, ~, imarisTime] = connImaris.getSizes();
    if imarisDepth > 1 && imarisTime > 1
        if ~isempty(options.mibGUI)
            answer = utils.dlgs.inputUniversalDlg(options.mibGUI, '', ...
                {sprintf('A 5D dataset is open in Imaris!\nEnter a time point to update (starting from 0), or -1 to replace completely:')}, ...
                {num2str(mibDataset.slices{5}(1))}, 'Time point', struct());
        else
            answer = inputdlg(sprintf('!!! Warning !!!\n\nA 5D dataset is open in Imaris!\nPlease enter a time point to update (starting from 0)\nor type "-1" to replace dataset completely'), ...
                'Time point', 1, {num2str(mibDataset.slices{5}(1))});
        end
        if isempty(answer); return; end
        imarisOptions.insertInto = answer;
    end
end
imarisOptions.type = 'labels';
imarisOptions.mode = mode;
imarisOptions.mibGUI = options.mibGUI;

if ~isempty(options.mibGUI)
    progressDlg = uiprogressdlg(options.mibGUI, 'Value', 0, 'Message', 'Rendering model in Imaris...', 'Title', 'Render model in Imaris');
else
    progressDlg = waitbar(0, 'Rendering model in Imaris...');
end
tic
for materialIdx = materialStart:materialEnd
    imarisOptions.modelIndex = materialIdx;
    connImaris = io.imaris.setImarisDataset(mibDataset, connImaris, imarisOptions);
    imarisDataset = connImaris.mImarisApplication.GetDataSet();
    if isempty(imarisDataset)
        if ~isempty(options.mibGUI)
            utils.dlgs.showErrorDialog(options.mibGUI, 'The dataset was not transferred to Imaris.', 'Transfer Error');
        else
            errordlg('The dataset was not transferred to Imaris.', 'Transfer Error');
        end
        if ~isempty(options.mibGUI); close(progressDlg); else; delete(progressDlg); end
        return;
    end

    % generate surface
    surfaces = connImaris.mImarisApplication.GetImageProcessing.DetectSurfaces(...
        imarisDataset, [], 0, smoothingFactor, 0, 0, .5, '');

    surfaces.SetName(mibDataset.labels.materialNames{materialIdx});
    colorRGBA = [mibDataset.labels.materialColors(materialIdx, :), 0];
    colorRGBA = connImaris.mapRgbaVectorToScalar(colorRGBA);
    surfaces.SetColorRGBA(colorRGBA);
    connImaris.mImarisApplication.GetSurpassScene.AddChild(surfaces, -1);

    if ~isempty(options.mibGUI)
        progressDlg.Value = materialIdx / numberOfMaterials;
    else
        waitbar(materialIdx / numberOfMaterials, progressDlg);
    end
end
if ~isempty(options.mibGUI); close(progressDlg); else; delete(progressDlg); end
toc
end
