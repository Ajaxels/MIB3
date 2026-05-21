function status = convertImage(obj, format, options)
% CONVERTIMAGE - Convert pixel data to a new color type or bit depth.
%
% Syntax:
%   .. code-block:: matlab
%
%       status = obj.convertImage(format, options)
%
% Converts the image in ``obj.data{1}`` to the requested color type or bit
% depth.  All color-space paths from MIB2 are preserved.  The data array
% has layout ``[H, W, Z, C, T]``.
%
% Input Arguments:
%   - **format** — char, target format:
%
%     - ``'grayscale'``   — single channel
%     - ``'multichannel'`` — 2-or-3-channel RGB
%     - ``'hsvcolor'``    — 3 channels HSV
%     - ``'indexed'``     — indexed color; colormap stored in ``obj.colormap``
%     - ``'uint8'``       — cast to 8-bit  [0 – 255]
%     - ``'uint16'``      — cast to 16-bit [0 – 65535]
%     - ``'uint32'``      — cast to 32-bit [0 – 4294967295]
%
%   - **options** — *(optional)* struct with fields:
%
%     - ``.showWaitbar`` — logical, show or not the progress dialog; default ``true``
%     - ``.parentFigure`` — ``matlab.ui.Figure``, parent for dialogs; pass ``[]`` when unavailable
%     - ``.selectedColorChannels`` — vector of color indices used for LUT blending
%       when converting multichannel (>3 ch) to grayscale or indexed; default ``1:obj.colors``
%
% Output Arguments:
%   - **status** — ``1`` on success, ``0`` on failure or user cancel
%
% **Example 1** — convert to grayscale
%
%   .. code-block:: matlab
%
%      opt.parentFigure = obj.mibGUI;
%      status = img.convertImage('grayscale', opt);
%
% **Example 2** — cast to 8-bit using current viewport stretch
%
%   .. code-block:: matlab
%
%      opt.showWaitbar = false;
%      status = img.convertImage('uint8', opt);
%

% Updates
% 

status = 0;
if nargin < 3; options = struct(); end
if ~isfield(options, 'showWaitbar');           options.showWaitbar = true; end
if ~isfield(options, 'parentFigure');          options.parentFigure = []; end
if ~isfield(options, 'selectedColorChannels'); options.selectedColorChannels = 1:obj.colors; end

maxCounter = obj.time * obj.depth;
from = '';

% Open waitbar only when desired and a parent figure is available
if options.showWaitbar && ~isempty(options.parentFigure)
    waitbar = uiprogressdlg(options.parentFigure, 'Value', 0, ...
        'Message', ['Converting image to ' format ' format'], ...
        'Title', 'Converting image');
    showWb = true;
else
    waitbar = [];
    showWb = false;
end

% =========================================================================
%  Helper: show error dialog using MIB3 utils when parentFigure is set
% =========================================================================
function showError(msg, title)
    if ~isempty(options.parentFigure)
        utils.dlgs.showErrorDialog(options.parentFigure, msg, title);
    else
        errordlg(msg, title);
    end
end

function button = showQuest(msg, title, btn1, btn2, defBtn)
    if ~isempty(options.parentFigure)
        button = utils.dlgs.inputQuestDlg(options.parentFigure, msg, title, btn1, btn2, defBtn);
    else
        button = questdlg(msg, title, btn1, btn2, defBtn);
    end
end

