function deleteColorChannel(obj, channel1, options)
% DELETECOLORCHANNEL - Delete one or more color channels from obj.data.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.deleteColorChannel(channel1, options)
%
% Input Arguments:
%   - **channel1** - vector of 1-based channel indices to delete
%   - **options** - *(optional)* struct with fields:
%
%     - ``.showWaitbar`` - logical; show progress bar (default ``true``)
%     - ``.ParentFigure`` - handle to parent figure for the progress dialog (default ``[]``)
%
% Usage:
%   **Example 1** - delete channel 3
%
%   .. code-block:: matlab
%
%
%     obj.image.deleteColorChannel(3);
%

% Updates
%

if nargin < 3; options = struct; end
if ~isfield(options, 'showWaitbar');  options.showWaitbar  = true; end
if ~isfield(options, 'ParentFigure'); options.ParentFigure = [];   end

if obj.colors < 2
    dlgOpt.MsgBoxOnly  = true;
    dlgOpt.Icon        = 'puffin_error';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(options.ParentFigure, 'Cannot delete the last color channel!', ...
        {''}, {'There is only one color channel available.'}, 'Not enough colors', dlgOpt);
    return;
end

if options.showWaitbar
    wb = uiprogressdlg(options.ParentFigure, ...
        'Title', 'Delete color channel', ...
        'Message', sprintf('Deleting color channel(s) %s\nPlease wait...', mat2str(channel1)), ...
        'Value', 0);
end

colorList      = 1:obj.colors;
keepMask       = ~ismember(colorList, channel1);
obj.data    = obj.data(:,:,:,keepMask,:);
obj.colors     = obj.colors - numel(channel1);
obj.dim_yxzct(4) = obj.colors;

if options.showWaitbar; wb.Value = 0.66; end

obj.viewPort.min   = obj.viewPort.min(keepMask);
obj.viewPort.max   = obj.viewPort.max(keepMask);
obj.viewPort.gamma = obj.viewPort.gamma(keepMask);
obj.lutColors(channel1, :) = [];

if obj.colors == 1; obj.colorType = 'grayscale'; end

obj.updateActionLog(sprintf('Delete color channel(s) %s', mat2str(channel1)));

if options.showWaitbar; wb.Value = 1; delete(wb); end
end
