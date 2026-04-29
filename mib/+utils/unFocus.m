function unFocus(hObject)
% UNFOCUS - Move focus away from the currently focused widget.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      unFocus(hObject)
%
% Temporarily disables and re-enables the widget to transfer focus back
% to the parent figure, preventing unwanted keyboard capture by input fields.
%
% Input Arguments:
%   - **hObject** — handle to the UI widget that should lose focus
%
% Usage:
%
%   **Example 1** — unfocus a button after clicking
%
%   .. code-block:: matlab
%
%      utils.unFocus(obj.view.handles.panels.segmentation.handles.addMaterial);
%

hObject.Enable = 'off';
drawnow;
hObject.Enable = 'on';
end
