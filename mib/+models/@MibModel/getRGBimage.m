function [imgRGB, imgRAW, modelRAW] = getRGBimage(obj, options, datasetId, sImgIn)
% GETRGBIMAGE - Generate RGB image from all layers for display.
%
% Syntax:
%   .. code-block:: matlab
%
%      [imgRGB, imgRAW] = obj.getRGBimage(options)
%      [imgRGB, imgRAW] = obj.getRGBimage(options, datasetId)
%      [imgRGB, imgRAW] = obj.getRGBimage(options, datasetId, sImgIn)
%
% Combines image data, segmentation model, mask, selection layer,
% annotations, and 3D lines into a single RGB image for visualization.
%
% Input Arguments:
%   - **options** - struct with display parameters
%   - ``.blockModeSwitch`` - *(optional)* ``0`` return full slice [*default*], ``1`` crop to visible area
%   - ``.resizeToMagnification`` - *(optional)* ``true`` resize to current magnification [*default*], ``false`` return at 100%
%   - ``.sliceNo`` - *(optional)* specific slice index to display
%   - ``.markerType`` - *(optional)* annotation display type, default from preferences
%     (``'Marker'``, ``'Label'``, ``'Value'``, ``'Label + Value'``)
%   - ``.t`` - *(optional)* [tmin, tmax] time point to display
%   - ``.y`` - *(optional)* [ymin, ymax] Y-coordinates of region to extract
%   - ``.x`` - *(optional)* [xmin, xmax] X-coordinates of region to extract
%   - ``.useLut`` - *(optional)* ``0`` or ``1`` to use LUT color table [*default*: current dataset setting]
%   - **datasetId** - *(optional)* index of the dataset; when empty uses the currently selected dataset
%   - **sImgIn** - *(optional)* custom 3D image stack to use instead of loading from dataset
%
% Output Arguments:
%   - **imgRGB** - RGB image combining all visible layers [height × width × 3]
%   - **imgRAW** - raw image data (used for virtual stacking mode)
%   - **modelRAW** - model material-index raster aligned with imgRAW (Virtual/
%     BigData modes); empty when no model overlay is rendered. Used by the
%     cursor material readout in gui_WinMouseMotionFcn
%
% Usage:
%   **Example 1** - get full slice RGB with all layers
%
%   .. code-block:: matlab
%
%      options.blockModeSwitch = 0;
%      imgRGB = obj.getRGBimage(options);
%
%   **Example 2** - get cropped RGB of visible area only
%
%   .. code-block:: matlab
%
%      options.blockModeSwitch = 1;
%      options.resizeToMagnification = true;
%      imgRGB = obj.getRGBimage(options);
%
%   **Example 3** - get specific slice without resizing
%
%   .. code-block:: matlab
%
%      options.sliceNo = 50;
%      options.resizeToMagnification = false;
%      imgRGB = obj.getRGBimage(options);
%

if nargin < 4; sImgIn = []; end
if nargin < 3; datasetId = []; end
customImgProvided = false;
customImgClass    = '';

if isempty(datasetId); datasetId = obj.id; end
dataset = obj.I{datasetId};

%% Parse input parameters
if ~isfield(options, 'blockModeSwitch'); options.blockModeSwitch = false; end
if ~isfield(options, 'resizeToMagnification'); options.resizeToMagnification = true; end
if ~isfield(options, 'markerType'); options.markerType = obj.preferences.SegmTools.Annotations.DisplayAs; end
if ~isfield(options, 't')
    options.t = [dataset.slices{5}(1), dataset.slices{5}(1)]; 
end
if ~isfield(options, 'useLut')
    options.useLut = dataset.useLUT; 
end
options.roiId = -1; % do not show ROIs in this mode

%% Initialize display parameters
% Get current slice and orientation info
slices = dataset.slices;
orientation = dataset.orientation;

% Calculate magnification factor for resizing
if options.resizeToMagnification
    magnificationFactor = dataset.magFactor; % datasetVoxels / shownVoxels
else
    magnificationFactor = 1;
end

% Determine resize method based on magnification
if strcmp(obj.preferences.System.ImageResizeMethod, 'auto')
    if magnificationFactor > 1
        imageResizeMethod = 'bicubic';
    else
        imageResizeMethod = 'nearest';
    end
else
    imageResizeMethod = obj.preferences.System.ImageResizeMethod;
