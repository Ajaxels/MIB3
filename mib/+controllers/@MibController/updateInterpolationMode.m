function updateInterpolationMode(obj, keepCurrent)
% UPDATEINTERPOLATIONMODE - Function to set the state of the interpolation button in the Selection ribbon.
%
% Syntax:
%   function updateInterpolationMode(obj, keepCurrent)
%
% When the ''options'' variable is omitted the function works as a standard
% callback and changes the type of interpolation: ''shape'' or ''line''.
% However, when ''options'' are specified the function sets the state of
% the button to the currently selected type.
%
% Input Arguments:
%   - **keepCurrent** — [*optional,* logical],
%     - true - set the state of the button to the currently
%   selected type of the interpolation (obj.mibModel.preferences.SegmTools.Interpolation.Type)
%     - false - swaps the interpolation type
%
% Output Arguments:
%
% Usage:
%   ``obj.mibController.updateInterpolationMode(true);     // call from mibController; update the interpolation button icon, using the currently selected interpolation type``
%   ``obj.mibController.updateInterpolationMode();     // call from mibController; swap the interpolation type``
%

% swap the interpolation types
if nargin < 2; keepCurrent = false; end

% force to initialize the Selection ribbon
if ~isfield(obj.view.handles, 'ribbonSelection'); obj.globalTabGroup_SelectionCallback('Selection'); end

if ~keepCurrent
    if strcmp(obj.mibModel.preferences.SegmTools.Interpolation.Type, 'shape')
        % set it as line interpolation
        obj.mibModel.preferences.SegmTools.Interpolation.Type = 'line';
    else
        % set it as shape interpolation
        obj.mibModel.preferences.SegmTools.Interpolation.Type = 'shape';
    end
end

if strcmp(obj.mibModel.preferences.SegmTools.Interpolation.Type, 'line')
    obj.view.handles.ribbonSelection.interpolate.Icon = fullfile(obj.mibPath, 'assets', 'icons', 'selection_line_24px.png');
    obj.view.handles.ribbonSelection.interpolate.Text = sprintf('Interpolate as\nline');
else
    obj.view.handles.ribbonSelection.interpolate.Icon = fullfile(obj.mibPath, 'assets', 'icons', 'selection_shape_24px.png');
    obj.view.handles.ribbonSelection.interpolate.Text = sprintf('Interpolate as\nshape');
end
end

