function saveProjectStructure(rootFolder, outputFile, excludeFolders)
% SAVEPROJECTSTRUCTURE - Generate a hierarchical text file listing the project folder structure.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      saveProjectStructure(rootFolder, outputFile)
%      saveProjectStructure(rootFolder, outputFile, excludeFolders)
%
% Input Arguments:
%   - **rootFolder** - [char] root directory path to scan, e.g. ``'C:\Projects\MIB'`` or ``pwd``
%   - **outputFile** - [char] output file path, e.g. ``'project_structure.txt'``
%   - **excludeFolders** *(optional)* - [cell of char] folder names to skip (default: ``{'.git', 'assets', 'external'}``).
%     Matching is case-sensitive against bare folder names.
%
% Usage:
%
%   **Example 1** - scan current directory with default exclusions
%
%   .. code-block:: matlab
%
%      utils.saveProjectStructure(pwd, 'structure.txt');
%
%   **Example 2** - scan with custom exclusions
%
%   .. code-block:: matlab
%
%      utils.saveProjectStructure(pwd, 'structure.txt', {'assets', 'docs', 'test_data'});
%
%   **Example 3** - scan MIB mib/ subfolder
%
%   .. code-block:: matlab
%
%      utils.saveProjectStructure('C:\Matlab\MIB3\mib', 'mib_structure.txt', ...
%          {'external', 'assets', 'jars', 'plugins', 'guide'});
%

    % Set default exclusions if not provided
    if nargin < 3
        excludeFolders = {'.git', 'assets', 'external'};
    end
    
    % Open output file
    fid = fopen(outputFile, 'w');
    if fid == -1
        error('Cannot open file: %s', outputFile);
    end
    
    % Write header
    fprintf(fid, 'Project Structure for: %s\n', rootFolder);
    fprintf(fid, 'Generated: %s\n', datestr(now));
    fprintf(fid, 'Excluded folders: %s\n\n', strjoin(excludeFolders, ', '));
    
    % Generate structure
    listFilesRecursive(rootFolder, fid, '', excludeFolders);
    
    % Close file
    fclose(fid);
    fprintf('Project structure saved to: %s\n', outputFile);
end

function listFilesRecursive(folder, fid, indent, excludeFolders)
    % LISTFILESRECURSIVE - Get all files and folders.
    %
    % Syntax:
    %   function listFilesRecursive(folder, fid, indent, excludeFolders)
    %
    files = dir(folder);
    
    for i = 1:length(files)
        % Skip current and parent directory
        if strcmp(files(i).name, '.') || strcmp(files(i).name, '..')
            continue;
        end
        
        % Check if folder should be excluded
        if files(i).isdir && ismember(files(i).name, excludeFolders)
            fprintf(fid, '%s%s/ [EXCLUDED]\n', indent, files(i).name);
            continue;
        end
        
        % Write file or folder name
        if files(i).isdir
            fprintf(fid, '%s%s/\n', indent, files(i).name);
            % Recurse into subdirectory
            subfolder = fullfile(folder, files(i).name);
            listFilesRecursive(subfolder, fid, [indent '  '], excludeFolders);
        else
            fprintf(fid, '%s%s\n', indent, files(i).name);
        end
    end
end