% =========================================================================
%  FORMAT: grayscale
% =========================================================================
if strcmp(format, 'grayscale')
    switch obj.colorType
        case 'grayscale'
            if showWb; delete(waitbar); end
            status = 1;
            return;

        case 'multichannel'
            from = 'multichannel';
            if size(obj.data{1}, 4) > 3
                % LUT blending: blend selected channels into RGB, then grayscale
                I = zeros([obj.height, obj.width, obj.depth, 1, obj.time], obj.dataClass);
                selectedColorsLUT = obj.lutColors(options.selectedColorChannels, :);
                maxIntValue = obj.maxInt;
                index = 0;
                for t = 1:obj.time
                    for sliceId = 1:obj.depth
                        R = zeros([obj.height, obj.width], obj.dataClass);
                        G = zeros([obj.height, obj.width], obj.dataClass);
                        B = zeros([obj.height, obj.width], obj.dataClass);
                        for colorId = 1:numel(options.selectedColorChannels)
                            channelImg = obj.data{1}(:, :, sliceId, options.selectedColorChannels(colorId), t);
                            adjImg = imadjust(channelImg, ...
                                [obj.viewPort.min(options.selectedColorChannels(colorId))/maxIntValue ...
                                 obj.viewPort.max(options.selectedColorChannels(colorId))/maxIntValue], ...
                                [0 1], obj.viewPort.gamma(options.selectedColorChannels(colorId)));
                            R = R + adjImg * selectedColorsLUT(colorId, 1);
                            G = G + adjImg * selectedColorsLUT(colorId, 2);
                            B = B + adjImg * selectedColorsLUT(colorId, 3);
                        end
                        I(:, :, sliceId, 1, t) = rgb2gray(cat(3, R, G, B));
                        index = index + 1;
                        if showWb && mod(index, 10) == 0; waitbar.Value = index / maxCounter; end
                    end
                end
                obj.data{1} = I;
            else
                % Pad to 3 channels then rgb2gray slice-by-slice
                I = obj.data{1};
                numColors = size(I, 4);
                rgbData = zeros([obj.height, obj.width, obj.depth, 3, obj.time], class(I));
                rgbData(:,:,:,1:numColors,:) = I;
                obj.data{1} = zeros([obj.height, obj.width, obj.depth, 1, obj.time], class(I));
                index = 0;
                for t = 1:obj.time
                    for i = 1:obj.depth
                        sliceRGB = zeros(obj.height, obj.width, 3, class(rgbData));
                        sliceRGB(:,:,1) = rgbData(:,:,i,1,t);
                        sliceRGB(:,:,2) = rgbData(:,:,i,2,t);
                        sliceRGB(:,:,3) = rgbData(:,:,i,3,t);
                        obj.data{1}(:,:,i,1,t) = rgb2gray(sliceRGB);
                        index = index + 1;
                        if showWb && mod(index, 10) == 0; waitbar.Value = index / maxCounter; end
                    end
                end
            end

        case 'hsvcolor'
            if showWb; delete(waitbar); end
            showError('Please convert the image to RGB color!', 'Wrong image format!');
            return;

        case 'indexed'
            from = 'indexed';
            I = obj.data{1};
            obj.data{1} = zeros([obj.height, obj.width, obj.depth, 1, obj.time], class(I));
            index = 0;
            for t = 1:obj.time
                for i = 1:obj.depth
                    obj.data{1}(:,:,i,1,t) = ind2gray(I(:,:,i,1,t), obj.colormap);
                    index = index + 1;
                    if showWb && mod(index, 10) == 0; waitbar.Value = index / maxCounter; end
                end
            end
            obj.colormap = [];
    end
    obj.colorType = 'grayscale';

% =========================================================================
%  FORMAT: multichannel
% =========================================================================
elseif strcmp(format, 'multichannel')
    switch obj.colorType
        case 'grayscale'
            from = 'grayscale';
            I = obj.data{1};
            obj.data{1} = zeros([obj.height, obj.width, obj.depth, 3, obj.time], class(I));
            obj.data{1}(:,:,:,1,:) = I;
            obj.data{1}(:,:,:,2,:) = I;
            obj.data{1}(:,:,:,3,:) = I;
            if showWb; waitbar.Value = 0.85; end

        case 'multichannel'
            if showWb; delete(waitbar); end
            status = 1;
            return;

        case 'hsvcolor'
            from = 'hsvcolor';
            I = obj.data{1};
            obj.data{1} = zeros([obj.height, obj.width, obj.depth, 3, obj.time], 'uint8');
            index = 0;
            for t = 1:obj.time
                for i = 1:obj.depth
                    sliceHSV = zeros(obj.height, obj.width, 3, 'double');
                    sliceHSV(:,:,1) = double(I(:,:,i,1,t)) / 255;
                    sliceHSV(:,:,2) = double(I(:,:,i,2,t)) / 255;
                    sliceHSV(:,:,3) = double(I(:,:,i,3,t)) / 255;
                    sliceRGB = uint8(hsv2rgb(sliceHSV) * 255);
                    obj.data{1}(:,:,i,1,t) = sliceRGB(:,:,1);
                    obj.data{1}(:,:,i,2,t) = sliceRGB(:,:,2);
                    obj.data{1}(:,:,i,3,t) = sliceRGB(:,:,3);
                    index = index + 1;
                    if showWb && mod(index, 10) == 0; waitbar.Value = index / maxCounter; end
                end
            end
            if showWb; waitbar.Value = 0.85; end

        case 'indexed'
            from = 'indexed';
            I = obj.data{1};
            maxIntValue = double(intmax(class(I)));
            obj.data{1} = zeros([obj.height, obj.width, obj.depth, 3, obj.time], class(I));
            index = 0;
            for t = 1:obj.time
                for i = 1:obj.depth
                    sliceRGB = cast(ind2rgb(I(:,:,i,1,t), obj.colormap) * maxIntValue, class(I));
                    obj.data{1}(:,:,i,1,t) = sliceRGB(:,:,1);
                    obj.data{1}(:,:,i,2,t) = sliceRGB(:,:,2);
                    obj.data{1}(:,:,i,3,t) = sliceRGB(:,:,3);
                    index = index + 1;
                    if showWb && mod(index, 10) == 0; waitbar.Value = index / maxCounter; end
                end
            end
            obj.colormap = [];
    end
    obj.colorType = 'multichannel';

