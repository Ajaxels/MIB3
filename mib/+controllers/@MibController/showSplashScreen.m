function [hSplashScreen, hSplashAxes, hLabel] = showSplashScreen(obj, titleText, initText)
% SHOWSPLASHSCREEN - Show MIB splash screen while loading.
%
% Syntax:
%   .. code-block:: matlab
%
%      [hSplashScreen, hSplashAxes, hLabel] = obj.showSplashScreen()
%      [hSplashScreen, hSplashAxes, hLabel] = obj.showSplashScreen(titleText, initText)
%
% Input Arguments:
%   - **titleText** - char with the window title
%   - **initText** - char with the initial status text
%
% Output Arguments:
%   - **hSplashScreen** - handle to the splash screen ``figure``
%   - **hSplashAxes** - handle to the ``axes`` used to display the splash image
%   - **hLabel** - handle to the status text ``uicontrol``
%

arguments (Input)
    obj controllers.MibController
    titleText char = 'Splash screen'
    initText char = 'Please wait...'
end

arguments (Output)
    hSplashScreen 
    hSplashAxes
    hLabel
end

hSplashScreen = figure(...
    'Resize', 'off', ...
    'NumberTitle', 'off', ...
    'MenuBar', 'none', ...
    'Name', titleText, ...
    'Toolbar','none', ...
    'Units','pixels', ...
    'Visible','off');

hSplashAxes = axes(hSplashScreen, 'Units', 'normalized');

imshow(imread(fullfile(obj.mibPath, 'assets', 'images','splashscreen.jpg')), ...
    'Parent', hSplashAxes, 'border', 'tight');
set(hSplashAxes,'Position', [0 0 1 1]);
set(gca, 'DataAspectRatioMode', 'auto');
movegui(hSplashScreen, 'center');

set(hSplashScreen,'Visible','on')

hLabel = text(hSplashAxes, 260, 505, ...
    initText, ...
    'Color', 'y', ...
    'VerticalAlignment', 'bottom', ...
    'HorizontalAlignment', 'center', ...
    'FontName', 'FixedWidth', ...
    'Fontweight', 'bold', ...
    'FontSize', 10, ...
    'Interpreter', 'none');

drawnow nocallbacks;
end
