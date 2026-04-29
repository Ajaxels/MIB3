function homeHandles = addRibbonHome(obj)
% ADDRIBBONHOME - build the Home tab group (obj.handles.ribbon.home) and add it to obj.handles.ribbon.global.
%
% Syntax:
%   function homeHandles = addRibbonHome(obj)
%

arguments (Input)
    obj views.MibView
end

%% Init shorter variables and import classes
iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');
import matlab.ui.internal.toolstrip.Icon
import matlab.ui.internal.toolstrip.SplitButton
import matlab.ui.internal.toolstrip.PopupList
import matlab.ui.internal.toolstrip.PopupListHeader
import matlab.ui.internal.toolstrip.ListItem
import matlab.ui.internal.toolstrip.GalleryCategory
import matlab.ui.internal.toolstrip.GalleryItem
import matlab.ui.internal.toolstrip.Button
import matlab.ui.internal.toolstrip.DropDownButton
import matlab.ui.internal.toolstrip.PopupListSeparator

obj.handles.ribbon.home = matlab.ui.internal.toolstrip.Tab("Home");

%% ============= Make "Import" section =============
section = obj.handles.ribbon.home.addSection("Import image");

% --------- Open ---------
column = section.addColumn();
homeHandles.loadFile =  SplitButton("Load", Icon.OPEN_24);
homeHandles.loadFile.Description = "Load dataset";
% add the dropdown button to the column
column.add(homeHandles.loadFile);

% --------- Import ---------
column = section.addColumn();

% IMPORT split button
homeHandles.import =  SplitButton("Import", Icon.IMPORT_24);
homeHandles.import.Description = "Import datasets to MIB";

% make a popup list for the dropdown button
popupList = PopupList();
% add header
header1 = PopupListHeader('Import dataset from');
popupList.add(header1);
% import from MATLAB
homeHandles.importFromMatlab = ListItem('MATLAB', Icon.MATLAB_24);
homeHandles.importFromMatlab.Description = 'Import dataset from MATLAB';
popupList.add(homeHandles.importFromMatlab);
% import from clipboard
homeHandles.importFromClipboard = ListItem('System Clipboard', Icon.PASTE_24);
homeHandles.importFromClipboard.Description = 'Import from system clipboard';
popupList.add(homeHandles.importFromClipboard);
% import from Imaris
homeHandles.importFromImaris = ListItem('Imaris', Icon(fullfile(iconPath, 'imaris_24px.png')));
homeHandles.importFromImaris.Description = 'Import from Imaris';
popupList.add(homeHandles.importFromImaris);
% import from OMERO
homeHandles.importFromOmero = ListItem('Omero', Icon(fullfile(iconPath, 'omero_24px.png')));
homeHandles.importFromOmero.Description = 'Import dataset from OMERO';
popupList.add(homeHandles.importFromOmero);
% import from URL
homeHandles.importFromURL = ListItem('URL', Icon(fullfile(iconPath, 'internet_24px.png')));
homeHandles.importFromURL.Description = 'Import dataset from URL';
popupList.add(homeHandles.importFromURL);

% add the popup list to the SplitButton button
homeHandles.import.Popup = popupList;

% add the dropdown button to the column
column.add(homeHandles.import);

% --------- EXAMPLES split button ---------
column = section.addColumn('Width', 70);
% generate menu
popup = matlab.ui.internal.toolstrip.GalleryPopup('GalleryItemTextLineCount', 2, 'GalleryItemRowCount', 1, ...
    'IconSize', 24, 'DisplayState', 'icon_view');  % list_view/icon_view; IconSize: 16(x16), 24(x24), 40(x50)

