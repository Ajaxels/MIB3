function updateInterpolationSettings(obj)
% UPDATEINTERPOLATIONSETTINGS - Show a dialog to modify the selection interpolation settings for the brush tool.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateInterpolationSettings()
%
% Presents an input dialog (via utils.dlgs.inputUniversalDlg) allowing the
% user to choose the interpolation type ('Shape' or 'Line'), the number of
% interpolation points, and the line width (used only in line-interpolation
% mode). After confirmation the validated values are stored in
% obj.mibModel.preferences.SegmTools.Interpolation and the interpolation
% button in the Selection ribbon is refreshed via
% obj.mibController.updateInterpolationMode(true).
%
% Input Arguments:
%   (none beyond implicit obj)
%
% Output Arguments:
%   (none) - returns early when the user cancels the dialog or when a
%   validated value is out of range.
%
% Usage:
%   Example 1::
%
%     obj.cSegmentation.updateInterpolationSettings();  // called from MibController
%

% Updates
%

if strcmp(obj.mibModel.preferences.SegmTools.Interpolation.Type, 'shape')
    typeVal = 1;
else
    typeVal = 2;
end

prompts = {
    'Interpolation type'
    sprintf('Number of points\n(more points give smoother results but longer to calculate):')
    'Line width (only for the line interpolation)'
    };
defAns = {
    {'Shape', 'Line', typeVal}
    obj.mibModel.preferences.SegmTools.Interpolation.NoPoints
    obj.mibModel.preferences.SegmTools.Interpolation.LineWidth
    };
dlgTitle = 'Interpolation settings';
options.WindowStyle   = 'normal';
options.Focus         = 1;
options.WindowHeight = 200;
options.mibPath       = obj.mibController.mibPath;

[answer, ~] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, options);
if isempty(answer); return; end

noPoints = round(answer{2});
if noPoints < 2
    errOpts.MsgBoxOnly   = true;
    errOpts.mibPath      = obj.mibController.mibPath;
    utils.dlgs.inputUniversalDlg(obj.view.gui, 'Ops!', {''}, {'Number of points should be more than 1'}, 'Wrong value', errOpts);
    return;
end

lineWidth = round(answer{3});
if lineWidth < 1
    errOpts.MsgBoxOnly   = true;
    errOpts.mibPath      = obj.mibController.mibPath;
    utils.dlgs.inputUniversalDlg(obj.view.gui, 'Ops!', {''}, {'Line width should be more than 0'}, 'Wrong value', errOpts);
    return;
end

obj.mibModel.preferences.SegmTools.Interpolation.Type      = lower(answer{1});
obj.mibModel.preferences.SegmTools.Interpolation.NoPoints  = noPoints;
obj.mibModel.preferences.SegmTools.Interpolation.LineWidth  = lineWidth;

obj.mibController.updateInterpolationMode(true);    % refresh the ribbon button icon
end
