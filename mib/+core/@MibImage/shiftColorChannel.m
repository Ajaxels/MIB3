function shiftColorChannel(obj, channel1, dx, dy, fillValue, options)
% SHIFTCOLORCHANNEL - Shift a color channel by dx/dy pixels.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.shiftColorChannel(channel1, dx, dy, fillValue, options)
%
% Pixels that shift out of the frame are discarded; the vacated border
% region is filled with ``fillValue``.
%
% Input Arguments:
%   - **channel1** — 1-based index of the channel to shift
%   - **dx** — shift in X (columns), in pixels; positive = shift right
%   - **dy** — shift in Y (rows), in pixels; positive = shift down
%   - **fillValue** — *(optional)* intensity used to fill the vacated border;
%     default ``0``
%   - **options** — *(optional)* struct with fields:
%
%     - ``.showWaitbar`` — logical; show progress bar (default ``true``)
%     - ``.ParentFigure`` — handle to parent figure for the progress dialog (default ``[]``)
%
% Usage:
%   **Example 1** — shift channel 1 by +10 px in X and -5 px in Y
%
%   .. code-block:: matlab
%
%
%     obj.image.shiftColorChannel(1, 10, -5, 0);
%

% Updates
%

if nargin < 6; options   = struct; end
if nargin < 5; fillValue = 0;      end
if isempty(fillValue); fillValue = 0; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, ...
        'Title', 'Shift color channel', ...
        'Message', sprintf('Shifting channel %d by dx=%d, dy=%d\nPlease wait...', channel1, dx, dy), ...
        'Value', 0.1);
end

if dx < 0 && dy < 0
    dx2 = abs(dx); dy2 = abs(dy);
    obj.data{1}(1:end-dy2, 1:end-dx2, :, channel1, :) = obj.data{1}(dy2+1:end, dx2+1:end, :, channel1, :);
    obj.data{1}(end-dy2+1:end, :, :, channel1, :)     = fillValue;
    obj.data{1}(:, end-dx2+1:end, :, channel1, :)     = fillValue;
elseif dx <= 0 && dy >= 0
    dx2 = abs(dx);
    obj.data{1}(dy+1:end, 1:end-dx2, :, channel1, :) = obj.data{1}(1:end-dy, dx2+1:end, :, channel1, :);
    obj.data{1}(1:dy, :, :, channel1, :)              = fillValue;
    obj.data{1}(:, end-dx2+1:end, :, channel1, :)     = fillValue;
elseif dx >= 0 && dy <= 0
    dy2 = abs(dy);
    obj.data{1}(1:end-dy2, dx+1:end, :, channel1, :) = obj.data{1}(dy2+1:end, 1:end-dx, :, channel1, :);
    obj.data{1}(end-dy2+1:end, :, :, channel1, :)    = fillValue;
    obj.data{1}(:, 1:dx, :, channel1, :)             = fillValue;
else
    obj.data{1}(dy+1:end, dx+1:end, :, channel1, :) = obj.data{1}(1:end-dy, 1:end-dx, :, channel1, :);
    obj.data{1}(1:dy, :, :, channel1, :)            = fillValue;
    obj.data{1}(:, 1:dx, :, channel1, :)            = fillValue;
end

if options.showWaitbar; wb.Value = 0.95; end

obj.updateActionLog(sprintf('Shift channel %d, dx=%d, dy=%d, fillValue=%g', channel1, dx, dy, fillValue));

if options.showWaitbar; wb.Value = 1; delete(wb); end
end