end

% Handle special cases for pan mode and image pyramids
panModeException = 0;
if (options.blockModeSwitch == 0 && magnificationFactor < 1) || ...
   ~isempty(dataset.image.pyramid.levelNames)
    panModeException = 1;
end

% Determine which slice to show
if isfield(options, 'sliceNo')
    sliceToShowIdx = options.sliceNo;
else
    sliceToShowIdx = slices{orientation}(1);
end

%% Load image data
if isempty(sImgIn)
    % Load image from dataset
    sImgIn  = cell2mat(dataset.getData2D('image', sliceToShowIdx, NaN, [], options));
    
    colortype = dataset.image.colorType;
    currViewPort = dataset.image.viewPort;
    showModelSwitch = obj.showModel;
    showMaskSwitch = obj.showMask;
else
    % Use provided custom image
    if size(sImgIn, 3) > 1
        colortype = 'multichannel';
    else
        colortype = 'grayscale';
    end
    % Generate default viewport for custom image
    currViewPort.min = zeros([size(sImgIn, 3), 1]);
    currViewPort.max = zeros([size(sImgIn, 3), 1]) + double(intmax(class(sImgIn)));
    currViewPort.gamma = zeros([size(sImgIn, 3), 1]) + 1;
    showModelSwitch = 0;
    showMaskSwitch = 0;
    customImgProvided = true;
    customImgClass    = class(sImgIn);
end

%% Resize image to display resolution
% Precompute subsampling indices once - reused for image, model, mask, selection
if magnificationFactor > 1
    rowIdx = round(.51:magnificationFactor:size(sImgIn,1)+.49);
    colIdx = round(.51:magnificationFactor:size(sImgIn,2)+.49);
end

if panModeException == 1
    % Image already at correct size (pan mode or pyramid)
    sImg = sImgIn;
else
    if magnificationFactor > 1
        % Downsample image
        if strcmp(imageResizeMethod, 'nearest') || strcmp(colortype, 'indexed')
            sImg = sImgIn(rowIdx, colIdx, :);
        else
            % Quality resize with preallocated output stack
            firstChannel = imresize(sImgIn(:,:,1), 1/magnificationFactor, imageResizeMethod);
            sImg = zeros([size(firstChannel,1), size(firstChannel,2), size(sImgIn,3)], 'like', sImgIn);
            sImg(:,:,1) = firstChannel;
            for colCh = 2:size(sImgIn, 3)
                sImg(:,:,colCh) = imresize(sImgIn(:,:,colCh), 1/magnificationFactor, imageResizeMethod);
            end
        end
    else
        sImg = sImgIn;
    end
end
clear sImgIn;

% Store raw image for on-demand modes (Virtual / BigData) - used by the
% cursor pixel-value readout (gui_WinMouseMotionFcn reads mibModel.Iraw)
imgRAW = [];
if any(dataset.datasetType(1) == ['V' 'B']); imgRAW = sImg; end
% Model material-index raster for the cursor readout (set below, after the
% model overlay has been resized to match the displayed image)
modelRAW = [];

%% Apply display adjustments to image
% Hide image if requested
if obj.hideImage; sImg(:) = 0; end

max_int = double(dataset.image.maxInt);
% When a custom image was supplied it may have a different bit depth than the
% dataset (e.g. uint8 preview of a uint16 dataset).  Override max_int so that
% the viewport fractions (currViewPort.max / max_int) stay in [0, 1].
if customImgProvided && ~ismember(customImgClass, {'double', 'single'})
    max_int = double(intmax(customImgClass));
end

% Apply live stretch if enabled
if obj.onFlyImageStretch
    if ~isa(sImg, 'uint32')
        % imadjust only accepts 2-D or H×W×3 - fall back to per-channel for 2 or 4+ channels
        if size(sImg, 3) == 1 || size(sImg, 3) == 3
            sImg = imadjust(sImg, stretchlim(sImg, [0 1]), []);
        else
            for i = 1:size(sImg, 3)
                sImg(:,:,i) = imadjust(sImg(:,:,i), stretchlim(sImg(:,:,i), [0 1]), []);
            end
        end
    else
        % Handle uint32 separately
        for i = 1:size(sImg, 3)
            minVal = min(min(sImg(:,:,i)));
            maxVal = max(max(sImg(:,:,i)));
            sImg(:,:,i) = double((sImg(:,:,i) - minVal)) / double((maxVal - minVal)) * 255;
        end
        sImg = double(sImg);
    end