% =========================================================================
%  FORMAT: hsvcolor
% =========================================================================
elseif strcmp(format, 'hsvcolor')
    switch obj.colorType
        case 'grayscale'
            if showWb; delete(waitbar); end
            showError('Please convert the image to RGB color!', 'Wrong image format!');
            return;

        case 'multichannel'
            from = 'multichannel';
            if size(obj.data{1}, 4) ~= 3
                if showWb; delete(waitbar); end
                showError('Please convert the image to RGB color!', 'Wrong image format!');
                return;
            end
            I = obj.data{1};
            obj.data{1} = zeros([obj.height, obj.width, obj.depth, 3, obj.time], 'uint8');
            index = 0;
            for t = 1:obj.time
                for i = 1:obj.depth
                    sliceRGB = zeros(obj.height, obj.width, 3, 'double');
                    sliceRGB(:,:,1) = double(I(:,:,i,1,t)) / 255;
                    sliceRGB(:,:,2) = double(I(:,:,i,2,t)) / 255;
                    sliceRGB(:,:,3) = double(I(:,:,i,3,t)) / 255;
                    sliceHSV = uint8(rgb2hsv(sliceRGB) * 255);
                    obj.data{1}(:,:,i,1,t) = sliceHSV(:,:,1);
                    obj.data{1}(:,:,i,2,t) = sliceHSV(:,:,2);
                    obj.data{1}(:,:,i,3,t) = sliceHSV(:,:,3);
                    index = index + 1;
                    if showWb && mod(index, 10) == 0; waitbar.Value = index / maxCounter; end
                end
            end
            if showWb; waitbar.Value = 0.85; end

        case 'hsvcolor'
            if showWb; delete(waitbar); end
            status = 1;
            return;

        case 'indexed'
            if showWb; delete(waitbar); end
            showError('Please convert the image to RGB color!', 'Wrong image format!');
            return;
    end
    obj.colorType = 'hsvcolor';

