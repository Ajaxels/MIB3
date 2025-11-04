function buildHomeTab(obj)
% function buildHomeTab(obj)
% build the Home tab group (obj.handles.toolbar.home)
% and add it to obj.handles.toolbar.global 
arguments (Input)
    obj views.MibView
end

obj.handles.toolbar.home = matlab.ui.internal.toolstrip.Tab("Home");

%% ============= Make "Import" section =============
section = obj.handles.toolbar.home.addSection("Import image");

% --------- Open ---------
column = section.addColumn();
obj.handles.home.loadFile =  matlab.ui.internal.toolstrip.SplitButton("Open", matlab.ui.internal.toolstrip.Icon.OPEN_24);
obj.handles.home.loadFile.Description = "Import datasets to MIB";
obj.handles.home.loadFile.ButtonPushedFcn  = @(varargin)disp('Open dataset pressed');

% make a popup list for the dropdown button
popupList = matlab.ui.internal.toolstrip.PopupList();
% add header
header = matlab.ui.internal.toolstrip.PopupListHeader('Recent directories');
popupList.add(header);
obj.handles.home.loadFile.Popup = popupList;

% add the dropdown button to the column
column.add(obj.handles.home.loadFile);

% --------- Import ---------
column = section.addColumn();

% IMPORT split button
obj.handles.home.import =  matlab.ui.internal.toolstrip.SplitButton("Import", matlab.ui.internal.toolstrip.Icon.IMPORT_24);
obj.handles.home.import.Description = "Import datasets to MIB";
obj.handles.home.import.ButtonPushedFcn  = @(varargin)disp('Import from Matlab pressed');

