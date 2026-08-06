function [pythonEnv, errorMessage] = initPythonEnv(pythonPath, executionMode)
% INITPYTHONENV - Load or reuse the Python interpreter for MIB.
%
% Syntax:
%   .. code-block:: matlab
%
%      [pythonEnv, errorMessage] = utils.initPythonEnv(pythonPath, executionMode)
%
% Wraps ``pyenv`` with handling for an already-loaded interpreter: a loaded
% interpreter cannot be reconfigured, and only OutOfProcess interpreters can
% be terminated and restarted. When the loaded interpreter matches
% ``pythonPath`` it is reused even if its execution mode differs from the
% requested one, since ``pyrun``/``py.`` calls work identically in both
% modes. When an InProcess interpreter with a different executable is
% loaded, the request cannot be satisfied and ``errorMessage`` explains
% that MATLAB must be restarted.
%
% Input Arguments:
%   - **pythonPath** - [char] full path to the Python executable
%   - **executionMode** - [char] ``'InProcess'`` or ``'OutOfProcess'``
%
% Output Arguments:
%   - **pythonEnv** - ``matlab.pyclient.PythonEnvironment`` on success;
%     ``[]`` on failure
%   - **errorMessage** - [char] empty on success; otherwise a message
%     suitable for ``utils.dlgs.showErrorDialog``
%
% Usage:
%   **Example**
%
%   .. code-block:: matlab
%
%     [obj.mibModel.pythonEnv, errorMessage] = utils.initPythonEnv( ...
%         obj.mibModel.preferences.ExternalDirs.PythonInstallationPath, 'InProcess');
%     if ~isempty(errorMessage)
%         utils.dlgs.showErrorDialog(obj.mibModel.getProgressBarParent(), errorMessage, 'Python init');
%         return;
%     end
%

pythonEnv = [];
errorMessage = '';

try
    pythonEnv = pyenv('Version', pythonPath, 'ExecutionMode', executionMode);
catch err
    if ~strcmp(err.identifier, 'MATLAB:Pyenv:PythonLoaded')
        errorMessage = err.message;
        return;
    end

    loadedEnv = pyenv;
    if strcmpi(char(loadedEnv.Executable), pythonPath)
        % the requested interpreter is already loaded - reuse it
        pythonEnv = loadedEnv;
    elseif loadedEnv.ExecutionMode == "OutOfProcess"
        terminate(loadedEnv);
        pythonEnv = pyenv('Version', pythonPath, 'ExecutionMode', executionMode);
    else
        errorMessage = sprintf(['Python is already loaded in the InProcess mode from\n%s\n\n' ...
            'and cannot be switched to\n%s\n\n' ...
            'Please restart MATLAB to change the Python interpreter'], ...
            char(loadedEnv.Executable), pythonPath);
    end
end
end
