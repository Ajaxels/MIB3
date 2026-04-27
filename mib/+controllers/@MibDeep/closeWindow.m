function closeWindow(obj)
% function closeWindow(obj)
% callback on closing of DeepMIB window

% update preferences structure
obj.mibModel.preferences.Deep.OriginalTrainingImagesDir = obj.BatchOpt.OriginalTrainingImagesDir;
obj.mibModel.preferences.Deep.OriginalPredictionImagesDir = obj.BatchOpt.OriginalPredictionImagesDir;
obj.mibModel.preferences.Deep.ImageFilenameExtension = obj.BatchOpt.ImageFilenameExtension;
obj.mibModel.preferences.Deep.ResultingImagesDir = obj.BatchOpt.ResultingImagesDir;
obj.mibModel.preferences.Deep.CompressProcessedImages = obj.BatchOpt.CompressProcessedImages;
obj.mibModel.preferences.Deep.ValidationFraction = obj.BatchOpt.ValidationFraction{1};
obj.mibModel.preferences.Deep.MiniBatchSize = obj.BatchOpt.T_MiniBatchSize{1};
obj.mibModel.preferences.Deep.RandomGeneratorSeed = obj.BatchOpt.RandomGeneratorSeed{1};
%obj.mibModel.preferences.Deep.RelativePaths = obj.BatchOpt.RelativePaths;

obj.mibModel.preferences.Deep.TrainingOpt = obj.TrainingOpt;
obj.mibModel.preferences.Deep.AugOpt2D = obj.AugOpt2D;
obj.mibModel.preferences.Deep.AugOpt3D = obj.AugOpt3D;
obj.mibModel.preferences.Deep.InputLayerOpt = obj.InputLayerOpt;
obj.mibModel.preferences.Deep.PatchPreviewOpt = obj.PatchPreviewOpt;
obj.mibModel.preferences.Deep.ActivationLayerOpt = obj.ActivationLayerOpt;
obj.mibModel.preferences.Deep.SegmentationLayerOpt = obj.SegmentationLayerOpt;
obj.mibModel.preferences.Deep.DynamicMaskOpt = obj.DynamicMaskOpt;

obj.mibModel.preferences.Deep.SendReports = obj.SendReports;

% switch off warning for unetLayers
warning('off', 'vision:semanticseg:unetLayersDeprecation')

% close child controllers before tearing down own GUI
for i = numel(obj.childControllers):-1:1
    child = obj.childControllers{i};
    if isa(child, 'handle') && isvalid(child)
        child.closeWindow();
    end
end
obj.childControllers    = {};
obj.childControllersIds = {};

% close gpu into window if it is open
if ~isempty(obj.gpuInfoFig) && isvalid(obj.gpuInfoFig)
    delete(obj.gpuInfoFig);
end

% closing MibDeep window
if isvalid(obj.view.gui)
    delete(obj.view.gui);   % delete childController window
end

% delete listeners, otherwise they stay after deleting of the
% controller
for i=1:numel(obj.listener)
    delete(obj.listener{i});
end

notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
end