% DeepMIB projects
category = GalleryCategory('DeepMIB projects');
% 2D large spots synthetic (62 Mb)
homeHandles.deepmib2dLargeSpots = GalleryItem('2D large spots synthetic (62 Mb)', Icon(fullfile(iconPath, 'large_spots_24px.png')));
homeHandles.deepmib2dLargeSpots.Description = 'DeepLabV3-Resnet18 network for detecting large spots on a black background';
category.add(homeHandles.deepmib2dLargeSpots);
% 2D small spots synthetic (8 Mb)
homeHandles.deepmib2dSmallSpots = GalleryItem('2D small spots synthetic (8 Mb)', Icon(fullfile(iconPath, 'small_spots_24px.png')));
homeHandles.deepmib2dSmallSpots.Description = 'U-net network for detecting small random spots of two colors on a black background';
category.add(homeHandles.deepmib2dSmallSpots);
% 2.5D large spots synthetic (121 Mb)
homeHandles.deepmib25dLargeSpots = GalleryItem('2.5D large spots synthetic (121 Mb)', Icon(fullfile(iconPath, 'large_spots_3d_24px.png')));
homeHandles.deepmib25dLargeSpots.Description = '2.5D DeepLabV3-Resnet18 and U-net networks for segmenting large 3D spots (ignoring 2D spots)';
category.add(homeHandles.deepmib25dLargeSpots);
% 2D patch-wise synthetic (42 Mb)
homeHandles.deepmib2dPatchWise = GalleryItem('2D patch-wise synthetic (42 Mb)', Icon(fullfile(iconPath, 'patch_wise_24px.png')));
homeHandles.deepmib2dPatchWise.Description = 'Resnet18 network for detecting patches of large white spots on a black background';
category.add(homeHandles.deepmib2dPatchWise);
% separator
separator = PopupListSeparator();
popupList.add(separator);
% 2D EM Membranes (219 Mb)
homeHandles.deepmib2dMembranesEM = GalleryItem('2D EM Membranes (219 Mb)', Icon(fullfile(iconPath, 'examples_membranes_24px.png')));
homeHandles.deepmib2dMembranesEM.Description = 'Segmentation of membranes from serial-section TEM images';
category.add(homeHandles.deepmib2dMembranesEM);
% 2D LM Nuclei (174 Mb)
homeHandles.deepmib2dNucleiLM = GalleryItem('2D LM Nuclei (174 Mb)', Icon(fullfile(iconPath, 'examples_nuclei_24px.png')));
homeHandles.deepmib2dNucleiLM.Description = 'Segmentation of nuclei, boundaries, and touching edges';
category.add(homeHandles.deepmib2dNucleiLM);
% 3D EM Mitochondria (256 Mb)
homeHandles.deepmib3dMitoEM = GalleryItem('3D EM Mitochondria (256 Mb)', Icon(fullfile(iconPath, 'examples_mito_24px.png')));
homeHandles.deepmib3dMitoEM.Description = 'Segmentation of mitochondria using 3D U-net';
category.add(homeHandles.deepmib3dMitoEM);
% 3D LM hair cells (138 Mb)
homeHandles.deepmib3dHairCellsLM = GalleryItem('3D LM hair cells (138 Mb)', Icon(fullfile(iconPath, 'examples_hair_24px.png')));
homeHandles.deepmib3dHairCellsLM.Description = 'Segmentation of hair cells using anisotropic 3D U-net';
category.add(homeHandles.deepmib3dHairCellsLM);
popup.add(category);

% Light microscopy datasets
category = GalleryCategory('Light microscopy');
% 3D SIM ER (21 Mb)
homeHandles.lm3dsimER = GalleryItem('3D SIM ER (21 Mb)', Icon(fullfile(iconPath, 'examples_sim_24px.png')));
homeHandles.lm3dsimER.Description = '3D super-resolution structured illumination light microscopy dataset of endoplasmic reticulum';
category.add(homeHandles.lm3dsimER);
popup.add(category);
% 3D STED (27 Mb)
homeHandles.lm3dsted = GalleryItem('3D STED (27 Mb)', Icon(fullfile(iconPath, 'examples_sted_24px.png')));
homeHandles.lm3dsted.Description = '3D super-resolution Stimulated Emission Depletion (STED) microscopy';
category.add(homeHandles.lm3dsted);
popup.add(category);
% WF ER Photobleaching (58 Mb)
homeHandles.lmWFbleaching = GalleryItem('Widefield ER Photobleaching (21 Mb)', Icon(fullfile(iconPath, 'examples_wf_24px.png')));
homeHandles.lmWFbleaching.Description = 'Wide-field time-lapse imaging dataset of endoplasmic reticulum with visible photobleaching effect';
category.add(homeHandles.lmWFbleaching);
popup.add(category);

