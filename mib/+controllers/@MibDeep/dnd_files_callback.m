function dnd_files_callback(obj, hWidget, dragIn)
    % function dnd_files_callback(obj, hWidget, dragIn)
    % drag and drop config name to obj.view.handles.NetworkPanel to
    % load it
    %
    % Parameters:
    % hWidget: a handle to the object where the drag action landed
    % dragIn: a structure containing the dragged object
    % .ctrlKey - 0/1 whether the control key was pressed
    % .shiftKey - 0/1 whether the control key was pressed
    % .names - cell array with filenames

    fullFilenameIn = dragIn.names{1};
    % fix the slash characters
    %fullFilenameIn = strrep(fullFilenameIn, '/', filesep);
    %fullFilenameIn = strrep(fullFilenameIn, '\', filesep);

    [pathIn, fnIn, extIn] = fileparts(fullFilenameIn);
    switch extIn
        case '.mibCfg'
            obj.loadConfig(fullFilenameIn);
        case '.mibDeep'

    end
end

