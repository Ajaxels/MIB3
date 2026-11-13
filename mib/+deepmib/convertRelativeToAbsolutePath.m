function result = convertRelativeToAbsolutePath(relativePath, absolutePath, templateText)
% CONVERTRELATIVETOABSOLUTEPATH - Convert a relative path back to an absolute path,
% where ``templateText`` in the relative path is replaced with ``absolutePath``.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = convertRelativeToAbsolutePath(relativePath, absolutePath, templateText)
%
% Input Arguments:
%   - **relativePath** - [string] relative path starting with the template, e.g.
%     ``'[RELATIVE]\..\..\dir1\subdir1'``. Each leading ``..`` segment moves one
%     directory up from ``absolutePath``; any number of them is accepted. A path
%     that does not start with the template (an absolute path, e.g. one on another
%     drive, see ``deepmib.convertAbsoluteToRelativePath``) is returned unchanged
%   - **absolutePath** - [string] absolute base path, e.g.
%     ``'c:\myfiles\dir2\subdir2'``
%   - **templateText** - [string] placeholder to replace, e.g. ``'[RELATIVE]'``
%
% Output Arguments:
%   - **result** - [string] reconstructed absolute path
%
% Usage:
%
%   .. note::
%      The reverse operation is done using ``deepmib.convertAbsoluteToRelativePath``.
%
%   **Example 1** - convert a relative path back to an absolute one
%
%   .. code-block:: matlab
%
%      relativePath = '[RELATIVE]\..\..\dir1\subdir1';
%      absolutePath = 'c:\myfiles\dir2\subdir2';
%      templateText = '[RELATIVE]';
%      result = convertRelativeToAbsolutePath(relativePath, absolutePath, templateText);
%      % result = 'c:\myfiles\dir1\subdir1'
%

if ~startsWith(relativePath, templateText)
    result = relativePath;  % an absolute path, nothing to restore
    return;
end

remainder = regexprep(relativePath(numel(templateText)+1:end), '^[\\/]+', '');
% leading parent-directory segments; ".." inside a folder name (e.g. "a..b") is not one
parentSteps = regexp(remainder, '^(\.\.([\\/]+|$))+', 'match', 'once');
parentDirsNo = numel(strfind(parentSteps, '..'));
for dirIndex = 1:parentDirsNo
    absolutePath = fileparts(absolutePath);
end
% fullfile removes duplicated separators and keeps the leading \\ of a UNC path
result = fullfile(absolutePath, remainder(numel(parentSteps)+1:end));

end
