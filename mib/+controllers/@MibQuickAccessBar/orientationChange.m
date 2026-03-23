function orientationChange(obj, hWidget, moveMouseSw)
% function orientationChange(obj, hWidget, moveMouseSw)
% Callback for the orientation toggle buttons in the Quick Access Bar.
% Switches the viewing plane of the current dataset to YX (XY), XZ, or YZ.
% Converted from MIB2 @mibController/mibToolbarPlaneToggle.m
%
% Parameters:
% hWidget: handle to the pressed orientation button (yx_orientation,
%          xz_orientation, or yz_orientation), or a char with the target
%          orientation description string (for keyboard-shortcut callers).
% moveMouseSw: [@em optional] logical, when true moves the mouse cursor to the
%              pivot point of the orientation change (used with Alt+1/2/3
%              keyboard shortcuts so the cursor stays over the image).
%              Default: false.
%
% Return values:
%   none
%
% Example:
%   % Called from gui_Callbacks when an orientation button is pressed:
%   obj.orientationChange(hWidget);
%
%   % Called from gui_WindowKeyPressFcn with mouse centering (Alt+1):
%   obj.mibController.cActiveDataset.cQAB.orientationChange( ...
%       obj.mibController.view.handles.qab.handles.yx_orientation, true);

if nargin < 3; moveMouseSw = false; end

% developer mode
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibQuickAccessBar.orientationChange: pressed\n');
end

dataset = obj.mibModel.I{obj.mibModel.id};

% Ensure only the pressed button is active (radio-button behaviour)
obj.handles.yx_orientation.Value = false;
obj.handles.xz_orientation.Value = false;
obj.handles.yz_orientation.Value = false;

% If dataset has only one z-slice, force YX and bail out
if dataset.image.depth == 1
    obj.handles.yx_orientation.Value = true;
    return;
end

if isprop(hWidget, 'Selected')
    hWidget.Selected = true;
else
    hWidget.Value = true;
end

% Save current magnification before transpose (transpose does not touch magFactor)
savedMag = dataset.magFactor;

% Transpose the dataset to the requested orientation.
% transpose() argument:  3 -> 'yx' (XY plane)
%                        1 -> 'xz' (ZX plane)
%                        2 -> 'yz' (ZY plane)
switch hWidget.Description
    case 'Switch dataset to the YX orientation'
        dataset.transpose(3);   % -> 'yx'
    case 'Switch dataset to the XZ orientation'
        dataset.transpose(1);   % -> 'xz'
    case 'Switch dataset to the YZ orientation'
        dataset.transpose(2);   % -> 'yz'
end

% Keep the saved magnification across the orientation change.
% Compute the new image dimensions and coef_z after transpose, then
% centre the view on the image at the saved magFactor.
if dataset.orientation == 3
    coef_z_new = dataset.image.pixSize.x / dataset.image.pixSize.y;
    newH = dataset.dim_yxzct(1);
    newW = dataset.dim_yxzct(2);
elseif dataset.orientation == 1
    coef_z_new = dataset.image.pixSize.z / dataset.image.pixSize.x;
    newH = dataset.dim_yxzct(2);
    newW = dataset.dim_yxzct(3);
else  % orientation == 2
    coef_z_new = dataset.image.pixSize.z / dataset.image.pixSize.y;
    newH = dataset.dim_yxzct(1);
    newW = dataset.dim_yxzct(3);
end

cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
axSize = cImageDoc.handles.imViewAxes.InnerPosition;
halfW  = axSize(3) * savedMag / (2 * coef_z_new);
halfH  = axSize(4) * savedMag / 2;
dataset.setAxesLimits([newW/2 - halfW, newW/2 + halfW], ...
                      [newH/2 - halfH, newH/2 + halfH]);
dataset.magFactor = savedMag;

% Use 'resize' mode so listener_updateDatasetAxes keeps the restored magFactor
Options.mode = 'resize';
eventdata = core.ToggleEventData(Options);
notify(obj.mibModel, 'UpdateDatasetAxes', eventdata);

% Update all GUI widgets (ribbon controls, spinners, etc.)
obj.mibController.updateGuiWidgets({'depthSlider'}); % only depth slider needs to be updated

% Render the image
obj.mibController.showImage();

% ---- Move mouse cursor to the pivot point (for keyboard shortcut callers) ----
if moveMouseSw
    cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};

    % Determine pivot coordinates in dataset space for the new orientation
    switch hWidget.Description
        case 'Switch dataset to the YX orientation'
            x = dataset.current_yxz(2);
            y = dataset.current_yxz(1);
        case 'Switch dataset to the XZ orientation'
            x = dataset.current_yxz(3);
            y = dataset.current_yxz(2);
        case 'Switch dataset to the YZ orientation'
            x = dataset.current_yxz(3);
            y = dataset.current_yxz(1);
    end

    % Center the view on the pivot point and re-render
    dataset.moveView(x, y);
    obj.mibController.showImage();

    % Get panel / axes geometry to compute screen coordinates of axes centre
    leftPanelW = 0;
    if isfield(obj.view.gui.Layout.panelLayout, 'left')
        leftPanelW   = obj.view.gui.Layout.panelLayout.left.freeDimension;
        if obj.view.gui.Layout.panelLayout.left.collapsed; leftPanelW   = 0; end
    end
    bottomPanelH = 0;
    if isfield(obj.view.gui.Layout.panelLayout, 'bottom')
        bottomPanelH = obj.view.gui.Layout.panelLayout.bottom.freeDimension;
        if obj.view.gui.Layout.panelLayout.bottom.collapsed; bottomPanelH = 0; end
    end

    winBounds = obj.view.gui.WindowBounds;          % [left, top, width, height], top-left origin
    posAxes = cImageDoc.handles.imViewAxes.Position; % [left, bottom, width, height], bottom-left within document

    screenX = winBounds(1) + leftPanelW + posAxes(1) + posAxes(3)/2;
    screenY = winBounds(2) + winBounds(4) - bottomPanelH - posAxes(2) - posAxes(4)/2;

    scaling = obj.mibModel.preferences.System.GUI.systemscaling;
    screenSize = get(0, 'ScreenSize');
    pointerX = (screenX + 8) * scaling;
    pointerY = (screenSize(4) - screenY + 26) * scaling;

    gr = groot();
    gr.PointerLocation = [pointerX, pointerY];
end
end
