% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi 
% Date: 25.04.2023

function hObject = moveWindowOutside(hObject, mibGUI, alignH, alignV)
% function hObject = moveWindowOutside(hObject, mibGUI, alignH, alignV)
% Determine the position of the dialog - on a side of the main figure
% if available, else, centered on the main figure
% Parameters:
% hObject: handle of the window to be moved
% mibGUI: handle to the main MIB gui, can be obtained from obj.mibModel.mibGUI
% alignH: an optional string with the preferred horizontal alignment: 'left' (@em default), 'right', 'center'
% alignV: an optional string with the preferred vertical alignment: 'top' (@em default), 'bottom', 'center'

if nargin < 4; alignV = 'top'; end
if nargin < 3; alignH = 'left'; end
if nargin < 2; mibGUI = []; end
if isempty(alignH); alignH = 'left'; end

if ismember(alignH, {'left', 'right', 'center'}) == 0
    warndlg('Wrong alignH parameter; alignH should be one of those: ''left'',''right'',''center''', 'moveWindowOutside');
    alignH = 'left';
end

if ismember(alignV, {'top', 'bottom', 'center'}) == 0
    warndlg('Wrong alignV parameter; alignV should be one of those: ''top'',''bottom'',''center''', 'moveWindowOutside');
    alignV = 'top';
end

OldUnits = hObject.Units;
hObject.Units = 'pixels';
OldPos = hObject.OuterPosition;
FigWidth = OldPos(3);   % width of the window to move
FigHeight = OldPos(4);  % height of the window to move

if isempty(mibGUI)
    ScreenUnits=get(0, 'Units');
    set(0, 'Units', 'pixels');
    ScreenSize = get(0, 'ScreenSize');
    set(0, 'Units', ScreenUnits);
    
    FigPos(1) = 1/2*(ScreenSize(3)-FigWidth);
    FigPos(2) = 2/3*(ScreenSize(4)-FigHeight);
else
    screenSize = get(0, 'ScreenSize');
    
    if isa(mibGUI, 'matlab.ui.container.internal.AppContainer') % modern GUI
        GCBFPos = mibGUI.WindowBounds; % main MIB window position [top-left-x, top-left-y, width, height]
        % Convert WindowBounds (top-left origin) to bottom-left origin
        GCBFPos(2) = screenSize(4) - GCBFPos(2) - GCBFPos(4);
        % Use innerPosition to account for child window's Position vs OuterPosition difference
        useInnerPosition = true;
    else
        GCBFOldUnits = get(gcbf, 'Units');
        set(gcbf, 'Units', 'pixels');
        GCBFPos = get(gcbf, 'OuterPosition'); % parent window position
        set(gcbf, 'Units', GCBFOldUnits);
        useInnerPosition = false;
    end
    
    switch alignH
        case 'left'
            if GCBFPos(1)-FigWidth > 0  % put figure on the left side of the main figure
                FigPos(1) = GCBFPos(1) - FigWidth;
            elseif GCBFPos(1) + GCBFPos(3) + FigWidth < screenSize(3)  % put figure on the right side of the main figure
                FigPos(1) = GCBFPos(1) + GCBFPos(3);
            else
                FigPos(1) = (GCBFPos(1) + GCBFPos(3) / 2) - FigWidth / 2;
                alignV = 'center';
            end
        case 'right'
            if GCBFPos(1) + GCBFPos(3) + FigWidth < screenSize(3)  % put figure on the right side of the main figure
                FigPos(1) = GCBFPos(1) + GCBFPos(3);
            elseif GCBFPos(1)-FigWidth > 0  % put figure on the left side of the main figure
                FigPos(1) = GCBFPos(1) - FigWidth;
            else
                FigPos(1) = (GCBFPos(1) + GCBFPos(3) / 2) - FigWidth / 2;
                alignV = 'center';
            end
        case 'center'
            FigPos(1) = (GCBFPos(1) + GCBFPos(3) / 2) - FigWidth / 2;
    end
    
    switch alignV
        case 'top'
            FigPos(2) = GCBFPos(2)+GCBFPos(4)-FigHeight;
        case 'bottom'
            FigPos(2) = GCBFPos(2);
        case 'center'
            FigPos(2) = (GCBFPos(2) + GCBFPos(4) / 2) - FigHeight / 2;
    end
end

FigPos(3:4)=[FigWidth FigHeight];

% Use Position property for App Designer windows to avoid the gap
if useInnerPosition
    hObject.Position = FigPos;
else
    try
        hObject.OuterPosition = FigPos;
    catch
        FigPos(2) = FigPos(2) - 32;
        hObject.Position = FigPos;
    end
end

hObject.Units = OldUnits;
end