end

%% Load segmentation model layer
if showModelSwitch && dataset.modelExist && obj.preferences.Colors.ModelTransparency < 1
    sOver1 = cell2mat(dataset.getData2D('labels', sliceToShowIdx, [], [], options));

    % Resize model to match image
    if panModeException == 0 && magnificationFactor > 1
        if strcmp(imageResizeMethod, 'nearest') || strcmp(colortype, 'indexed')
            sOver1 = sOver1(rowIdx, colIdx);
        else
            sOver1 = imresize(sOver1, 1/magnificationFactor, 'nearest');
        end
    end
else
    sOver1 = NaN;
end

%% Load mask layer
if showMaskSwitch && dataset.maskExist && obj.preferences.Colors.MaskTransparency < 1
    sOver2 = cell2mat(dataset.getData2D('mask', sliceToShowIdx, NaN, NaN, options));

    % Resize mask to match image
    if panModeException == 0 && magnificationFactor > 1
        if strcmp(imageResizeMethod, 'nearest') || strcmp(colortype, 'indexed')
            sOver2 = sOver2(rowIdx, colIdx);
        else
            sOver2 = imresize(sOver2, 1/magnificationFactor, 'nearest');
        end
    end
else
    sOver2 = NaN;
end

%% Load selection layer
if dataset.enableSelection && obj.preferences.Colors.SelectionTransparency < 1
    selectionLayer = cell2mat(dataset.getData2D('selection', sliceToShowIdx, NaN, NaN, options));
    if ~isempty(selectionLayer)
        % Resize selection to match image
        if panModeException == 0 && magnificationFactor > 1
            if strcmp(imageResizeMethod, 'nearest') || strcmp(colortype, 'indexed')
                selectionLayer = selectionLayer(rowIdx, colIdx);
            else
                selectionLayer = imresize(selectionLayer, 1/magnificationFactor, 'nearest');
            end
        end
    else
        selectionLayer = NaN;
    end
else
    selectionLayer = NaN;
end

%% Match overlay resolution to the displayed image (on-demand datasets)
% For pyramidal Virtual/BigData datasets panModeException==1, so the model/
% mask/selection overlays are NOT resized above. The BigData model store is
% full-resolution while the image is shown at the pyramid/zoom resolution, so
% the layers can differ in size. Resize each overlay (nearest, labels are
% categorical) to the displayed image size so compositing indices line up.
if any(dataset.datasetType(1) == ['V' 'B'])
    targetSize = [size(sImg, 1), size(sImg, 2)];
    if ~isnan(sOver1(1)) && ~isequal([size(sOver1, 1), size(sOver1, 2)], targetSize)
        sOver1 = imresize(sOver1, targetSize, 'nearest');
    end
    if ~isnan(sOver2(1)) && ~isequal([size(sOver2, 1), size(sOver2, 2)], targetSize)
        sOver2 = imresize(sOver2, targetSize, 'nearest');
    end
    if ~isnan(selectionLayer(1)) && ~isequal([size(selectionLayer, 1), size(selectionLayer, 2)], targetSize)
        selectionLayer = imresize(selectionLayer, targetSize, 'nearest');
    end

    % Cache the model material-index raster (now aligned to the displayed
    % image, i.e. same grid as imgRAW) for the cursor readout. NaN means no
    % model overlay was rendered.
    if ~isnan(sOver1(1)); modelRAW = sOver1; end
end

%% Generate RGB channels from image data
colorScale = max_int;
% For a custom-provided image the channel count in sImg may differ from the
% number of channels the dataset currently displays (slices{4}).  Reset to
% sequential indices so the LUT loop never reads beyond sImg's channels.
if customImgProvided
    slices{4} = 1:size(sImg, 3);
end
selectedColorsLUT = dataset.image.lutColors(min(slices{4}, size(dataset.image.lutColors, 1)), :);

