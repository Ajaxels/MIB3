function copyColorChannel(obj, channel1, channel2, options)
% COPYCOLORCHANNEL - Copy channel1 intensity to channel2 position.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.copyColorChannel(channel1, channel2, options)
%
% If ``channel2 > obj.colors`` a new channel is appended; otherwise the
% existing channel is overwritten.
%
% Input Arguments:
%   - **channel1** - 1-based index of the source channel
%   - **channel2** - 1-based index of the destination channel; pass
%     ``obj.colors + 1`` to append as a new channel
%   - **options** - *(optional)* struct with fields:
%
%     - ``.showWaitbar`` - logical; show progress bar (default ``true``)
%     - ``.ParentFigure`` - handle to parent figure for the progress dialog (default ``[]``)
%
% Usage:
%   **Example 1** - copy channel 1 intensities to channel 3
%
%   .. code-block:: matlab
%
%
%     obj.image.copyColorChannel(1, 3);
%

% Updates
%

if nargin < 4; options = struct; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, ...
        'Title', 'Copy color channel', ...
        'Message', sprintf('Copying intensities from channel %d to %d\nPlease wait...', channel1, channel2), ...
        'Value', 0);
end

if channel2 > obj.colors
    obj.data(:,:,:,channel2,:) = obj.data(:,:,:,channel1,:);
    obj.colors = obj.colors + 1;
    obj.dim_yxzct(4) = obj.colors;
    obj.viewPort.min(channel2)   = 0;
    obj.viewPort.max(channel2)   = obj.maxInt;
    obj.viewPort.gamma(channel2) = 1;
    obj.colorType = 'multichannel';
    while size(obj.lutColors, 1) < obj.colors
        obj.lutColors(end+1, :) = rand(1, 3);
    end
else
    obj.data(:,:,:,channel2,:) = obj.data(:,:,:,channel1,:);
    obj.viewPort.min(channel2)   = obj.viewPort.min(channel1);
    obj.viewPort.max(channel2)   = obj.viewPort.max(channel1);
    obj.viewPort.gamma(channel2) = obj.viewPort.gamma(channel1);
end
obj.lutColors(channel2, :) = obj.lutColors(channel1, :);

if options.showWaitbar; wb.Value = 0.99; end

obj.updateActionLog(sprintf('Copy color channel %d to %d', channel1, channel2));

if options.showWaitbar; wb.Value = 1; delete(wb); end
end
