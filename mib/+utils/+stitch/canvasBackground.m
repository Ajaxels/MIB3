function backgroundValue = canvasBackground(dataClass, canvasColor)
% CANVASBACKGROUND - Fill value for mosaic pixels that no tile covers.
%
% Syntax:
%   .. code-block:: matlab
%
%      backgroundValue = utils.stitch.canvasBackground(dataClass)
%      backgroundValue = utils.stitch.canvasBackground(dataClass, canvasColor)
%
% Tiles almost never tile the canvas rectangle exactly: the solved positions
% leave a ragged frame around the mosaic, and that frame is filled with this
% value by every fusion path (``options.background`` of
% :func:`utils.stitch.fuseInMemory` / :func:`utils.stitch.fuseStreaming` /
% :func:`utils.stitch.fuseSliceComposite`).
%
% Which value reads as "nothing here" depends on the imaging modality, not on
% the data: on transmission EM an empty field is BRIGHT, so a zero frame draws a
% black border around the specimen; on fluorescence it is dark, so zero is
% right. Hence the choice, and the ``'white'`` default - MIB's stitching input is
% predominantly EM. :func:`utils.stitch.autocropCanvas` removes the frame
% altogether; the colour still shows through any gap left by a missing tile.
%
% Input Arguments:
%   - **dataClass** — [char] numeric class of the mosaic (``canvas.dataClass``).
%   - **canvasColor** *(optional)* — [char] ``'black'`` (default) | ``'white'``.
%
% Output Arguments:
%   - **backgroundValue** — [double] fill value, ready for
%     ``cast(backgroundValue, dataClass)``.
%
% **Example** — fuse an EM mosaic on a white canvas:
%
%   .. code-block:: matlab
%
%      fuseOptions.background = utils.stitch.canvasBackground(canvas.dataClass, 'white');
%      imgOut = utils.stitch.fuseInMemory(layout, canvas, fuseOptions);

if nargin < 2 || isempty(canvasColor); canvasColor = 'black'; end

switch lower(char(canvasColor))
    case 'black'
        backgroundValue = 0;
    case 'white'
        switch dataClass
            case {'single', 'double'}
                % realmax would be the literal answer and a useless one - it
                % saturates every display and overflows any later arithmetic.
                % Float image data in MIB is carried on the normalised 0..1
                % scale, so 1 is the ceiling that means "white" here.
                backgroundValue = 1;
            case 'logical'
                backgroundValue = 1;
            otherwise
                backgroundValue = double(intmax(dataClass));
        end
    otherwise
        error('utils:stitch:canvasBackground:badColor', ...
            'Unknown canvasColor "%s" (expected "black" or "white")', char(canvasColor));
end
end
