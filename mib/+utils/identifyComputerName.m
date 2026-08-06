function computerName = identifyComputerName()
% IDENTIFYCOMPUTERNAME - Return the current computer name, safe for use as a filename prefix.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      computerName = utils.identifyComputerName()
%
% Output Arguments:
%   - **computerName** - [char] computer hostname with non-alphanumeric characters
%     replaced by underscores; empty string on failure
%
% Usage:
%   **Example 1** - get computer name for override preferences file
%
%   .. code-block:: matlab
%
%      computerName = utils.identifyComputerName();
%      overrideFile = fullfile(mibPath, sprintf('mib3_prefs_override_%s.mat', computerName));

computerName = '';
try
    if ispc
        % alternative, does not work on Linux
        % java.net.InetAddress.getLocalHost.getHostName
        computerName = getenv('COMPUTERNAME');
    else
        [~, computerName] = system('hostname');
        computerName = strtrim(computerName);
    end
    computerName = regexprep(computerName, '[^a-zA-Z0-9-]', '_');
catch
end

end
