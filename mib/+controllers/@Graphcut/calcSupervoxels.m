function [Graphcut, cancelled] = calcSupervoxels(Graphcut, img, parLoopOptions, usePrecomputedSlic)
% CALCSUPERVOXELS - Generate 3D supervoxels and build the boundary graph for graph-cut.
%
% Syntax:
%   .. code-block:: matlab
%
%      Graphcut = controllers.Graphcut.calcSupervoxels(Graphcut, img, parLoopOptions)
%      Graphcut = controllers.Graphcut.calcSupervoxels(Graphcut, img, parLoopOptions, usePrecomputedSlic)
%      [Graphcut, cancelled] = controllers.Graphcut.calcSupervoxels(Graphcut, img, parLoopOptions, usePrecomputedSlic)
%
% Input Arguments:
%   - **Graphcut** - struct with graphcut data (fields modified by this function):
%
%     - ``.slic``        - label array (read when ``usePrecomputedSlic=1``, written otherwise)
%     - ``.noPix``       - number of supervoxels (written)
%     - ``.Edges``       - cell of ``[N×2]`` adjacency edge lists (written)
%     - ``.EdgesValues`` - cell of ``[N×1]`` mean-intensity differences per edge (written)
%     - ``.dilateMode``  - ``'pre'`` or ``'post'``; set by Watershed path
%
%   - **img** - [uint8 | uint16] 3-D image array ``[height × width × depth]``
%   - **parLoopOptions** - struct with processing options:
%
%     - ``.binVal``             - [1×2 numeric] ``[xyBin, zBin]`` binning factors
%     - ``.binHeight``          - [numeric] pre-calculated binned height
%     - ``.binWidth``           - [numeric] pre-calculated binned width
%     - ``.binDepth``           - [numeric] pre-calculated binned depth
%     - ``.waitbar``            - ``uiprogressdlg`` handle or ``[]`` to skip progress updates
%     - ``.cancelProgressBar``  - ``uiprogressdlg`` handle or ``[]``; checked at phase
%       boundaries so the user can cancel without disrupting the progress display
%     - ``.viewPort``           - struct with ``.min``, ``.max``, ``.gamma`` for contrast mapping
%     - ``.mibLiveStretchCheck``- [logical] use auto-stretch instead of viewPort limits
%     - ``.superPixType``       - [char] ``'SLIC'`` or ``'Watershed'``
%     - ``.blackOnWhite``       - [logical] invert image before watershed
%     - ``.superpixelSize``     - [numeric] target supervoxel volume (SLIC) or h-minima depth (Watershed)
%     - ``.superpixelCompact``  - [numeric] SLIC compactness parameter
%     - ``.tilesX``             - [numeric] number of SLIC tiles in X
%     - ``.tilesY``             - [numeric] number of SLIC tiles in Y
%
%   - **usePrecomputedSlic** *(optional)* - [logical] when ``1``, skip supervoxel
%     calculation and use ``Graphcut.slic`` as-is; default: ``0``
%
% Output Arguments:
%   - **Graphcut** - updated struct with ``.slic``, ``.noPix``, ``.Edges``,
%     ``.EdgesValues``, and (Watershed only) ``.dilateMode`` populated
%   - **cancelled** *(optional)* - [logical] ``true`` when the user cancelled via
%     ``parLoopOptions.cancelProgressBar``; the caller must detect this and clean up

if nargin < 4; usePrecomputedSlic = 0; end
cancelled = false;
if ~isfield(parLoopOptions, 'cancelProgressBar'); parLoopOptions.cancelProgressBar = []; end
cancelPB = parLoopOptions.cancelProgressBar;

img = squeeze(img);

% bin dataset
if parLoopOptions.binVal(1) ~= 1 || parLoopOptions.binVal(2) ~= 1
    if ~isempty(parLoopOptions.waitbar)
        parLoopOptions.waitbar.Value = 0.05;
        parLoopOptions.waitbar.Message = 'Binning the dataset...';
    end
    resizeOptions.height = parLoopOptions.binHeight;
    resizeOptions.width  = parLoopOptions.binWidth;
    resizeOptions.depth  = parLoopOptions.binDepth;
    resizeOptions.method = 'bicubic';
    img = utils.resizeImage3d(img, [], resizeOptions);
end