% make a popup list for the dropdown button
popupList = matlab.ui.internal.toolstrip.PopupList();
% add header
header1 = matlab.ui.internal.toolstrip.PopupListHeader('Import dataset from');
popupList.add(header1);
% import from MATLAB
obj.handles.home.importFromMatlab = matlab.ui.internal.toolstrip.ListItem('MATLAB', matlab.ui.internal.toolstrip.Icon.MATLAB_24);
obj.handles.home.importFromMatlab.Description = 'Import dataset from MATLAB';
obj.handles.home.importFromMatlab.ItemPushedFcn  = @(varargin)disp('Import dataset from Matlab pressed');
popupList.add(obj.handles.home.importFromMatlab);
% import from clipboard
obj.handles.home.importFromClipboard = matlab.ui.internal.toolstrip.ListItem('System Clipboard', matlab.ui.internal.toolstrip.Icon.PASTE_24);
obj.handles.home.importFromClipboard.Description = 'Import from system clipboard';
obj.handles.home.importFromClipboard.ItemPushedFcn  = @(varargin)disp('Import from Clipboard pressed');
popupList.add(obj.handles.home.importFromClipboard);
% import from Imaris
obj.handles.home.importFromImaris = matlab.ui.internal.toolstrip.ListItem('Imaris', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/imaris_24px.png')));
obj.handles.home.importFromImaris.Description = 'Import from Imaris';
obj.handles.home.importFromImaris.ItemPushedFcn  = @(varargin)disp('Import from Imaris pressed');
popupList.add(obj.handles.home.importFromImaris);
% import from OMERO
obj.handles.home.importFromOmero = matlab.ui.internal.toolstrip.ListItem('Omero', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/omero_24px.png')));
obj.handles.home.importFromOmero.Description = 'Import dataset from OMERO';
obj.handles.home.importFromOmero.ItemPushedFcn  = @(varargin)disp('Import from importFromOmero pressed');
popupList.add(obj.handles.home.importFromOmero);
% import from URL
obj.handles.home.importFromURL = matlab.ui.internal.toolstrip.ListItem('URL', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/internet_24px.png')));
obj.handles.home.importFromURL.Description = 'Import dataset from URL';
obj.handles.home.importFromURL.ItemPushedFcn  = @(varargin)disp('Import from URL pressed');
popupList.add(obj.handles.home.importFromURL);

% add the popup list to the SplitButton button
obj.handles.home.import.Popup = popupList;

% add the dropdown button to the column
column.add(obj.handles.home.import);

% --------- EXAMPLES split button ---------
column = section.addColumn('Width', 70);
% generate menu
popup = matlab.ui.internal.toolstrip.GalleryPopup('GalleryItemTextLineCount', 2, 'GalleryItemRowCount', 1, ...
    'IconSize', 24, 'DisplayState', 'icon_view');  % list_view/icon_view; IconSize: 16(x16), 24(x24), 40(x50)

% DeepMIB projects
category = matlab.ui.internal.toolstrip.GalleryCategory('DeepMIB projects');
% 2D large spots synthetic (62 Mb)
obj.handles.home.deepmib2dLargeSpots = matlab.ui.internal.toolstrip.GalleryItem('2D large spots synthetic (62 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/large_spots_24px.png')));
obj.handles.home.deepmib2dLargeSpots.Description = 'DeepLabV3-Resnet18 network for detecting large spots on a black background';
obj.handles.home.deepmib2dLargeSpots.ItemPushedFcn = @(varargin)disp('obj.handles.home.deepmib2dLargeSpots pressed');
category.add(obj.handles.home.deepmib2dLargeSpots);
% 2D small spots synthetic (8 Mb)
obj.handles.home.deepmib2dSmallSpots = matlab.ui.internal.toolstrip.GalleryItem('2D small spots synthetic (8 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/small_spots_24px.png')));
obj.handles.home.deepmib2dSmallSpots.Description = 'U-net network for detecting small random spots of two colors on a black background';
obj.handles.home.deepmib2dSmallSpots.ItemPushedFcn = @(varargin)disp('obj.handles.home.deepmib2dSmallSpots pressed');
category.add(obj.handles.home.deepmib2dSmallSpots);
% 2.5D large spots synthetic (121 Mb)
obj.handles.home.deepmib25dLargeSpots = matlab.ui.internal.toolstrip.GalleryItem('2.5D large spots synthetic (121 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/large_spots_3d_24px.png')));
obj.handles.home.deepmib25dLargeSpots.Description = '2.5D DeepLabV3-Resnet18 and U-net networks for segmenting large 3D spots (ignoring 2D spots)';
obj.handles.home.deepmib25dLargeSpots.ItemPushedFcn = @(varargin)disp('obj.handles.home.deepmib25dLargeSpots pressed');
category.add(obj.handles.home.deepmib25dLargeSpots);
% 2D patch-wise synthetic (42 Mb)
obj.handles.home.deepmib2dPatchWise = matlab.ui.internal.toolstrip.GalleryItem('2D patch-wise synthetic (42 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/patch-wise_24px.png')));
obj.handles.home.deepmib2dPatchWise.Description = 'Resnet18 network for detecting patches of large white spots on a black background';
obj.handles.home.deepmib2dPatchWise.ItemPushedFcn = @(varargin)disp('obj.handles.home.deepmib2dPatchWise pressed');
category.add(obj.handles.home.deepmib2dPatchWise);
% separator
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);
% 2D EM Membranes (219 Mb)
obj.handles.home.deepmib2dMembranesEM = matlab.ui.internal.toolstrip.GalleryItem('2D EM Membranes (219 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_membranes_24px.png')));
obj.handles.home.deepmib2dMembranesEM.Description = 'Segmentation of membranes from serial-section TEM images';
obj.handles.home.deepmib2dMembranesEM.ItemPushedFcn = @(varargin)disp('obj.handles.home.deepmib2dMembranesEM pressed');
category.add(obj.handles.home.deepmib2dMembranesEM);
% 2D LM Nuclei (174 Mb)
obj.handles.home.deepmib2dNucleiLM = matlab.ui.internal.toolstrip.GalleryItem('2D LM Nuclei (174 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_nuclei_24px.png')));
obj.handles.home.deepmib2dNucleiLM.Description = 'Segmentation of nuclei, boundaries, and touching edges';
obj.handles.home.deepmib2dNucleiLM.ItemPushedFcn = @(varargin)disp('obj.handles.home.deepmib2dNucleiLM pressed');
category.add(obj.handles.home.deepmib2dNucleiLM);
% 3D EM Mitochondria (256 Mb)
obj.handles.home.deepmib3dMitoEM = matlab.ui.internal.toolstrip.GalleryItem('3D EM Mitochondria (256 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_mito_24px.png')));
obj.handles.home.deepmib3dMitoEM.Description = 'Segmentation of mitochondria using 3D U-net';
obj.handles.home.deepmib3dMitoEM.ItemPushedFcn = @(varargin)disp('obj.handles.home.deepmib3dMitoEM pressed');
category.add(obj.handles.home.deepmib3dMitoEM);
% 3D LM hair cells (138 Mb)
obj.handles.home.deepmib3dHairCellsLM = matlab.ui.internal.toolstrip.GalleryItem('3D LM hair cells (138 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_hair_24px.png')));
obj.handles.home.deepmib3dHairCellsLM.Description = 'Segmentation of hair cells using anisotropic 3D U-net';
obj.handles.home.deepmib3dHairCellsLM.ItemPushedFcn = @(varargin)disp('obj.handles.home.deepmib3dHairCellsLM pressed');
category.add(obj.handles.home.deepmib3dHairCellsLM);
popup.add(category);

