function loadProtocol(obj)
% function loadProtocol(obj)
% load a protocol from a .mibProtocol file via a dialog
%
% Stores an undo snapshot before replacing the current protocol.
%
%|
% @b Examples:
% @code obj.loadProtocol(); @endcode
%
% Updates
%

if isempty(obj.mibModel.I{obj.mibModel.id}.image.filename)
    path = obj.mibModel.currentDirectory;
else
    path = fileparts(obj.mibModel.I{obj.mibModel.id}.image.filename);
    if isempty(path); path = obj.mibModel.currentDirectory; end
end

[filename, path] = utils.dlgs.mibUiGetFile(...
    {'*.mibProtocol',  'Matlab format (*.mibProtocol)'; ...
    '*.*',  'All Files (*.*)'}, ...
    'Load a protocol...', path);
if isequal(filename,0); return; end % check for cancel

res = load(fullfile(path, filename{1}), '-mat');
obj.backupProtocol();   % store the current protocol
obj.Protocol = res.Protocol;
obj.protocolListIndex = 1;
obj.updateProtocolList();
obj.protocolList_SelectionCallback();
end
