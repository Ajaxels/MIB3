function updateInterpolationMode(obj, keepCurrent)
% function updateInterpolationMode(obj, options)
% Function to set the state of the interpolation button in the Selection ribbon
%
% When the ''options'' variable is omitted the function works as a standard
% callback and changes the type of interpolation: ''shape'' or ''line''.
% However, when ''options'' are specified the function sets the state of
% the button to the currently selected type.
%
% Parameters:
% keepCurrent: [@em optional, logical], 
% @li true - set the state of the button to the currently
% selected type of the interpolation (obj.mibModel.preferences.SegmTools.Interpolation.Type)
% @li false - swaps the interpolation type
%
% Return values:
% 
%| @b Examples:
% @code obj.mibController.updateInterpolationMode(true);     // call from mibController; update the interpolation button icon, using the currently selected interpolation type @endcode
% @code obj.mibController.updateInterpolationMode();     // call from mibController; swap the interpolation type @endcode
%
% Updates
% 

% swap the interpolation types
if nargin < 2; keepCurrent = false; end

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

