function swapColorChannels(obj, channel1, channel2, options)
% SWAPCOLORCHANNELS - Swap two color channels in obj.data.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.swapColorChannels(channel1, channel2, options)
%
% Input Arguments:
%   - **channel1** — 1-based index of the first channel
%   - **channel2** — 1-based index of the second channel
%   - **options** — *(optional)* struct with fields:
%
%     - ``.showWaitbar`` — logical; show progress bar (default ``true``)
%     - ``.ParentFigure`` — handle to parent figure for the progress dialog (default ``[]``)
%
% Usage:
%   **Example 1** — swap channels 1 and 3
%
%   .. code-block:: matlab
%
%
%     obj.image.swapColorChannels(1, 3);
%

% Updates
%

if nargin < 4; options = struct; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, ...
        'Title', 'Swap color channels', ...
        'Message', sprintf('Swapping color channels %d and %d\nPlease wait...', channel1, channel2), ...
        'Value', 0);
end

dummy = obj.data(:,:,:,channel1,:);
if options.showWaitbar; wb.Value = 0.33; end
obj.data(:,:,:,channel1,:) = obj.data(:,:,:,channel2,:);
if options.showWaitbar; wb.Value = 0.66; end
obj.data(:,:,:,channel2,:) = dummy;

obj.updateActionLog(sprintf('Swap color channels %d and %d', channel1, channel2));

if options.showWaitbar; wb.Value = 1; delete(wb); end
end
