function insertEmptyColorChannel(obj, channel1, options)
% INSERTEMPTYCOLORCHANNEL - Insert a zero-filled color channel at the given position.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.insertEmptyColorChannel(channel1, options)
%
% Input Arguments:
%   - **channel1** - 1-based index of the position to insert the new channel.
%     Use ``obj.colors + 1`` to append at the end.
%   - **options** - *(optional)* struct with fields:
%
%     - ``.showWaitbar`` - logical; show progress bar (default ``true``)
%     - ``.ParentFigure`` - handle to parent figure for the progress dialog (default ``[]``)
%
% Usage:
%   **Example 1** - insert empty channel before channel 2
%
%   .. code-block:: matlab
%
%
%     obj.image.insertEmptyColorChannel(2, struct('showWaitbar', false));
%

% Updates
%

if nargin < 3; options = struct; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, ...
        'Title', 'Insert empty color channel', ...
        'Message', sprintf('Inserting empty color channel to position %d\nPlease wait...', channel1), ...
        'Value', 0);
end

if channel1 == 1
    obj.data(:,:,:,2:obj.colors+1,:) = obj.data;
    obj.data(:,:,:,1,:) = zeros([obj.height, obj.width, obj.depth, 1, obj.time], obj.dataClass);
    obj.lutColors = [rand([1, 3]); obj.lutColors];
elseif channel1 == obj.colors + 1
    obj.data(:,:,:,obj.colors+1,:) = zeros([obj.height, obj.width, obj.depth, 1, obj.time], obj.dataClass);
    obj.lutColors = [obj.lutColors; rand([1, 3])];
else
    obj.data(:,:,:,channel1+1:obj.colors+1,:) = obj.data(:,:,:,channel1:obj.colors,:);
    obj.data(:,:,:,channel1,:) = zeros([obj.height, obj.width, obj.depth, 1, obj.time], obj.dataClass);
    obj.lutColors = [obj.lutColors(1:channel1-1,:); rand([1, 3]); obj.lutColors(channel1:end,:)];
end

if options.showWaitbar; wb.Value = 0.66; end

obj.colors = obj.colors + 1;
obj.dim_yxzct(4) = obj.colors;
obj.viewPort.min(obj.colors)   = 0;
obj.viewPort.max(obj.colors)   = obj.maxInt;
obj.viewPort.gamma(obj.colors) = 1;
obj.colorType = 'multichannel';

obj.updateActionLog(sprintf('Insert empty color channel to position %d', channel1));

if options.showWaitbar; wb.Value = 1; delete(wb); end
end
