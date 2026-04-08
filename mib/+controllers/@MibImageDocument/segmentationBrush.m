function segmentationBrush(obj, y, x, modifier)
% function segmentationBrush(obj, y, x, modifier)
% Start segmentation using the brush tool
%
% This method initializes the brush tool for interactive painting on the
% image. It creates a structural element based on the brush radius,
% performs an undo backup, and sets up mouse callbacks for brush motion
% and button release. Supports normal brush, eraser (Ctrl), and
% superpixel-assisted (SLIC/Watershed) modes.
%
% Parameters:
% y: double, y-coordinate of the mouse cursor at the starting point (in shown image coords)
% x: double, x-coordinate of the mouse cursor at the starting point (in shown image coords)
% modifier: cell array of chars or char, modifier keys held during click
% @li empty '' - add selection
% @li 'control' - subtract selection (eraser mode)
%
% Return values:
%   (none)
%

%|
% @b Examples:
% @code obj.segmentationBrush(50, 75, '');  // start brush from shown position [y,x]=50,75 @endcode
% @code obj.segmentationBrush(50, 75, 'control');  // start eraser from shown position @endcode

% Updates
%

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

hFig = obj.UIFigure;
dataset = obj.mibModel.I{obj.mibModel.id};

% ---- do backup ----
backupOptions.blockModeSwitch = true;
obj.mibModel.backup('selection', 0, backupOptions);

% ---- read brush radius ----
radius = obj.view.handles.panels.segmentation.handles.brushRadius.Value;
if radius == 0; return; end

% ---- determine add/subtract mode ----
if iscell(modifier)
    isCtrl = any(strcmp(modifier, 'control'));
elseif ischar(modifier)
    isCtrl = strcmp(modifier, 'control');
else
    isCtrl = false;
end

if isCtrl
    brush_switch = 'subtract';
else
    brush_switch = 'add';
end

% ---- initialize brush selection overlay ----
shownH = size(obj.mibModel.Ishown, 1);
shownW = size(obj.mibModel.Ishown, 2);
obj.brushSelection = {};
obj.brushSelection{1}.selection = false(shownH, shownW);

% brushPrevXY is stored in data/axes coords so that the cursor delta in
% gui_WindowBrushMotionFcn is computed in the same space as CurrentPoint.
obj.brushPrevXY = [x, y];

% Convert (x, y) from data/axes space to CData pixel indices for the
% initial dot. imageHandle.XData = [1, shownW * coef_z], so for ZX/ZY
% orientations (coef_z >> 1) a simple clamp would place the dot at the
% wrong column; the linear mapping below handles any coef_z correctly.
XData = obj.imageHandle.XData;
YData = obj.imageHandle.YData;
if XData(end) > XData(1) && shownW > 1
    xc = round((x - XData(1)) / (XData(end) - XData(1)) * (shownW - 1)) + 1;
    xc = max(1, min(shownW, xc));
else
    xc = max(1, min(shownW, x));
end
if YData(end) > YData(1) && shownH > 1
    yc = round((y - YData(1)) / (YData(end) - YData(1)) * (shownH - 1)) + 1;
    yc = max(1, min(shownH, yc));
else
    yc = max(1, min(shownH, y));
end

% ---- generate the structural element for the brush ----
radius = radius - 1;
if radius < 1; radius = 0.5; end
magFactor = obj.mibModel.getMagFactor();
se_size = round(radius / magFactor);

structElement = zeros(se_size*2+1, se_size*2+1);
[xx, yy] = meshgrid(-se_size:se_size, -se_size:se_size);
ball = sqrt((xx/se_size).^2 + (yy/se_size).^2);
structElement(ball <= 1) = 1;

% ---- place initial brush dot ----
obj.brushSelection{1}.selection(yc, xc) = true;

% when the brush is large use bwdist function instead of imdilate
if size(structElement, 2) < 10
    obj.brushSelection{1}.selection = imdilate(obj.brushSelection{1}.selection, structElement);
else
    obj.brushSelection{1}.selection = bwdist(obj.brushSelection{1}.selection) <= size(structElement, 1)/2;
end

% ---- superpixel/cluster mode (not for eraser) ----
clusterMode = obj.mibController.cSegmentation.handles.brushUseClustering.SelectedObject.Text;

