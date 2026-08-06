function rotateColorChannel(obj, channel1, angle, options)
% ROTATECOLORCHANNEL - Rotate a color channel by 90, 180, or -90 degrees.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.rotateColorChannel(channel1, angle, options)
%
% Only square images are supported (``obj.width == obj.height``).
%
% Input Arguments:
%   - **channel1** - 1-based index of the channel to rotate
%   - **angle** - rotation angle in degrees; must be a multiple of 90
%   - **options** - *(optional)* struct with fields:
%
%     - ``.showWaitbar`` - logical; show progress bar (default ``true``)
%     - ``.ParentFigure`` - handle to parent figure for the progress dialog (default ``[]``)
%
% Usage:
%   **Example 1** - rotate channel 1 by 90 degrees
%
%   .. code-block:: matlab
%
%
%     obj.image.rotateColorChannel(1, 90);
%

% Updates
%

if nargin < 4; options = struct; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

if obj.width ~= obj.height
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_error';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(options.ParentFigure, 'Cannot rotate non-square image!', ...
        {''}, {'Channel rotation requires a square image (width == height).'}, ...
        'Wrong image dimensions', dlgOpt);
    return;
end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, ...
        'Title', 'Rotate color channel', ...
        'Message', sprintf('Rotating channel %d by %d°\nPlease wait...', channel1, angle), ...
        'Value', 0);
end

noIter = -round(angle / 90);   % rot90 convention: positive n = CCW

imageData = obj.data;
for t = 1:obj.time
    for slice = 1:obj.depth
        imageData(:,:,slice,channel1,t) = rot90(imageData(:,:,slice,channel1,t), noIter);
    end
    if options.showWaitbar; wb.Value = t / obj.time; end
end
obj.data = imageData;

obj.updateActionLog(sprintf('Rotate color channel %d by %d degrees', channel1, angle));

if options.showWaitbar; wb.Value = 1; delete(wb); end
end
