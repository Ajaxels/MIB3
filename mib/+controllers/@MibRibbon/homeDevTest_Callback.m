function homeDevTest_Callback(obj, hWidget, hData)
% function homeDevTest_Callback(obj, hWidget, hData)
% Reserved for MIB developmental purposes

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.homeDevTest_Callback: pressed\n');
end


% find a loader that should be used for this specific dataset mode, selected reader and filename extension
% call from mibModel class
loaderInfo = obj.extensionRegistryLoad.resolveLoader(filenames{1}, obj.I{obj.id}.datasetType, reader);

% Create file loader
loader = io.LoaderFactory.create(loaderInfo, options);
% Load metadata (img_info dictionary) and populate structure array with files information (files)
[img_info, files] = loader.loadMetadata(BatchOpt.Filenames, options);

% Load images
[img, img_info] = loader.loadImages(files, img_info, options);
if isempty(img); return; end

obj.mibModel.loadImages('Combine datasets');

%obj.mibController.mibModel.clearSelection();
%obj.mibController.mibModel.clearLayer('selection');
%obj.mibController.mibModel.clearLayer('selection', '2D, Slice');
%obj.mibController.mibModel.I{obj.mibController.mibModel.id}.clearLayer('selection');
end