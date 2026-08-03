function helpBtn_Callback(obj)
% HELPBTN_CALLBACK - Open the online help page for the Stitching Inspector tool.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.helpBtn_Callback()
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.StitchingInspector.helpBtn_Callback: triggered\n');
end
helpFilePath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'dataset', 'dataset-stitch-inspector.html');
if isfile(helpFilePath)
    web(helpFilePath, '-browser');
else
    web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/dataset/dataset-stitch-inspector.html', '-browser');
end

end
