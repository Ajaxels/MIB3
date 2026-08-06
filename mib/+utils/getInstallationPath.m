function path = getInstallationPath(softwareName)
% GETINSTALLATIONPATH - Get the installation directory of a deployed MATLAB application.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      path = getInstallationPath(softwareName)
%
% In the development environment, uses ``which(softwareName)`` to locate the file.
% In deployed mode, uses ``ctfroot`` / process-inspection fallbacks.
%
% Input Arguments:
%   - **softwareName** - [char] name of the software entry-point m-file (e.g. ``'mib3'``)
%
% Output Arguments:
%   - **path** - [char] full path to the installation directory; ``[]`` on failure
%
% Usage:
%
%   **Example 1** - get MIB installation directory
%
%   .. code-block:: matlab
%
%      installDir = utils.getInstallationPath('mib3');
%

arguments (Input)
    softwareName (1,:) char
end

path = [];

% ---- obtain path to the software
try
    if isdeployed()
        path = fileparts(utils.GetExeLocation());
        
        if ismac
            % fix  path = '/Applications/MIB/application/MIB.app/Contents/MacOS'
            % for some macos versions
            posIndex = strfind(path, [softwareName '.app']);
            if ~isempty(posIndex)
                path = path(1:posIndex-2);    % clip the path to '/Applications/MIB/application'
            end
        end
    else
        path = fileparts(which(softwareName));
    end
catch err
    utils.dlgs.showErrorDialog([], err, 'Can not identify installation location');
    path = [];
end

% try to obtain path differently
if isempty(path)
    if isdeployed
        if isunix()
            if ismac()
                NameOfDeployedApp = softwareName; % do not include the '.app' extension
                [~, result] = system(['top -n100 -l1 | grep ' NameOfDeployedApp ' | awk ''{print $1}''']);
                result = strtrim(result);
                [status, result] = system(['ps xuwww -p ' result ' | tail -n1 | awk ''{print $NF}''']);
                if status == 0
                    diridx = strfind(result, [NameOfDeployedApp '.app']);
                    path = result(1:diridx-2);
                else
                    path = sprintf('/Applications/%s/application/', softwareName);
                end
            else
                % the code below does not work on Mac OS X Yosemite and R2016a
                % so fix softwareName location
                [~, result] = system('path');
                path = char(regexpi(result, 'Path=(.*?);', 'tokens', 'once'));
            end
        else
            [~, result] = system('path');
            path = char(regexpi(result, 'Path=(.*?);', 'tokens', 'once'));
        end
    else
        path = fileparts(which(softwareName));
    end
end
