function mibDir = dlgResolveMibDir(mibPath)
% DLGRESOLVEMIBDIR - Resolve and cache the MIB installation folder for dialog assets.
%
% Syntax:
%   .. code-block:: matlab
%
%      mibDir = dlgResolveMibDir(mibPath)
%
% Shared by the ``+utils/+dlgs`` dialogs. The folder is detected once and cached
% in a persistent variable; passing a non-empty ``mibPath`` refreshes the cache.
%
% Input Arguments:
%   - **mibPath** - [char] explicit MIB installation path; pass ``''`` to use the cache.
%
% Output Arguments:
%   - **mibDir** - [char] resolved MIB installation folder.

persistent cachedMibDir

if nargin >= 1 && ~isempty(mibPath)
    cachedMibDir = mibPath;   % caller provided a fresh path; cache it
end
if isempty(cachedMibDir)
    if isdeployed
        [~, result] = system('path');
        toks = regexp(result, 'Path=(.*?);', 'tokens', 'once');
        if ~isempty(toks); cachedMibDir = char(toks{1}); else; cachedMibDir = pwd; end
    else
        cachedMibDir = fileparts(which('mib3'));
        if isempty(cachedMibDir); cachedMibDir = pwd; end
    end
end
mibDir = cachedMibDir;
end
