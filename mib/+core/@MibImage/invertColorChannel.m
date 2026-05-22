function invertColorChannel(obj, channel1, options)
% INVERTCOLORCHANNEL - Invert pixel values in a color channel.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.invertColorChannel(channel1, options)
%
% Each pixel value ``v`` is replaced by ``maxInt - v``.
%
% Input Arguments:
%   - **channel1** — 1-based index of the channel to invert; ``0`` targets the last channel
%   - **options** — *(optional)* struct with fields:
%
%     - ``.showWaitbar`` — logical; show progress bar (default ``true``)
%     - ``.ParentFigure`` — handle to parent figure for the progress dialog (default ``[]``)
%
% Usage:
%   **Example 1** — invert channel 2
%
%   .. code-block:: matlab
%
%
%     obj.image.invertColorChannel(2);
%

% Updates
%

if nargin < 3; options = struct; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

if channel1 == 0; channel1 = obj.colors; end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, ...
        'Title', 'Invert color channel', ...
        'Message', sprintf('Inverting color channel %d\nPlease wait...', channel1), ...
        'Value', 0.1);
end

obj.data{1}(:,:,:,channel1,:) = obj.maxInt - obj.data{1}(:,:,:,channel1,:);

if options.showWaitbar; wb.Value = 0.95; end

obj.updateActionLog(sprintf('Invert color channel %d', channel1));

if options.showWaitbar; wb.Value = 1; delete(wb); end
end
