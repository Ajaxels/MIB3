function helpBtn_Callback(obj)
%HELPBTN_CALLBACK - show documentation

helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'site', 'user-interface', 'ribbon', 'tools', 'tools-randforest.html');
if isfile(helpFilPath)
    web(helpFilPath, '-browser');
else
    web('http://mib.helsinki.fi/help/main3/user-interface/ribbon/tools/tools-randforest.html', '-browser');
end

end