% SBF-SEM
category = GalleryCategory('Serial block-face SEM');
% Huh-7 and model (29 Mb)
homeHandles.sbfsemHuh7 = GalleryItem('Huh-7 and model (29 Mb)', Icon(fullfile(iconPath, 'examples_huh7_24px.png')));
homeHandles.sbfsemHuh7.Description = 'Huh-7 cell and a model of nuclei, endoplasmic reticulum, mitochondria, and lipid droplets';
category.add(homeHandles.sbfsemHuh7);
% Trypanosoma and model (247 Mb)
homeHandles.sbfsemTrypanosoma = GalleryItem('Trypanosoma and model (247 Mb)', Icon(fullfile(iconPath, 'examples_trypis_24px.png')));
homeHandles.sbfsemTrypanosoma.Description = 'Trypanosoma brucei cell and a model of nuclei, endoplasmic reticulum, mitochondria, vesicles, lipid droplets, and cytoplasm';
category.add(homeHandles.sbfsemTrypanosoma);
popup.add(category);

% MRI
category = GalleryCategory('Magnetic resonance imaging');
% MATLAB Brain and model (3 Mb)
homeHandles.mriBrain = GalleryItem('MATLAB Brain and model (3 Mb)', Icon(fullfile(iconPath, 'examples_mri_24px.png')));
homeHandles.mriBrain.Description = 'Test brain dataset from MATLAB, captured with magnetic resonance imaging (MRI), including a tumor model';
category.add(homeHandles.mriBrain);
popup.add(category);

homeHandles.examples = matlab.ui.internal.toolstrip.DropDownGalleryButton(popup, 'Examples', Icon(fullfile(iconPath, 'gallery_24px.png')));
homeHandles.examples.Description = 'Example datasets and projects for MIB';
column.add(homeHandles.examples);

%% ============= Make "Export" section =============
section = obj.handles.ribbon.home.addSection("Export image");

% % --------- SAVE ---------
column = section.addColumn();
homeHandles.saveFileAs = Button("Save as",  Icon.SAVE_COPY_AS_24);
homeHandles.snapshot.Description = 'Save current dataset to a file';

% % split button with two options
% homeHandles.saveFileAs = SplitButton("Save", Icon.SAVE_COPY_AS_24); 
% homeHandles.saveFileAs.Description = "Save current image to a new file";
% % make a popup list for the dropdown button
% popupList = PopupList();
% % add header
% header1 = PopupListHeader('Import dataset from');
% popupList.add(header1);
% % Save
% homeHandles.saveFile = ListItem('Save', Icon.SAVE_DIRTY_24);
% homeHandles.saveFile.Description = 'Save and overwrite the current image';
% popupList.add(homeHandles.saveFile);
% % Save as... the default operation by pressing the split button
% homeHandles.saveFileAs2 = ListItem('Save as', Icon.SAVE_COPY_AS_24);
% homeHandles.saveFileAs2.Description = 'Save current image to a new file';
% popupList.add(homeHandles.saveFileAs2);
% % add the popup list to the SplitButton button
% homeHandles.saveFileAs.Popup = popupList;

% add the dropdown button to the column
column.add(homeHandles.saveFileAs);

% % --------- EXPORT ---------
column = section.addColumn();
homeHandles.export = SplitButton("Export", Icon.EXPORT_24);
homeHandles.export.Description = "Export to MATLAB";

% make a popup list for the dropdown button
popupList = PopupList();
% add header
header1 = PopupListHeader('Export dataset to');
popupList.add(header1);
% Export to MATLAB
homeHandles.exportToMatlab = ListItem('Export to MATLAB', Icon.MATLAB_24);
homeHandles.exportToMatlab.Description = 'Export the current dataset to MATLAB';
popupList.add(homeHandles.exportToMatlab);
% Export to Imaris
homeHandles.exportToImaris = ListItem('Export to Imaris', Icon(fullfile(iconPath, 'imaris_24px.png')));
homeHandles.exportToImaris.Description = 'Export the current dataset to Imaris';
popupList.add(homeHandles.exportToImaris);

