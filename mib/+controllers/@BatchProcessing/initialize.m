function initialize(obj)
% INITIALIZE - build the obj.Sections catalogue of all available batch actions.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.initialize()
%
% Populates obj.Sections as a struct array where each element represents one section visible in the section dropdown:
%   - Sections(id).Name              - display name shown in selectProtocolSection
%   - Sections(id).Actions(id2).Name - action name shown in selectProtocolAction
%   - Sections(id).Actions(id2).Command - MATLAB expression evaluated by doBatchStep; the variable *Batch* is the BatchOpt struct
%
% Called once from the constructor before the view is created so that
% the section popup can be populated immediately.
%
% Currently defined sections (14 total):
%   - 'Menu Home'             - load/save, loops, directory/file ops
%   - 'Menu Dataset'          - alignment, crop, resample, transform, etc.
%   - 'Menu Image'            - intensity, colour, mode, morphology
%   - 'Menu Models'           - model management
%   - 'Menu Mask'             - mask management
%   - 'Menu Selection'        - selection operations
%   - 'Menu Plugins'          - plugins
%   - 'Segmentation panel'       - segmentation tools
%   - 'Semi-automatic segmentation' - thresholding, watershed, region-growing
%   - 'Menu Tools'            - rendering, stitch, drift correction, etc.
%   - 'Annotations'              - annotation tools
%   - 'Lines 3D'                 - 3D skeleton tools
%   - 'DeepMIB'                  - deep learning
%   - 'Service steps'            - STOP EXECUTION
%
% Usage:
%   Example 1::
%
%     obj.initialize();
%
secIndex = 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Ribbon -> Home';
obj.Sections(secIndex).Actions(actionId).Name = 'Load and combine images';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.loadImages([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Example datasets';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cRibbon.homeExamples_Callback(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Import image from MATLAB';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.importDataset("image", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Export image to MATLAB';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.exportDataset("image", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Export image to Imaris';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.exportDatasetToImaris("image", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Make snapshot';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.Snapshot'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Save dataset';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.saveImage("image", [], Batch);'; actionId = actionId + 1;

obj.Sections(secIndex).Actions(actionId).Name = 'Chunk dataset...';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.ChunkingExport'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Stitch chunked datasets...';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.ChunkingImport'', [], Batch);'; actionId = actionId + 1;


obj.Sections(secIndex).Actions(actionId).Name = 'DIRECTORY LOOP START';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.directoryLoopAction_Callback(Batch)'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'DIRECTORY LOOP STOP';
obj.Sections(secIndex).Actions(actionId).Command = []; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'FILE LOOP START';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.fileLoopAction_Callback(Batch)'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'FILE LOOP STOP';
obj.Sections(secIndex).Actions(actionId).Command = []; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Directory operations';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.directoryOperationsAction_Callback(Batch)'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'File operations';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.fileOperationsAction_Callback(Batch)'; actionId = actionId + 1;

secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Ribbon -> Dataset';
obj.Sections(secIndex).Actions(actionId).Name = 'Alignment / Drift correction...';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.Alignment'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Crop dataset';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.CropDataset'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Resample...';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.ResampleDataset'', [], Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Transform...';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuDatasetTrasform_Callback([], Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Transform... --> Add frame (width/height)';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuDatasetTrasform_Callback(''Add frame (width/height)'', Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Transform... --> Add frame (dX/dY)';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuDatasetTrasform_Callback(''Add frame (dX/dY)'', Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Slice -> Copy slice';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.copySwapSlice([], [], ''replace'', Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Slice -> Delete slice/frame';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.deleteSlice([], [], Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Slice -> Insert an empty slice';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.insertEmptySlice(Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Slice -> Stride reslicing';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.resliceDataset([], [], Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Slice -> Swap slices';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.copySwapSlice([], [], ''swap'', Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Bounding Box';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.BoundingBox'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Voxels';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cRibbon.updateVoxelSizes([], Batch);'; actionId = actionId + 1;

secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Ribbon -> Image';
% obj.Sections(secIndex).Actions(actionId).Name = 'Mode';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuImageMode_Callback([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Adjust Display/Image';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.DisplayAdjust'', [], Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Color channel actions';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.colorChannelActions([], [], [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Contrast -> Contrast-limited adaptive histogram equalization';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.contrastCLAHE(''Current stack (3D)'', Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Contrast -> Normalize layers';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.ContrastNormalization'', [], Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Invert image';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuImageInvert_Callback([], Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Image filters';
%obj.Sections(secIndex).Actions(actionId).Command = ''; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Tools for Images -> Content-aware fill';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.contentAwareFill(Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Tools for Images -> Debris removal';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''mibDebrisRemovalController'', [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Tools for Images -> Image Arithmetics';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''mibImageArithmeticController'', [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Tools for Images -> Intensity projection';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuImageToolsProjection_Callback(Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Tools for Images -> Select Image Frame';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''mibImageSelectFrameController'', [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Tools for Images -> White balance correction';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''mibWhiteBalanceController'', [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Morphological operations';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''mibImageMorphOpsController'', [], Batch);'; actionId = actionId + 1;

secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Ribbon -> Model';
obj.Sections(secIndex).Actions(actionId).Name = 'Model to Mask';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.moveLayers(''labels'', ''mask'', [], [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Model to Selection';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.moveLayers(''labels'', ''selection'', [], [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Convert type';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.convertModel([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'New model';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.createModel([], [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Load model';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.loadModel([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Import model from MATLAB';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.importDataset("model", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Import model from MIB container';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.importDatasetFromMib("model", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Export model to MATLAB';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.exportDataset("model", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Export model to MIB container';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.exportDatasetToMib("model", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Export model to Imaris';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.exportDatasetToImaris("model", Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Export model or material';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.modelExport(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Save model';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.saveLabels([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Material actions';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.materialsActions([], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Material actions';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.materialsActions([], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Materials color swap';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.materialsSwapColors(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Interpolate material';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.interpolateImage(''labels'', [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Smooth model';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.smoothImage(''labels'', Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Quantification';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.Quantification'', [], Batch);'; actionId = actionId + 1;

secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Ribbon -> Mask';
obj.Sections(secIndex).Actions(actionId).Name = 'Mask to Model';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.moveLayers(''mask'', ''labels'', [], [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Mask to Selection';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.moveLayers(''mask'', ''selection'', [], [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Clear mask';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.clearMask(Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Load mask';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.loadMask([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Import mask from MATLAB';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.importDataset("mask", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Import mask from MIB container';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.importDatasetFromMib("mask", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Export mask to MATLAB';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.exportDataset("mask", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Export mask to MIB container';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.exportDatasetToMib("mask", Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Export mask to Imaris';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.exportDatasetToImaris("mask", Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Save mask';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.saveMask([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Interpolate mask';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.interpolateImage(''mask'', [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Invert mask';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuMaskInvert_Callback(''mask'', Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Replace masked area in the image';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuMaskImageReplace_Callback(''mask'', Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Smooth mask';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.smoothImage(''mask'', Batch)'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Fill mask';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.fillSelectionOrMask(''mask'', Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Quantification';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''controllers.Quantification'', -1, Batch);'; actionId = actionId + 1;


secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Ribbon -> Selection';
% obj.Sections(secIndex).Actions(actionId).Name = 'Selection to Model';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.mibModel.moveLayers(''selection'', ''labels'', [], [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Selection to Mask';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.mibModel.moveLayers(''selection'', ''mask'', [], [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Interpolate selection';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.interpolateImage(''selection'', [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Replace selected area in the image';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuMaskImageReplace_Callback(''selection'', Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Smooth selection';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.smoothImage(''selection'', Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Invert selection';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.menuMaskInvert_Callback(''selection'', Batch);'; actionId = actionId + 1;

% secIndex = secIndex + 1;
% actionId = 1;
% obj.Sections(secIndex).Name = 'Ribbon -> Tools';
% obj.Sections(secIndex).Actions(actionId).Name = 'Semi-automatic segmentation --> Global thresholding';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''mibHistThresController'', [], Batch);'; actionId = actionId + 1;

secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Ribbon -> Plugins';
obj.Sections(secIndex).Actions(actionId).Name = 'Convert image files';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''ImageConverter'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Demo Plugin';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''DemoPlugin'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'GuiTutorial Batch';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''GuiTutorialBatch'', [], Batch);'; actionId = actionId + 1;

% obj.Sections(secIndex).Actions(actionId).Name = 'Demo Plugin GUIDE Batch';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''DemoPluginGuideBatchController'', [], Batch);'; actionId = actionId + 1;

secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Quick access bar';
obj.Sections(secIndex).Actions(actionId).Name = 'Change magnification';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cStatus.zoomEdit_Callback([], Batch);'; actionId = actionId + 1;


secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Panel -> Datasets';
% obj.Sections(secIndex).Actions(actionId).Name = 'Change container';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.mibBufferToggle_Callback([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Duplicate dataset';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cActiveDataset.buffers_ContextMenu(''duplicate'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Close dataset';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cActiveDataset.buffers_ContextMenu(''close'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Close all datasets in set';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cActiveDataset.buffers_ContextMenu(''closeSet'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Sync views';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cActiveDataset.buffers_ContextMenu(''sync_xy'', [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Link views';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cActiveDataset.buffers_ContextMenu(''link_views'', [], Batch);'; actionId = actionId + 1;

secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Panel -> Segmentation';
% obj.Sections(secIndex).Actions(actionId).Name = 'Modify parameters';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.mibSegmentationPanelCheckboxes(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Add material';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.addMaterial(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'New model';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.createModel([], [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Rename material';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.renameMaterial(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Remove material';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.removeMaterial(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = '3D ball';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentationBall3D([], [], [], [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Black and white thresholding';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentBlackWhiteThreshold(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Drag & Drop materials';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.gui_WindowButtonUpDragAndDropFcn([], [], [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Lasso manual selection';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentationLassoManual(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Magic Wand';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentationMagicWand([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Region Growing';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentationRegionGrowing([], Batch);'; actionId = actionId + 1;

% obj.Sections(secIndex).Actions(actionId).Name = 'Segment-anything model';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.mibSegmentationSAM([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Spot';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.segmentationSpot([], [], [], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Material actions';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.materialsActions([], Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Materials color swap';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.materialsSwapColors(Batch);'; actionId = actionId + 1;


secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Panel -> Image view';
obj.Sections(secIndex).Actions(actionId).Name = 'Change slice number';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.updateSliceNumber(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Change frame/time number';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.updateFrameNumber(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Change magnification';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cStatus.zoomEdit_Callback([], Batch);'; actionId = actionId + 1;
%obj.Sections(secIndex).Actions(actionId).Name = 'Recenter the view';
%obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.mibPixelInfo_Callback([], Batch);'; actionId = actionId + 1;

% secIndex = secIndex + 1;
% actionId = 1;
% obj.Sections(secIndex).Name = 'Panel -> View settings';
% % obj.Sections(secIndex).Actions(actionId).Name = 'Modify parameters';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.mibViewSettingsPanelCheckboxes(Batch);'; actionId = actionId + 1;
% obj.Sections(secIndex).Actions(actionId).Name = 'Display';
% obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''mibImageAdjController'', [], Batch);'; actionId = actionId + 1;

secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Panel -> Selection and View Settings';
obj.Sections(secIndex).Actions(actionId).Name = 'Clear selection';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.clearSelection([], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Modify parameters';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.cSelection.selectionPanelCheckboxes(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Erode';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.erodeImage(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Dilate';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.dilateImage(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Clear layer';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.clearLayer([], [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Fill selection';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.fillSelectionOrMask(''selection'', Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Selection to Mask';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.moveLayers(''selection'', ''mask'', [], [], Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'Selection to Model';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibModel.moveLayers(''selection'', ''labels'', [], [], Batch);'; actionId = actionId + 1;

% secIndex = secIndex + 1;
% obj.Sections(secIndex).Name = 'Panel -> Image filters';
% FiltersList = {'Average', 'Disk', 'DistanceMap', 'Entropy', 'Frangi', 'Gaussian', 'Gradient', 'LoG', 'MathOps', 'Mode', 'Motion','Prewitt','Range', 'SaltAndPepper','Sobel','Std',...
%     'AnisotropicDiffusion', 'Bilateral', 'DNNdenoise', 'Median', 'NonLocalMeans', 'Wiener',...
%     'AddNoise', 'FastLocalLaplacian', 'FlatfieldCorrection', 'LocalBrighten', 'LocalContrast', 'ReduceHaze', 'UnsharpMask',...
%     'Edge', 'SlicClustering', 'WatershedClustering'};
% % add BMxD filter if available
% if ~isempty(obj.mibModel.preferences.ExternalDirs.bm3dInstallationPath)
%     if exist(fullfile(obj.mibModel.preferences.ExternalDirs.bm3dInstallationPath, 'BM3D.m'), 'file') == 2
%         FiltersList{end+1} = 'BMxD';
%     end
% end
% FiltersList = sort(FiltersList);
% % for actionId = 1:numel(FiltersList)
% %     obj.Sections(secIndex).Actions(actionId).Name = FiltersList{actionId};
% %     obj.Sections(secIndex).Actions(actionId).Command = sprintf('obj.mibController.startController(''mibImageFiltersController'', ''%s'', Batch);', FiltersList{actionId});
% % end

secIndex = secIndex + 1;
actionId = 1;
obj.Sections(secIndex).Name = 'Service steps';
obj.Sections(secIndex).Actions(actionId).Name = 'STOP EXECUTION';
obj.Sections(secIndex).Actions(actionId).Command = []; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'DIRECTORY LOOP START';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.directoryLoopAction_Callback(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'DIRECTORY LOOP STOP';
obj.Sections(secIndex).Actions(actionId).Command = []; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'FILE LOOP START';
obj.Sections(secIndex).Actions(actionId).Command = 'obj.fileLoopAction_Callback(Batch);'; actionId = actionId + 1;
obj.Sections(secIndex).Actions(actionId).Name = 'FILE LOOP STOP';
obj.Sections(secIndex).Actions(actionId).Command = []; actionId = actionId + 1;
end
