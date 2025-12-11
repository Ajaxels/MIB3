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

% close child controllers
for i=numel(obj.childControllers):-1:1
    if isvalid(obj.childControllers{i})
        obj.childControllers{i}.closeWindow();
    end
end

% terminate python session to release GPU memory
if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end

% unload OMERO
if ~isdeployed
    if exist('unloadOmero.m','file') == 2
        % preserve Omero path
        omeroPath = findOmero;
        warning('off','MATLAB:javaclasspath:jarAlreadySpecified');    % switch off warnings for latex
        unloadOmero;
        addpath(omeroPath);
        warning('on','MATLAB:javaclasspath:jarAlreadySpecified');    % switch off warnings for latex
    end
end

% define structure to store preferences
mib_pars = struct();
mib_pars.preferences = obj.mibModel.preferences; %#ok<STRNU>     % store preferences
mib_pars.preferences.System.Dirs.LastPath = obj.mibModel.myPath;    % store current path
mib_pars.mibVersion = obj.mibVersionNumeric;   % define version of MIB for which preferences generated

prefdir = utils.getPrefDir();

try
    mib_pars.preferences.Users = rmfield(mib_pars.preferences.Users, 'Tiers'); % remove user's stats from the output preferences structure
    save(fullfile(prefdir, 'mib3.mat'), 'mib_pars');
    % additionally save preferences.Users.Tiers to mib_user.mat
    Tiers = obj.mibModel.preferences.Users.Tiers;
    save(fullfile(prefdir, 'mib_user.mat'), 'Tiers');
catch err
    utils.dlgs.showErrorDialog([], err, 'Save preferences error ', ...
        [], sprintf('There is a problem with saving preferences to\n%s\n%s', fullfile(prefdir, 'mib3.mat')));
end

result = true;

end