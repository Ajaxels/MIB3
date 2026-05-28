function segmentationLines3D(obj, y, x, z, modifier)
% SEGMENTATIONLINES3D - Handle mouse clicks for 3D line skeleton annotation.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.segmentationLines3D(y, x, z, modifier)
%
% Reads the action from the Lines3D segmentation-panel dropdowns
% (click / shift-click / ctrl-click / alt-click) and delegates to the
% corresponding method of ``core.Lines3D``.
%
% Input Arguments:
%   - **y** — [double] y-coordinate of clicked point in full-dataset pixels
%   - **x** — [double] x-coordinate of clicked point in full-dataset pixels
%   - **z** — [double] z-coordinate (slice index) of clicked point
%   - **modifier** — [char|cell] modifier key held during click:
%
%     - ``''`` or ``{}`` — use default click action
%     - ``'shift'`` — use shift-click action
%     - ``'control'`` — use ctrl-click action
%     - ``'alt'`` — use alt-click action
%
% Output Arguments:
%   (none)
%
% **Example 1** — default click action:
%
%   .. code-block:: matlab
%
%      obj.segmentationLines3D(50, 75, 10, {});
%
% **Example 2** — shift-click action:
%
%   .. code-block:: matlab
%
%      obj.segmentationLines3D(50, 75, 10, {'shift'});
%

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};

obj.mibModel.backup('lines3d');

[x, y, z] = dataset.convertPixelsToUnits(x, y, z);     % convert pixels to units

% --- determine action from segmentation panel dropdowns ---
segHandles = obj.view.handles.panels.segmentation.handles;
if isempty(modifier) || (iscell(modifier) && isempty(modifier{1}))
    action = segHandles.linesClick.Value;
else
    if iscell(modifier); modifier = modifier{1}; end
    switch modifier
        case 'shift'
            action = segHandles.linesShiftClick.Value;
        case 'control'
            action = segHandles.linesCtrlClick.Value;
        case 'alt'
            action = segHandles.linesAltClick.Value;
        otherwise
            action = segHandles.linesClick.Value;
    end
end

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfLine3D = obj.mibModel.preferences.Users.Tiers.numberOfLine3D + 1;
notify(obj.mibModel, 'UpdateUserScore');

switch action
    case 'Assign active node'
        dataset.lines3D.setActiveNode(x, y, z, dataset.orientation);
        eventdata = core.ToggleEventData('Assign active node');

    case 'Delete node'
        dataset.lines3D.deleteNode(x, y, z, dataset.orientation);
        eventdata = core.ToggleEventData('Delete node');

    case 'Modify active node'
        nodeId = dataset.lines3D.activeNodeId;
        dataset.lines3D.updateNodeCoordinate(nodeId, x, y, z);
        eventdata = core.ToggleEventData('Modify active node');

    case 'New tree'
        newTreeSwitch = 1;
        options.pixSize = dataset.image.pixSize;
        dataset.lines3D.addNode(x, y, z, newTreeSwitch, options);
        eventdata = core.ToggleEventData('New tree');

    case 'Split tree'
        dataset.lines3D.splitAtNode(x, y, z, dataset.orientation);
        eventdata = core.ToggleEventData('Split tree');

    case 'Add node'
        options.pixSize = dataset.image.pixSize;
        options.BoundingBox = dataset.image.boundingBox;
        dataset.lines3D.addNode(x, y, z, 0, options);
        eventdata = core.ToggleEventData('Add node');

    case 'Insert node after active'
        activeNodeId = dataset.lines3D.activeNodeId;
        if isempty(activeNodeId)
            dlgOpt.MsgBoxOnly = true;
            header = sprintf('!!! Error !!!\nPlease select first an active node!\nA new node will be inserted after the active node');
            dlgOpt.HeaderLines = 3;
            utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, header, {}, {}, 'Missing active node', dlgOpt);
            return;
        end
        dataset.lines3D.insertNode(activeNodeId, x, y, z);
        eventdata = core.ToggleEventData('Insert node');

    case 'Connect to node'
        targetNodeId = dataset.lines3D.findClosestNode(x, y, z, dataset.orientation);
        activeNodeId = dataset.lines3D.activeNodeId;
        dataset.lines3D.connectNodes(targetNodeId, activeNodeId);
        eventdata = core.ToggleEventData('Connect to node');
end

obj.mibModel.showLines3D = true;
notify(obj.mibModel, 'UpdatedLines3D', eventdata);
end
