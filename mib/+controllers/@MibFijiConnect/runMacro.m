function runMacro(obj)
% RUNMACRO - Run a Fiji/ImageJ macro command or a text file of macro commands.
%
% Reads the macro command or file path from the macro text field. If the
% value is a path to an existing text file each line is executed as a
% separate Fiji macro command. Otherwise the value is run as a single
% command. Fiji is started automatically if it is not already running.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.runMacro()
%
% Updates
%

% ensure Fiji/MIJ is running
if exist('MIJ', 'class') == 8
    if ~isempty(ij.gui.Toolbar.getInstance)
        ijInstance = char(ij.gui.Toolbar.getInstance.toString);
        if contains(ijInstance, 'invalid')  % instance exists but window was closed
            utils.fiji.Miji_wrapper(true);
        end
    else
        utils.fiji.Miji_wrapper(true);
    end
else
    utils.fiji.Miji_wrapper(true);
end

command = obj.handles.macroText.Value;
if isempty(command); return; end

if exist(command, 'file') == 2  % value is a path to a text file with macro commands
    fileId = fopen(command);
    textLine = fgetl(fileId);
    while ischar(textLine)
        runFijiCommand(textLine);
        textLine = fgetl(fileId);
    end
    fclose(fileId);
else
    runFijiCommand(command);
end
end


function runFijiCommand(command)
command = strrep(command, '"', '''');   % Fiji macros use single quotes
command = strrep(command, '/', '\\');   % normalise path separators for Fiji

if contains(command, 'run')  % command already includes the run() wrapper
    try
        eval(['MIJ.' command]);
    catch err
        disp(err);
    end
else
    if command(1) ~= ''''; command = ['''' command]; end
    if command(end) ~= ''''; command = [command '''']; end
    try
        eval(sprintf('MIJ.run(%s);', command));
    catch err
        disp(err);
    end
end
end
