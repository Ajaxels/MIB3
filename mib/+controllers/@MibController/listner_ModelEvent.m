function listner_ModelEvent(obj, model, evnt)
% LISTNER_MODELEVENT - Listener callback for generic MibModel events dispatched via ``modelNotify``.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listner_ModelEvent(model, evnt)
%
% Requires making the eventdata instance of the ``core.ToggleEventData`` class.
%
% Input Arguments:
%   - **model** — handle to MibModel (event source)
%   - **evnt** — instance of ``core.ToggleEventData``; ``evnt.EventName`` identifies the
%     event and ``evnt.Parameters`` carries event-specific payload
%
% Output Arguments:
%   (none)
%
% **Example 1** — fire a generic model notification:
%
%   .. code-block:: matlab
%
%      notifyEvent.Name = "updateSegmentationTable";
%      eventdata = core.ToggleEventData(notifyEvent);
%      notify(obj, "modelNotify", eventdata);
%

% arguments (Input)
%     obj controllers.MibController
%     model 
%     evnt (1,1) ToggleEventData
% end

% if ~ismember('Parameters', fieldnames(evnt))
%     errorText = sprintf(['Parameters field is required!\n\n' ...
%         'Example,\n' ...
%         '  notifyEvent.Name = "updateSegmentationTable";\n' ...
%         '  eventdata = ToggleEventData(notifyEvent);\n' ...
%         '  notify(obj, "modelNotify", eventdata);']);
% 
%     errorOpts.mibPath      = obj.mibModel.mibPath;
%     utils.dlgs.showErrorDialog(obj.view.gui, errorText, 'Listner error', 'listner_ModelEvent error', '', errorOpts);
%     return;
% end

switch evnt.EventName
    case 'UpdateUserScore'
        % increase user score after use of a segmentation tool
        % or performing operations in MIB
        scalingFactor = 1;
        if ismember('Parameters', fieldnames(evnt)); scalingFactor = evnt.Parameters; end
        obj.mibModel.preferences.Users.Tiers.collectedPoints = ...
            obj.mibModel.preferences.Users.Tiers.collectedPoints+obj.mibModel.preferences.Users.singleToolScores*scalingFactor;
        % fprintf('Collected points: %f\n', obj.mibModel.preferences.Users.Tiers.collectedPoints);

    case 'modelNotify'
        % generic notification event to make the list of listners smaller,
        % call it as notify(obj, 'modelNotify', eventdata); see in mibModel.renameMaterial
        switch evnt.Parameters.Name
            case 'updateSegmentationTable'  % update the segmentation table
                %obj.updateSegmentationTable();
                %fprintf('listner2_ModelEvent: new file created!\n');
            case 'newFileCreated'
                %fprintf('listner2_ModelEvent: new file created!\n');
        end
end
end
