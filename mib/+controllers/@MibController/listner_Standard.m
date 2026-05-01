function listner_Standard(obj, model, evnt)
% LISTNER_STANDARD - Standard listener callback dispatched by evnt.EventName.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.listner_Standard(model, evnt)
%
% Input Arguments:
%   - **model** — event source (object that fired the event)
%   - **evnt** — event data; ``evnt.EventName`` identifies the event type
%
% Output Arguments:
%   (none)
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
