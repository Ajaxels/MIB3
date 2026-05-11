function alignDriftCorrectionHDD_Alignment(obj, parameters)
% ALIGNDRIFTCORRECTIONHDD_ALIGNMENT - Streaming drift correction over a directory of images.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.alignDriftCorrectionHDD_Alignment(parameters)
%
% Streaming variant of :meth:`DriftCorrection_Alignment` for stacks that
% do not fit in memory. Reads slices one at a time from
% ``obj.BatchOpt.HDD_InputDir`` (filtered by ``HDD_InputFilenameExtension``)
% via :class:`matlab.io.datastore.ImageDatastore` configured with
% :func:`io.loadImagesWrapper` as its ``ReadFcn``; computes FFT
% cross-correlation pairwise; integrates pairwise shifts via ``cumsum``
% (``CorrelateWith = 'Previous slice'`` / ``'Relative to'``) or keeps
% slice 1 as the reference throughout (``CorrelateWith = 'First slice'``);
% optionally smooths via :func:`utils.align.subtractRunningAverage`;
% then re-reads each image, places it onto a padded canvas, and saves it
% to ``<InputDir>/HDD_OutputSubfolderName`` in the chosen format via
% :meth:`core.MibImage.save`.
%
% No in-memory dataset is modified — only files in the output directory.
% This means **no backup is taken** (there's nothing to back up) and the
% trailing ``NewDataset`` notify is suppressed.
%
% Cancellation: a :class:`core.PoolWaitbar` is constructed with
% ``Cancelable = true`` whenever ``BatchOpt.showWaitbar`` is set; cancel
% state is polled between every image.
%
% Input Arguments:
%   - **parameters** — struct produced by :meth:`continueBtn_Callback`.
%     Reads ``method``, ``colorCh``, ``backgroundColor``, ``useBatchMode``,
%     ``refFrame``, ``Subarea``, ``minX/maxX/minY/maxY``,
%     ``IntensityGradient``.

% Updates
%

% Parent figure for any dialogs — ``obj.view`` is empty in batch mode
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

% --- Pre-flight: same-size requirement reminder
if ~parameters.useBatchMode
    questOpt.Icon = 'puffin_warning';
    questOpt.WindowStyle = 'modal';
    answer = utils.dlgs.inputQuestDlg(parentFig, ...
        sprintf(['Before proceeding, please confirm that all images in the input ' ...
                'directory have the same dimensions.\n\nIf images have variable ' ...
                'dimensions, try the HDD mode of the Automatic feature-based ' ...
                'algorithm instead.']), ...
        'HDD drift correction', 'Yes, images are the same size', 'Cancel', '', ...
        'Yes, images are the same size', questOpt);
    if isempty(answer) || strcmp(answer, 'Cancel'); return; end
end

% --- Subarea (manual ROI) for FFT correlation
manualModeSwitch = false;
x1 = []; x2 = []; y1 = []; y2 = [];
if isempty(obj.shiftsX) && strcmp(obj.BatchOpt.Subarea{1}, 'Manually specified')
    x1 = obj.BatchOpt.minX{1};
    x2 = obj.BatchOpt.maxX{1};
    y1 = obj.BatchOpt.minY{1};
    y2 = obj.BatchOpt.maxY{1};
    manualModeSwitch = true;
end

% --- Build the imageDatastore
inputDir = obj.BatchOpt.HDD_InputDir;
if ~isfolder(inputDir)
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('Input directory does not exist: "%s"', inputDir), 'HDD drift');
    return;
end
ext = lower(['.' obj.BatchOpt.HDD_InputFilenameExtension{1}]);

readOpt = struct();
readOpt.mibBioformatsCheck = obj.BatchOpt.HDD_BioformatsReader;
readOpt.verbose = false;
readOpt.BioFormatsIndices = obj.BatchOpt.HDD_BioformatsIndex{1};

try
    imgDS = imageDatastore(inputDir, ...
        'FileExtensions', ext, ...
        'IncludeSubfolders', false, ...
        'ReadFcn', @(fn) io.loadImagesWrapper(fn, readOpt));
catch ME
    utils.dlgs.showErrorDialog(parentFig, ME, 'HDD drift');
    return;
end

NumFiles = numel(imgDS.Files);
if NumFiles < 2
    utils.dlgs.showErrorDialog(parentFig, ...
        sprintf('Found %d files in "%s" — need at least 2 to align.', NumFiles, inputDir), ...
        'HDD drift');
    return;
end

% --- Set up cancelable progress
pwb = [];
if obj.BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(NumFiles, 'HDD drift: computing shifts...', ...
        parentFig, 'Alignment', true);
end
cleanupWb = onCleanup(@() safeDeleteWaitbar(pwb));