% add the popup list to the SplitButton button
homeHandles.export.Popup = popupList;

% add the dropdown button to the column
column.add(homeHandles.export);

% % --------- SNAPSHOT ---------
%icon = core.MibIconCache.get('icons', 'snapshot_16px');
%snapshot = Button("Snapshot",  Icon(core.MibIconCache.get('icons', 'snapshot_16px')));

column = section.addColumn(); 
homeHandles.snapshot = Button("Snapshot",  Icon(fullfile(iconPath, 'snapshot_16px.png')));
homeHandles.snapshot.Description = 'Start the snapshot tool';
column.add(homeHandles.snapshot);

% % --------- MOVIE/RENDER ---------
column = section.addColumn('Width', 100); 
% Render movie
homeHandles.movie = Button("Movie",  Icon(fullfile(iconPath, 'documentary_16px.png')));
homeHandles.movie.Description = 'Start the movie maker tool';
column.add(homeHandles.movie);
% Render volume
homeHandles.render = SplitButton("Render", Icon(fullfile(iconPath, 'volume_rendering_16px.png')));
homeHandles.render.Description = 'Show the dataset using volume rendering';

popupList = PopupList();
header1 = PopupListHeader('3D rendering engines');
popupList.add(header1);
homeHandles.renderMIB = ListItem( 'MIB Rendering',  Icon(fullfile(iconPath, 'mib_icon_24px.png'))); 
popupList.add(homeHandles.renderMIB);
homeHandles.renderMatlab = ListItem( 'MATLAB Volume Viewer',  Icon.MATLAB_24);
homeHandles.renderMatlab.ItemPushedFcn = @(varargin)disp('MATLAB Volume Viewer pressed');
popupList.add(homeHandles.renderMatlab);
homeHandles.renderFiji = ListItem( '3D viewer in Fiji',  Icon(fullfile(iconPath, 'fiji_24px.png'))); 
popupList.add(homeHandles.renderFiji);
homeHandles.render.Popup = popupList;
column.add(homeHandles.render);
column.addEmptyControl();

%% ============= Make "I/O Tools" section =============
section = obj.handles.ribbon.home.addSection("I/O Tools");

% % --------- Batch processing ---------
column = section.addColumn();
homeHandles.batch = Button(sprintf("Batch\nprocessing"),  Icon(fullfile(iconPath, 'batch_processing_24px.png')));
homeHandles.batch.Description = 'Start the batch processing tool';
column.add(homeHandles.batch);

% % --------- Dataset chunking ---------
column = section.addColumn();
homeHandles.chunking = DropDownButton(sprintf("Dataset\nchunking"), Icon(fullfile(iconPath, 'grid_24px.png')));
homeHandles.chunking.Description = "Split datasets into chunks or stitch them back for efficient processing";
popupList = PopupList();
header1 = PopupListHeader('Split to subvolumes');
popupList.add(header1);
homeHandles.chunk = ListItem( 'Chunk dataset', Icon(fullfile(iconPath, 'split_24px.png')));
homeHandles.chunk.Description = 'Split the image into smaller chunks for block-based processing';
popupList.add(homeHandles.chunk);
homeHandles.stitch = ListItem( 'Stitch dataset', Icon(fullfile(iconPath, 'restore_24px.png')));
homeHandles.stitch.Description = 'Reassemble previously chunked subvolumes back into the full image';
popupList.add(homeHandles.stitch);
homeHandles.chunking.Popup = popupList;
column.add(homeHandles.chunking);
% % --------- Image shuffling ---------
column = section.addColumn('Width', 80);
homeHandles.rename =  DropDownButton(sprintf("Image\nshuffling"), Icon(fullfile(iconPath, 'random_24px.png')));
homeHandles.rename.Description = "Shuffle or restore image order to reduce processing bias";
popupList = PopupList();
header1 = PopupListHeader('Image Anonymization');
popupList.add(header1);
homeHandles.shuffle =  ListItem('Shuffle images', Icon(fullfile(iconPath, 'random_24px.png')));
homeHandles.shuffle.Description = 'Randomly reorder and rename images to reduce processing bias';
popupList.add(homeHandles.shuffle);
homeHandles.reshuffle =  ListItem('Restore order',  Icon(fullfile(iconPath, 'shuffle_restore_24px.png')));
homeHandles.reshuffle.Description = 'Revert images to their original order and filenames';
popupList.add(homeHandles.reshuffle);
homeHandles.rename.Popup = popupList;
column.add(homeHandles.rename);