switch colortype
    case 'grayscale'
        % Apply contrast adjustment if needed
        if ~obj.onFlyImageStretch && ...
           (currViewPort.min(1) ~= 0 || currViewPort.max(1) ~= max_int || currViewPort.gamma(1) ~= 1)

            if ~isa(sImg, 'uint32')
                [lowIn, highIn, lowOut, highOut] = dataset.image.getImAdjustStretchCoef(1);
                sImg = imadjust(sImg, [lowIn, highIn], [lowOut highOut], currViewPort.gamma(1));
            else
                sImg = uint8(double((sImg - currViewPort.min)) / ...
                            double((currViewPort.max - currViewPort.min)) * 255);
                colorScale = 255;
            end
        elseif isa(sImg, 'double')
            sImg = uint8(sImg);
            colorScale = 255;
        end

        % Apply LUT or grayscale
        if options.useLut
            R = sImg * selectedColorsLUT(1, 1);
            G = sImg * selectedColorsLUT(1, 2);
            B = sImg * selectedColorsLUT(1, 3);
        else
            R = sImg;
            G = sImg;
            B = sImg;
        end

    case 'indexed'
        % Convert indexed image to RGB
        cmap = dataset.image.colormap;
        sImg = uint8(ind2rgb(sImg, cmap) * 255);
        R = sImg(:,:,1);
        G = sImg(:,:,2);
        B = sImg(:,:,3);

    otherwise % multichannel
        if options.useLut
            % Use LUT for color mixing
            adjImg = imadjust(sImg(:,:,1), ...
                [currViewPort.min(slices{4}(1))/max_int, currViewPort.max(slices{4}(1))/max_int], ...
                [0 1], currViewPort.gamma(slices{4}(1)));
            R = adjImg * selectedColorsLUT(1, 1);
            G = adjImg * selectedColorsLUT(1, 2);
            B = adjImg * selectedColorsLUT(1, 3);

            if numel(slices{4}) > 1
                for i = 2:numel(slices{4})
                    adjImg = imadjust(sImg(:,:,i), ...
                        [currViewPort.min(slices{4}(i))/max_int, currViewPort.max(slices{4}(i))/max_int], ...
                        [0 1], currViewPort.gamma(slices{4}(i)));
                    R = R + adjImg * selectedColorsLUT(i, 1);
                    G = G + adjImg * selectedColorsLUT(i, 2);
                    B = B + adjImg * selectedColorsLUT(i, 3);
                end
            end
        else
            % Standard RGB display
            if numel(slices{4}) > 3
                % More than 3 channels - use first 3, batched imadjust
                [lowIn, highIn, lowOut, highOut] = dataset.image.getImAdjustStretchCoef(1:3);
                adjRGB = imadjust(sImg(:,:,1:3), [lowIn(:)'; highIn(:)'], [lowOut(:)'; highOut(:)'], currViewPort.gamma(1:3));
                R = adjRGB(:,:,1); G = adjRGB(:,:,2); B = adjRGB(:,:,3);

            elseif numel(slices{4}) == 3
                % Exactly 3 channels selected, batched imadjust
                [lowIn, highIn, lowOut, highOut] = dataset.image.getImAdjustStretchCoef(slices{4});
                adjRGB = imadjust(sImg(:,:,1:3), [lowIn(:)'; highIn(:)'], [lowOut(:)'; highOut(:)'], currViewPort.gamma(slices{4}));
                R = adjRGB(:,:,1); G = adjRGB(:,:,2); B = adjRGB(:,:,3);

            elseif numel(slices{4}) == 2
                % Two channels - map to RGB based on selection
                [lowIn, highIn, lowOut, highOut] = dataset.image.getImAdjustStretchCoef(slices{4});

                if dataset.image.colors == 3 || slices{4}(end) < 4
                    if slices{4}(1) ~= 1
                        R = zeros(size(sImg,1), size(sImg,2), 'like', sImg);
                        G = imadjust(sImg(:,:,1), [lowIn(1), highIn(1)], [lowOut(1) highOut(1)], currViewPort.gamma(slices{4}(1)));
                        B = imadjust(sImg(:,:,2), [lowIn(2), highIn(2)], [lowOut(2) highOut(2)], currViewPort.gamma(slices{4}(2)));
                    elseif slices{4}(2) ~= 2
                        R = imadjust(sImg(:,:,1), [lowIn(1), highIn(1)], [lowOut(1) highOut(1)], currViewPort.gamma(slices{4}(1)));
                        G = zeros(size(sImg,1), size(sImg,2), 'like', sImg);
                        B = imadjust(sImg(:,:,2), [lowIn(2), highIn(2)], [lowOut(2) highOut(2)], currViewPort.gamma(slices{4}(2)));
                    else
                        R = imadjust(sImg(:,:,1), [lowIn(1), highIn(1)], [lowOut(1) highOut(1)], currViewPort.gamma(slices{4}(1)));
                        G = imadjust(sImg(:,:,2), [lowIn(2), highIn(2)], [lowOut(2) highOut(2)], currViewPort.gamma(slices{4}(2)));
                        B = zeros(size(sImg,1), size(sImg,2), 'like', sImg);
                    end
                else
                    R = imadjust(sImg(:,:,1), [lowIn(1), highIn(1)], [lowOut(1) highOut(1)], currViewPort.gamma(slices{4}(1)));
                    G = imadjust(sImg(:,:,2), [lowIn(2), highIn(2)], [lowOut(2) highOut(2)], currViewPort.gamma(slices{4}(2)));
                    B = zeros(size(sImg,1), size(sImg,2), 'like', sImg);
                end

            elseif isscalar(slices{4})
                % Single channel - display as grayscale
                [lowIn, highIn, lowOut, highOut] = dataset.image.getImAdjustStretchCoef(slices{4}(1));
                R = imadjust(sImg(:,:,1), [lowIn, highIn], [lowOut highOut], currViewPort.gamma(slices{4}(1)));
                G = R;
                B = R;
            end
        end
