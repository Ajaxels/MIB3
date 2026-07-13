function helpBtn_Callback(obj)
% HELPBTN_CALLBACK - Open the online help page for the Stitching tool.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.helpBtn_Callback()
%

helpFilePath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', ...
    'user-interface', 'ribbon', 'dataset', 'dataset-stitch.html');
if isfile(helpFilePath)
    web(helpFilePath, '-browser');
else
    web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/dataset/dataset-stitch.html', '-browser');
end

end
