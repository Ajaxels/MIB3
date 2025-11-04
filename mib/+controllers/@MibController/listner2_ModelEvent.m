function listner2_ModelEvent(obj, model, evnt)
% function listner2_ModelEvent(obj, model, evnt)
% listener callback function for detection of MibModel events
% Requires to make eventdata instance of the ToggleEventData class

%|
% @b Examples:
% @code
% notifyEvent.Name = "updateSegmentationTable";
% eventdata = ToggleEventData(notifyEvent);\n' ...
% notify(obj, "modelNotify", eventdata);
% @endcode

arguments (Input)
    obj controllers.MibController
    model 
    evnt (1,1) ToggleEventData
end

if ~ismember('Parameter', fieldnames(evnt))
    errorText = sprintf(['<b>!!! Listner error !!!</b>\n\n' ...
        'Parameter field is required!\n\n' ...
        '                    Example,\n' ...
        '                    notifyEvent.Name = "updateSegmentationTable";\n' ...
        '                    eventdata = ToggleEventData(notifyEvent);\n' ...
        '                    notify(obj, "modelNotify", eventdata);']);

    utils.showErrorDialog([], errorText, title='Listner error', prefix='listner2_ModelEvent error');
    return;
end

switch evnt.EventName
    case 'modelNotify'
        % generic notification event to make the list of listners smaller,
        % call it as notify(obj, 'modelNotify', eventdata); see in mibModel.renameMaterial
        switch evnt.Parameter.Name
            case 'updateSegmentationTable'  % update the segmentation table
                %obj.updateSegmentationTable();
                %fprintf('listner2_ModelEvent: new file created!\n');
            case 'newFileCreated'
                %fprintf('listner2_ModelEvent: new file created!\n');
        end
end
end