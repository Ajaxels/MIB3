function output = addColorChannel(obj, img, channelId, lutColors, options)
% ADDCOLORCHANNEL - Add or replace a color channel in the existing dataset.
%
% Syntax:
%   function output = addColorChannel(obj, img, channelId, lutColors, options)
%
% Input Arguments:
%   - **img** — image stack [height, width, depth, colors, time] to add/replace
%   - **channelId** — *(optional)* 1-based channel index to replace;
%     NaN (default) - append img as new color channel(s)
%   - **lutColors** — *(optional)* matrix [nNewChannels x 3] with LUT colors in
%     the range 0-1. Pass NaN (default) to auto-assign random colors.
%   - **options** — *(optional)* struct with fields:
%
%     - ``.ParentFigure`` — handle to parent figure for dialogs (default [])
%     - ``.showWaitbar`` — logical; show progress bar (default true)
%
% Output Arguments:
%   - **output** — 1 - success; 0 - cancelled or failed
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.image.addColorChannel(img, NaN, lutColors, opts);
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.image.addColorChannel(img, 2);    % replace channel 2
%

% Updates
%

output = 0;
if nargin < 5; options   = struct; end
if nargin < 4; lutColors = NaN;    end
if nargin < 3; channelId = NaN;    end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = []; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end

% ---- dimension mismatch check ----------------------------------------
% MIB3 dimension order: [y, x, z, colors, t]
if size(obj.data{1}, 1) ~= size(img, 1) || ...
   size(obj.data{1}, 2) ~= size(img, 2) || ...
   size(obj.data{1}, 5) ~= size(img, 5)
    if ~isempty(options.ParentFigure)
        selection = uiconfirm(options.ParentFigure, ...
            sprintf('Some of the image dimensions mismatch.\nContinue anyway?'), ...
            'Dimensions mismatch!', ...
            'Options', ["Continue", "Cancel"], ...
            'DefaultOption', 1, 'CancelOption', 2, 'Icon', 'warning');
        if strcmp(selection, 'Cancel'); return; end
    end
end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, 'Title', 'Add color channel...', ...
        'Message', 'Please wait...', 'Value', 0);
end

tMax = min([size(obj.data{1}, 5), size(img, 5)]);
zMax = min([size(obj.data{1}, 3), size(img, 3)]);
xMax = min([size(obj.data{1}, 2), size(img, 2)]);
yMax = min([size(obj.data{1}, 1), size(img, 1)]);

noExistingColors = obj.colors;
noExtraColors    = size(img, 4);

if isnan(channelId)
    % ---- append new channel(s) ----------------------------------------
    if options.showWaitbar; wb.Value = 0.1; end
    obj.data{1}(1:yMax, 1:xMax, 1:zMax, noExistingColors+1:noExistingColors+noExtraColors, 1:tMax) = ...
        img(1:yMax, 1:xMax, 1:zMax, :, 1:tMax);
    if options.showWaitbar; wb.Value = 0.9; end

    obj.colors    = noExistingColors + noExtraColors;
    obj.colorType = 'multichannel';
    obj.viewPort.min(noExistingColors+1:noExistingColors+noExtraColors)   = 0;
    obj.viewPort.max(noExistingColors+1:noExistingColors+noExtraColors)   = obj.maxInt;
    obj.viewPort.gamma(noExistingColors+1:noExistingColors+noExtraColors) = 1;
else
    % ---- replace existing channel -------------------------------------
    if options.showWaitbar; wb.Value = 0.1; end
    obj.data{1}(1:yMax, 1:xMax, 1:zMax, channelId, 1:tMax) = ...
        img(1:yMax, 1:xMax, 1:zMax, 1, 1:tMax);
    if options.showWaitbar; wb.Value = 0.9; end

    obj.viewPort.min(channelId)   = 0;
    obj.viewPort.max(channelId)   = obj.maxInt;
    obj.viewPort.gamma(channelId) = 1;
end

% ---- update LUT colors -----------------------------------------------
if ~isscalar(lutColors) || ~isnan(lutColors)
    currLutColors = obj.lutColors(1:noExistingColors, :);
    currLutColors(noExistingColors+1:noExistingColors+noExtraColors, :) = lutColors(1:noExtraColors, :);
    obj.lutColors = currLutColors;
else
    % auto-extend LUT with a random color for each added channel
    while size(obj.lutColors, 1) < obj.colors
        obj.lutColors(end+1, :) = rand(1, 3); %#ok<AGROW>
    end
end

% ensure viewPort vectors are column vectors
if size(obj.viewPort.min,   2) > 1; obj.viewPort.min   = obj.viewPort.min';   end
if size(obj.viewPort.max,   2) > 1; obj.viewPort.max   = obj.viewPort.max';   end
if size(obj.viewPort.gamma, 2) > 1; obj.viewPort.gamma = obj.viewPort.gamma'; end

obj.dim_yxzct = [obj.height, obj.width, obj.depth, obj.colors, obj.time];

if options.showWaitbar; wb.Value = 1; delete(wb); end
output = 1;
end
