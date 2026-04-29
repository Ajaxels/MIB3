function evaluateSegmentationPatches(obj)
% EVALUATESEGMENTATIONPATCHES - evaluate segmentation results for the patches in the.
%
% Syntax:
%   function evaluateSegmentationPatches(obj)
%
% patch-wise mode

filename = fullfile(obj.BatchOpt.ResultingImagesDir, 'PredictionImages', 'ResultsModels', 'patchPredictionResults.mat');
load(filename, 'patchWiseOutout', '-mat');

C = confusionmat(patchWiseOutout.RealClass, patchWiseOutout.PredictedClass);
figure(randi(1000))
confusionchart(C, strsplit(patchWiseOutout.ClassNames{1}, ', '));
[~, fn, ext] = fileparts(obj.BatchOpt.NetworkFilename);
title(sprintf('%s %s, %s', obj.BatchOpt.Workflow{1}, obj.BatchOpt.Architecture{1}, [fn, ext]));
end

