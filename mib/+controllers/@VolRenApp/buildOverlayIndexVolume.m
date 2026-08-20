function [overlayIdx, overlayInfo] = buildOverlayIndexVolume(obj, overlayData, overlayType)
% BUILDOVERLAYINDEXVOLUME - map an overlay layer onto the 255 colour slots available in volshow.
%
% Syntax:
%   .. code-block:: matlab
%
%       [overlayIdx, overlayInfo] = obj.buildOverlayIndexVolume(overlayData, overlayType)
%
% MATLAB keeps the overlay colour and alpha maps of ``volshow`` in fixed 256-entry
% lookup tables (``OverlayColormap_I`` is ``uint8 [3 256]`` and ``OverlayAlphamap_I``
% is ``uint8 [256 1]``), so no more than 255 materials plus the background can ever be
% displayed at once. This function converts an arbitrary label volume into a uint8
% index volume that fits those tables and returns the matching 256-row colormap.
% The caller must pair it with ``OverlayDisplayRangeMode = 'manual'`` and
% ``OverlayDisplayRange = [0 255]`` so that index N always lands on colormap row N+1.
%
% Behaviour depends on the model type and on the mode selected in the
% ``overlayMaterialsMode`` dropdown:
%
% - ``'mask'`` / ``'selection'`` layers, or a single material fetched as a binary
%   mask: one row, using the layer or material colour
% - models with fewer than 256 materials: the label values are used directly
% - large models (65535 / 4294967295) in ``'All materials'`` mode: labels are
%   cycled into 255 colour bins with ``mod(index-1, 255)+1``, the same trick
%   :func:`models.MibModel.getRGBimage` uses for the 2D view
% - large models in ``'Selected materials'`` mode: only the indices listed in
%   ``obj.overlayMaterialsSelection`` are shown, each with its exact colour
%
% Input Arguments:
%   - **overlayData** - [numeric] 3-D overlay volume as returned by ``getData3D``,
%     already resized to match the rendered image volume
%   - **overlayType** - [char] layer type: ``'labels'``, ``'mask'`` or ``'selection'``
%
% Output Arguments:
%   - **overlayIdx** - [uint8] index volume; ``0`` = background, ``1..N`` = colormap row minus 1
%   - **overlayInfo** - struct describing the generated rows:
%
%     - ``.colormap`` - ``[256 x 3]`` colormap; row 1 is the background, unused tail rows are zero
%     - ``.rowMaterials`` - real material index behind each table row; ``[]`` in the cycled mode
%     - ``.rowNames`` - cell array with the name shown in the material table
%     - ``.rowColors`` - ``[N x 3]`` background colours for the material table
%     - ``.rowMap`` - cell array; for each table row, the alphamap rows it controls
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [overlayIdx, overlayInfo] = obj.buildOverlayIndexVolume(overlay, 'labels');
%     obj.volume.OverlayData = overlayIdx;
%     obj.volume.OverlayColormap = overlayInfo.colormap;
%

% Updates
%

maxRows = 255;      % volshow keeps the overlay colormap and alphamap in 256-entry tables

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};

overlayColormap = zeros([256, 3]);

