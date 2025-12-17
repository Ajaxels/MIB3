function updateVisualizationMode(obj, mode)
% function updateVisualizationMode(obj, mode)
% Function to set type of image interpolation for the visualization (from Image Ribbon)
%
% When the ''mode'' variable is omitted the function works as a standard
% callback and changes the type of image interpolation: ''bicubic'', ''nearest'', ''automatic''
% However, when ''mode'' is specified, the provided mode is used
%
% Parameters:
% mode: [@em optional, char]
% @li when @b'''' or not provided, change the mode using the sequence: ''bicubic'', ''nearest'', ''automatic''
% @li when @b ''keepcurrent'' set the state of the button to the currently selected type of the interpolation in @em obj.mibModel.preferences.System.ImageResizeMethod
% @li when @b ''bicubic'' set the visualization mode to bicubic interpolation
% @li when @b ''nearest'' set the visualization mode to nearest-neighborhood interpolation
% @li when @b ''auto'' set the visualization mode to the automatic mode using bicubic for zoom-out and nearest for zoom-in
%
% Return values:
% 

%| @b Examples:
% @code obj.updateVisualizationMode();     // call from mibController; toggle to the next visualization mode @endcode
% @code obj.updateVisualizationMode('keepcurrent');     // call from mibController; update the image interpolation button icon @endcode
% @code obj.updateVisualizationMode('bicubic');     // call from mibController; select the bicubic interpolation @endcode

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