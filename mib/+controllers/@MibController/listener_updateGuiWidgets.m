function listener_updateGuiWidgets(obj, ~, evtData)
% function listener_updateGuiWidgets(obj, src, evtData)
% Listener callback for the MibModel 'UpdateGuiWidgets' event
%
% Delegates to obj.updateGuiWidgets(), optionally restricting the update to
% a specific subset of panels when the caller supplies panel names via
% core.ToggleEventData.Parameters.  When Parameters is absent or empty all
% panels are refreshed.
%
% Parameters:
% src: handle to MibModel (unused, indicated by ~ in the signature)
% evtData: event data; an instance of core.ToggleEventData or a plain
%   event.EventData when no panel filtering is required.
%   .Parameters: [@em optional] char or cell array of chars with the names
%     of the panels to refresh.  When omitted or empty, all panels are
%     updated.  Valid panel name strings:
%     @li 'ribbonImage'        - Image ribbon tab (bit depth, color type)
%     @li 'ribbonModel'        - Model ribbon tab (model type radio buttons)
%     @li 'QuickAccessBar'     - Orientation buttons, ROI, block-mode toggle
%     @li 'depthSlider'        - Z-slice number slider and edit field
%     @li 'timeSlider'         - Time-frame slider and edit field
%     @li 'checkboxes'         - Show mask / model checkboxes, restrict controls
%     @li 'imView'             - Image view panel title
%     @li 'activeDataset'      - Dataset buffer buttons in the Datasets panel
%     @li 'dirContentsDataset' - Directory contents file list and filter
%     @li 'panelThresholding'  - Black/white threshold sliders
%     @li 'selectionPanel'     - LUT checkbox and colour table
%     @li 'statusBar'          - Status bar current-directory field
%
% Return values:
%

%|
% @b Examples:
% @code
% % Update ALL panels (fire and forget — no event data needed):
% notify(obj.mibModel, 'UpdateGuiWidgets');
% @endcode
%
% @code
% % Update only the Model ribbon tab and the checkboxes panel:
% eventdata = core.ToggleEventData({'ribbonModel', 'checkboxes'});
% notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
% @endcode

if ~isprop(evtData, 'Parameters') || isempty(evtData.Parameters)
    updatePanels = {};
else
    updatePanels = evtData.Parameters;
end

obj.updateGuiWidgets(updatePanels);
end
