function listener_updateGuiWidgets(obj, ~, evtData)
% LISTENER_UPDATEGUIWIDGETS - Listener callback for the MibModel 'UpdateGuiWidgets' event.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listener_updateGuiWidgets(src, evtData)
%
% Delegates to obj.updateGuiWidgets(), optionally restricting the update to
% a specific subset of panels when the caller supplies panel names via
% core.ToggleEventData.Parameters.  When Parameters is absent or empty all
% panels are refreshed.
%
% Input Arguments:
%   - **src** - handle to MibModel (unused, indicated by ~ in the signature)
%   - **evtData** - event data; an instance of ``core.ToggleEventData`` or a plain
%     ``event.EventData`` when no panel filtering is required.
%     ``evtData.Parameters``: *(optional)* char or cell array of panel name strings;
%     when omitted or empty, all panels are updated.  Valid values:
%
%     - ``'ribbonImage'``        - Image ribbon tab (bit depth, color type)
%     - ``'ribbonModel'``        - Model ribbon tab (model type radio buttons)
%     - ``'QuickAccessBar'``     - Orientation buttons, ROI, block-mode toggle
%     - ``'depthSlider'``        - Z-slice number slider and edit field
%     - ``'timeSlider'``         - Time-frame slider and edit field
%     - ``'checkboxes'``         - Show mask / model checkboxes, restrict controls
%     - ``'imView'``             - Image view panel title
%     - ``'activeDataset'``      - Dataset buffer buttons in the Datasets panel
%     - ``'dirContentsDataset'`` - Directory contents file list and filter
%     - ``'panelThresholding'``  - Black/white threshold sliders
%     - ``'selectionPanel'``     - LUT checkbox and colour table
%     - ``'statusBar'``          - Status bar current-directory field
%
% Output Arguments:
%   (none)
%
% **Example 1** - update ALL panels (fire and forget - no event data needed):
%
%   .. code-block:: matlab
%
%      notify(obj.mibModel, 'UpdateGuiWidgets');
%
% **Example 2** - update only the Model ribbon tab and the checkboxes panel:
%
%   .. code-block:: matlab
%
%      eventdata = core.ToggleEventData({'ribbonModel', 'checkboxes'});
%      notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
%

if ~isprop(evtData, 'Parameters') || isempty(evtData.Parameters)
    updatePanels = {};
else
    updatePanels = evtData.Parameters;
end

obj.updateGuiWidgets(updatePanels);
end
