function listener_updateToolbar(obj, src, evtData)
% LISTENER_UPDATETOOLBAR - Update buttons in MIB toolbar.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listener_updateToolbar(src, evtData)
%
% executed upon catch of MibModel->"UpdateToolbar" event
%
% Input Arguments:
%   - **src** - handle to MibModel
%   - **evtData** - event data, an instance of core.ToggleEventData class with the following fields:
%     .Parameters field containing a structure with the
%     .evtData.Parameters.button - [char] handle of the button in the toolbar, e.g. "fastpan",
%     .evtData.Parameters.state - [logical] state of the button true->pressed, false->depressed
%     .Source handle to MibModel
%     .EventName string with the event name that triggered the callback
%     see example in MibModel.datasetsSetsOps-> 'Add set'
%
% Output Arguments:
%   (none)
%
% **Example 1** - update the state of the fastpan button:
%
%   .. code-block:: matlab
%
%      Options.button = 'fastpan';
%      Options.state = true;
%      eventdata = core.ToggleEventData(Options);
%      notify(obj, 'UpdateToolbar', eventdata);
%

switch evtData.Parameters.button
    case 'fastpan'
        obj.cQuickAccessBar.handles.fastpan.Value = evtData.Parameters.state;
        obj.fastPanningMode = evtData.Parameters.state;
    case 'roiMode'
        obj.cQuickAccessBar.handles.roiMode.Value = evtData.Parameters.state;
    case 'blockMode'
        obj.cQuickAccessBar.handles.blockMode.Value = evtData.Parameters.state;
end
