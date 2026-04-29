function helpBtn_Callback(obj)
% HELPBTN_CALLBACK - open the batch processing help page in the system browser.
%
% Syntax:
%   function helpBtn_Callback(obj)
%
% Usage:
%   Example 1::
%
%     obj.helpBtn_Callback();
%

web(fullfile(obj.mibModel.mibPath, 'techdoc/html/user-interface/menu/file/file-batchprocessing.html'), '-browser');
end
