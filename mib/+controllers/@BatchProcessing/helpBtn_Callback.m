function helpBtn_Callback(obj)
% HELPBTN_CALLBACK - open the batch processing help page in the system browser.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.helpBtn_Callback()
%
% Usage:
%   Example 1::
%
%     obj.helpBtn_Callback();
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.BatchProcessing.helpBtn_Callback: triggered\n');
end
helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'home', 'home-batchprocessing.html');
if isfile(helpFilPath)
    web(helpFilPath, '-browser');
else
    web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-batchprocessing.html', '-browser');
end

end