switch overlayType
    case 'mask'
        rowColors = obj.mibModel.preferences.Colors.MaskColor;
        rowNames = {'mask'};
        rowMaterials = 1;
        rowMap = {2};
        colormapRows = rowColors;
        overlayIdx = uint8(overlayData ~= 0);
    case 'selection'
        rowColors = obj.mibModel.preferences.Colors.SelectionColor;
        rowNames = {'selection'};
        rowMaterials = 1;
        rowMap = {2};
        colormapRows = rowColors;
        overlayIdx = uint8(overlayData ~= 0);
    otherwise   % labels
        materialId = obj.overlayMaterialId;
        if isempty(materialId); materialId = NaN; end
        isLargeModel = dataset.labels.maxMaterials >= 256;

        if ~isnan(materialId) && materialId > 0
            % a single material was fetched, getData3D returned it as a binary mask
            palette = ensurePalette(dataset, min(materialId, 65535));
            rowMaterials = materialId;
            rowColors = palette(mod(materialId-1, size(palette, 1)) + 1, :);
            rowNames = {materialRowName(dataset, materialId)};
            rowMap = {2};
            colormapRows = rowColors;
            overlayIdx = uint8(overlayData ~= 0);
        elseif ~isLargeModel
            % 63 and 255 material models: the label values are already valid colormap rows
            noMaterials = min(numel(dataset.labels.materialNames), maxRows);
            palette = ensurePalette(dataset, noMaterials);
            rowMaterials = 1:noMaterials;
            rowColors = palette(1:noMaterials, :);
            rowNames = dataset.labels.materialNames(1:noMaterials);
            rowMap = num2cell((1:noMaterials) + 1);
            colormapRows = rowColors;
            overlayIdx = uint8(overlayData);
            overlayIdx(overlayIdx > noMaterials) = 0;
        elseif strcmp(obj.overlayMaterialsMode, 'Selected materials')
            selectedMaterials = obj.overlayMaterialsSelection(:)';
            noMaterials = numel(selectedMaterials);
            rowMaterials = selectedMaterials;
            rowNames = arrayfun(@(x) sprintf('%d', x), selectedMaterials, 'UniformOutput', false)';
            rowMap = num2cell((1:noMaterials) + 1);
            if noMaterials == 0
                rowColors = zeros([0, 3]);
                overlayIdx = zeros(size(overlayData), 'uint8');
            else
                palette = ensurePalette(dataset, min(max(selectedMaterials), 65535));
                rowColors = palette(mod(selectedMaterials-1, size(palette, 1)) + 1, :);
                overlayIdx = mapSelectedMaterials(overlayData, selectedMaterials);
            end
            colormapRows = rowColors;
        else
            % large model, all materials: cycle the labels through 255 colour bins
            palette = ensurePalette(dataset, maxRows);
            rowMaterials = [];
            rowColors = [1 1 1];    % 255 colours cannot be shown in a single table cell
            rowNames = {sprintf('All materials (%d cycled colors)', maxRows)};
            rowMap = {2:256};
            colormapRows = palette(1:maxRows, :);
            overlayIdx = mapCycledMaterials(overlayData, maxRows);
        end
end

if ~isempty(colormapRows)
    overlayColormap(2:size(colormapRows, 1)+1, :) = colormapRows;
end

overlayInfo.colormap = overlayColormap;
overlayInfo.rowMaterials = rowMaterials;
overlayInfo.rowNames = rowNames(:);
overlayInfo.rowColors = rowColors;
overlayInfo.rowMap = rowMap(:)';
end

function palette = ensurePalette(dataset, requiredRows)
% generate missing colours so that a model loaded with a short palette still renders;
% dataset is a handle, so the top-up is kept for the 2D view as well
palette = dataset.labels.materialColors;
if isempty(palette); palette = zeros([0, 3]); end
if size(palette, 1) < requiredRows
    palette(size(palette, 1)+1:requiredRows, :) = rand([requiredRows-size(palette, 1), 3]);
    dataset.labels.materialColors = palette;
end
end

function name = materialRowName(dataset, materialIndex)
% name of a material: the stored name for small models, the index itself for large ones
if dataset.labels.maxMaterials < 256 && materialIndex <= numel(dataset.labels.materialNames)
    name = dataset.labels.materialNames{materialIndex};
else
    name = sprintf('%d', materialIndex);
end
end

function overlayIdx = mapCycledMaterials(overlayData, noBins)
% assign each label to one of noBins colour bins, keeping 0 as the background
overlayIdx = zeros(size(overlayData), 'uint8');
if isa(overlayData, 'uint8') || isa(overlayData, 'uint16')
    lut = zeros([65536, 1], 'uint8');
    lut(2:end) = uint8(mod((1:65535) - 1, noBins) + 1);
    for z = 1:size(overlayData, 3)
        overlayIdx(:,:,z) = lut(uint32(overlayData(:,:,z)) + 1);
    end
else
    % 4294967295 type models: a full lookup table is not possible
    for z = 1:size(overlayData, 3)
        slice = double(overlayData(:,:,z));
        binned = uint8(mod(slice - 1, noBins) + 1);
        binned(slice == 0) = 0;
        overlayIdx(:,:,z) = binned;
    end
end
end

function overlayIdx = mapSelectedMaterials(overlayData, selectedMaterials)
% keep only the listed materials, renumbered to 1..numel(selectedMaterials)
overlayIdx = zeros(size(overlayData), 'uint8');
if isa(overlayData, 'uint8') || isa(overlayData, 'uint16')
    lut = zeros([65536, 1], 'uint8');
    for matId = 1:numel(selectedMaterials)
        if selectedMaterials(matId) >= 1 && selectedMaterials(matId) <= 65535
            lut(selectedMaterials(matId) + 1) = uint8(matId);
        end
    end
    for z = 1:size(overlayData, 3)
        overlayIdx(:,:,z) = lut(uint32(overlayData(:,:,z)) + 1);
    end
else
    % 4294967295 type models: compare against each requested index instead
    for matId = 1:numel(selectedMaterials)
        overlayIdx(overlayData == selectedMaterials(matId)) = uint8(matId);
    end
end
end