% --- Phase 1: compute pairwise shifts (skipped if replayed from obj.shiftsX)
if isempty(obj.shiftsX)
    [shiftX, shiftY, ok] = computeHDDShifts(imgDS, parameters, manualModeSwitch, ...
        x1, x2, y1, y2, obj.BatchOpt.IntensityGradient, ...
        obj.BatchOpt.Algorithm{1}, pwb, parentFig);
    if ~ok; return; end

    % Integrate pairwise shifts according to refFrame
    switch parameters.refFrame
        case 0      % Previous slice
            shiftX = cumsum(shiftX);
            shiftY = cumsum(shiftY);
        case 1      % First slice (already absolute — done inside computeHDDShifts)
            % no-op
        otherwise   % Relative to N (negative refFrame)
            % Same windowed-step accumulation as MIB2's option 2
            step = -parameters.refFrame;
            sX = shiftX;  sY = shiftY;
            refId = step;
            for j = step + 2 : numel(sY)
                if mod(j, step) == 0
                    sX(j) = shiftX(j) + sX(refId);
                    sY(j) = shiftY(j) + sY(refId);
                    refId = j;
                else
                    sX(j) = shiftX(j) + sX(refId - step + 1);
                    sY(j) = shiftY(j) + sY(refId - step + 1);
                end
            end
            shiftX = round(utils.align.windv(sX, step));
            shiftY = round(utils.align.windv(sY, step));
    end

    % --- Optional running-average smoothing
    if obj.BatchOpt.SubtractRunningAverage
        halfwidth     = obj.BatchOpt.SubtractRunningAverageStep{1};
        excludePeaks  = obj.BatchOpt.SubtractRunningAverageExcludePeaks{1};
        [shiftX, shiftY] = utils.align.subtractRunningAverage(parentFig, ...
            shiftX, shiftY, halfwidth, excludePeaks, parameters.useBatchMode);
        if isempty(shiftX); return; end
    end

    obj.shiftsX = shiftX;
    obj.shiftsY = shiftY;
end

% --- Phase 2: apply shifts — re-read, pad, save each image to the output dir
shiftsX = obj.shiftsX;
shiftsY = obj.shiftsY;
minX = min(shiftsX);   maxX = max(shiftsX);
minY = min(shiftsY);   maxY = max(shiftsY);
deltaX = abs(minX) + maxX;
deltaY = abs(minY) + maxY;

outputDir = fullfile(inputDir, obj.BatchOpt.HDD_OutputSubfolderName);
if ~isfolder(outputDir); mkdir(outputDir); end

saveOpt = saveOptionsFromExt(obj.BatchOpt.HDD_OutputFileExtension{1});
saveOpt.showWaitbar = false;
saveOpt.silent      = true;
saveOpt.overwrite   = true;

imgDS.reset();
if ~isempty(pwb)
    pwb.updateText('HDD drift: warping & saving images...');
    pwb.setCurrentIteration(0);
end

for imgId = 1:NumFiles
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
    end
    [imgIn5D, fileinfo] = readimage(imgDS, imgId);   % [H, W, Z=1, C, T=1]
    [height, width, ~, nColors] = size(imgIn5D, 1:4);
    imgIn = reshape(imgIn5D(:, :, 1, :, 1), height, width, nColors);

    % Allocate output canvas
    bg = resolveBgValue(parameters.backgroundColor, imgIn);
    imgOut = zeros(height + deltaY, width + deltaX, nColors, class(imgIn));
    if bg ~= 0; imgOut = imgOut + cast(bg, class(imgIn)); end

    Xo = shiftsX(imgId) - minX + 1;
    Yo = shiftsY(imgId) - minY + 1;
    imgOut(Yo:Yo+height-1, Xo:Xo+width-1, :) = imgIn;

    % Save to the output directory under the same basename + chosen extension
    [~, baseName, ~] = fileparts(fileinfo.Filename);
    fnOut = fullfile(outputDir, [baseName lower(['.' obj.BatchOpt.HDD_OutputFileExtension{1}])]);

    % Wrap into a MibImage and save
    mibImg = core.MibImage(reshape(imgOut, [size(imgOut, 1), size(imgOut, 2), 1, nColors, 1]));
    mibImg.save(fnOut, saveOpt);

    if ~isempty(pwb); pwb.increment(); end
end

% Note: HDD mode doesn't touch the in-memory dataset, so no backup or
% NewDataset notify here. Only the output directory has been written.
obj.mibModel.I{obj.mibModel.getActiveId()}.image.updateActionLog(sprintf( ...
    'HDD-aligned using %s; refFrame=%d, output → %s', ...
    parameters.method, parameters.refFrame, outputDir));
end

% =============================================================================
function [shiftX, shiftY, ok] = computeHDDShifts(imgDS, parameters, manualMode, ...
    x1, x2, y1, y2, intensityGradient, algorithmName, pwb, parentFig)
% Walk the datastore pair by pair; FFT cross-correlate; record per-frame
% shifts in [px]. Refframe-aware: ``parameters.refFrame == 1`` keeps the
% slice-1 FFT as the reference throughout (absolute), otherwise the
% reference rolls forward to the current frame (pairwise).