% convert to 8-bit
currViewPort = parLoopOptions.viewPort;
if isa(img, 'uint16')
    if parLoopOptions.mibLiveStretchCheck
        for sliceId = 1:size(img, 3)
            img(:,:,sliceId) = imadjust(img(:,:,sliceId), stretchlim(img(:,:,sliceId),[0 1]), []);
        end
    else
        for sliceId = 1:size(img, 3)
            img(:,:,sliceId) = imadjust(img(:,:,sliceId), [currViewPort.min/65535 currViewPort.max/65535], [0 1], currViewPort.gamma);
        end
    end
    img = uint8(img/255);
else
    if currViewPort.min > 1 || currViewPort.max < 255
        for sliceId = 1:size(img, 3)
            img(:,:,sliceId) = imadjust(img(:,:,sliceId), [currViewPort.min/255 currViewPort.max/255], [0 1], currViewPort.gamma);
        end
    end
end

dims = size(img);

if strcmp(parLoopOptions.superPixType, 'SLIC')
    Graphcut.noPix = ceil(dims(1)*dims(2)*dims(3) / parLoopOptions.superpixelSize);

    if usePrecomputedSlic == 0
        if ~isempty(parLoopOptions.waitbar)
            parLoopOptions.waitbar.Value = 0.05;
            parLoopOptions.waitbar.Message = sprintf('Calculating %d SLIC supervoxels...', Graphcut.noPix);
        end

        if parLoopOptions.tilesX > 1 || parLoopOptions.tilesY > 1
            [heightChop, widthChop, depthChop] = size(img);
            Graphcut.slic = zeros([heightChop widthChop depthChop], 'int32');
            noPix  = 0;
            xStep  = ceil(widthChop  / parLoopOptions.tilesX);
            yStep  = ceil(heightChop / parLoopOptions.tilesY);
            for x = 1:parLoopOptions.tilesX
                for y = 1:parLoopOptions.tilesY
                    yMin = (y-1)*yStep + 1;
                    yMax = min([(y-1)*yStep + yStep, heightChop]);
                    xMin = (x-1)*xStep + 1;
                    xMax = min([(x-1)*xStep + xStep, widthChop]);
                    [slicChop, noPixChop] = slicsupervoxelmex_byte( ...
                        img(yMin:yMax, xMin:xMax, :), ...
                        round(Graphcut.noPix / (parLoopOptions.tilesX * parLoopOptions.tilesY)), ...
                        parLoopOptions.superpixelCompact);
                    Graphcut.slic(yMin:yMax, xMin:xMax, :) = slicChop + noPix + 1;
                    noPix = noPixChop + noPix;

                    % check for cancel
                    if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end
                end
            end
            Graphcut.noPix = double(noPix);
        else
            [Graphcut.slic, Graphcut.noPix] = slicsupervoxelmex_byte(img, Graphcut.noPix, parLoopOptions.superpixelCompact);
            Graphcut.noPix = double(Graphcut.noPix);
            Graphcut.slic  = Graphcut.slic + 1;
        end
    end

    % check for cancel
    if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end

    if ~isempty(parLoopOptions.waitbar)
        parLoopOptions.waitbar.Value = 0.25;
        parLoopOptions.waitbar.Message = 'Calculating MeanIntensity for labels...';
    end
    STATS = regionprops(Graphcut.slic, img, 'MeanIntensity');

    if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end

    if ~isempty(parLoopOptions.waitbar)
        parLoopOptions.waitbar.Value = 0.3;
        parLoopOptions.waitbar.Message = 'Calculating adjacent matrix for labels...';
    end
    gap = 0;
    Graphcut.Edges{1}      = double(imRAG(Graphcut.slic, gap));
    Graphcut.EdgesValues{1} = zeros([size(Graphcut.Edges{1},1), 1]);
    meanVals = [STATS.MeanIntensity];
    for i = 1:size(Graphcut.Edges{1}, 1)
        Graphcut.EdgesValues{1}(i) = abs(meanVals(Graphcut.Edges{1}(i,1)) - meanVals(Graphcut.Edges{1}(i,2)));
    end

