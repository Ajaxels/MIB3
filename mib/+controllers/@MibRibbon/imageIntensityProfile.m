function imageIntensityProfile(obj, mode)
% IMAGEINTENSITYPROFILE - Draw a line or freehand path and display the intensity profile.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.imageIntensityProfile(mode)
%
% Lets the user draw an interactive ROI on the current image view, then on
% double-click **or Enter** computes ``improfile`` for each displayed color
% channel and shows the result in a two-panel MATLAB figure (image with
% overlay on top, intensity vs. distance on the bottom).  Press Escape to
% cancel without computing.
%
% Input Arguments:
%   - **mode** - char; drawing mode
%
%     - ``'line'``      - straight line between two endpoints
%     - ``'arbitrary'`` - freehand open path
%
% Output Arguments:
%   (none)
%
% Usage:
%   **Example 1** - called from image_Callbacks
%
%   .. code-block:: matlab
%
%       obj.imageIntensityProfile('line');
%       obj.imageIntensityProfile('arbitrary');
%

% Updates
%

id = obj.mibModel.getActiveId();
colorChannel = obj.mibModel.I{id}.slices{4};   % currently shown color channels (index 4 in MIB3)

cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
savedWBDF = cImageDoc.UIFigure.WindowButtonDownFcn;
savedKPF  = cImageDoc.UIFigure.WindowKeyPressFcn;
cImageDoc.UIFigure.WindowButtonDownFcn = [];
obj.mibModel.disableSegmentation = true;

switch mode
    case 'line'
        roi = drawline(cImageDoc.handles.imViewAxes);
    case 'arbitrary'
        roi = drawfreehand(cImageDoc.handles.imViewAxes, 'Closed', false);
    otherwise
        cImageDoc.UIFigure.WindowButtonDownFcn = savedWBDF;
        obj.mibModel.disableSegmentation = false;
        return;
end

cImageDoc.UIFigure.WindowButtonDownFcn = savedWBDF;

if ~isvalid(roi)
    obj.mibModel.disableSegmentation = false;
    return;
end

% Install temporary key handler: Enter = accept, Escape = cancel.
profileKPF = @(~, evt) handleProfileKey(evt, roi, obj, id, colorChannel, mode, cImageDoc, savedKPF);
cImageDoc.UIFigure.WindowKeyPressFcn = profileKPF;

% Double-click accepts; ROI deletion cleans up.
addlistener(roi, 'ROIClicked',  @(src, evt) onROIClicked(src, evt, obj, id, colorChannel, mode, cImageDoc, savedKPF));
addlistener(roi, 'DeletingROI', @(~,~) cleanupProfileROI(obj, cImageDoc, savedKPF));

end

% -------------------------------------------------------------------------
function handleProfileKey(evt, roi, obj, id, colorChannel, mode, cImageDoc, savedKPF)
% HANDLEPROFILEKEY - Temporary WindowKeyPressFcn while profile ROI is active.
if ~isvalid(roi); return; end
switch evt.Key
    case 'return'
        finalizeProfile(roi, obj, id, colorChannel, mode, cImageDoc, savedKPF);
    case 'escape'
        delete(roi);   % triggers DeletingROI → cleanupProfileROI
end
end

% -------------------------------------------------------------------------
function onROIClicked(roi, evt, obj, id, colorChannel, mode, cImageDoc, savedKPF)
% ONROICLICKED - Accept profile on double-click; ignore single clicks.
if ~strcmp(evt.SelectionType, 'double'); return; end
finalizeProfile(roi, obj, id, colorChannel, mode, cImageDoc, savedKPF);
end

% -------------------------------------------------------------------------
function cleanupProfileROI(obj, cImageDoc, savedKPF)
% CLEANUPPROILEROI - Restore state when the ROI is deleted without finalising.
obj.mibModel.disableSegmentation = false;
cImageDoc.UIFigure.WindowKeyPressFcn = savedKPF;
end

% -------------------------------------------------------------------------
function finalizeProfile(roi, obj, id, colorChannel, mode, cImageDoc, savedKPF)
% FINALIZEPROFILE - Compute and display the intensity profile, then clean up.

if ~isvalid(roi); return; end
pos = roi.Position;    % [2×2] for line; [N×2] for freehand - columns are [x, y]
delete(roi);           % triggers DeletingROI, but cleanupProfileROI is idempotent

% Restore key handler and segmentation immediately so MIB is interactive
% while the (potentially slow) profile figure is being built.
cImageDoc.UIFigure.WindowKeyPressFcn = savedKPF;
obj.mibModel.disableSegmentation = false;

