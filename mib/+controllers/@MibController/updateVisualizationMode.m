function updateVisualizationMode(obj, mode)
% UPDATEVISUALIZATIONMODE - Function to set type of image interpolation for the visualization (from Image Ribbon).
%
% Syntax:
%   function updateVisualizationMode(obj, mode)
%
% When the ''mode'' variable is omitted the function works as a standard
% callback and changes the type of image interpolation: ''bicubic'', ''nearest'', ''automatic''
% However, when ''mode'' is specified, the provided mode is used
%
% Input Arguments:
%   - **mode** — [*optional,* char]
%     - when @b'''' or not provided, change the mode using the sequence: ''bicubic'', ''nearest'', ''automatic''
%     - when **''keepcurrent''** set the state of the button to the currently selected type of the interpolation in *obj.mibModel.preferences.System.ImageResizeMethod*
%     - when **''bicubic''** set the visualization mode to bicubic interpolation
%     - when **''nearest''** set the visualization mode to nearest-neighborhood interpolation
%     - when **''auto''** set the visualization mode to the automatic mode using bicubic for zoom-out and nearest for zoom-in
%
% Output Arguments:
%
% Usage:
%   Example 1::
%
%     obj.updateVisualizationMode();     // call from mibController; toggle to the next visualization mode
%
%   Example 2::
%
%     obj.updateVisualizationMode('keepcurrent');     // call from mibController; update the image interpolation button icon
%
%   Example 3::
%
%     obj.updateVisualizationMode('bicubic');     // call from mibController; select the bicubic interpolation
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

% update the button icon
obj.view.handles.ribbonImage.visualization.Icon = fullfile(obj.mibPath, 'assets', 'icons', sprintf('image_%s_24px.png', obj.mibModel.preferences.System.ImageResizeMethod));

end
