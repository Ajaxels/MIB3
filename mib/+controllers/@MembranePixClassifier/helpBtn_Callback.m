function helpBtn_Callback(obj)
%HELPBTN_CALLBACK - show documentation

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MembranePixClassifier.helpBtn_Callback: triggered\n');
end

helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'tools', 'tools-randforest.html');
if isfile(helpFilPath)
    web(helpFilPath, '-browser');
else
    web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/tools/tools-randforest.html', '-browser');
end

end