% Light microscopy datasets
category = matlab.ui.internal.toolstrip.GalleryCategory('Light microscopy');
% 3D SIM ER (21 Mb)
obj.handles.home.lm3dsimER = matlab.ui.internal.toolstrip.GalleryItem('3D SIM ER (21 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_sim_24px.png')));
obj.handles.home.lm3dsimER.Description = '3D super-resolution structured illumination light microscopy dataset of endoplasmic reticulum';
obj.handles.home.lm3dsimER.ItemPushedFcn = @(varargin)disp('obj.handles.home.lm3dsimER pressed');
category.add(obj.handles.home.lm3dsimER);
popup.add(category);
% 3D STED (27 Mb)
obj.handles.home.lm3dsted = matlab.ui.internal.toolstrip.GalleryItem('3D SIM ER (21 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_sted_24px.png')));
obj.handles.home.lm3dsted.Description = '3D super-resolution Stimulated Emission Depletion (STED) microscopy';
obj.handles.home.lm3dsted.ItemPushedFcn = @(varargin)disp('obj.handles.home.lm3dsted pressed');
category.add(obj.handles.home.lm3dsted);
popup.add(category);
% WF ER Photobleaching (58 Mb)
obj.handles.home.lmWFbleaching = matlab.ui.internal.toolstrip.GalleryItem('Widefield ER Photobleaching (21 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_wf_24px.png')));
obj.handles.home.lmWFbleaching.Description = 'Wide-field time-lapse imaging dataset of endoplasmic reticulum with visible photobleaching effect';
obj.handles.home.lmWFbleaching.ItemPushedFcn = @(varargin)disp('obj.handles.home.lmWFbleaching pressed');
category.add(obj.handles.home.lmWFbleaching);
popup.add(category);

% SBF-SEM
category = matlab.ui.internal.toolstrip.GalleryCategory('Serial block-face SEM');
% Huh-7 and model (29 Mb)
obj.handles.home.sbfsemHuh7 = matlab.ui.internal.toolstrip.GalleryItem('Huh-7 and model (29 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_huh7_24px.png')));
obj.handles.home.sbfsemHuh7.Description = 'Huh-7 cell and a model of nuclei, endoplasmic reticulum, mitochondria, and lipid droplets';
obj.handles.home.sbfsemHuh7.ItemPushedFcn = @(varargin)disp('obj.handles.home.sbfsemHuh7 pressed');
category.add(obj.handles.home.sbfsemHuh7);
% Trypanosoma and model (247 Mb)
obj.handles.home.sbfsemTrypanosoma = matlab.ui.internal.toolstrip.GalleryItem('Trypanosoma and model (247 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_trypis_24px.png')));
obj.handles.home.sbfsemTrypanosoma.Description = 'Trypanosoma brucei cell and a model of nuclei, endoplasmic reticulum, mitochondria, vesicles, lipid droplets, and cytoplasm';
obj.handles.home.sbfsemTrypanosoma.ItemPushedFcn = @(varargin)disp('obj.handles.home.sbfsemTrypanosoma pressed');
category.add(obj.handles.home.sbfsemTrypanosoma);
popup.add(category);