%% ============= Make "PREFERENCES" section =============
section = obj.handles.ribbon.home.addSection("PREFERENCES");

% % --------- LAYOUT ---------
column = section.addColumn(); 
% --------- Restore layout ---------
homeHandles.loadLayout =  SplitButton("Load layout", Icon(fullfile(iconPath, 'load_layout_local_16px.png')));
homeHandles.loadLayout.Description = 'Restore the default layout of panels';

prefDir = utils.getPrefDir();
popupList = PopupList();
header1 = PopupListHeader('Update the current GIU layout');
popupList.add(header1);
homeHandles.loadLayoutLocalDefault =  ListItem( 'Load local default layout', Icon(fullfile(iconPath, 'load_layout_local_24px.png')));
homeHandles.loadLayoutLocalDefault.Description = sprintf('Load local default layout from %s', fullfile(prefDir, 'mibDefaultLayout.json'));
popupList.add(homeHandles.loadLayoutLocalDefault);
homeHandles.loadLayoutCustom =  ListItem( 'Load custom layout', Icon(fullfile(iconPath, 'load_layout_custom_24px.png')));
homeHandles.loadLayoutCustom.Description = sprintf('Load custom layout from a file, typically stored in %s', prefDir);
popupList.add(homeHandles.loadLayoutCustom);
homeHandles.loadLayoutMibDefault =  ListItem( 'Load MIB default layout', Icon(fullfile(iconPath, 'load_layout_global_24px.png')));
homeHandles.loadLayoutMibDefault.Description = sprintf('Load default MIB layout from %s', fullfile(obj.controller.mibPath, 'assets', 'mibDefaultLayout.json'));
popupList.add(homeHandles.loadLayoutMibDefault);
homeHandles.loadLayout.Popup = popupList;
column.add(homeHandles.loadLayout);

% --------- Store layout ---------
homeHandles.saveLayout =  SplitButton("Save layout", Icon(fullfile(iconPath, 'layout_save_16px.png')));
homeHandles.saveLayout.Description = 'Save the current layout of panels as default';

popupList = PopupList();
header1 = PopupListHeader('Save current GUI layout');
popupList.add(header1);
homeHandles.saveLayoutLocalDefault =  ListItem( 'Save the current layout as default', Icon(fullfile(iconPath, 'layout_save_24px.png')));
homeHandles.saveLayoutLocalDefault.Description = sprintf('Save the current layout as default to %s', fullfile(prefDir, 'mibDefaultLayout.json'));
popupList.add(homeHandles.saveLayoutLocalDefault);
homeHandles.saveLayoutCustom =  ListItem( 'Save the current layout in a custom file', Icon(fullfile(iconPath, 'save_layout_custom_24px.png')));
homeHandles.saveLayoutCustom.Description = sprintf('Save the current layout in a custom file, typically stored in %s', prefDir); 
popupList.add(homeHandles.saveLayoutCustom);
homeHandles.saveLayoutMibDefault =  ListItem( 'Save the current layout as MIB default', Icon(fullfile(iconPath, 'load_layout_global_24px.png')));
homeHandles.saveLayoutMibDefault.Description = sprintf('Save the current layout as MIB default to %s', fullfile(obj.controller.mibPath, 'assets', 'mibDefaultLayout.json'));
popupList.add(homeHandles.saveLayoutMibDefault);

homeHandles.saveLayout.Popup = popupList;
column.add(homeHandles.saveLayout);
% Empty
column.addEmptyControl();

