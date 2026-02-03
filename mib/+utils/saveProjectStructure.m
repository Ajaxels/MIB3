function saveProjectStructure(rootFolder, outputFile, excludeFolders)
% SAVEPROJECTSTRUCTURE Generate a hierarchical text file of project structure
%
% Syntax:
%   saveProjectStructure(rootFolder, outputFile)
%   saveProjectStructure(rootFolder, outputFile, excludeFolders)
%
% Parameters:
%   rootFolder - String or char array specifying the root directory path
%                Example: 'C:\Projects\MIB' or pwd
%
%   outputFile - String or char array specifying output file path
%                Example: 'project_structure.txt'
%
%   excludeFolders - Cell array of folder names to exclude from listing
%                    (Optional, default: {'.git', 'assets', 'external'})
%                    Example: {'assets', 'external', 'temp', 'bin'}
%                    Note: Folder names are case-sensitive
%
% Examples:
%   % Basic usage - uses default exclusions
%   utils.saveProjectStructure(pwd, 'structure.txt');
%
%   % Custom exclusions
%   utils.saveProjectStructure(pwd, 'structure.txt', {'assets', 'docs', 'test_data'});
%
%   % No exclusions (empty cell array)
%   utils.saveProjectStructure(pwd, 'structure.txt', {});
%
%   % Specific project path
%   utils.saveProjectStructure('C:\Matlab\MIB3\mib', 'mib_structure.txt', {'external', 'assets', 'jars', 'plugins','guide'});

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
    % Get all files and folders
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
