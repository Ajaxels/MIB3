function result = convertRelativeToAbsolutePath(relativePath, absolutePath, templateText)
% MIBGETMIBVERSIONNUMBERIC - Convert a relative path back to an absolute path,
% where ``templateText`` in the relative path is replaced with ``absolutePath``.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      result = convertRelativeToAbsolutePath(relativePath, absolutePath, templateText)
%
% Input Arguments:
%   - **relativePath** — [string] relative path containing the template, e.g.
%     ``'[RELATIVE]\..\..\dir1\subdir1'``
%   - **absolutePath** — [string] absolute base path, e.g.
%     ``'c:\myfiles\dir2\subdir2'``
%   - **templateText** — [string] placeholder to replace, e.g. ``'[RELATIVE]'``
%
% Output Arguments:
%   - **result** — [string] reconstructed absolute path
%
% Usage:
%
%   .. note::
%      The reverse operation is done using ``utils.deepmib.convertAbsoluteToRelativePath``.
%
%   **Example 1** — convert a relative path back to an absolute one
%
%   .. code-block:: matlab
%
%      relativePath = '[RELATIVE]\..\..\dir1\subdir1';
%      absolutePath = 'c:\myfiles\dir2\subdir2';
%      templateText = '[RELATIVE]';
%      result = convertRelativeToAbsolutePath(relativePath, absolutePath, templateText);
%      % result = 'c:\myfiles\dir1\subdir1'
%

parentDirsIndices = strfind(relativePath, '..');  % get number of times the parent directory needs to be called
parentDirsNo = numel(parentDirsIndices);  % get number of times the parent directory needs to be called
if parentDirsNo == 0
    result = strrep(relativePath, templateText, absolutePath);
else
    for dirIndex = 1:parentDirsNo
        absolutePath = fileparts(absolutePath);
    end
    result = fullfile(absolutePath, relativePath(parentDirsIndices+3:end));
end

% fix double slashes
result = strrep(result, '\\', '\');
result = strrep(result, '//', '/');

end
