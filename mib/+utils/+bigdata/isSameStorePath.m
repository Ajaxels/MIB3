function same = isSameStorePath(firstPath, secondPath)
% ISSAMESTOREPATH - True when two paths name the same store folder.
%
% Syntax:
%   .. code-block:: matlab
%
%       same = utils.bigdata.isSameStorePath(firstPath, secondPath)
%
% Compares the absolute paths without a trailing separator, case-insensitively
% (Windows folders), so ``C:\data\a.zarr3\`` and ``c:/data/a.zarr3`` are the same
% store. Used to refuse an output store that would overwrite an open one: the
% source image of ``utils.bigdata.processImageToStore`` or any store open in MIB
% (``controllers.BigDataOptions``). An empty path is never the same as another.
%
% Input Arguments:
%   - **firstPath**, **secondPath** - [char|string] folder paths, absolute or relative
%
% Output Arguments:
%   - **same** - [logical]

% Updates
%

same = false;
if isempty(firstPath) || isempty(secondPath) || strlength(firstPath) == 0 || strlength(secondPath) == 0
    return;
end
same = strcmpi(localNormalize(firstPath), localNormalize(secondPath));
end

function normalized = localNormalize(pathText)
% LOCALNORMALIZE - Absolute path with one kind of separator and no trailing one.
normalized = char(java.io.File(char(pathText)).getAbsolutePath());
normalized = regexprep(normalized, '[\\/]+', '/');
normalized = regexprep(normalized, '/$', '');
end
