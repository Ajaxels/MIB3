function centerCursorInAxes(obj, cursorOverAxes)
% CENTERCURSORINAXES - Move the OS mouse cursor to the centre of this document's image axes.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.centerCursorInAxes()
%      obj.centerCursorInAxes(cursorOverAxes)
%
% Called after ``moveView`` so the cursor lands at the new image centre,
% matching the zoom-in behaviour in ``MibStatusBar.zoomEdit_Callback``.
% Works for both docked and undocked (floating) documents - the geometry is
% computed by :func:`axesCenterPointerLocation`.
%
% Input Arguments:
%   - **cursorOverAxes** *(optional)* - [logical] pass ``true`` when the OS
%     cursor is currently over this document's axes (zoom / middle-click
%     recenter) to use the precise runtime self-calibration. Defaults to
%     ``false`` (geometric reconstruction), used for ribbon-triggered calls.
%
% Output Arguments:
%   (none)
%
% See also :func:`axesCenterPointerLocation`.

arguments
    obj
    cursorOverAxes (1,1) logical = false
end

[pointerX, pointerY] = obj.axesCenterPointerLocation(cursorOverAxes);

gr = groot();
gr.PointerLocation = [pointerX, pointerY];
end
