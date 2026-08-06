function imgOut = crossShiftStack(imgIn, shiftsX, shiftsY, options)
% CROSSSHIFTSTACK - Apply per-slice X/Y translations to an image stack.
%
% Syntax:
%   .. code-block:: matlab
%
%      imgOut = utils.align.crossShiftStack(imgIn, shiftsX, shiftsY)
%      imgOut = utils.align.crossShiftStack(imgIn, shiftsX, shiftsY, options)
%
% Translates each slice of ``imgIn`` by the corresponding ``shiftsX``/``shiftsY``
% values and pads the output canvas to accommodate the union of all shifts. The
% padding intensity is controlled by ``options.backgroundColor``.
%
% Input layout is MIB3-native: ``[h, w, d]`` for service layers, ``[h, w, d, c]``
% for image stacks, or ``[h, w, d, c, t]`` for image stacks with a time axis.
% The depth axis is always dim 3 - color and time are after depth, matching
% :attr:`core.MibImage.data` ``{1}``.
%
% Input Arguments:
%   - **imgIn** - [numeric] input stack in MIB3 layout: ``[h, w, d]``,
%     ``[h, w, d, c]``, or ``[h, w, d, c, t]``.
%   - **shiftsX** - [numeric vector] X translation per slice, length ``d``.
%   - **shiftsY** - [numeric vector] Y translation per slice, length ``d``.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.backgroundColor`` - [char|numeric] padding colour: ``'black'`` (default),
%       ``'white'``, ``'mean'``, or a numeric scalar of the same class as ``imgIn``.
%     - ``.waitbar`` - [:class:`core.PoolWaitbar`] existing handle to reuse for
%       progress reporting; pass ``[]`` or omit to disable progress reporting.
%
% Output Arguments:
%   - **imgOut** - [numeric] aligned stack with the same layout / class as
%     ``imgIn`` and enlarged ``h`` / ``w``.
%
% **Example** - apply shifts and use the parent figure's PoolWaitbar:
%
% .. code-block:: matlab
%
%    opts.backgroundColor = 'mean';
%    opts.waitbar = pwb;
%    aligned = utils.align.crossShiftStack(I, shiftX, shiftY, opts);

% Updates
%

if nargin < 3
    error('utils:align:crossShiftStack:missingArgs', ...
        'crossShiftStack requires at least 3 arguments: imgIn, shiftsX, shiftsY');
end
if nargin < 4; options = struct(); end
if ~isfield(options, 'backgroundColor'); options.backgroundColor = 'black'; end
if ~isfield(options, 'waitbar');         options.waitbar = []; end

pwb = options.waitbar;
showProgress = ~isempty(pwb) && isvalid(pwb);

% MIB3 layout - work natively in [h, w, d, c, t]. Service-layer 3-D and
% image-stack 4-D inputs are handled by querying the missing trailing dims
% as size 1; the assignment below copes uniformly with all three cases.
[height, width, depth, colors, times] = size(imgIn, 1:5);

minX = min(shiftsX);    maxX = max(shiftsX);
minY = min(shiftsY);    maxY = max(shiftsY);
deltaX = abs(minX) + maxX;
deltaY = abs(minY) + maxY;
newH   = height + deltaY;
newW   = width  + deltaX;

% Resolve the background fill value
if isnumeric(options.backgroundColor)
    bg = options.backgroundColor;
elseif strcmp(options.backgroundColor, 'black')
    bg = 0;
elseif strcmp(options.backgroundColor, 'white')
    bg = intmax(class(imgIn));
else
    bg = mean(imgIn, 'all');
end

imgOut = zeros([newH, newW, depth, colors, times], class(imgIn));
if bg ~= 0
    imgOut = imgOut + cast(bg, class(imgIn));
end

if showProgress
    pwb.updateMaxNumberOfIterations(depth);
    pwb.setCurrentIteration(0);
    pwb.updateText('Aligning slices...');
end

for sliceIdx = 1:depth
    xOffset = shiftsX(sliceIdx) - minX + 1;
    yOffset = shiftsY(sliceIdx) - minY + 1;
    imgOut(yOffset:yOffset+height-1, xOffset:xOffset+width-1, sliceIdx, :, :) = ...
        imgIn(:, :, sliceIdx, :, :);
    if showProgress
        if pwb.getCancelState()
            imgOut = [];
            return;
        end
        if mod(sliceIdx, 10) == 0; pwb.increment(); end
    end
end
end
