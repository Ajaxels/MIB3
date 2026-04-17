% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% Date: 25.04.2023
% License: BSD-3 clause (https://opensource.org/license/bsd-3-clause/)

function stopTrainingSwitch = stopTrainingWithoutPlots(progressStruct)
% function stopTrainingSwitch = stopTrainingWithoutPlots(progressStruct)
% stop training, when it is done without the training plot

global mibDeepStopTraining

stopTrainingSwitch =  mibDeepStopTraining;
drawnow;
end