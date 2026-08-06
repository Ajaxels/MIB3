function status = terminatePythonEnv()
% TERMINATEPYTHONENV - Safely terminate the loaded Python interpreter.
%
% Syntax:
%   .. code-block:: matlab
%
%      status = utils.terminatePythonEnv()
%
% ``terminate(pyenv)`` is only supported for the OutOfProcess execution
% mode. SAM/SAM2 load Python InProcess (see
% ``controllers.MibImageDocument.segmentationSAM2`` for the reason), where
% the interpreter lives inside the MATLAB process and cannot be unloaded
% until MATLAB restarts. Calling ``terminate`` on it throws
% "Termination not supported for InProcess execution mode".
%
% Output Arguments:
%   - **status** - [logical] **true** when no Python interpreter remains
%     loaded after the call (it was terminated or was never loaded);
%     **false** when an InProcess interpreter is loaded and stays loaded
%
% Usage:
%   **Example**
%
%   .. code-block:: matlab
%
%     utils.terminatePythonEnv();          % instead of terminate(pyenv)
%     obj.mibModel.pythonEnv = [];
%

pythonEnv = pyenv;
status = true;
if pythonEnv.Status ~= "Loaded"; return; end

if pythonEnv.ExecutionMode == "OutOfProcess"
    terminate(pythonEnv);
else
    status = false;     % InProcess interpreter stays until MATLAB restarts
end
end
