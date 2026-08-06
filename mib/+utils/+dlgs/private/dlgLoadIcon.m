function [iconImg, iconColumnWidth] = dlgLoadIcon(iconName, requestedWidth, bgColor, mibDir)
% DLGLOADICON - Load, alpha-composite, resize and cache a dialog icon.
%
% Syntax:
%   .. code-block:: matlab
%
%      [iconImg, iconColumnWidth] = dlgLoadIcon(iconName, requestedWidth, bgColor, mibDir)
%
% The icon is composited against the figure background color (so ``uiimage``
% receives a pre-blended uint8 array) and the result is cached in a persistent
% dictionary; the cache is invalidated when the background color changes
% (theme switch).
%
% Input Arguments:
%   - **iconName** - [char] icon identifier (``'puffin_question'``, ``'warning_48px'``, ...);
%     unknown ids fall back to a random puffin question icon
%   - **requestedWidth** - [numeric] target width in pixels, or ``[]`` to keep the
%     natural image width; ignored for ``'celebrate'``/``'call4help'`` (always 220 px)
%   - **bgColor** - [1x3 double] figure background color used for alpha compositing
%   - **mibDir** - [char] MIB installation folder containing ``assets/images``
%
% Output Arguments:
%   - **iconImg** - [uint8] composited image array for ``uiimage``; ``[]`` when unavailable
%   - **iconColumnWidth** - [numeric] width of the returned image in pixels
%     (48 when the icon could not be loaded, to keep the layout column sane)

persistent iconCompositeCache   % dictionary: cacheKey -> composited uint8 image
persistent iconCacheBgColor     % RGB triplet used for compositing

% Icon id -> filename; several ids map to a random variant of the same icon
switch iconName
    case 'warning_48px';    iconFilename = 'warning_48px.png';
    case 'question_48px';   iconFilename = 'question_48px.png';
    case 'celebrate';       iconFilename = sprintf('puffin_cheering_%d_220px.png', randi(2)); requestedWidth = 220;
    case 'call4help';       iconFilename = sprintf('puffin_call4help_%d_220px.png', randi(3)); requestedWidth = 220;
    case 'puffin_error';    iconFilename = sprintf('puffin_error_%d_96px.png', randi(4));
    case 'puffin_warning';  iconFilename = sprintf('puffin_warning_%d_96px.png', randi(3));
    case 'puffin_question'; iconFilename = sprintf('puffin_quest_%d_96px.png', randi(7));
    case 'puffin_measure';  iconFilename = sprintf('puffin_measure_%d_96px.png', randi(5));
    case 'puffin_info';     iconFilename = sprintf('puffin_info_%d_96px.png', randi(5));
    case 'puffin_waiting';  iconFilename = sprintf('puffin_waiting_%d_96px.png', randi(3));
    otherwise;              iconFilename = sprintf('puffin_quest_%d_96px.png', randi(7));
end

iconImg = [];
iconColumnWidth = 48;   % layout fallback when the icon cannot be loaded
iconPath = fullfile(mibDir, 'assets', 'images', iconFilename);
if ~exist(iconPath, 'file'); return; end

try
    % (Re)initialize the cache; invalidate on background color change (theme switch)
    if isempty(iconCompositeCache) || ~isequal(iconCacheBgColor, bgColor)
        iconCompositeCache = configureDictionary("string", "cell");
        iconCacheBgColor = bgColor;
    end

    widthKey = 0;
    if ~isempty(requestedWidth); widthKey = requestedWidth; end
    cacheKey = string(sprintf('%s_%d', iconFilename, widthKey));

    if isKey(iconCompositeCache, cacheKey)
        iconImg = iconCompositeCache{cacheKey};
    else
        % Read the image and composite the alpha channel with the figure background
        [img, ~, alpha] = imread(iconPath);
        if ~isempty(alpha)
            img = im2double(img);
            alpha = im2double(alpha);
            if size(img, 3) == 3
                for k = 1:3
                    img(:,:,k) = img(:,:,k) .* alpha + bgColor(k) * (1 - alpha);
                end
            else
                img = img .* alpha + mean(bgColor) * (1 - alpha);
            end
            iconImg = im2uint8(img);
        else
            iconImg = img;
        end
        if ~isempty(requestedWidth)
            iconImg = imresize(iconImg, [NaN requestedWidth]);
        end
        iconCompositeCache(cacheKey) = {iconImg};
    end
    iconColumnWidth = size(iconImg, 2);
catch
    iconImg = [];
    iconColumnWidth = 48;
end
end
