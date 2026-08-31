function setPickMode(obj, enable)
% SETPICKMODE - Take over, or hand back, the mouse on the image document.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setPickMode(true)
%       obj.setPickMode(false)
%
% While pick mode is on, a click on the image selects the object under the
% cursor instead of running the active segmentation tool. The takeover follows
% the pattern used by the ROI drawing helper of
% ``MibImageDocument.segmentationObjectPicker``: save what is being replaced,
% swap it, and put it back exactly as it was.
%
% ``WindowButtonDownFcn`` is one callback for every mouse button, so taking it
% over takes the right-button pan with it. ``imageButtonDown`` hands back
% everything that is not one of the three picking gestures, which is what keeps
% panning - the way the user reaches the next object - working throughout.
%
% Everything that is taken over is restored on the way out, including from
% ``closeWindow`` - a window that leaves ``disableSegmentation`` set or the
% figure's ``WindowButtonDownFcn`` pointing at a deleted controller makes the
% whole application unusable, and the user has no way to guess why.
%
% Input Arguments:
%   - **enable** - logical, switch pick mode on or off
%
% Output Arguments:
%   (none)

% Updates
%

if nargin < 2; enable = false; end

if enable
    if obj.pickModeActive; return; end
    imageDocument = obj.imageDocument();
    if isempty(imageDocument)
        obj.view.handles.pickByClick.Value = false;
        return;
    end

    obj.savedMouseState = struct(...
        'imageDocument',        imageDocument, ...
        'WindowButtonDownFcn',  imageDocument.UIFigure.WindowButtonDownFcn, ...
        'Pointer',              imageDocument.UIFigure.Pointer, ...
        'disableSegmentation',  obj.mibModel.disableSegmentation);

    % disableSegmentation stops the other mouse handlers (motion, scroll, brush)
    % from acting on a click that is no longer meant for them.
    obj.mibModel.disableSegmentation = true;
    imageDocument.UIFigure.WindowButtonDownFcn = @(~, ~) obj.imageButtonDown();
    imageDocument.UIFigure.Pointer = 'crosshair';
    obj.pickModeActive = true;
else
    if ~obj.pickModeActive; return; end
    saved = obj.savedMouseState;
    if ~isempty(saved) && isvalid(saved.imageDocument) && isvalid(saved.imageDocument.UIFigure)
        saved.imageDocument.UIFigure.WindowButtonDownFcn = saved.WindowButtonDownFcn;
        saved.imageDocument.UIFigure.Pointer = saved.Pointer;
    end
    if ~isempty(saved)
        obj.mibModel.disableSegmentation = saved.disableSegmentation;
    end
    obj.savedMouseState = [];
    obj.pickModeActive = false;
end

if ~isempty(obj.view) && isvalid(obj.view.gui)
    obj.view.handles.pickByClick.Value = obj.pickModeActive;
end
end
