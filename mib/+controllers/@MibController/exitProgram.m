function result = exitProgram(obj, target)
% EXITPROGRAM - Close MIB, release resources, and signal the AppContainer to exit.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = obj.exitProgram(target)
%
% Closes all child controller windows, terminates any active Python session
% (to free GPU memory), and unloads the OMERO library if present.
% Registered as ``AppContainer.ExitFcn`` in MibController.initialize.
%
% Input Arguments:
%   - **target** — ``matlab.ui.container.internal.AppContainer`` handle to the
%     main application container
%
% Output Arguments:
%   - **result** — always ``true``; reserved for future cancel-on-close support
%

arguments (Input)
    obj controllers.MibController
    target matlab.ui.container.internal.AppContainer
end

% result = false;
% prompt = "Close " + target.Title + "?";
% answer = questdlg(char(prompt), 'Close', 'Yes', 'No', 'No');
% if strcmp(answer, 'Yes'); result = true; end

% stop and delete the check-for-update timer, if it has not fired yet
if ~isempty(obj.updateCheckTimer) && isvalid(obj.updateCheckTimer)
    stop(obj.updateCheckTimer);
    delete(obj.updateCheckTimer);
end
obj.updateCheckTimer = [];

% close child controllers
for i=numel(obj.childControllers):-1:1
    child = obj.childControllers{i};
    if isa(child, 'handle') && isvalid(child)
        child.closeWindow();
    end
end

% terminate python session to release GPU memory; InProcess interpreters
% (used by SAM/SAM2) cannot be terminated and end together with MATLAB
if ~isempty(obj.mibModel.pythonEnv); utils.terminatePythonEnv(); end

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
mib_pars.preferences.System.Dirs.LastPath = obj.mibModel.currentDirectory;    % store current path
mib_pars.mibVersion = obj.mibVersionNumeric;   % define version of MIB for which preferences generated

prefdir = utils.getPrefDir();

try
    mib_pars.preferences.Users = rmfield(mib_pars.preferences.Users, 'Tiers'); % remove user's stats from the output preferences structure
    save(fullfile(prefdir, 'mib3.mat'), 'mib_pars');
    % Save user Tiers stats to the path stored in preferences (roaming by default;
    % user can override via the milestone dialog).
    Tiers = obj.mibModel.preferences.Users.Tiers;
    userStatsFn = obj.mibModel.preferences.System.UserStatsProfile;
    userStatsDir = fileparts(userStatsFn);
    if ~exist(userStatsDir, 'dir')
        mkdir(userStatsDir);
    end
    save(userStatsFn, 'Tiers');
catch err
    errorOpts.mibPath = obj.mibModel.mibPath;
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Save preferences error ', ...
        '', sprintf('There is a problem with saving preferences to\n%s\n%s', fullfile(prefdir, 'mib3.mat')), ...
        errorOpts);
end

result = true;

end