NumFiles = numel(imgDS.Files);
shiftX = zeros(NumFiles, 1);
shiftY = zeros(NumFiles, 1);
ok = false;

% Sobel kernels for the optional intensity-gradient pre-filter
hy = fspecial('sobel');
hx = hy';

try
    firstImg = readimage(imgDS, 1);   % [H, W, Z=1, C, T=1]
catch ME
    utils.dlgs.showErrorDialog(parentFig, ME, 'HDD drift: read failed (slice 1)');
    return;
end
fixedImg = sliceTo2D(firstImg, parameters.colorCh, manualMode, x1, x2, y1, y2);
if intensityGradient
    fixedImg = sobelGradient(fixedImg, hx, hy);
end
IrefFirst = fft2(fixedImg);
Iref = IrefFirst;
keepFirstAsReference = (parameters.refFrame == 1);

for imgId = 2:NumFiles
    if ~isempty(pwb)
        if pwb.getCancelState(); return; end
        if mod(imgId, 10) == 0; pwb.increment(); end
    end

    try
        curImg = readimage(imgDS, imgId);
    catch ME
        utils.dlgs.showErrorDialog(parentFig, ME, ...
            sprintf('HDD drift: read failed (slice %d)', imgId));
        return;
    end
    movingImg = sliceTo2D(curImg, parameters.colorCh, manualMode, x1, x2, y1, y2);
    if intensityGradient
        movingImg = sobelGradient(movingImg, hx, hy);
    end
    Icur = fft2(movingImg);

    [Height, Width] = size(Iref);
    imgCenterX = floor(Width  / 2) + 1;
    imgCenterY = floor(Height / 2) + 1;

    prod_ = Iref .* conj(Icur);
    cc = ifft2(prod_);

    if strcmp(algorithmName, 'Drift correction')
        [Yo, Xo] = find(fftshift(cc) == max(cc(:)));
        shiftX(imgId) = Xo(1) - imgCenterX;
        shiftY(imgId) = Yo(1) - imgCenterY;
        % FFT periodic-boundary ambiguity guard
        if abs(shiftX(imgId) - shiftX(imgId - 1)) > Width / 2
            shiftX(imgId) = shiftX(imgId) - sign(shiftX(imgId) - shiftX(imgId - 1)) * Width;
        end
        if abs(shiftY(imgId) - shiftY(imgId - 1)) > Height / 2
            shiftY(imgId) = shiftY(imgId) - sign(shiftY(imgId) - shiftY(imgId - 1)) * Height;
        end
    else
        [Yo, Xo] = find(cc == max(cc(:)));
        shiftY(imgId) = Yo(1);
        shiftX(imgId) = Xo(1);
    end

    if ~keepFirstAsReference
        Iref = Icur;
    end
end
ok = true;
end

% =============================================================================
function img2D = sliceTo2D(img5D, colorCh, manualMode, x1, x2, y1, y2)
% Reduce a [H, W, Z=1, C, T=1] image to a 2-D single-channel matrix on
% the user-selected color channel, optionally cropped to a manual ROI.

img2D = squeeze(img5D(:, :, 1, colorCh, 1));
if manualMode
    img2D = img2D(y1:y2, x1:x2);
end
end

% =============================================================================
function g = sobelGradient(img2D, hx, hy)
Ix = imfilter(double(img2D), hx, 'replicate');
Iy = imfilter(double(img2D), hy, 'replicate');
g  = sqrt(Ix.^2 + Iy.^2);
end

% =============================================================================
function bg = resolveBgValue(backgroundColor, imgIn)
if isnumeric(backgroundColor)
    bg = backgroundColor;
elseif strcmp(backgroundColor, 'black')
    bg = 0;
elseif strcmp(backgroundColor, 'white')
    bg = double(intmax(class(imgIn)));
else    % 'mean'
    bg = mean(imgIn(:));
end
end

% =============================================================================
function saveOpt = saveOptionsFromExt(extLabel)
% Map an `HDD_OutputFileExtension` short code (`'AM'`, `'JPG'`, ...) to a
% ``core.MibImage.save`` format descriptor.

switch extLabel
    case 'AM';   saveOpt.Format = 'Amira Mesh binary (*.am)';
    case 'JPG';  saveOpt.Format = 'Joint Photographic Experts Group (*.jpg)';
    case 'MRC';  saveOpt.Format = 'MRC format for IMOD (*.mrc)';
    case 'NRRD'; saveOpt.Format = 'NRRD Data Format (*.nrrd)';
    case 'PNG';  saveOpt.Format = 'Portable Network Graphics (*.png)';
    case 'TIF';  saveOpt.Format = 'TIF format uncompressed (*.tif)';
    otherwise;   saveOpt.Format = 'TIF format uncompressed (*.tif)';
end
end

% =============================================================================
function safeDeleteWaitbar(pwb)
if ~isempty(pwb) && isvalid(pwb)
    pwb.deletePoolWaitbar();
end
end