else    % Watershed supervoxels

    if usePrecomputedSlic == 0
        if parLoopOptions.blackOnWhite == 1
            if ~isempty(parLoopOptions.waitbar)
                parLoopOptions.waitbar.Value = 0.05;
                parLoopOptions.waitbar.Message = 'Complementing the image...';
            end
            img = imcomplement(img);
            % cancel check
            if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end
        end

        if ~isempty(parLoopOptions.waitbar)
            parLoopOptions.waitbar.Value = 0.1;
            parLoopOptions.waitbar.Message = 'Extended-minima transform...';
        end

        if parLoopOptions.superpixelSize > 0
            mask = imextendedmin(img, parLoopOptions.superpixelSize);
            % cancel check
            if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end
            if ~isempty(parLoopOptions.waitbar)
                parLoopOptions.waitbar.Value = 0.15;
                parLoopOptions.waitbar.Message = 'Impose minima...';
            end
            mask = imimposemin(img, mask);
            % cancel check
            if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end
            if ~isempty(parLoopOptions.waitbar)
                parLoopOptions.waitbar.Value = 0.2;
                parLoopOptions.waitbar.Message = 'Calculating watershed...';
            end
            Graphcut.slic = watershed(mask);
            % cancel check
            if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end
        else
            if ~isempty(parLoopOptions.waitbar)
                parLoopOptions.waitbar.Value = 0.2;
                parLoopOptions.waitbar.Message = 'Calculating watershed...';
            end
            Graphcut.slic = watershed(img);
            % cancel check
            if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end
        end
    else
        if parLoopOptions.blackOnWhite == 1
            if ~isempty(parLoopOptions.waitbar)
                parLoopOptions.waitbar.Value = 0.05;
                parLoopOptions.waitbar.Message = 'Complementing the image...';
            end
            img = imcomplement(img);
            % cancel check
            if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end
        end
    end

    if ~isempty(parLoopOptions.waitbar)
        parLoopOptions.waitbar.Value = 0.7;
        parLoopOptions.waitbar.Message = 'Calculating adjacency graph...';
    end
    [Graphcut.Edges{1}, Graphcut.EdgesValues{1}] = imRichRAG(Graphcut.slic, 1, img);
    Graphcut.noPix = double(max(max(max(Graphcut.slic))));

    % cancel check
    if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end

    % remove isolated supervoxels not present in the edge list
    vec = sort(unique(Graphcut.Edges{1}));
    excludeSupervoxels = find(diff(vec) > 1);
    if ~isempty(excludeSupervoxels)
        vec2 = 1:numel(excludeSupervoxels);
        excludeSupervoxels = excludeSupervoxels + vec2';
        Graphcut.slic(ismember(Graphcut.slic, excludeSupervoxels)) = 0;
    end

    if ~isempty(parLoopOptions.waitbar)
        parLoopOptions.waitbar.Value = 0.9;
        parLoopOptions.waitbar.Message = 'Generating the final graph...';
    end

    Graphcut.dilateMode = 'pre';
    if strcmp(Graphcut.dilateMode, 'pre')
        Graphcut.slic = imdilate(Graphcut.slic, ones([3 3 3]));
    end
    % cancel check
    if ~isempty(cancelPB) && isvalid(cancelPB) && cancelPB.CancelRequested; cancelled = true; return; end

    % fix zero-index pixels left after exclusion / dilation
    excludeIndices = find(Graphcut.slic == 0);
    [height1, width1, depth1] = size(Graphcut.slic);
    for exIndex = 1:numel(excludeIndices)
        [~, ~, Z1] = ind2sub([height1, width1, depth1], excludeIndices(exIndex));
        if excludeIndices(exIndex) > 1
            [~, ~, Z2] = ind2sub([height1, width1, depth1], excludeIndices(exIndex)-1);
            if Z2 == Z1
                Graphcut.slic(excludeIndices(exIndex)) = Graphcut.slic(excludeIndices(exIndex)-1);
            else
                Graphcut.slic(excludeIndices(exIndex)) = Graphcut.slic(excludeIndices(exIndex)+1);
            end
        else
            Graphcut.slic(excludeIndices(exIndex)) = Graphcut.slic(excludeIndices(exIndex)+1);
        end
    end
end

% downcast slic labels to the smallest integer type that fits
if max(Graphcut.noPix) < 256
    Graphcut.slic = uint8(Graphcut.slic);
elseif max(Graphcut.noPix) < 65536
    Graphcut.slic = uint16(Graphcut.slic);
elseif max(Graphcut.noPix) < 4294967295
    Graphcut.slic = uint32(Graphcut.slic);
end

end