% =========================================================================
%  FORMAT: indexed
% =========================================================================
elseif strcmp(format, 'indexed')
    if strcmp(obj.colorType, 'indexed')
        if showWb; delete(waitbar); end
        status = 1;
        return;
    end
    if strcmp(obj.colorType, 'hsvcolor')
        if showWb; delete(waitbar); end
        showError('Please convert the image to RGB color!', 'Wrong image format!');
        return;
    end

    % Ask for number of gray levels
    if ~isempty(options.parentFigure)
        answer = utils.dlgs.inputUniversalDlg(options.parentFigure, '', ...
            {sprintf('Please enter number of graylevels\n [1-65535]')}, {'255'}, ...
            'Convert to indexed image', struct());
    else
        answer = inputdlg(sprintf('Please enter number of graylevels\n [1-65535]'), ...
            'Convert to indexed image', 1, {'255'});
    end
    if isempty(answer); if showWb; delete(waitbar); end; return; end
    levels = round(str2double(answer{1}));
    if levels >= 1 && levels <= 255
        classId = 'uint8';
    elseif levels > 255 && levels <= 65535
        classId = 'uint16';
    else
        if showWb; delete(waitbar); end
        showError('Wrong number of gray levels', 'Error');
        return;
    end

    switch obj.colorType
        case 'grayscale'
            from = 'grayscale';
            I = obj.data{1};
            obj.data{1} = zeros([obj.height, obj.width, obj.depth, 1, obj.time], classId);
            index = 0;
            for t = 1:obj.time
                for i = 1:obj.depth
                    [obj.data{1}(:,:,i,1,t), obj.colormap] = gray2ind(I(:,:,i,1,t), levels);
                    index = index + 1;
                    if showWb && mod(index, 10) == 0; waitbar.Value = index / maxCounter; end
                end
            end

        case 'multichannel'
            from = 'multichannel';
            if size(obj.data{1}, 4) > 3
                % LUT blending for >3 channels
                I = zeros([obj.height, obj.width, obj.depth, 1, obj.time], classId);
                selectedColorsLUT = obj.lutColors(options.selectedColorChannels, :);
                maxIntValue = obj.maxInt;
                index = 0;
                for t = 1:obj.time
                    for sliceId = 1:obj.depth
                        R = zeros([obj.height, obj.width], obj.dataClass);
                        G = zeros([obj.height, obj.width], obj.dataClass);
                        B = zeros([obj.height, obj.width], obj.dataClass);
                        for colorId = 1:numel(options.selectedColorChannels)
                            channelImg = obj.data{1}(:, :, sliceId, options.selectedColorChannels(colorId), t);
                            adjImg = imadjust(channelImg, ...
                                [obj.viewPort.min(options.selectedColorChannels(colorId))/maxIntValue ...
                                 obj.viewPort.max(options.selectedColorChannels(colorId))/maxIntValue], ...
                                [0 1], obj.viewPort.gamma(options.selectedColorChannels(colorId)));
                            R = R + adjImg * selectedColorsLUT(colorId, 1);
                            G = G + adjImg * selectedColorsLUT(colorId, 2);
                            B = B + adjImg * selectedColorsLUT(colorId, 3);
                        end
                        [I(:,:,sliceId,1,t), obj.colormap] = rgb2ind(cat(3, R, G, B), levels);
                        index = index + 1;
                        if showWb && mod(index, 10) == 0; waitbar.Value = index / maxCounter; end
                    end
                end
                obj.data{1} = I;
            else
                % ≤3 channels: direct rgb2ind
                I = obj.data{1};
                numColors = size(I, 4);
                obj.data{1} = zeros([obj.height, obj.width, obj.depth, 1, obj.time], classId);
                index = 0;
                for t = 1:obj.time
                    for i = 1:obj.depth
                        sliceRGB = zeros(obj.height, obj.width, 3, class(I));
                        for c = 1:numColors
                            sliceRGB(:,:,c) = I(:,:,i,c,t);
                        end
                        [obj.data{1}(:,:,i,1,t), obj.colormap] = rgb2ind(sliceRGB, levels);
                        index = index + 1;
                        if showWb && mod(index, 10) == 0; waitbar.Value = index / maxCounter; end
                    end
                end
            end
    end
    obj.colorType = 'indexed';

