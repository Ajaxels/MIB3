%% Things that need to be fixed before release

%% Uncomment in exitProgram
% result = false;
% prompt = "Close " + target.Title + "?";
% answer = questdlg(char(prompt), 'Close', 'Yes', 'No', 'No');
% if strcmp(answer, 'Yes'); result = true; end

%% MibImage.clearLayer
% requires implementation of core.MibLabels63 logic!
% whenever core.MibLabels63 is used the type of the layer needs to be
% specified