end

%% Overlay segmentation model
if ~isempty(sOver1) && ~isnan(sOver1(1,1,1))
    sList = dataset.labels.materialNames;
    T = obj.preferences.Colors.ModelTransparency;

    if dataset.labels.maxMaterials ~= 127 && dataset.labels.maxMaterials ~= 32767
        M = sOver1;
        selectedObject = dataset.getSelectedMaterialIndex();

        % Convert to contour if needed
        if obj.preferences.Styles.Labels.ShowAsContours
            if dataset.showAllMaterials
                if strcmp(obj.preferences.Styles.Contour.ThicknessRendering, 'quality')
                    M2 = zeros(size(M), 'uint8');
                    for ind = 1:numel(sList)
                        M3 = zeros(size(M2), 'uint8');
                        M3(M == ind) = 1;
                        M3 = M3 - imerode(M3, strel('disk', obj.preferences.Styles.Contour.ThicknessModels));
                        M2(M3 == 1) = ind;
                    end
                    M = M2;
                else
                    M = M - imerode(M, strel('disk', obj.preferences.Styles.Contour.ThicknessModels));
                end
            elseif selectedObject > 0
                ind = selectedObject;
                M2 = zeros(size(M), 'uint8');
                M2(M == ind) = ind;
                M = M2 - imerode(M2, strel('disk', obj.preferences.Styles.Contour.ThicknessModels));
            end
        end

        % Blend model colors with image
        if dataset.showAllMaterials
            % labeloverlay path: single optimized C call (uint8 RGB only, ≤65535 materials)
            useLabelOverlay = isa(R, 'uint8') && dataset.labels.maxMaterials <= 65535;
            if useLabelOverlay && any(M, 'all')
                imgTmp = cat(3, R, G, B);
                imgTmp = labeloverlay(imgTmp, M, ...
                    'Colormap', dataset.labels.materialColors, ...
                    'Transparency', T);
                R = imgTmp(:,:,1); G = imgTmp(:,:,2); B = imgTmp(:,:,3);
            else
                nzMask = (M ~= 0);
                if any(nzMask, 'all')
                    switch class(R)
                        case 'uint8'
                            modColors = uint8(dataset.labels.materialColors * colorScale);
                        case 'uint16'
                            modColors = uint16(dataset.labels.materialColors * colorScale);
                        case 'uint32'
                            modColors = uint32(dataset.labels.materialColors * colorScale);
                    end

                    if dataset.labels.maxMaterials <= 65535
                        Mvals = M(nzMask);
                    else
                        Mvals = mod(M(nzMask) - 1, 65535) + 1;
                    end
                    R(nzMask) = imlincomb(T, R(nzMask), 1-T, modColors(Mvals, 1));
                    G(nzMask) = imlincomb(T, G(nzMask), 1-T, modColors(Mvals, 2));
                    B(nzMask) = imlincomb(T, B(nzMask), 1-T, modColors(Mvals, 3));
                end
            end
        elseif selectedObject > 0
            materialIdx = selectedObject;
            nzMask = (M == materialIdx);
            if dataset.labels.maxMaterials > 65535
                materialIdx = mod(materialIdx - 1, 65535) + 1;
            end
            if any(nzMask, 'all')
                R(nzMask) = R(nzMask) * T + dataset.labels.materialColors(materialIdx, 1) * colorScale * (1 - T);
                G(nzMask) = G(nzMask) * T + dataset.labels.materialColors(materialIdx, 2) * colorScale * (1 - T);
                B(nzMask) = B(nzMask) * T + dataset.labels.materialColors(materialIdx, 3) * colorScale * (1 - T);
            end
        end
    elseif dataset.modelType == 127 || dataset.modelType == 32767
        % Special signed model visualization
        maximum = max(sOver1, [], 'all');
        coef = double(1 + 255/maximum * (1 - T));
        R = zeros(size(R), 'uint8');
        R(sOver1 < 0) = uint8(abs(sOver1(sOver1 < 0))) * coef;
        B = zeros(size(B), 'uint8');
        B(sOver1 > 0) = uint8(sOver1(sOver1 > 0)) * coef;
    end