% MRI
category = matlab.ui.internal.toolstrip.GalleryCategory('Magnetic resonance imaging');
% MATLAB Brain and model (3 Mb)
obj.handles.home.mriBrain = matlab.ui.internal.toolstrip.GalleryItem('MATLAB Brain and model (3 Mb)', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/examples_mri_24px.png')));
obj.handles.home.mriBrain.Description = 'Test brain dataset from MATLAB, captured with magnetic resonance imaging (MRI), including a tumor model';
obj.handles.home.mriBrain.ItemPushedFcn = @(varargin)disp('obj.handles.home.mriBrain pressed');
category.add(obj.handles.home.mriBrain);
popup.add(category);

obj.handles.home.examples = matlab.ui.internal.toolstrip.DropDownGalleryButton(popup, 'Examples', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/gallery_24px.png')));
obj.handles.home.examples.Description = 'Example datasets and projects for MIB';
column.add(obj.handles.home.examples);

obj.handles.home.importButton =  matlab.ui.internal.toolstrip.SplitButton("Import", matlab.ui.internal.toolstrip.Icon.IMPORT_24);
obj.handles.home.importButton.Description = "Import datasets to MIB";
obj.handles.home.importButton.ButtonPushedFcn  = @(varargin)disp('Import from Matlab pressed');

%% ============= Make "Export" section =============
section = obj.handles.toolbar.home.addSection("Export image");

% % --------- SAVE ---------
column = section.addColumn();
obj.handles.home.saveFileAs =  matlab.ui.internal.toolstrip.SplitButton("Save", matlab.ui.internal.toolstrip.Icon.SAVE_COPY_AS_24); 
obj.handles.home.saveFileAs.Description = "Save current image to a new file";
obj.handles.home.saveFileAs.ButtonPushedFcn  = @(varargin)disp('Save dataset pressed');

% make a popup list for the dropdown button
popupList = matlab.ui.internal.toolstrip.PopupList();
% add header
header1 = matlab.ui.internal.toolstrip.PopupListHeader('Import dataset from');
popupList.add(header1);
% Save
obj.handles.home.saveFile = matlab.ui.internal.toolstrip.ListItem('Save', matlab.ui.internal.toolstrip.Icon.SAVE_DIRTY_24);
obj.handles.home.saveFile.Description = 'Save and overwrite the current image';
obj.handles.home.saveFile.ItemPushedFcn  = @(varargin)disp('Save image to the current filename pressed');
popupList.add(obj.handles.home.saveFile);
% Save as... the default operation by pressing the split button
obj.handles.home.saveFileAs2 = matlab.ui.internal.toolstrip.ListItem('Save as', matlab.ui.internal.toolstrip.Icon.SAVE_COPY_AS_24);
obj.handles.home.saveFileAs2.Description = 'Save current image to a new file';
obj.handles.home.saveFileAs2.ItemPushedFcn  = @(varargin)disp('Save current image to a new file pressed');
popupList.add(obj.handles.home.saveFileAs2);

% add the popup list to the SplitButton button
obj.handles.home.saveFileAs.Popup = popupList;

% add the dropdown button to the column
column.add(obj.handles.home.saveFileAs);

% % --------- EXPORT ---------
column = section.addColumn();
obj.handles.home.export =  matlab.ui.internal.toolstrip.SplitButton("Export", matlab.ui.internal.toolstrip.Icon.EXPORT_24);
obj.handles.home.export.Description = "Export to MATLAB";
obj.handles.home.export.ButtonPushedFcn  = @(varargin)disp('Export to MATLAB pressed');

% make a popup list for the dropdown button
popupList = matlab.ui.internal.toolstrip.PopupList();
% add header
header1 = matlab.ui.internal.toolstrip.PopupListHeader('Export dataset to');
popupList.add(header1);
% Export to MATLAB
obj.handles.home.exportToMatlab = matlab.ui.internal.toolstrip.ListItem('Export to MATLAB', matlab.ui.internal.toolstrip.Icon.MATLAB_24);
obj.handles.home.exportToMatlab.Description = 'Export the current dataset to MATLAB';
obj.handles.home.exportToMatlab.ItemPushedFcn  = @(varargin)disp('Export the current dataset to MATLAB pressed');
popupList.add(obj.handles.home.exportToMatlab);
% Export to Imaris
obj.handles.home.exportToImaris = matlab.ui.internal.toolstrip.ListItem('Export to Imaris', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/imaris_24px.png')));
obj.handles.home.exportToImaris.Description = 'Export the current dataset to Imaris';
obj.handles.home.exportToImaris.ItemPushedFcn  = @(varargin)disp('Export the current dataset to Imaris pressed');
popupList.add(obj.handles.home.exportToImaris);

% add the popup list to the SplitButton button
obj.handles.home.export.Popup = popupList;

% add the dropdown button to the column
column.add(obj.handles.home.export);

% % --------- SNAPSHOT ---------
column = section.addColumn(); 
obj.handles.home.snapshot = matlab.ui.internal.toolstrip.Button("Snapshot",  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/snapshot_16.png')));
obj.handles.home.snapshot.Description = 'Start the snapshot tool';
obj.handles.home.snapshot.ButtonPushedFcn = @(varargin)disp('Start the snapshot tool pressed');
column.add(obj.handles.home.snapshot);

% % --------- MOVIE/RENDER ---------
column = section.addColumn('Width', 100); 
% Render movie
obj.handles.home.movie = matlab.ui.internal.toolstrip.Button("Movie",  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/documentary_16px.png')));
obj.handles.home.movie.Description = 'Start the movie maker tool';
obj.handles.home.movie.ButtonPushedFcn = @(varargin)disp('Start the movie maker tool pressed');
column.add(obj.handles.home.movie);
% Render volume
obj.handles.home.render =  matlab.ui.internal.toolstrip.SplitButton("Render", matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/volume_rendering_16px.png')));
obj.handles.home.render.Description = 'Show the dataset using volume rendering';
obj.handles.home.render.ButtonPushedFcn = @(varargin)disp('Show the dataset using volume rendering pressed');

popupList = matlab.ui.internal.toolstrip.PopupList();
obj.handles.home.renderMIB =  matlab.ui.internal.toolstrip.ListItem( 'MIB Rendering',  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/mib_icon_24px.png'))); 
obj.handles.home.renderMIB.ItemPushedFcn = @(varargin)disp('MIB Rendering pressed');
popupList.add(obj.handles.home.renderMIB);
obj.handles.home.renderMatlab =  matlab.ui.internal.toolstrip.ListItem( 'MATLAB Volume Viewer',  matlab.ui.internal.toolstrip.Icon.MATLAB_24);
obj.handles.home.renderMatlab.ItemPushedFcn = @(varargin)disp('MATLAB Volume Viewer pressed');
popupList.add(obj.handles.home.renderMatlab);
obj.handles.home.renderFiji =  matlab.ui.internal.toolstrip.ListItem( '3D viewer in Fiji',  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/fiji_24px.png'))); 
obj.handles.home.renderFiji.ItemPushedFcn = @(varargin)disp('3D viewer in Fiji pressed');
popupList.add(obj.handles.home.renderFiji);
obj.handles.home.render.Popup = popupList;
column.add(obj.handles.home.render);
column.addEmptyControl();

%% ============= Make "Tools" section =============
section = obj.handles.toolbar.home.addSection("I/O Tools");

% % --------- Batch processing ---------
column = section.addColumn();
obj.handles.home.batch = matlab.ui.internal.toolstrip.Button(sprintf("Batch\nprocessing"),  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/batch_processing_24px.png')));
obj.handles.home.batch.Description = 'Start the batch processing tool';
obj.handles.home.batch.ButtonPushedFcn = @(varargin)disp('Start the batch processing tool pressed');
column.add(obj.handles.home.batch);

% % --------- Dataset chunking ---------
column = section.addColumn();
obj.handles.home.chunking =  matlab.ui.internal.toolstrip.DropDownButton(sprintf("Dataset\nchunking"), matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/grid_24px.png')));
obj.handles.home.chunking.Description = "Split datasets into chunks or stitch them back for efficient processing";
popupList = matlab.ui.internal.toolstrip.PopupList();
obj.handles.home.chunk =  matlab.ui.internal.toolstrip.ListItem( 'Chunk dataset', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/split_24px.png')));
obj.handles.home.chunk.Description = 'Split the image into smaller chunks for block-based processing';
obj.handles.home.chunk.ItemPushedFcn = @(varargin)disp('Split the image pressed');
popupList.add(obj.handles.home.chunk);
obj.handles.home.stitch =  matlab.ui.internal.toolstrip.ListItem( 'Stitch dataset', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/restore_24px.png')));
obj.handles.home.stitch.Description = 'Reassemble previously chunked subvolumes back into the full image';
obj.handles.home.stitch.ItemPushedFcn = @(varargin)disp('Reassemble previously chunked subvolumes pressed');
popupList.add(obj.handles.home.stitch);
obj.handles.home.chunking.Popup = popupList;
column.add(obj.handles.home.chunking);
% % --------- Image shuffling ---------
column = section.addColumn('Width', 80);
obj.handles.home.rename =  matlab.ui.internal.toolstrip.DropDownButton(sprintf("Image\nshuffling"), matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/random_24px.png')));
obj.handles.home.rename.Description = "Shuffle or restore image order to reduce processing bias";
popupList = matlab.ui.internal.toolstrip.PopupList();
obj.handles.home.shuffle =  matlab.ui.internal.toolstrip.ListItem('Shuffle images', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/random_24px.png')));
obj.handles.home.shuffle.Description = 'Randomly reorder and rename images to reduce processing bias';
obj.handles.home.shuffle.ItemPushedFcn = @(varargin)disp('Shuffling pressed');
popupList.add(obj.handles.home.shuffle);
obj.handles.home.reshuffle =  matlab.ui.internal.toolstrip.ListItem('Restore order',  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/shuffle_restore_24px.png')));
obj.handles.home.reshuffle.Description = 'Revert images to their original order and filenames';
obj.handles.home.reshuffle.ItemPushedFcn = @(varargin)disp('Revert images pressed');
popupList.add(obj.handles.home.reshuffle);
obj.handles.home.rename.Popup = popupList;
column.add(obj.handles.home.rename);

%% ============= Make "PREFERENCES" section =============
section = obj.handles.toolbar.home.addSection("PREFERENCES");

% % --------- LAYOUT ---------
column = section.addColumn(); 
% --------- Restore layout ---------
obj.handles.home.loadLayout =  matlab.ui.internal.toolstrip.SplitButton("Load layout", matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/load_layout_local_16px.png')));
obj.handles.home.loadLayout.Description = 'Restore the default layout of panels';
obj.handles.home.loadLayout.ButtonPushedFcn = @(varargin)obj.controller.loadLayout('localDefault');

prefDir = utils.getPrefDir();
popupList = matlab.ui.internal.toolstrip.PopupList();
obj.handles.home.loadLayoutLocalDefault =  matlab.ui.internal.toolstrip.ListItem( 'Load local default layout', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/load_layout_local_24px.png')));
obj.handles.home.loadLayoutLocalDefault.Description = sprintf('Load local default layout from %s', fullfile(prefDir, 'mibDefaultLayout.json'));
obj.handles.home.loadLayoutLocalDefault.ItemPushedFcn = @(varargin)obj.controller.loadLayout('localDefault');
popupList.add(obj.handles.home.loadLayoutLocalDefault);
obj.handles.home.loadLayoutCustom =  matlab.ui.internal.toolstrip.ListItem( 'Load custom layout', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/load_layout_custom_24px.png')));
obj.handles.home.loadLayoutCustom.Description = sprintf('Load custom layout from a file, typically stored in %s', prefDir);
obj.handles.home.loadLayoutCustom.ItemPushedFcn = @(varargin)obj.controller.loadLayout('custom');
popupList.add(obj.handles.home.loadLayoutCustom);
obj.handles.home.loadLayoutMibDefault =  matlab.ui.internal.toolstrip.ListItem( 'Load MIB default layout', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/load_layout_global_24px.png')));
obj.handles.home.loadLayoutMibDefault.Description = sprintf('Load default MIB layout from %s', fullfile(obj.controller.mibPath, 'assets', 'mibDefaultLayout.json'));
obj.handles.home.loadLayoutMibDefault.ItemPushedFcn = @(varargin)obj.controller.loadLayout('globalDefault');
popupList.add(obj.handles.home.loadLayoutMibDefault);
obj.handles.home.loadLayout.Popup = popupList;
column.add(obj.handles.home.loadLayout);

% --------- Store layout ---------
obj.handles.home.saveLayout =  matlab.ui.internal.toolstrip.SplitButton("Save layout", matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/layout_save_16px.png')));
obj.handles.home.saveLayout.Description = 'Save the current layout of panels as default';
obj.handles.home.saveLayout.ButtonPushedFcn = @(varargin)obj.controller.saveLayout('localDefault');

popupList = matlab.ui.internal.toolstrip.PopupList();
obj.handles.home.saveLayoutLocalDefault =  matlab.ui.internal.toolstrip.ListItem( 'Save the current layout as default', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/layout_save_24px.png')));
obj.handles.home.saveLayoutLocalDefault.Description = sprintf('Save the current layout as default to %s', fullfile(prefDir, 'mibDefaultLayout.json'));
obj.handles.home.saveLayoutLocalDefault.ItemPushedFcn = @(varargin)obj.controller.saveLayout('localDefault');
popupList.add(obj.handles.home.saveLayoutLocalDefault);
obj.handles.home.saveLayoutCustom =  matlab.ui.internal.toolstrip.ListItem( 'Save the current layout in a custom file', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/save_layout_custom_24px.png')));
obj.handles.home.saveLayoutCustom.Description = sprintf('Save the current layout in a custom file, typically stored in %s', prefDir); 
obj.handles.home.saveLayoutCustom.ItemPushedFcn = @(varargin)obj.controller.saveLayout('custom');
popupList.add(obj.handles.home.saveLayoutCustom);
obj.handles.home.saveLayoutMibDefault =  matlab.ui.internal.toolstrip.ListItem( 'Save the current layout as MIB default', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/load_layout_global_24px.png')));
obj.handles.home.saveLayoutMibDefault.Description = sprintf('Save the current layout as MIB default to %s', fullfile(obj.controller.mibPath, 'assets', 'mibDefaultLayout.json'));
obj.handles.home.saveLayoutMibDefault.ItemPushedFcn = @(varargin)obj.controller.saveLayout('globalDefault');
popupList.add(obj.handles.home.saveLayoutMibDefault);

obj.handles.home.saveLayout.Popup = popupList;
column.add(obj.handles.home.saveLayout);
% Empty
column.addEmptyControl();

% % --------- Preferences ---------
column = section.addColumn();
obj.handles.home.preferences = matlab.ui.internal.toolstrip.Button(sprintf("Preferences"),  matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/preferences_24px.png')));
obj.handles.home.preferences.Description = 'Start the batch processing tool';
obj.handles.home.preferences.ButtonPushedFcn = @(varargin)disp('Preferences pressed');
column.add(obj.handles.home.preferences);

% --------- Help ---------
column = section.addColumn();

% HELP split button
obj.handles.home.help =  matlab.ui.internal.toolstrip.SplitButton("Help", matlab.ui.internal.toolstrip.Icon.HELP_24);
obj.handles.home.help.Description = "Open MIB help";
obj.handles.home.help.ButtonPushedFcn  = @(varargin)disp('Opem MIB help pressed');

% make a popup list for the dropdown button
popupList = matlab.ui.internal.toolstrip.PopupList();
% add header
%header = matlab.ui.internal.toolstrip.PopupListHeader('Help and support');
%popupList.add(header);
% MIB help
obj.handles.home.helpMenu = matlab.ui.internal.toolstrip.ListItem('Open MIB help', matlab.ui.internal.toolstrip.Icon.HELP_16);
%obj.handles.home.helpMenu.Description = 'Open MIB help';
obj.handles.home.helpMenu.ItemPushedFcn  = @(varargin)disp('Open MIB help pressed');
popupList.add(obj.handles.home.helpMenu);
% Tip of the day
obj.handles.home.tipOfDay = matlab.ui.internal.toolstrip.ListItem('Tip of the day', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/bulb_16px.png')));
%obj.handles.home.tipOfDay.Description = 'Tip of the day';
obj.handles.home.tipOfDay.ItemPushedFcn  = @(varargin)disp('Tip of the day pressed');
popupList.add(obj.handles.home.tipOfDay);
% Support on forum.image.sc
obj.handles.home.support = matlab.ui.internal.toolstrip.ListItem('Support on image.sc', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/image_sc_16px.png')));
%obj.handles.home.support.Description = 'Get support on forum.image.sc';
obj.handles.home.support.ItemPushedFcn  = @(varargin)disp('Support on image.sc pressed');
popupList.add(obj.handles.home.support);
% Call 4 help support
obj.handles.home.call4help = matlab.ui.internal.toolstrip.ListItem('Personal support session', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/call4help_16px.png')));
%obj.handles.home.call4help.Description = 'Book a personal online support session';
obj.handles.home.call4help.ItemPushedFcn  = @(varargin)disp('Call 4 help pressed');
popupList.add(obj.handles.home.call4help);
% Class reference
obj.handles.home.classReference = matlab.ui.internal.toolstrip.ListItem('API class reference', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/class_reference_16px.png')));
%obj.handles.home.classReference.Description = 'API class reference';
obj.handles.home.classReference.ItemPushedFcn  = @(varargin)disp('API class reference pressed');
popupList.add(obj.handles.home.classReference);

% add header
%header = matlab.ui.internal.toolstrip.PopupListHeader('New version');
%popupList.add(header);
% separator
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);
% Check for update
obj.handles.home.checkUpdate =  matlab.ui.internal.toolstrip.ListItem('Check for update', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/update_check_16px.png')));
%obj.handles.home.checkUpdate.Description = 'Check for availability of a new version of MIB';
obj.handles.home.checkUpdate.ItemPushedFcn = @(varargin)disp('Check for update pressed');
popupList.add(obj.handles.home.checkUpdate);

% add header
%header = matlab.ui.internal.toolstrip.PopupListHeader('Stats');
%popupList.add(header);
% separator
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);
% Check for update
obj.handles.home.personalStats =  matlab.ui.internal.toolstrip.ListItem('Your personal stats', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/personal_stats_16px.png')));
%obj.handles.home.personalStats.Description = 'See your personal stats';
obj.handles.home.personalStats.ItemPushedFcn = @(varargin)disp('Your personal stats pressed');
popupList.add(obj.handles.home.personalStats);

% add header
%header = matlab.ui.internal.toolstrip.PopupListHeader('About');
%popupList.add(header);
% separator
separator = matlab.ui.internal.toolstrip.PopupListSeparator();
popupList.add(separator);
% Licenses
obj.handles.home.licenses =  matlab.ui.internal.toolstrip.ListItem('Licenses', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/licenses_16px.png')));
%obj.handles.home.licenses.Description = 'See your personal stats';
obj.handles.home.licenses.ItemPushedFcn = @(varargin)disp('Licenses pressed');
popupList.add(obj.handles.home.licenses);

% About MIB
obj.handles.home.about =  matlab.ui.internal.toolstrip.ListItem('About MIB', matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/about_16px.png')));
%obj.handles.home.about.Description = 'See your personal stats';
obj.handles.home.about.ItemPushedFcn = @(varargin)disp('About MIB pressed');
popupList.add(obj.handles.home.about);

obj.handles.home.help.Popup = popupList;
column.add(obj.handles.home.help);


%% Add the home tab to the global tab group
obj.handles.toolbar.global.add(obj.handles.toolbar.home);

end