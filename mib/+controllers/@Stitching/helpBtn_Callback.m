function helpBtn_Callback(obj)
% HELPBTN_CALLBACK - Open the online help page for the Stitching tool.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.helpBtn_Callback()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Stitching.helpBtn_Callback: triggered\n');
end
helpFilePath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'dataset', 'dataset-stitch.html');
utils.openHelpPage(helpFilePath, ...
    'http://mib.helsinki.fi/help/main3/user-interface/ribbon/dataset/dataset-stitch.html');

end
