function updateVisualizationMode(obj, mode)
% UPDATEVISUALIZATIONMODE - Function to set type of image interpolation for the visualization (from Image Ribbon).
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.updateVisualizationMode()
%      obj.updateVisualizationMode(mode)
%
% When ``mode`` is omitted the function cycles through ``bicubic``,
% ``nearest``, and ``automatic`` interpolation modes.
% When ``mode`` is specified the provided mode is applied directly.
%
% Input Arguments:
%   - **mode** - *(optional)* char, default: ``''`` (cycle/toggle)
%
%     - ``''`` or not provided - cycle: ``bicubic`` → ``nearest`` → ``automatic``
%     - ``'keepcurrent'`` - sync the button icon to the mode stored in
%       ``obj.mibModel.preferences.System.ImageResizeMethod`` without changing it
%     - ``'bicubic'`` - set bicubic interpolation
%     - ``'nearest'`` - set nearest-neighbor interpolation
%     - ``'auto'`` - set automatic mode (bicubic for zoom-out, nearest for zoom-in)
%
% Output Arguments:
%   (none)
%
% **Example 1** - cycle to the next visualization mode:
%
%   .. code-block:: matlab
%
%      obj.updateVisualizationMode();
%
% **Example 2** - sync the button icon without changing the mode:
%
%   .. code-block:: matlab
%
%      obj.updateVisualizationMode('keepcurrent');
%
% **Example 3** - select bicubic interpolation:
%
%   .. code-block:: matlab
%
%      obj.updateVisualizationMode('bicubic');
%

% Updates
% 

arguments (Input)
    obj controllers.MibController
    mode (1,:) char = ''
end

% standard call from the button
if isempty(mode)
    if strcmp(obj.mibModel.preferences.System.ImageResizeMethod, 'bicubic')
        obj.mibModel.preferences.System.ImageResizeMethod = 'nearest';
    elseif strcmp(obj.mibModel.preferences.System.ImageResizeMethod, 'nearest')
        obj.mibModel.preferences.System.ImageResizeMethod = 'auto';
    else
        obj.mibModel.preferences.System.ImageResizeMethod = 'bicubic';
    end
elseif ~strcmp(mode, 'keepcurrent')
    obj.mibModel.preferences.System.ImageResizeMethod = mode;
end

% update the button icon - only when the Image ribbon has actually been built
% (lazy init). Writing into obj.view.handles.ribbonImage before that would
% auto-vivify a partial 'visualization' struct, which then fools the
% isfield(...,'ribbonImage') guard in globalTabGroup_SelectionCallback into
% skipping the real initialization. addRibbonImage sets this icon from the
% current ImageResizeMethod preference when it builds the tab, so nothing is
% lost by skipping it here.
if isfield(obj.view.handles, 'ribbonImage') && ...
        isfield(obj.view.handles.ribbonImage, 'visualization') && ...
        isobject(obj.view.handles.ribbonImage.visualization)
    obj.view.handles.ribbonImage.visualization.Icon = fullfile(obj.mibPath, 'assets', 'icons', sprintf('image_%s_24px.png', obj.mibModel.preferences.System.ImageResizeMethod));
end
notify(obj.mibModel, 'ShowImage');
end