if ~strcmp(clusterMode, 'No clusters') && ~isCtrl
    % read color channel
    col_channel = dataset.selectedColorChannel;
    if col_channel == 0; col_channel = NaN; end
    if isnan(col_channel) && (dataset.image.colors ~= 3 && dataset.image.colors ~= 1)
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        header = 'Please select the color channel!';
        dlgOpt.HeaderLines = 1;
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {'Selection panel -> Color channel'}, {''}, 'MibImageDocument.segmentationBrush', dlgOpt);

        % restore callbacks and return
        hFig.Pointer = 'crosshair';
        hFig.WindowButtonUpFcn = [];
        hFig.WindowButtonDownFcn = @(~, ~)obj.gui_WindowButtonDownFcn();
        hFig.WindowKeyPressFcn = @(hWidget, hData)obj.mibController.gui_WindowKeyPressFcn(hWidget, hData);
        obj.mibController.showImage();
        hFig.WindowButtonMotionFcn = @(~, ~)obj.gui_WinMouseMotionFcn();
        return;
    end

    % get 2D image data and resize to shown size
    getDataOptions.blockModeSwitch = 1;
    sImage = cell2mat(obj.mibModel.getData2D('image', [], [], col_channel, getDataOptions));
    sImage = imresize(sImage, [shownH, shownW]);

    % read superpixel parameters
    noLabels = obj.mibController.cSegmentation.handles.clustersPar1.Value;
    compactFactor = obj.mibController.cSegmentation.handles.clustersPar2.Value;

    % apply viewport contrast stretching
    % stretch image for preview
    if obj.mibModel.onFlyImageStretch
        for i=1:size(sImage,3)
            sImage(:,:,i) = imadjust(sImage(:,:,i) ,stretchlim(sImage(:,:,i), [0 1]), []);
        end
    end

    currViewPort = dataset.image.viewPort;
    if isnan(col_channel)
        selectedColChannels = dataset.slices{3};
    else
        selectedColChannels = col_channel;
    end
    max_int = double(intmax(class(sImage)));

    if isa(sImage, 'uint16')
        for colCh = 1:numel(selectedColChannels)
            sImage(:,:,colCh) = imadjust(sImage(:,:,colCh), ...
                [currViewPort.min(selectedColChannels(colCh))/max_int ...
                 currViewPort.max(selectedColChannels(colCh))/max_int], ...
                [0 1], currViewPort.gamma(selectedColChannels(colCh)));
        end
        sImage = uint8(sImage/255);
    elseif isa(sImage, 'uint8')
        for colCh = 1:numel(selectedColChannels)
            if currViewPort.min(selectedColChannels(colCh)) ~= 0 || ...
                    currViewPort.max(selectedColChannels(colCh)) ~= max_int || ...
                    currViewPort.gamma(selectedColChannels(colCh)) ~= 1
                sImage(:,:,colCh) = imadjust(sImage(:,:,colCh), ...
                    [currViewPort.min(selectedColChannels(colCh))/max_int ...
                     currViewPort.max(selectedColChannels(colCh))/max_int], ...
                    [0 1], currViewPort.gamma(selectedColChannels(colCh)));
            end
        end
    end

    if strcmp(clusterMode, 'SLIC')
        % calculate SLIC superpixels
        if exist('slicmex', 'file') == 3
            [slicImage, noLabels] = slicmex(sImage, noLabels, compactFactor);
            slicImage = slicImage + 1;  % remove superpixel with 0 value
        else
            % fallback: use superpixels function (R2016a+)
            [slicImage, noLabels] = superpixels(sImage, noLabels, 'Compactness', compactFactor);
        end
    else  % Watershed
        if compactFactor > 0
            slicImage = imcomplement(sImage);  % invert: ridges become white
        else
            slicImage = sImage;
        end
        mask = imextendedmin(slicImage, noLabels);
        mask = imimposemin(slicImage, mask);
        slicImageB = watershed(mask);
        slicImage = imdilate(slicImageB, ones(3));
        noLabels = max(slicImage(:));
    end

    if noLabels < 255
        obj.brushSelection{2}.slic = uint8(slicImage);
    else
        obj.brushSelection{2}.slic = uint16(slicImage);
    end

    % compute boundary overlay for preview
    if strcmp(clusterMode, 'SLIC')
        if exist('drawregionboundaries', 'file') == 2
            boundaries = drawregionboundaries(obj.brushSelection{2}.slic);
        else
            % fallback: dilate > erode boundary detection
            boundaries = imdilate(obj.brushSelection{2}.slic, ones(3)) > ...
                         imerode(obj.brushSelection{2}.slic, ones(3));
        end
    else
        boundaries = slicImageB == 0;  % watershed boundaries
    end

    CData = obj.imageHandle.CData;
    T2 = obj.mibModel.preferences.Colors.MaskTransparency;
    for ch = 1:3
        img = CData(:,:,ch);
        img(boundaries) = img(boundaries) * T2 + ...
            obj.mibModel.preferences.Colors.MaskColor(ch) * intmax(class(CData)) * (1 - T2);
        CData(:,:,ch) = img;
    end
    obj.imageHandle.CData = CData;

    % NOTE: adaptive dilate mode is not yet ported to MIB3 (no UI widget)
    % When the adaptive checkbox is added, implement brushSelection{3} stats here

    % set special key callback for Ctrl+Z undo of superpixels
    hFig.WindowKeyPressFcn = @(hWidget, hData)obj.gui_WindowKeyPressFcn_BrushSuperpixel(hData);

    % record which superpixels are initially selected
    selectedSlicIndices = unique(obj.brushSelection{2}.slic(obj.brushSelection{1}.selection));
    obj.brushSelection{2}.selectedSlic = ismember(obj.brushSelection{2}.slic, selectedSlicIndices);
    obj.brushSelection{2}.selectedSlicIndices = selectedSlicIndices;
    obj.brushSelection{2}.CData = CData;  % store CData with boundaries for undo
end

obj.brushSelection{1}.travelPathInPixels = 0;  % counter for brush travel distance

% ---- set brush cursor to solid (painting mode) ----
obj.updateBrushCursor([], '-');

% ---- swap figure callbacks for brush drawing ----
hFig.WindowButtonDownFcn = [];
hFig.Pointer = 'custom';
hFig.PointerShapeCData = nan(16);

hFig.WindowButtonMotionFcn = @(~, ~)obj.gui_WindowBrushMotionFcn(structElement);
hFig.WindowButtonUpFcn = @(~, ~)obj.gui_WindowButtonUpFcn(brush_switch);

end
