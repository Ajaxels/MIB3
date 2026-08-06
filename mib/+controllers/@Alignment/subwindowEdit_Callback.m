function subwindowEdit_Callback(obj, hObject)
% SUBWINDOWEDIT_CALLBACK - Validate the manual subarea (minX/minY/maxX/maxY) widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.subwindowEdit_Callback()
%      obj.subwindowEdit_Callback(hObject)
%
% Input Arguments:
%   - **hObject** *(optional)* - handle to the widget that fired the callback.
%
% Coerces out-of-range values back into ``[1, width]`` / ``[1, height]`` and
% reports the correction via :func:`utils.dlgs.showErrorDialog`.

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Alignment.subwindowEdit_Callback: triggered\n');
end
if nargin < 2; hObject = []; end

id = obj.mibModel.getActiveId();
imgWidth  = obj.mibModel.I{id}.image.width;
imgHeight = obj.mibModel.I{id}.image.height;

h = obj.view.handles;
x1 = h.minX.Value;
y1 = h.minY.Value;
x2 = h.maxX.Value;
y2 = h.maxY.Value;

if x1 < 1 || x1 > imgWidth
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf('The minX value must be between 1 and %d.', imgWidth), 'Wrong X min');
    h.minX.Value = 1;
elseif y1 < 1 || y1 > imgHeight
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf('The minY value must be between 1 and %d.', imgHeight), 'Wrong Y min');
    h.minY.Value = 1;
elseif x2 < 1 || x2 > imgWidth
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf('The maxX value must be between 1 and %d.', imgWidth), 'Wrong X max');
    h.maxX.Value = imgWidth;
elseif y2 < 1 || y2 > imgHeight
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        sprintf('The maxY value must be between 1 and %d.', imgHeight), 'Wrong Y max');
    h.maxY.Value = imgHeight;
end

if ~isempty(hObject)
    obj.updateBatchOptFromGUI(hObject);
end

end
