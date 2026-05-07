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
% Input Arguments:
%   - **imgIn** — [numeric] input stack: ``[height, width, depth]`` (3-D) or
%     ``[height, width, color, depth]`` (4-D).
%   - **shiftsX** — [numeric vector] X translation per slice, length ``depth``.
%   - **shiftsY** — [numeric vector] Y translation per slice, length ``depth``.
%   - **options** *(optional)* — struct with fields:
%
%     - ``.backgroundColor`` — [char|numeric] padding colour: ``'black'`` (default),
%       ``'white'``, ``'mean'``, or a numeric scalar of the same class as ``imgIn``.
%     - ``.waitbar`` — [:class:`core.PoolWaitbar`] existing handle to reuse for
%       progress reporting; pass ``[]`` or omit to disable progress reporting.
%
% Output Arguments:
%   - **imgOut** — [numeric] aligned stack with same dimensionality as ``imgIn`` and
%     enlarged ``height``/``width``.
%
% **Example** — apply shifts and use the parent figure's PoolWaitbar:
%
% .. code-block:: matlab
%
%    opts.backgroundColor = 'mean';
%    opts.waitbar = pwb;
%    aligned = utils.align.crossShiftStack(I, shiftX, shiftY, opts);

if nargin < 3
    error('utils:align:crossShiftStack:missingArgs', ...
        'crossShiftStack requires at least 3 arguments: imgIn, shiftsX, shiftsY');
end
if nargin < 4; options = struct(); end
if ~isfield(options, 'backgroundColor'); options.backgroundColor = 'black'; end
if ~isfield(options, 'waitbar');         options.waitbar = []; end

pwb = options.waitbar;
showProgress = ~isempty(pwb) && isvalid(pwb);

% Normalize to 4-D (height, width, color, depth)
mode = '4D';
if ndims(imgIn) == 3
    mode = '3D';
    imgIn = permute(imgIn, [1 2 4 3]);
end

[height, width, color, depth] = size(imgIn);
minX = min(shiftsX);    maxX = max(shiftsX);
minY = min(shiftsY);    maxY = max(shiftsY);
deltaX = abs(minX) + maxX;
deltaY = abs(minY) + maxY;

if isnumeric(options.backgroundColor)
    imgOut = zeros([height+deltaY, width+deltaX, color, depth], class(imgIn)) + options.backgroundColor;
elseif strcmp(options.backgroundColor, 'black')
    imgOut = zeros([height+deltaY, width+deltaX, color, depth], class(imgIn));
elseif strcmp(options.backgroundColor, 'white')
    imgOut = zeros([height+deltaY, width+deltaX, color, depth], class(imgIn)) + intmax(class(imgIn));
else
    backgroundIntensity = mean(imgIn, 'all');
    imgOut = zeros([height+deltaY, width+deltaX, color, depth], class(imgIn)) + backgroundIntensity;
end

if showProgress
    pwb.updateMaxNumberOfIterations(depth);
    pwb.setCurrentIteration(0);
    pwb.updateText('Aligning slices...');
end

for sliceIdx = 1:depth
    xOffset = shiftsX(sliceIdx) - minX + 1;
    yOffset = shiftsY(sliceIdx) - minY + 1;
    imgOut(yOffset:yOffset+height-1, xOffset:xOffset+width-1, :, sliceIdx) = imgIn(:,:,:,sliceIdx);
    if showProgress
        if pwb.getCancelState()
            imgOut = [];
            return;
        end
        pwb.increment();
    end
end

if strcmp(mode, '3D')
    imgOut = squeeze(imgOut);
end

end
