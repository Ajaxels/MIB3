function dirOut = obtainDirectoryForAction(obj, dirModeField, filenameField, stepId, stepOptions)
% OBTAINDIRECTORYFORACTION - resolve and return an output directory for a single protocol step.
%
% Syntax:
%   .. code-block:: matlab
%
%       dirOut = obj.obtainDirectoryForAction(dirModeField, filenameField, stepId, stepOptions)
%
% Evaluates the directory-mode field of the step's BatchOpt and returns the
% corresponding absolute path.  If the directory does not yet exist it is
% created (except for the 'Inherit from Directory loop' modes).  Returns an
% empty array on error so that the caller can abort cleanly.
%
% Supported directory modes (value of *dirModeField):*
%   - 'Absolute'                    - use the path stored in *filenameField* verbatim
%   - 'Relative to current MIB path'- append *filenameField* to obj.mibModel.currentDirectory; leading "../" sequences navigate up the tree
%   - 'Inherit from Directory loop' - take stepOptions.DirectoryName from the enclosing directory loop
%   - 'Inherit dirs +Dirname'       - concatenate stepOptions.DirectoryName with obj.Protocol(stepId).Batch.DirectoryName
%
% Input Arguments:
%   - **dirModeField** - name of a BatchOpt field whose value selects the directory mode
%   - **filenameField** - name of a BatchOpt field that holds the actual directory path string
%   - **stepId** - index of the protocol step being executed
%   - **stepOptions** - a struct passed down from the loop runner; may contain:
%     - .DirectoryName - directory provided by an enclosing Directory loop
%
% Output Arguments:
%   - **dirOut** - resolved absolute directory path, or [] on failure
%
% Usage:
%   Example 1::
%
%     dirOut = obj.obtainDirectoryForAction('Mode', 'DirectoryName', stepId, stepOptions);
%
%   Example 2::
%
%     sourceDir = obj.obtainDirectoryForAction('CurrentDirectoryMode', 'CurrentDirectory', stepId, stepOptions);
%

warning('off', 'MATLAB:MKDIR:DirectoryExists'); % disable warning of existing directories

dirOut = [];
switch obj.Protocol(stepId).Batch.(dirModeField){1}
    case 'Absolute'
        if ~isfolder(obj.Protocol(stepId).Batch.(filenameField))
            try
                mkdir(obj.Protocol(stepId).Batch.(filenameField));
            catch err
                errOpts.MsgBoxOnly = true; errOpts.Icon = 'puffin_error';
                header = sprintf('%s\n\n%s', err.identifier, err.message);
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Problem with directory', errOpts);
                warning('on', 'MATLAB:MKDIR:DirectoryExists'); % enable warning of existing directories
                return;
            end
        end
        dirOut = obj.Protocol(stepId).Batch.DirectoryName;
    case 'Relative to current MIB path'
        % search for ".."
        pos = strfind(obj.Protocol(stepId).Batch.(filenameField), '..');
        if ~isempty(pos)
            cPath = obj.mibModel.currentDirectory;
            for i=1:numel(pos)
                cPath = fileparts(cPath);
            end
            dirOut = obj.Protocol(stepId).Batch.(filenameField)(pos(end)+3:end);
            dirOut = fullfile(cPath, dirOut);
            if ~isfolder(dirOut)
                try
                    mkdir(dirOut);
                catch err
                    errOpts.MsgBoxOnly = true; errOpts.Icon = 'puffin_error';
                header = sprintf('%s\n\n%s', err.identifier, err.message);
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Problem with directory', errOpts);
                    warning('on', 'MATLAB:MKDIR:DirectoryExists'); % enable warning of existing directories
                    return;
                end
            end
        else
            dirOut = fullfile(obj.mibModel.currentDirectory, obj.Protocol(stepId).Batch.(filenameField));
            if ~isfolder(dirOut); mkdir(dirOut); end    % create a new folder if needed
        end
    case 'Inherit from Directory loop'
        if ~isfield(stepOptions, 'DirectoryName')
            errOpts.MsgBoxOnly = true; errOpts.Icon = 'puffin_error';
            header = 'Wrong settings: Inherit from Directory loop parameter requires Directory loop before this action!';
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'ObtainDirectoryForAction error', errOpts);
            warning('on', 'MATLAB:MKDIR:DirectoryExists'); % enable warning of existing directories
            return;
        end
        dirOut = stepOptions.DirectoryName;
    case 'Inherit dirs +Dirname'    % get directory from the loop and add subfolder
        if ~isfield(stepOptions, 'DirectoryName')
            errOpts.MsgBoxOnly = true; errOpts.Icon = 'puffin_error';
            header = 'Wrong settings: Inherit from Directory loop parameter requires Directory loop before this action!';
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'ObtainDirectoryForAction error', errOpts);
            warning('on', 'MATLAB:MKDIR:DirectoryExists'); % enable warning of existing directories
            return;
        end
        dirOut = fullfile(stepOptions.DirectoryName, obj.Protocol(stepId).Batch.DirectoryName);
end
warning('on', 'MATLAB:MKDIR:DirectoryExists');
end