% =========================================================================
%  FORMAT: uint8
% =========================================================================
elseif strcmp(format, 'uint8')
    if strcmp(obj.colorType, 'indexed')
        if showWb; delete(waitbar); end
        showError('Convert to RGB or Grayscale first', 'Error');
        return;
    end
    switch obj.dataClass
        case 'uint8'
            if showWb; delete(waitbar); end
            status = 1;
            return;
        case 'uint16'
            from = obj.dataClass;
            if max(obj.viewPort.min) > 0 || max(obj.viewPort.max) < 65535 || mean(obj.viewPort.gamma) ~= 1
                img = zeros(size(obj.data{1}), 'uint8');
                maxIndex = obj.time * obj.colors * obj.depth;
                index = 1;
                for t = 1:obj.time
                    for c = 1:obj.colors
                        for z = 1:obj.depth
                            img(:,:,z,c,t) = uint8(imadjust(obj.data{1}(:,:,z,c,t), ...
                                [obj.viewPort.min(c)/65535 obj.viewPort.max(c)/65535], ...
                                [0 1], obj.viewPort.gamma(c)) / 255);
                            if showWb && mod(index, 10) == 0; waitbar.Value = index / maxIndex; end
                            index = index + 1;
                        end
                    end
                end
                obj.data{1} = img;
                logText = ['ContrastGamma: Min:' num2str(obj.viewPort.min') ', Max: ' num2str(obj.viewPort.max') ...
                    ', Gamma: ' num2str(obj.viewPort.gamma')];
                obj.updateActionLog(regexprep(logText, ' +', ' '));
            else
                obj.data{1} = uint8(obj.data{1} / (double(intmax('uint16')) / double(intmax('uint8'))));
            end
        case 'uint32'
            from = obj.dataClass;
            maxIntValue = double(intmax('uint32'));
            if max(obj.viewPort.min) > 0 || max(obj.viewPort.max) < maxIntValue || mean(obj.viewPort.gamma) ~= 1
                if mean(obj.viewPort.gamma) ~= 1
                    button = showQuest( ...
                        sprintf('!!! Warning !!!\n\nThe gamma correction is not yet implemented and will not be applied to the images!\nWould you like to continue?'), ...
                        'Do conversion without gamma', ...
                        'Continue conversion without Gamma correction', 'Cancel', ...
                        'Continue conversion without Gamma correction');
                    if strcmp(button, 'Cancel'); if showWb; delete(waitbar); end; return; end
                end
                img = zeros(size(obj.data{1}), 'uint8');
                maxIndex = obj.time * obj.colors * obj.depth;
                index = 1;
                for t = 1:obj.time
                    for c = 1:obj.colors
                        minVal = obj.viewPort.min(c);
                        maxVal = obj.viewPort.max(c);
                        for z = 1:obj.depth
                            img(:,:,z,c,t) = uint8((double(obj.data{1}(:,:,z,c,t)) - minVal) * (256 / (maxVal - minVal)));
                            if showWb && mod(index, 10) == 0; waitbar.Value = index / maxIndex; end
                            index = index + 1;
                        end
                    end
                end
                obj.data{1} = img;
                logText = ['ContrastGamma: Min:' num2str(obj.viewPort.min') ', Max: ' num2str(obj.viewPort.max') ...
                    ', Gamma: ' num2str(obj.viewPort.gamma')];
                obj.updateActionLog(regexprep(logText, ' +', ' '));
            else
                obj.data{1} = uint8(obj.data{1} / (maxIntValue / double(intmax('uint8'))));
            end
    end
    obj.dataClass = 'uint8';
    obj.maxInt = double(intmax('uint8'));

% =========================================================================
%  FORMAT: uint16
% =========================================================================
elseif strcmp(format, 'uint16')
    if strcmp(obj.colorType, 'indexed')
        if showWb; delete(waitbar); end
        showError('Convert to RGB or Grayscale first', 'Error');
        return;
    end
    switch obj.dataClass
        case 'uint16'
            from = obj.dataClass;
            if max(obj.viewPort.min) > 0 || max(obj.viewPort.max) < 65535 || mean(obj.viewPort.gamma) ~= 1
                maxIndex = obj.time * obj.colors * obj.depth;
                index = 1;
                for t = 1:obj.time
                    for c = 1:obj.colors
                        for z = 1:obj.depth
                            obj.data{1}(:,:,z,c,t) = imadjust(obj.data{1}(:,:,z,c,t), ...
                                [obj.viewPort.min(c)/65535 obj.viewPort.max(c)/65535], ...
                                [0 1], obj.viewPort.gamma(c));
                            if showWb && mod(index, 10) == 0; waitbar.Value = index / maxIndex; end
                            index = index + 1;
                        end
                    end
                end
                logText = ['ContrastGamma: Min:' num2str(obj.viewPort.min') ', Max: ' num2str(obj.viewPort.max') ...
                    ', Gamma: ' num2str(obj.viewPort.gamma')];
                obj.updateActionLog(regexprep(logText, ' +', ' '));
            else
                if showWb; delete(waitbar); end
                status = 1;
                return;
            end
        case 'uint8'
            from = obj.dataClass;
            if max(obj.viewPort.min) > 0 || max(obj.viewPort.max) < 255 || mean(obj.viewPort.gamma) ~= 1
                obj.data{1} = uint16(obj.data{1});
                maxIndex = obj.time * obj.colors * obj.depth;
                index = 1;
                for t = 1:obj.time
                    for c = 1:obj.colors
                        for z = 1:obj.depth
                            obj.data{1}(:,:,z,c,t) = imadjust(obj.data{1}(:,:,z,c,t), ...
                                [obj.viewPort.min(c)/65535 obj.viewPort.max(c)/65535], ...
                                [0 1], obj.viewPort.gamma(c));
                            if showWb && mod(index, 10) == 0; waitbar.Value = index / maxIndex; end
                            index = index + 1;
                        end
                    end
                end
                logText = ['ContrastGamma: Min:' num2str(obj.viewPort.min') ', Max: ' num2str(obj.viewPort.max') ...
                    ', Gamma: ' num2str(obj.viewPort.gamma')];
                obj.updateActionLog(regexprep(logText, ' +', ' '));
            else
                obj.data{1} = uint16(obj.data{1}) * (double(intmax('uint16')) / double(intmax('uint8')));
            end
        case 'uint32'
            from = obj.dataClass;
            maxIntValue = double(intmax('uint32'));
            if max(obj.viewPort.min) > 0 || max(obj.viewPort.max) < maxIntValue || mean(obj.viewPort.gamma) ~= 1
                if mean(obj.viewPort.gamma) ~= 1
                    button = showQuest( ...
                        sprintf('!!! Warning !!!\n\nThe gamma correction is not yet implemented and will not be applied to the images!\nWould you like to continue?'), ...
                        'Do conversion without gamma', ...
                        'Continue conversion without Gamma correction', 'Cancel', ...
                        'Continue conversion without Gamma correction');
                    if strcmp(button, 'Cancel'); if showWb; delete(waitbar); end; return; end
                end
                img = zeros(size(obj.data{1}), 'uint16');
                maxIndex = obj.time * obj.colors * obj.depth;
                index = 1;
                for t = 1:obj.time
                    for c = 1:obj.colors
                        minVal = obj.viewPort.min(c);
                        maxVal = obj.viewPort.max(c);
                        for z = 1:obj.depth
                            img(:,:,z,c,t) = uint16((double(obj.data{1}(:,:,z,c,t)) - minVal) * (65536 / (maxVal - minVal)));
                            if showWb && mod(index, 10) == 0; waitbar.Value = index / maxIndex; end
                            index = index + 1;
                        end
                    end
                end
                obj.data{1} = img;
                logText = ['ContrastGamma: Min:' num2str(obj.viewPort.min') ', Max: ' num2str(obj.viewPort.max') ...
                    ', Gamma: ' num2str(obj.viewPort.gamma')];
                obj.updateActionLog(regexprep(logText, ' +', ' '));
            else
                obj.data{1} = uint16(obj.data{1} / (maxIntValue / double(intmax('uint16'))));
            end
    end
    obj.dataClass = 'uint16';
    obj.maxInt = double(intmax('uint16'));

% =========================================================================
%  FORMAT: uint32
% =========================================================================
elseif strcmp(format, 'uint32')
    if strcmp(obj.colorType, 'indexed')
        if showWb; delete(waitbar); end
        showError('Convert to RGB or Grayscale first', 'Error');
        return;
    end
    switch obj.dataClass
        case 'uint32'
            if showWb; delete(waitbar); end
            status = 1;
            return;
        case 'uint8'
            from = obj.dataClass;
            obj.data{1} = uint32(obj.data{1}) * (double(intmax('uint32')) / double(intmax('uint8')));
        case 'uint16'
            from = obj.dataClass;
            obj.data{1} = uint32(obj.data{1}) * (double(intmax('uint32')) / double(intmax('uint16')));
    end
    obj.dataClass = 'uint32';
    obj.maxInt = double(intmax('uint32'));
end

% =========================================================================
%  Post-conversion: sync dimension properties, LUT, viewport, action log
% =========================================================================
obj.colors = size(obj.data{1}, 4);
obj.dim_yxzct = [obj.height obj.width obj.depth obj.colors obj.time];

numLutColors = size(obj.lutColors, 1);
if numLutColors < obj.colors
    obj.lutColors(numLutColors+1:obj.colors, :) = ...
        repmat(obj.lutColors(numLutColors, :), [obj.colors - numLutColors, 1]);
end

obj.getDefaultViewPort();
obj.updateActionLog(['Converted from ' from ' to ' format]);
if showWb; delete(waitbar); end
status = 1;
end
