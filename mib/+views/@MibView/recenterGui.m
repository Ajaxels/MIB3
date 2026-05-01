function recenterGui(obj)
% RECENTERGUI - recenter the MIB window to the center of the display screen.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.recenterGui()
%
arguments (Input)
    obj views.MibView
end

% get coordinates of screens for multiple connected displays as
% [displayId, x_pos, y_pos, width, height]
monitors = get(0, 'MonitorPositions'); 
screenSize = monitors(1,:); % get the screen size for the first monitor
screenWidth = screenSize(3);
screenHeight = screenSize(4);

% get the current MIB dimensions
width = obj.gui.WindowBounds(3);
height = obj.gui.WindowBounds(4);

% Calculate centered x_pos (left edge from left of screen)
x_pos = (screenWidth - width) / 2;

% Calculate centered y_pos (upper edge from top of screen)
y_pos = (screenHeight - height) / 2;

% Convert y_pos (upper-left) to MATLAB's bottom-left coordinate
y_bottom = screenHeight - y_pos - height;

% Set the position [x_pos y_bottom width height]
obj.gui.WindowBounds = [x_pos  y_bottom width height];
end
