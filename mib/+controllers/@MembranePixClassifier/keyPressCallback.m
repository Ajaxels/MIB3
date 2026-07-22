function keyPressCallback(obj, evnt)
% KEYPRESSCALLBACK - Forward key press events to the main MIB key handler.

arguments (Input)
    obj  controllers.MembranePixClassifier
    evnt
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MembranePixClassifier.keyPressCallback: triggered\n');
end

if isempty(evnt.Character); return; end
eventData = struct('eventdata', evnt);
eventData = core.ToggleEventData(eventData);
notify(obj.mibModel, 'keyPressEvent', eventData);

end
