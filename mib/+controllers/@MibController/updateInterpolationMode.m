function updateInterpolationMode(obj, keepCurrent)
% UPDATEINTERPOLATIONMODE - Function to set the state of the interpolation button in the Selection ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateInterpolationMode()
%      obj.updateInterpolationMode(keepCurrent)
%
% When ``keepCurrent`` is omitted the function works as a standard callback
% and swaps the interpolation type between ``shape`` and ``line``.
% When ``keepCurrent`` is ``true`` the button state is synced to the
% currently selected type without swapping.
%
% Input Arguments:
%   - **keepCurrent** — *(optional)* logical, default: ``false``
%
%     - ``true`` — sync the button icon to the currently selected interpolation type
%       (``obj.mibModel.preferences.SegmTools.Interpolation.Type``) without swapping
%     - ``false`` — swap the interpolation type
%
% Output Arguments:
%   (none)
%
% **Example 1** — sync the button icon to the current type (no swap):
%
%   .. code-block:: matlab
%
%      obj.mibController.updateInterpolationMode(true);
%
% **Example 2** — swap the interpolation type:
%
%   .. code-block:: matlab
%
%      obj.mibController.updateInterpolationMode();
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

