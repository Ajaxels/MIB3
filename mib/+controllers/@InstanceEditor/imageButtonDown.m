function imageButtonDown(obj)
% IMAGEBUTTONDOWN - Click on the image while pick mode is on: select the object under the cursor.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.imageButtonDown()
%
% The object index is read with a single-pixel ``getData2D``, the same trick
% ``MibController.findMaterialUnderCursor`` (Ctrl+F) uses: it costs nothing on
% any size of dataset and, unlike ``mibModel.IrawModel``, it is exact at full
% resolution rather than at display resolution, so it does not mis-pick when
% zoomed out.
%
% Picking follows the modifier convention MIB uses everywhere else:
%
%   - plain click - **start a new selection** with this object
%   - ``shift`` - add it to the selection
%   - ``control`` - remove it from the selection
%
% Every other click is handed back to
% ``MibImageDocument.gui_WindowButtonDownFcn`` unchanged, so panning with the
% right mouse button keeps working while the editor owns the mouse. Taking over
% ``WindowButtonDownFcn`` means taking over *every* button, and panning is how
% the user reaches the next object to pick.
%
% The modifier comes from ``mibController.currentModifier``; the figure's own
% ``CurrentModifier`` is unreliable here.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   (none)
%
% See also: controllers.InstanceEditor.setPickMode,
% controllers.InstanceEditor.reassertPickMode

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.InstanceEditor.imageButtonDown: triggered\n');
end

if ~obj.pickModeActive; return; end

imageDocument = obj.imageDocument();
if isempty(imageDocument); return; end

% Work out what the click is before anything else: a pan has to be passed on
% even when there is no model to pick from and even when the cursor is outside
% the image, which the picking guards below would both reject.
action = iClickAction(obj, imageDocument.UIFigure);
if strcmp(action, 'delegate') || ~obj.modelIsEditable()
    iDelegateToImageDocument(obj, imageDocument);
    return;
end

if isprop(imageDocument, 'isInsideImage') && ~imageDocument.isInsideImage; return; end

xy = imageDocument.handles.imViewAxes.CurrentPoint;
[x, y, z] = obj.mibModel.convertMouseToDataCoordinates(xy(1, 1), xy(1, 2), 'shown', 0);
x = ceil(x);  y = ceil(y);

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};
[height, width] = dataset.getDatasetDimensions('image', [], struct('blockModeSwitch', 0));
if x < 1 || y < 1 || x > width || y > height; return; end

readOptions = struct('blockModeSwitch', 0, 'id', id, 'x', [x, x], 'y', [y, y]);
objectId = double(cell2mat(obj.mibModel.getData2D('labels', z, [], [], readOptions)));

% Background is not an object, but a plain click there is still a request to
% start again - the same thing it does on an object.
if isempty(objectId); return; end
if objectId == 0
    if strcmp(action, 'replace'); obj.selectedObjects = []; else; return; end
else
    switch action
        case 'replace'
            obj.selectedObjects = objectId;
        case 'add'
            % Picking the same object twice is a click too many, not a request
            % to add it again - keep the order so "smallest index wins" stays
            % predictable.
            obj.selectedObjects = unique([obj.selectedObjects, objectId], 'stable');
        case 'remove'
            obj.selectedObjects = setdiff(obj.selectedObjects, objectId, 'stable');
    end
end

obj.updateSelectedList();
obj.updateObjectTable();
obj.highlightObjects();
end

% =====================================================================
function action = iClickAction(obj, hFig)
% Which picking gesture this click is, or 'delegate' when it belongs to the
% image document - panning above all.
%
% The pan/select split mirrors MibImageDocument.gui_WindowButtonDownFcn,
% including the System.LeftMouseButton preference that swaps the two buttons
% over. It is restated here rather than shared because that handler decides and
% acts in one pass, with no way to ask it the question alone; keep the two in
% step if the rule there changes.
modifier = obj.mibController.currentModifier;

% shift+alt+control+click is the document's own pan tweak, in either mode
if ~isempty(modifier) && sum(ismember(modifier, {'shift', 'alt', 'control'})) == 3
    action = 'delegate';
    return;
end

selectWithLeftButton = obj.mibModel.preferences.System.LeftMouseButton(1) == 's';

switch hFig.SelectionType
    case 'normal'       % LMB
        if selectWithLeftButton; action = 'replace'; else; action = 'delegate'; end
    case 'extend'       % shift + either button, MMB
        action = 'add';
    case 'alt'          % RMB, or control + either button
        % 'alt' cannot tell control+LMB from a plain right click on its own,
        % which is why the modifier state decides it here as it does there.
        if any(strcmp(modifier, 'control'))
            action = 'remove';
        elseif selectWithLeftButton
            action = 'delegate';    % plain RMB pans
        else
            action = 'replace';     % ...unless RMB is the selecting button
        end
    otherwise           % 'open' (double click) and anything added later
        action = 'delegate';
end
end

% =====================================================================
function iDelegateToImageDocument(obj, imageDocument)
% Hand the click back to the image document, then take the mouse again.
%
% The pan gesture clears WindowButtonDownFcn while it runs, and the
% WindowButtonUpFcn that ends it restores *the document's* handler rather than
% this one (see MibImageDocument.gui_WindowButtonUpFcn). Chaining onto that
% up-callback is what stops a single pan from quietly ending pick mode.
hFig = imageDocument.UIFigure;
imageDocument.gui_WindowButtonDownFcn();

panUpFcn = hFig.WindowButtonUpFcn;
if isempty(panUpFcn)
    % No gesture was started, so nothing will restore anything; the handler is
    % normally still ours, and reasserting costs nothing if it is.
    obj.reassertPickMode();
    return;
end
hFig.WindowButtonUpFcn = @(src, evnt) iGestureFinished(obj, panUpFcn, src, evnt);
end

% =====================================================================
function iGestureFinished(obj, originalFcn, src, evnt)
% Let the gesture end exactly as it would have, then take the mouse back.
originalFcn(src, evnt);
if isvalid(obj); obj.reassertPickMode(); end
end
