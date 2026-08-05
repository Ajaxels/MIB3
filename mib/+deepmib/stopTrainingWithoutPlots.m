function stopTrainingSwitch = stopTrainingWithoutPlots(progressStruct)
% STOPTRAININGWITHOUTPLOTS - Stop training when running without a training plot.
%
% Syntax:
%   .. code-block:: matlab
%
%      stopTrainingSwitch = stopTrainingWithoutPlots(progressStruct)
%
% Input Arguments:
%   - **progressStruct** — training progress struct (unused; required by ``trainNetwork`` callback signature)
%
% Output Arguments:
%   - **stopTrainingSwitch** — [logical] ``true`` when the global ``mibDeepStopTraining`` flag is set
%

global mibDeepStopTraining
global mibDeepTrainingProgressStruct

stopTrainingSwitch =  mibDeepStopTraining;

% The dltrain-based trainer behind trainSOLOV2 ('2D Instance') only leaves the inner
% per-epoch loop when asked to stop; its outer "for epoch = 1:MaxEpochs" loop still runs to
% the end, re-saving a checkpoint on every idle epoch. See deepmib.suspendCheckpointSaving.
% The Emergency brake is raised from deepmib.readInstancePatch, not here: this function is
% called from a notify() listener, and notify() downgrades listener errors to warnings.
if stopTrainingSwitch && isfield(mibDeepTrainingProgressStruct, 'dltrainBasedTrainer') && ...
        mibDeepTrainingProgressStruct.dltrainBasedTrainer
    % from here on every read is a throwaway prefetch, see deepmib.readInstancePatch
    mibDeepTrainingProgressStruct.spinDownActive = true;
    deepmib.suspendCheckpointSaving('suspend');
end

drawnow;
end
