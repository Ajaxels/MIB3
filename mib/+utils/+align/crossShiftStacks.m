function [imgOut, bbShiftXY] = crossShiftStacks(I1, I2, shiftX, shiftY, options)
% CROSSSHIFTSTACKS - Concatenate two stacks with an integer XY translation between them.
%
% Syntax:
%   .. code-block:: matlab
%
%      [imgOut, bbShiftXY] = utils.align.crossShiftStacks(I1, I2, shiftX, shiftY)
%      [imgOut, bbShiftXY] = utils.align.crossShiftStacks(I1, I2, shiftX, shiftY, options)
%
% Builds a single output stack that holds ``I1`` followed by ``I2`` along the
% depth dimension, with ``I2`` translated by ``(shiftX, shiftY)`` relative to
% ``I1``. The output canvas is grown to fit the union of both stacks; empty
% regions are filled with ``options.backgroundColor``. Used by landmark-based
% alignment to glue the unchanged reference slices to the warped tail.
%
% Input Arguments:
%   - **I1** - [numeric] reference stack in MIB3 layout
%     ``[height, width, depth, color]`` (4-D) or ``[height, width, depth]``
%     when ``options.modelSwitch = 1`` (service layers).
%   - **I2** - [numeric] stack to place after ``I1``; same layout / class as ``I1``.
%   - **shiftX** - [numeric scalar] integer X translation applied to ``I2``
%     relative to ``I1``.
%   - **shiftY** - [numeric scalar] integer Y translation applied to ``I2``
%     relative to ``I1``.
%   - **options** - *(optional)* struct with fields:
%
%     - ``.backgroundColor`` - [char|numeric] padding colour:
%       ``'black'`` *(default)*, ``'white'``, ``'mean'``, or a numeric scalar
%       of the same class as ``I1``.
%     - ``.modelSwitch`` - [logical] ``1`` when the input is 3-D
%       ``[H, W, Z]`` (mask / labels / selection), ``0`` *(default)* for the
%       4-D image layout ``[H, W, C, Z]``.
%     - ``.waitbar`` - [:class:`core.PoolWaitbar`] existing waitbar to reuse
%       *(optional)*. Cancellation polls ``getCancelState()`` once before the
%       big allocation; returns ``[]`` on cancel.
%
% Output Arguments:
%   - **imgOut** - [numeric] concatenated and shifted stack with depth
%     ``size(I1, end) + size(I2, end)``. Empty if cancelled or on input error.
%   - **bbShiftXY** - [1×2 numeric] ``[xMin, yMin]`` reference-side shift
%     introduced by the canvas resize; callers use this to update the
%     bounding box.
%
% **Example** - concatenate a warped tail onto a reference head:
%
% .. code-block:: matlab
%
%    opts.backgroundColor = 'mean';
%    opts.modelSwitch     = 0;     % 4-D image
%    [imgOut, bb] = utils.align.crossShiftStacks(I1, I2, shiftX, shiftY, opts);

% Updates
%

imgOut    = [];
bbShiftXY = [0, 0];

if nargin < 4
    error('utils:align:crossShiftStacks:missingArgs', ...
        'crossShiftStacks requires 4 arguments: I1, I2, shiftX, shiftY');
end
if nargin < 5; options = struct(); end
if ~isfield(options, 'backgroundColor'); options.backgroundColor = 'black'; end
if ~isfield(options, 'modelSwitch');     options.modelSwitch     = 0; end
if ~isfield(options, 'waitbar');         options.waitbar         = []; end

pwb = options.waitbar;
if ~isempty(pwb) && isvalid(pwb) && pwb.getCancelState(); return; end

% MIB3 layout - work natively in [h, w, d, c]. 3-D service-layer inputs
% (modelSwitch=1) are [h, w, d]; size(..., 4) returns 1 so the same code
% handles them without any permute.
[height1, width1, depth1, color1] = size(I1, 1:4);
[height2, width2, depth2, color2] = size(I2, 1:4);

if height1 == 0 || height2 == 0
    error('utils:align:crossShiftStacks:emptyInput', ...
        'I1 and I2 must be non-empty.');
end

% Resolve the background fill value to a single numeric scalar
if isnumeric(options.backgroundColor)
    backgroundColor = options.backgroundColor;
elseif strcmp(options.backgroundColor, 'black')
    backgroundColor = 0;
elseif strcmp(options.backgroundColor, 'white')
    backgroundColor = intmax(class(I1));
else    % 'mean'
    backgroundColor = mean(I1(:));
end

shiftX = round(shiftX);
shiftY = round(shiftY);
maxColor    = max(color1, color2);
totalDepth  = depth1 + depth2;

% Allocate and place - four quadrants depending on the sign of (shiftX, shiftY).
if shiftX <= 0
    bbShiftXY(1) = shiftX;
    if shiftY >= 0     % I2 sits lower-left relative to I1
        outH = max([height1, shiftY + height2]);
        outW = max([width2,  abs(shiftX) + width1]);
        imgOut = zeros(outH, outW, totalDepth, maxColor, class(I1)) + backgroundColor;
        imgOut(1:height1,                   1 + abs(shiftX):abs(shiftX) + width1, 1:depth1,            1:color1) = I1;
        imgOut(1 + shiftY:shiftY + height2, 1:width2,                              depth1 + 1:totalDepth, 1:color2) = I2;
    else               % I2 sits upper-left relative to I1
        bbShiftXY(2) = shiftY;
        outH = max([abs(shiftY) + height1, height2]);
        outW = max([abs(shiftX) + width1,  width2]);
        imgOut = zeros(outH, outW, totalDepth, maxColor, class(I1)) + backgroundColor;
        imgOut(1 + abs(shiftY):abs(shiftY) + height1, 1 + abs(shiftX):abs(shiftX) + width1, 1:depth1,            1:color1) = I1;
        imgOut(1:height2,                              1:width2,                              depth1 + 1:totalDepth, 1:color2) = I2;
    end
else
    if shiftY >= 0     % I2 sits lower-right relative to I1
        outH = max([height1, shiftY + height2]);
        outW = max([width1,  abs(shiftX) + width2]);
        imgOut = zeros(outH, outW, totalDepth, maxColor, class(I1)) + backgroundColor;
        imgOut(1:height1,                   1:width1,                              1:depth1,            1:color1) = I1;
        imgOut(1 + shiftY:shiftY + height2, 1 + abs(shiftX):abs(shiftX) + width2, depth1 + 1:totalDepth, 1:color2) = I2;
    else               % I2 sits upper-right relative to I1
        bbShiftXY(2) = shiftY;
        outH = max([height2, abs(shiftY) + height1]);
        outW = max([width1,  abs(shiftX) + width2]);
        imgOut = zeros(outH, outW, totalDepth, maxColor, class(I1)) + backgroundColor;
        imgOut(1 + abs(shiftY):abs(shiftY) + height1, 1:width1,                              1:depth1,            1:color1) = I1;
        imgOut(1:height2,                              1 + abs(shiftX):abs(shiftX) + width2, depth1 + 1:totalDepth, 1:color2) = I2;
    end
end

% Service-layer callers expect 3-D output [h, w, d] - drop the singleton
% colour dim that crept in via the 4-output ``size`` call above.
if options.modelSwitch == 1
    imgOut = imgOut(:, :, :, 1);
end
end
