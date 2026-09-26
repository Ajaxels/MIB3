function paintBufferButton(obj, buttonHandle, state)
% PAINTBUFFERBUTTON - set the background color of a buffer button of the Datasets panel.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.paintBufferButton(buttonHandle, state)
%
% Single place that defines the colors of the buffer buttons
% (``obj.handles.buffer1`` ... ``obj.handles.buffer10``), so that all code paths
% (``update_fromModel``, ``buffers_Callback``, ``buffers_ContextMenu``) paint them
% identically in the light and dark themes.
%
% The colors come from the ``buffer...`` fields of ``utils.themeColors`` for the
% theme of ``obj.UIFigure`` (``Theme.BaseColorStyle``): pastels in the light theme,
% darker tones of the same hues in the dark theme.
%
% The font color is never set and stays on auto, so it always follows the theme.
% An empty buffer gets ``BackgroundColorMode = 'auto'`` rather than a color, so it
% follows the theme on its own. The other states are explicit colors, which MATLAB
% does not remap on a theme switch; ``obj.UIFigure.ThemeChangedFcn`` therefore
% repaints the buttons via ``update_fromModel``. Releases without the figure
% ``Theme`` property (before R2025a) always get the light palette.
%
% Input Arguments:
%   - **buttonHandle** - [matlab.ui.control.Button] handle of the buffer button
%   - **state** - [char] state of the dataset stored in the buffer:
%     ``'empty'`` - placeholder, no data loaded;
%     ``'inMemory'`` - data present, but no file on disk (e.g. loaded from Examples);
%     ``'fileBacked'`` - data loaded from a file;
%     ``'selected'`` - the currently shown buffer, overrides the other states
%
% Usage:
%   .. code-block:: matlab
%
%      obj.paintBufferButton(obj.handles.buffer2, 'fileBacked');
%

arguments
    obj controllers.MibActiveDataset
    buttonHandle matlab.ui.control.Button
    state {mustBeMember(state, {'empty', 'inMemory', 'fileBacked', 'selected'})}
end

if strcmp(state, 'empty')
    buttonHandle.BackgroundColorMode = 'auto';
    return;
end

palette = utils.themeColors(obj.UIFigure);
switch state
    case 'inMemory'
        buttonHandle.BackgroundColor = palette.bufferInMemory;
    case 'fileBacked'
        buttonHandle.BackgroundColor = palette.bufferFileBacked;
    case 'selected'
        buttonHandle.BackgroundColor = palette.bufferSelected;
end

end
