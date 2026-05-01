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

stopTrainingSwitch =  mibDeepStopTraining;
drawnow;
end
