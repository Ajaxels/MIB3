function listner_Standard(obj, model, evnt)
% LISTNER_STANDARD - standard listener callback for event that is provided as evnt.EventName.
%
% Syntax:
%   function listner_Standard(obj, model, evnt)
%
 
arguments (Input)
    obj controllers.MibController
    model
    evnt
end

switch evnt.EventName
    case 'keyPressEvent'
        % evnt.Parameters.eventdata provides presesed key info
        %obj.mibGUI_WindowKeyPressFcn(evnt.Parameters.eventdata);
    case 'newFileCreated'
        %fprintf('listner1_Standard: new file created!\n');
end

end
