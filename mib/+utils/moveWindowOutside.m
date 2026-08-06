function hObject = moveWindowOutside(hObject, mibGUI, alignH, alignV)
% MOVEWINDOWOUTSIDE - Position a dialog window alongside the main MIB figure.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      hObject = moveWindowOutside(hObject, mibGUI)
%      hObject = moveWindowOutside(hObject, mibGUI, alignH, alignV)
%
% Attempts to place the dialog beside the main window.  Falls back to
% centring on the main figure when there is insufficient screen space.
%
% Input Arguments:
%   - **hObject** - handle of the window to be moved
%   - **mibGUI** - handle to the main MIB GUI (``obj.mibModel.mibGUI``); pass ``[]`` to centre on screen
%   - **alignH** *(optional)* - [char] horizontal alignment: ``'left'`` *(default)*, ``'right'``, ``'center'``
%   - **alignV** *(optional)* - [char] vertical alignment: ``'top'`` *(default)*, ``'bottom'``, ``'center'``
%
% Output Arguments:
%   - **hObject** - handle to the repositioned window
%
% Usage:
%
%   **Example 1** - position a child dialog to the left of the main window
%
%   .. code-block:: matlab
%
%      obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI);
%
%   **Example 2** - position to the right and bottom
%
%   .. code-block:: matlab
%
%      obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'right', 'bottom');
%

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
    else
        % Use mibGUI directly (gcbf only works inside callbacks, not constructors)
        GCBFOldUnits = mibGUI.Units;
        mibGUI.Units = 'pixels';
        GCBFPos = mibGUI.OuterPosition;
        mibGUI.Units = GCBFOldUnits;
    end
    % Always use Position for uifigures - writing OuterPosition can
    % trigger re-layout and shrink the window
    useInnerPosition = isa(hObject, 'matlab.ui.Figure');
    
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
            FigPos(2) = GCBFPos(2)+GCBFPos(4)-FigHeight-30;
        case 'bottom'
            FigPos(2) = GCBFPos(2);
        case 'center'
            FigPos(2) = (GCBFPos(2) + GCBFPos(4) / 2) - FigHeight / 2;
    end
end

FigPos(3:4)=[FigWidth FigHeight];

% Clamp to screen so bottom is never off-screen
screenSize = get(0, 'ScreenSize');
if FigPos(2) < 1
    FigPos(2) = 1;
end
if FigPos(1) < 1
    FigPos(1) = 1;
end
if FigPos(1) + FigWidth > screenSize(3)
    FigPos(1) = max(1, screenSize(3) - FigWidth);
end
if FigPos(2) + FigHeight > screenSize(4)
    FigPos(2) = max(1, screenSize(4) - FigHeight);
end

% Only reposition (X, Y) - never overwrite the size that MATLAB laid out.
% Reading OuterPosition while the figure is invisible can return a stale
% (smaller) height, so writing it back would shrink the window.
if useInnerPosition
    hObject.Position(1:2) = FigPos(1:2);
else
    try
        hObject.OuterPosition(1:2) = FigPos(1:2);
    catch
        hObject.Position(1:2) = FigPos(1:2);
    end
end

hObject.Units = OldUnits;
end
