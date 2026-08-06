function invertColorChannel(obj, channel1, options)
% INVERTCOLORCHANNEL - Invert pixel values in one or more color channels.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.invertColorChannel(channel1)
%       obj.invertColorChannel(channel1, options)
%
% Each pixel value ``v`` is replaced by ``maxInt - v``.
% Operates directly on ``obj.data`` (no ROI support; use
% ``MibModel.invertImage`` for ROI-aware 2D inversion).
%
% Input Arguments:
%   - **channel1** - channel index (scalar), vector of indices, or ``0`` = all channels
%   - **options** - *(optional)* struct with fields:
%
%     - ``.showWaitbar`` - logical; show progress bar (default ``true``)
%     - ``.ParentFigure`` - handle to parent figure for the progress dialog (default ``[]``)
%     - ``.tRange`` - ``[t1, t2]`` time-point range; default = all time points
%     - ``.zRange`` - ``[z1, z2]`` z-slice range (physical Z, dim 3 of ``data{1}``); default = all z-slices
%
% Usage:
%   **Example 1** - invert channel 2 across the full dataset
%
%   .. code-block:: matlab
%
%     obj.image.invertColorChannel(2);
%
%   **Example 2** - invert channels 1 and 3, time points 2-4 only
%
%   .. code-block:: matlab
%
%     opts.tRange = [2, 4];
%     obj.image.invertColorChannel([1, 3], opts);
%
%   **Example 3** - invert all channels
%
%   .. code-block:: matlab
%
%     obj.image.invertColorChannel(0);

% Updates
% 2026-05-24 - added multi-channel vector support and tRange/zRange options

if nargin < 3; options = struct; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end
if ~isfield(options, 'tRange'); options.tRange = [1, obj.time];  end
if ~isfield(options, 'zRange'); options.zRange = [1, obj.depth]; end

if isscalar(channel1) && channel1 == 0
    channel1 = 1:obj.colors;
end

t1 = options.tRange(1);
t2 = options.tRange(2);
z1 = options.zRange(1);
z2 = options.zRange(2);

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, ...
        'Title', 'Invert color channel', ...
        'Message', sprintf('Inverting color channel(s)\nPlease wait...'), ...
        'Indeterminate','on');
end

obj.data(:,:,z1:z2,channel1,t1:t2) = obj.maxInt - obj.data(:,:,z1:z2,channel1,t1:t2);

if isscalar(channel1)
    chStr = num2str(channel1);
else
    chStr = strtrim(sprintf('%d, ', channel1));
    chStr = chStr(1:end-1);
end
obj.updateActionLog(sprintf('Invert color channel(s): %s  z:[%d %d]  t:[%d %d]', chStr, z1, z2, t1, t2));

if options.showWaitbar; delete(wb); end
end