% ---- Build sample-point vectors (axes coordinate space) ----
switch mode
    case 'line'
        x1 = pos(1,1);  y1 = pos(1,2);
        x2 = pos(2,1);  y2 = pos(2,2);
        noPoints = max(abs(ceil(x2 - x1)), abs(ceil(y2 - y1)));
        if noPoints < 2; noPoints = 2; end
        posX = linspace(x1, x2, noPoints);
        posY = linspace(y1, y2, noPoints);
    case 'arbitrary'
        posX = pos(:,1);
        posY = pos(:,2);
end

% ---- Convert axes coordinates to full-dataset pixel coordinates ----
% roi.Position is in imViewAxes data space, which is stretched by coef_z in X
% and scaled by the current zoom (magFactor). 'shown' mode undoes both.
[posXdataset, posYdataset] = obj.mibModel.convertMouseToDataCoordinates(posX(:), posY(:), 'shown');
posXdataset = round(posXdataset);
posYdataset = round(posYdataset);

% ---- Fetch full-resolution image slice for the profile ----
sliceNumber = obj.mibModel.I{id}.getCurrentSliceNumber();
orientation = obj.mibModel.I{id}.orientation;
getDataOptions.blockModeSwitch = 0;
getDataOptions.id = id;
img = cell2mat(obj.mibModel.getData2D('image', sliceNumber, orientation, colorChannel, getDataOptions));

if isempty(img); return; end

% Clamp to image bounds
posXdataset = max(1, min(size(img, 2), posXdataset));
posYdataset = max(1, min(size(img, 1), posYdataset));

% ---- Compute intensity profiles (one column per channel) ----
nChannels    = size(img, 3);
sampleLength = numel(improfile(img(:,:,1), posXdataset, posYdataset));
profileData  = zeros(sampleLength, nChannels);
for colIdx = 1:nChannels
    profileData(:, colIdx) = improfile(img(:,:,colIdx), posXdataset, posYdataset);
end

% ---- Legend labels ----
legendLabels = arrayfun(@(ch) sprintf('Ch %d', ch), colorChannel, 'UniformOutput', false);

% ---- LUT colors for displayed channels ----
lutColors     = obj.mibModel.I{id}.image.lutColors;
channelColors = lutColors(colorChannel, :);

% ---- Build figure ----
profileFigure = figure(15214);
clf(profileFigure);
profileFigure.Name        = 'MIB: Intensity Profile';
profileFigure.NumberTitle = 'off';

% -- Top panel: full-resolution image with 3-D profile overlay --
ax1 = subplot(2, 1, 1, 'Parent', profileFigure);

for colIdx = 1:nChannels
    improfile(img(:,:,colIdx), posXdataset, posYdataset);
    hold(ax1, 'on');
end
profileLineHandles = findobj(ax1, 'Type', 'line');
for lineIdx = 1:numel(profileLineHandles)
    profileLineHandles(numel(profileLineHandles) - lineIdx + 1).Color = channelColors(lineIdx, :);
end

% Full-resolution RGB so background and profile overlay share the same coordinate space
getDataOpt.blockModeSwitch = 0;
getDataOpt.resize = 'no';
rgbImage = obj.mibModel.getRGBimage(getDataOpt, id);

imgH = size(rgbImage, 1);
imgW = size(rgbImage, 2);
ax1.YLim = [1, imgH];
ax1.XLim = [1, imgW];
[xGrid, yGrid] = meshgrid(1:imgW, 1:imgH);
zBase = zlim(ax1);
surf(ax1, xGrid, yGrid, zBase(1) + zeros(imgH, imgW), rgbImage, 'EdgeColor', 'none');
colormap(ax1, 'gray');
hold(ax1, 'off');

title(ax1, sprintf('Image profile - channel(s): %s', num2str(colorChannel)));
maxProfileVal = max(profileData(:));
if maxProfileVal > 0
    ax1.DataAspectRatio = [1, 1, maxProfileVal / imgH * 5];
end
grid(ax1, 'on');

% -- Bottom panel: intensity vs. point index --
ax2 = subplot(2, 1, 2, 'Parent', profileFigure);
plotHandles = plot(ax2, 1:sampleLength, profileData);
for lineIdx = 1:numel(plotHandles)
    plotHandles(lineIdx).Color = channelColors(lineIdx, :);
end
legend(ax2, legendLabels, 'Location', 'best');
xlabel(ax2, 'Point in the profile');
ylabel(ax2, 'Intensity');
grid(ax2, 'on');

end