% % --------- Preferences ---------
column = section.addColumn();
homeHandles.preferences = Button(sprintf("Preferences"),  Icon(fullfile(iconPath, 'preferences_24px.png')));
homeHandles.preferences.Description = 'Start the batch processing tool';
column.add(homeHandles.preferences);

% --------- Help ---------
column = section.addColumn();

% HELP split button
homeHandles.help = SplitButton("Help", Icon.HELP_24);
homeHandles.help.Description = "Open MIB help";

% make a popup list for the dropdown button
popupList = PopupList();
header1 = PopupListHeader('Help hotline');
popupList.add(header1);
% MIB help
homeHandles.helpMenu = ListItem('Open MIB help', Icon.HELP_16);
popupList.add(homeHandles.helpMenu);
% Tip of the day
homeHandles.tipOfDay = ListItem('Tip of the day', Icon(fullfile(iconPath, 'bulb_16px.png')));
popupList.add(homeHandles.tipOfDay);
% Support on forum.image.sc
homeHandles.support = ListItem('Support on image.sc', Icon(fullfile(iconPath, 'image_sc_16px.png')));
popupList.add(homeHandles.support);
% Call 4 help support
homeHandles.call4help = ListItem('Personal support session', Icon(fullfile(iconPath, 'call4help_16px.png')));
popupList.add(homeHandles.call4help);
% Class reference
homeHandles.classReference = ListItem('API class reference', Icon(fullfile(iconPath, 'class_reference_16px.png')));
popupList.add(homeHandles.classReference);

% separator
separator = PopupListSeparator();
popupList.add(separator);
% Check for update
homeHandles.checkUpdate = ListItem('Check for update', Icon(fullfile(iconPath, 'update_check_16px.png')));
popupList.add(homeHandles.checkUpdate);

% separator
separator = PopupListSeparator();
popupList.add(separator);
% Check for update
homeHandles.personalStats = ListItem('Your personal stats', Icon(fullfile(iconPath, 'personal_stats_16px.png')));
popupList.add(homeHandles.personalStats);

% separator
separator = PopupListSeparator();
popupList.add(separator);
% Licenses
homeHandles.licenses = ListItem('Licenses', Icon(fullfile(iconPath, 'licenses_16px.png')));
popupList.add(homeHandles.licenses);

% About MIB
homeHandles.about = ListItem('About MIB', Icon(fullfile(iconPath, 'about_16px.png')));
popupList.add(homeHandles.about);

homeHandles.help.Popup = popupList;
column.add(homeHandles.help);

%% ============= Make "Dev corner" section =============
section = obj.handles.ribbon.home.addSection("Dev corner");

column = section.addColumn();

homeHandles.devModeSplitBtn = SplitButton(sprintf("Development"),  Icon(fullfile(iconPath, 'dev_corner_24px.png')));
homeHandles.devModeSplitBtn.Description = 'Reserved for developmental purposes';
% make a popup list for the dropdown button
popupList = PopupList();
homeHandles.devModeEnabled = matlab.ui.internal.toolstrip.ListItemWithCheckBox('Developer mode', false);
homeHandles.devModeEnabled.Description = 'Enable developer mode that reports handles of widgets in tooltips';
popupList.add(homeHandles.devModeEnabled);
homeHandles.devMode = ListItem(sprintf("Development"),  Icon(fullfile(iconPath, 'dev_corner_16px.png')));
homeHandles.devMode.Description = 'Start developer callback ()';
popupList.add(homeHandles.devMode);
% add the popup list to the SplitButton
homeHandles.devModeSplitBtn.Popup = popupList;
column.add(homeHandles.devModeSplitBtn);

%homeHandles.devMode = Button(sprintf("Development"),  Icon(fullfile(iconPath, 'dev_corner_24px.png')));
%homeHandles.devMode.Description = 'Reserved for developmental purposes';
%column.add(homeHandles.devMode);

%% Finalize

obj.handles.ribbonHome = homeHandles;
% Add the home tab to the global tab group
obj.handles.ribbon.global.add(obj.handles.ribbon.home);

end
