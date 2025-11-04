function status = dragNdrop_Callback(obj, parameterIn)
% status = dragNdrop_Callback(obj, parameterIn)
% callback for filename drag-and-drop operation in MIB
%
% Parameters:
% parameterIn: a cell array, where 
% - the first element is a handle to the webWindow that was a target for the drag-and-drop operation
% - the second element is a filename that was dragged into MIB

arguments (Input)
    obj controllers.MibController
    parameterIn cell    
end

arguments (Output)
    status logical
end

status = false;

fprintf('MibController.dragNdrop_Callback: drag-and-drop file into MIB:\n%s\n', parameterIn{2});

status = true;
end