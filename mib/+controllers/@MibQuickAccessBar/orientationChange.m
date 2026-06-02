function orientationChange(obj, hWidget, moveMouseSw)
% ORIENTATIONCHANGE - Callback for the orientation toggle buttons in the Quick Access Bar.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.orientationChange(hWidget, moveMouseSw)
%
% Switches the viewing plane of the current dataset to YX (XY), XZ, or YZ.
% Converted from MIB2 @mibController/mibToolbarPlaneToggle.m
%
% Input Arguments:
%   - **hWidget** — [matlab.ui.control.Button|char] orientation button handle (``yx_orientation``, ``xz_orientation``, or ``yz_orientation``) or target orientation description string (for keyboard-shortcut callers)
%   - **moveMouseSw** *(optional)* — [logical] move mouse cursor to orientation change pivot point (default: ``false``); used with Alt+1/2/3 keyboard shortcuts to keep cursor over image
%
% **Example 1** — Called from gui_Callbacks when orientation button pressed:
%
%   .. code-block:: matlab
%
%      obj.orientationChange(hWidget);
%
% **Example 2** — Called from gui_WindowKeyPressFcn with mouse centering (Alt+1):
%
%   .. code-block:: matlab
%
%      obj.mibController.cActiveDataset.cQAB.orientationChange( ...
%          obj.mibController.view.handles.qab.handles.yx_orientation, true);
%

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

cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};

% Orientation switch changes coef_z (pixel aspect ratio).  showImage() has
% just updated imageHandle.XData with the new coef_z, so the stored brush
% cursor offset (computed for the old orientation) is now wrong.  Clear it
% so the next updateBrushCursor call recomputes the ellipse from fresh data.
cImageDoc.brushCursorOffset = [];

% ---- Move mouse cursor to the pivot point (for keyboard shortcut callers) ----
if moveMouseSw
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

    cImageDoc.centerCursorInAxes();
end
end
