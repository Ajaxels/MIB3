function pickObjectUnderCursor(obj, action)
% PICKOBJECTUNDERCURSOR - Add, remove or start a selection with the object under the mouse.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.pickObjectUnderCursor('replace')
%
% Shared by the two ways of picking from the image: a click while pick mode is
% on (``imageButtonDown``) and ++ctrl+f++ while shortcut mode is on, which needs
% no takeover of the mouse at all.
%
% The object index is read with a single-pixel ``getData2D``, the same trick
% ``MibController.findMaterialUnderCursor`` (Ctrl+F) uses: it costs nothing on
% any size of dataset and, unlike ``mibModel.IrawModel``, it is exact at full
% resolution rather than at display resolution, so it does not mis-pick when
% zoomed out.
%
% Input Arguments:
%   - **action** - char, what the cursor position does to the selection:
%
%     - ``'replace'`` - start a new selection with this object
%     - ``'add'`` - add it to the selection, once
%     - ``'remove'`` - take it out of the selection
%
% Output Arguments:
%   (none)
%
% See also: controllers.InstanceEditor.imageButtonDown,
% controllers.InstanceEditor.handleShortcut

% Updates
%

imageDocument = obj.imageDocument();
if isempty(imageDocument); return; end
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