end

%% Overlay mask layer
T1 = obj.preferences.Colors.SelectionTransparency;

if ~isempty(sOver2) && ~isnan(sOver2(1,1,1))
    T2 = obj.preferences.Colors.MaskTransparency;
    ind = 1;

    % Convert to contour if needed
    if obj.preferences.Styles.Masks.ShowAsContours
        if obj.preferences.Styles.Contour.ThicknessMethodMasks(1) == 'i'
            M = sOver2 - imerode(sOver2, strel('disk', obj.preferences.Styles.Contour.ThicknessMasks));
        else
            M = imdilate(sOver2, strel('disk', obj.preferences.Styles.Contour.ThicknessMasks)) - sOver2;
        end
    else
        M = sOver2;
    end

    % Blend mask color
    nzMask = (M == ind);
    if any(nzMask, 'all')
        R(nzMask) = R(nzMask) * T2 + obj.preferences.Colors.MaskColor(1) * colorScale * (1 - T2);
        G(nzMask) = G(nzMask) * T2 + obj.preferences.Colors.MaskColor(2) * colorScale * (1 - T2);
        B(nzMask) = B(nzMask) * T2 + obj.preferences.Colors.MaskColor(3) * colorScale * (1 - T2);
    end
end

%% Overlay selection layer
if ~isnan(selectionLayer(1))
    nzSel = logical(selectionLayer);
    R(nzSel) = R(nzSel) * T1 + obj.preferences.Colors.SelectionColor(1) * colorScale * (1 - T1);
    G(nzSel) = G(nzSel) * T1 + obj.preferences.Colors.SelectionColor(2) * colorScale * (1 - T1);
    B(nzSel) = B(nzSel) * T1 + obj.preferences.Colors.SelectionColor(3) * colorScale * (1 - T1);
end

%% Combine RGB channels
imgRGB = cat(3, R, G, B);

% Upscale image if zoomed out
if magnificationFactor < 1 && panModeException == 0
    if strcmp(imageResizeMethod, 'nearest') || strcmp(colortype, 'indexed')
        imgRGB = imgRGB(round(.51:magnificationFactor:end+.49), ...
                        round(.51:magnificationFactor:end+.49), :);
    else
        imgRGB = imresize(imgRGB, 1/magnificationFactor, imageResizeMethod);
    end
end

