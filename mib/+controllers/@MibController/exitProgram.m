function result = exitProgram(obj, target)
% function result = exitProgram(obj)
%   Exit MIB and do required closing tasks

arguments (Input)
    obj controllers.MibController
    target matlab.ui.container.internal.AppContainer
end


% result = false;
% prompt = "Close " + target.Title + "?";
% answer = questdlg(char(prompt), 'Close', 'Yes', 'No', 'No');
% if strcmp(answer, 'Yes'); result = true; end

result = true;

end