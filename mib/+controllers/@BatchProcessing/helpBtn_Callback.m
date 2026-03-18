function helpBtn_Callback(obj)
% function helpBtn_Callback(obj)
% open the batch processing help page in the system browser
%
%|
% @b Examples:
% @code obj.helpBtn_Callback(); @endcode
%
% Updates
%

web(fullfile(obj.mibModel.mibPath, 'techdoc/html/user-interface/menu/file/file-batchprocessing.html'), '-browser');
end