%% Add 3D lines overlay
if obj.showLines3D && dataset.lines3D.noTrees > 0
    pixBox(5:6) = [sliceToShowIdx sliceToShowIdx];

    if options.blockModeSwitch == 1
        [pixBox(3), pixBox(4), pixBox(1), pixBox(2)] = dataset.getCoordinatesOfShownImage();
    else
        [datasetHeight, datasetWidth] = dataset.getDatasetDimensions('image', [], options);
        pixBox(1) = 1;
        pixBox(2) = datasetWidth;
        pixBox(3) = 1;
        pixBox(4) = datasetHeight;
    end

    bb = dataset.image.boundingBox; % get bounding box of the dataset
    BoxOut = pixBox;

    % Convert pixel coordinates to physical coordinates
    if dataset.orientation == 3 % xy
        BoxOut(1:2) = pixBox(1:2) * dataset.image.pixSize.x + bb(1) - dataset.image.pixSize.x;
        BoxOut(3:4) = pixBox(3:4) * dataset.image.pixSize.y + bb(3) - dataset.image.pixSize.y;
        BoxOut(5:6) = pixBox(5:6) * dataset.image.pixSize.z + bb(5) - dataset.image.pixSize.z;
    elseif dataset.orientation == 1 % zx
        BoxOut(1:2) = pixBox(1:2) * dataset.image.pixSize.z + bb(5) - dataset.image.pixSize.z;
        BoxOut(3:4) = pixBox(3:4) * dataset.image.pixSize.x + bb(1) - dataset.image.pixSize.x;
        BoxOut(5:6) = pixBox(5:6) * dataset.image.pixSize.y + bb(3) - dataset.image.pixSize.y;
    elseif dataset.orientation == 2 % zy
        BoxOut(1:2) = pixBox(1:2) * dataset.image.pixSize.z + bb(5) - dataset.image.pixSize.z;
        BoxOut(3:4) = pixBox(3:4) * dataset.image.pixSize.y + bb(3) - dataset.image.pixSize.y;
        BoxOut(5:6) = pixBox(5:6) * dataset.image.pixSize.x + bb(1) - dataset.image.pixSize.x;
    end

    addLinesOptions.orientation = dataset.orientation;
    imgRGB = dataset.lines3D.addLinesToImage(imgRGB, BoxOut, addLinesOptions);
end

%% Add annotations overlay
if obj.showAnnotations
    Annotations = obj.preferences.SegmTools.Annotations;
    
    if dataset.annotations.getLabelsNumber() >= 1
        if ~isfield(options, 'sliceNo')
            options.sliceNo = dataset.slices{dataset.orientation}(1);
        end

        % Define depth range to display annotations
        zSlices = [options.sliceNo - Annotations.ShownExtraDepth, ...
                   options.sliceNo + Annotations.ShownExtraDepth];

        [labelsList, labelValues, labelPos] = dataset.getSliceLabels(zSlices);
        if isempty(labelsList); return; end

        % Get coordinate indices based on orientation
        if orientation == 3 % xy
            xId = 2;
            yId = 3;
        elseif orientation == 1 % zx
            xId = 1;
            yId = 2;
        elseif orientation == 2 % zy
            xId = 1;
            yId = 3;
        end

        % Calculate annotation positions
        if options.blockModeSwitch == 0
            % Full image mode
            if options.resizeToMagnification
                pos(:,1) = ceil(labelPos(:, xId) / max([magnificationFactor 1]));
                pos(:,2) = ceil(labelPos(:, yId) / max([magnificationFactor 1]));
            else
                pos(:,1) = ceil(labelPos(:, xId));
                pos(:,2) = ceil(labelPos(:, yId));
            end
        else
            % Block mode - adjust for visible area
            [axesX, axesY] = dataset.getAxesLimits();

            if options.resizeToMagnification
                pos(:,1) = ceil((labelPos(:, xId) - max([0 floor(axesX(1))])) / magnificationFactor);
                pos(:,2) = ceil((labelPos(:, yId) - max([0 floor(axesY(1))])) / magnificationFactor);
            else
                pos(:,1) = ceil((labelPos(:, xId) - max([0 floor(axesX(1))])));
                pos(:,2) = ceil((labelPos(:, yId) - max([0 floor(axesY(1))])));
            end
        end

        addTextOptions.markerText = options.markerType;
        addTextOptions.color = Annotations.Color;
        addTextOptions.fontSize = Annotations.FontSize;

        % Format annotation text based on display mode
        switch options.markerType
            case 'Value'
                modString = sprintf('%c.%df', '%', Annotations.Precision);
                labelsList = arrayfun(@(a) sprintf(modString, a), labelValues, 'UniformOutput', 0);

            case 'Label + Value'
                if Annotations.FocusOnValue
                    modString = sprintf('%c.%df: %cs', '%', Annotations.Precision, '%');
                    labelsList = cellfun(@(a, b) sprintf(modString, a, b), num2cell(labelValues), labelsList, 'UniformOutput', 0);
                else
                    modString = sprintf('%cs: %c.%df', '%', '%', Annotations.Precision);
                    labelsList = cellfun(@(a, b) sprintf(modString, a, b), labelsList, num2cell(labelValues), 'UniformOutput', 0);
                end
        end

        imgRGB = utils.addText2Img(imgRGB, labelsList, pos, addTextOptions);
    end
end
end
