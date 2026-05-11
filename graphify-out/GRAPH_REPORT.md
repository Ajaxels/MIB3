# Graph Report - C:\Matlab\MIB3\mib  (2026-05-11)

## Corpus Check
- Large corpus: 712 files · ~519,894 words. Semantic extraction will be expensive (many Claude tokens). Consider running on a subfolder, or use --no-semantic to run AST-only.

## Summary
- 1733 nodes · 2866 edges · 111 communities (84 shown, 27 thin omitted)
- Extraction: 75% EXTRACTED · 25% INFERRED · 0% AMBIGUOUS · INFERRED: 724 edges (avg confidence: 0.74)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]
- [[_COMMUNITY_Community 80|Community 80]]
- [[_COMMUNITY_Community 81|Community 81]]
- [[_COMMUNITY_Community 82|Community 82]]
- [[_COMMUNITY_Community 83|Community 83]]
- [[_COMMUNITY_Community 84|Community 84]]
- [[_COMMUNITY_Community 85|Community 85]]
- [[_COMMUNITY_Community 86|Community 86]]
- [[_COMMUNITY_Community 87|Community 87]]
- [[_COMMUNITY_Community 88|Community 88]]
- [[_COMMUNITY_Community 90|Community 90]]
- [[_COMMUNITY_Community 91|Community 91]]
- [[_COMMUNITY_Community 108|Community 108]]
- [[_COMMUNITY_Community 109|Community 109]]
- [[_COMMUNITY_Community 110|Community 110]]

## God Nodes (most connected - your core abstractions)
1. `MibController (main UI controller)` - 15 edges
2. `+controllers package` - 12 edges
3. `+io/+loaders (concrete loader classes)` - 11 edges
4. `+core package` - 10 edges
5. `MibModel (application state)` - 9 edges
6. `BaseImageLoader (abstract loader base)` - 9 edges
7. `+views/+components (.mlapp panel components)` - 8 edges
8. `+utils/+defaults (default generators)` - 8 edges
9. `Project structure snapshot for mib/` - 8 edges
10. `+io package` - 6 edges

## Surprising Connections (you probably didn't know these)
- `Project structure snapshot for mib/` --references--> `+controllers package`  [EXTRACTED]
  mib/project_structure.txt → mib/mib_structure.txt
- `Project structure snapshot for mib/` --references--> `+core package`  [EXTRACTED]
  mib/project_structure.txt → mib/mib_structure.txt
- `Project structure snapshot for mib/` --references--> `+io package`  [EXTRACTED]
  mib/project_structure.txt → mib/mib_structure.txt
- `Project structure snapshot for mib/` --references--> `+models package`  [EXTRACTED]
  mib/project_structure.txt → mib/mib_structure.txt
- `generatePreferences.m` --references--> `mib3.mat (user preferences file)`  [INFERRED]
  mib/mib_structure.txt → mib/mib3_prefs_override.txt

## Communities (111 total, 27 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.09
Nodes (5): ToggleEventData, MibModel, Calculate, closeWindow, PluginWithoutGUI

### Community 1 - "Community 1"
Cohesion: 0.04
Nodes (52): addAnimationKeyFrame, alphaAxesButtonDown, alphaCurveOperations, cameraListner_Callback, changeSlice, closeWindow, deleteAllAnimationKeyFrames, generateColorMap (+44 more)

### Community 2 - "Community 2"
Cohesion: 0.07
Nodes (26): closeWindow, MeasureTool, ViewListner_Callback2, ApplyButtonPushedCallback, BackupAndUndoPanelCallbacks, Calculate, CategoriesTreeSelectionChanged, closeWindow (+18 more)

### Community 3 - "Community 3"
Cohesion: 0.07
Nodes (3): MibDeep, tif3DFileRead, viewListner_Callback

### Community 5 - "Community 5"
Cohesion: 0.04
Nodes (33): addCallbacks, closeWindow, cropBtn_Callback, cropMaskCheck_Callback, cropModelCheck_Callback, CropObjects, dirEdit_Callback, generate3DPatches_Callback (+25 more)

### Community 6 - "Community 6"
Cohesion: 0.04
Nodes (7): addCallbacksToDatasetImage, addCallbacksToDatasetMask, addCallbacksToDatasetModel, addCallbacksToDatasetRibbon, addCallbacksToDatasetSelection, addCallbacksToDatasetTools, MibRibbon

### Community 8 - "Community 8"
Cohesion: 0.04
Nodes (44): addParentToPath, removeTempDir, setupTempDir, testAttributesPersist, testCreate, testCreate1DArray, testCreate2DArray, testCreateBoolArray (+36 more)

### Community 10 - "Community 10"
Cohesion: 0.05
Nodes (35): addCallbacks, Annotations, annotationTable_CellEditCallback, annotationTable_CellSelectionCallback, annotationTable_KeyPressFcn, closeWindow, deleteBtn_Callback, gui_KeyPressFcn (+27 more)

### Community 14 - "Community 14"
Cohesion: 0.12
Nodes (7): addCallbacks, BatchProcessing, closeWindow, createContextMenus, fitTableColumns, listener_Callbacks, updateWidgets

### Community 16 - "Community 16"
Cohesion: 0.07
Nodes (29): addCallbacks, addFindBtnContextMenus, adjHelpBtn_Callback, applyBtn_Callback, autoHistCheck_Callback, closeWindow, colorChannelCombo_Callback, DisplayAdjust (+21 more)

### Community 17 - "Community 17"
Cohesion: 0.07
Nodes (27): addCallbacks, axesLimitsChanged_Callback, binCheck_Callback, binMagButtons_Callback, closeWindow, crop_Callback, FileFormat_Callback, FileFormatTabGroup_Callback (+19 more)

### Community 18 - "Community 18"
Cohesion: 0.07
Nodes (29): addParentToPath, removeTempDir, setupTempDir, testAttributesPersist, testCreate, testCreateArray, testCreateArrayFromData, testCreateExisting (+21 more)

### Community 19 - "Community 19"
Cohesion: 0.07
Nodes (23): BioFormatsStdLoader, loadImages, loadMetadata, BioFormatsVirtualSetupLoader, loadImages, loadMetadata, initView, loadBioFormatsLibrary (+15 more)

### Community 24 - "Community 24"
Cohesion: 0.14
Nodes (25): ActiveDataset.mlapp, DirectoryContents.mlapp, ImageView.mlapp, MibActiveDataset (active dataset/buffer selector), MibController (main UI controller), MibDirContents (directory browser controller), MibModel (application state), MibQuickAccessBar (quick access toolbar) (+17 more)

### Community 25 - "Community 25"
Cohesion: 0.1
Nodes (15): delete, deletePoolWaitbar, getCancelState, getCurrentIteration, getMaxNumberOfIterations, getText, getWaitbarHandle, increaseMaxNumberOfIterations (+7 more)

### Community 27 - "Community 27"
Cohesion: 0.09
Nodes (21): addCallbacks, closeWindow, deleteBtn_Callback, edgesViewTable_cb, edgesViewTable_CellEditCallback, edgesViewTable_CellSelectionCallback, Lines3dDialog, loadBtn_Callback (+13 more)

### Community 29 - "Community 29"
Cohesion: 0.1
Nodes (20): BioFormatsReader_ValueChanged, closeWindow, Convert, generatePyramidalTIF, generateZarr, getPNGwithoutColormap, helpButton_Callback, ImageConverter (+12 more)

### Community 31 - "Community 31"
Cohesion: 0.1
Nodes (20): axisOrderToLabels, buildViewPort, classMaxInt, colorType, extractAxisOrder, extractAxisUnit, extractMultiscales, extractScaleFromCT (+12 more)

### Community 32 - "Community 32"
Cohesion: 0.1
Nodes (14): create, getAvailableLoaders, AmiraMeshLoader, loadImages, loadMetadata, ImodLoader, loadImages, loadMetadata (+6 more)

### Community 33 - "Community 33"
Cohesion: 0.11
Nodes (13): Accept, closeWindow, disableAugmentations, enableStateChange, help, MibDeepAugmentSettings, previewAugmentations, resetAugmentations (+5 more)

### Community 34 - "Community 34"
Cohesion: 0.11
Nodes (18): buildBytesCodec, buildChunkKeyEncoding, buildCodec, buildTransposeCodec, create, createFromData, dataType, defaultChunkShape (+10 more)

### Community 35 - "Community 35"
Cohesion: 0.11
Nodes (17): addMeasurementsToPlot, clearContents, clearData, computeAngle, computeCircleFit, computeDistance, computeKymograph, computeProfile (+9 more)

### Community 36 - "Community 36"
Cohesion: 0.11
Nodes (17): addCallbacks, captureCropDataPos, closeWindow, cropBtn_Callback, CropDataset, cropToBtn_Callback, editboxes_Callback, helpButton_Callback (+9 more)

### Community 37 - "Community 37"
Cohesion: 0.11
Nodes (17): buttonGroup_Callback, Calculate, canShowWaitbar, closeWindow, continueBtn_Callback, convertDataset, cropDataset, getDialogParent (+9 more)

### Community 38 - "Community 38"
Cohesion: 0.21
Nodes (17): AmiraMeshLoader, +io/+AmiraMesh (Amira mesh utilities), BaseImageLoader (abstract loader base), BioFormatsStdLoader, +io/+BioFormats (BioFormats utilities), ExtensionRegistryLoad (extension-to-loader map), HDF5HeaderLoader, HDF5NoHeaderLoader (+9 more)

### Community 40 - "Community 40"
Cohesion: 0.12
Nodes (15): addROIsToPlot, clearContents, clearData, convertLegacyTypes, crop, findIndexByLabel, getBoundingBox, getNumberOfROI (+7 more)

### Community 41 - "Community 41"
Cohesion: 0.21
Nodes (9): addCallbacks, Alignment, closeWindow, defaultAutomaticOptions, defaultTooltips, findMatchingPairs, updateBatchOptFromGUI, updateWidgets (+1 more)

### Community 42 - "Community 42"
Cohesion: 0.12
Nodes (15): autoPreviewValueChanged, closeWindow, FileListTableContextMenu, helpButton_Callback, MultiRenameTool, pad_numbers_exclude_prefixes, preview, processFileNames (+7 more)

### Community 43 - "Community 43"
Cohesion: 0.14
Nodes (11): HDF5HeaderLoader, loadBigDataViewerFormat, loadImages, loadMetadata, parseXMLHeader, HDF5NoHeaderLoader, loadImages, loadMetadata (+3 more)

### Community 44 - "Community 44"
Cohesion: 0.14
Nodes (11): closeWindow, updateWidgets, ViewListner_Callback, VolRenAppViewer, AmiraImportDlg, initView, onCancel, onContinue (+3 more)

### Community 45 - "Community 45"
Cohesion: 0.14
Nodes (13): changeImage, closeWindow, getActivations, getNewImage, makeCollage, MibDeepActivations, returnBatchOpt, ShiftImage (+5 more)

### Community 46 - "Community 46"
Cohesion: 0.14
Nodes (13): getBoundingBox, getLabelsVariable, getMaterialColors, getMaterialNames, getModelType, getSupportedFormats, MatlabSaver, save (+5 more)

### Community 47 - "Community 47"
Cohesion: 0.14
Nodes (13): addParentToPath, createTestMetadataJson, removeTempDir, setupTempDir, testCreateArray, testCreateWithMismatchedDimensions, testInfo, testInfoFromNonExistentPath (+5 more)

### Community 49 - "Community 49"
Cohesion: 0.15
Nodes (10): addCallbacks, cancelBtn_Callback, checkallBtn_Callback, closeWindow, okBtn_Callback, QuantificationProperties, uncheckallBtn_Callback, updateWidgets (+2 more)

### Community 50 - "Community 50"
Cohesion: 0.15
Nodes (12): addCallbacks, closeWindow, editbox_Callback, helpBtn_Callback, radio_Callback, resampleBtn_Callback, ResampleDataset, returnBatchOpt (+4 more)

### Community 51 - "Community 51"
Cohesion: 0.15
Nodes (12): calculateTransMatrix, initView, onCancel, onContinue, onKeyPress, onMetadataCheck, onReorderDimsCheck, onTableSelection (+4 more)

### Community 53 - "Community 53"
Cohesion: 0.17
Nodes (11): closeWindow, computeMeshVolume, computeSurfaceArea, extractComponent, isClosedMesh, runButton_Callback, selectDirButton_Callback, SurfaceMeasurements (+3 more)

### Community 54 - "Community 54"
Cohesion: 0.17
Nodes (11): buttonGroup_Callback, closeWindow, continueBtn_Callback, convertDataset, cropDataset, GuiTutorial, helpBtn_Callback, invertDataset (+3 more)

### Community 55 - "Community 55"
Cohesion: 0.17
Nodes (11): addCallbacks, applyButton_Callback, BoundingBox, closeButton_Callback, closeWindow, helpButton_Callback, importBtn_Callback, returnBatchOpt (+3 more)

### Community 56 - "Community 56"
Cohesion: 0.18
Nodes (12): Preferences (preferences dialog controller), PreferencesGUI.mlapp, generateKeyShortcuts.m, generateLUT.m, generatePreferences.m, generateSessionSettings.m, initializeImgInfo.m, initializePixSize.m (+4 more)

### Community 57 - "Community 57"
Cohesion: 0.25
Nodes (4): MibVirtualImage, computePermutation, readRegion, Zarr3VirtualLoader

### Community 61 - "Community 61"
Cohesion: 0.2
Nodes (9): create, createArray, createArrayFromData, createGroup, list, listContents, openArray, openGroup (+1 more)

### Community 62 - "Community 62"
Cohesion: 0.31
Nodes (10): Annotations (point annotations), Lines3D (3D lines/skeletons), MibDataset (open dataset container), MibIconCache (icon caching), MibImage (pixel data layer), MibLabels (segmentation labels), MibLabels63 (63-material labels variant), MibUndo (undo/backup history) (+2 more)

### Community 63 - "Community 63"
Cohesion: 0.22
Nodes (5): buildResourceFile, get, getDefaultAssetsDir, getDefaultResourcePath, getIconData

### Community 64 - "Community 64"
Cohesion: 0.22
Nodes (7): Calculate, closeWindow, DemoPlugin, returnBatchOpt, updateBatchOptFromGUI, updateWidgets, ViewListner_Callback2

### Community 65 - "Community 65"
Cohesion: 0.22
Nodes (8): initView, onCancel, onKeyPress, onOK, onSelectionChanged, run, selectModelTypeDlg, updateDescription

### Community 66 - "Community 66"
Cohesion: 0.22
Nodes (4): buildCommonHDFOptions, getSupportedFormats, HDF5Saver, save

### Community 67 - "Community 67"
Cohesion: 0.22
Nodes (9): ChildView (base class for child dialogs), Excluded folders filter (external, assets, jars, plugins, guide), Generated structure report, +models package, Project structure snapshot for mib/, +utils/+deepmib (DeepMIB utilities), +utils/+dlgs (dialog utilities), +utils package (+1 more)

### Community 68 - "Community 68"
Cohesion: 0.25
Nodes (7): clearContents, MibBackup, removeItem, replaceItem, setNumberOfHistorySteps, store, undo

### Community 69 - "Community 69"
Cohesion: 0.25
Nodes (7): defaultLoaderId, ExtensionRegistryLoad, generateKey, getAllowedExtensions, initDefaults, resolveLoader, setAllowedExtensions

### Community 70 - "Community 70"
Cohesion: 0.25
Nodes (7): fetchMetadata, getAttribute, getAttributes, isHttpUrl, joinPath, setAttribute, setAttributes

### Community 72 - "Community 72"
Cohesion: 0.29
Nodes (5): closeWindow, nextTipBtn_Callback, previousTipBtn_Callback, updateWidgets, WelcomeTips

### Community 74 - "Community 74"
Cohesion: 0.33
Nodes (5): BioFormatsVirtualLoader, close, delete, openReader, readPlane

### Community 78 - "Community 78"
Cohesion: 0.4
Nodes (3): getSupportedFormats, ImodContourSaver, save

### Community 79 - "Community 79"
Cohesion: 0.4
Nodes (4): autoDetectModelType, loadImages, loadMetadata, MatModelLoader

### Community 81 - "Community 81"
Cohesion: 0.4
Nodes (4): buildRegistry, create, getDefaultFormat, getFormats

### Community 82 - "Community 82"
Cohesion: 0.4
Nodes (3): getSupportedFormats, save, StlSaver

### Community 83 - "Community 83"
Cohesion: 0.5
Nodes (3): getSupportedFormats, PngSaver, save

### Community 84 - "Community 84"
Cohesion: 0.5
Nodes (3): getSupportedFormats, JpgSaver, save

### Community 85 - "Community 85"
Cohesion: 0.5
Nodes (3): loadImages, loadMetadata, VideoReaderLoader

### Community 86 - "Community 86"
Cohesion: 0.5
Nodes (3): ImreadLoader, loadImages, loadMetadata

### Community 87 - "Community 87"
Cohesion: 0.5
Nodes (3): HDF5VirtualLoader, readRegion, resolveAxisOrder

## Knowledge Gaps
- **798 isolated node(s):** `ViewListner_Callback2`, `findMatchingPairs`, `Alignment`, `updateWidgets`, `addCallbacks` (+793 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **27 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `MibModel (application state)` connect `Community 24` to `Community 38`, `Community 56`, `Community 67`, `Community 62`?**
  _High betweenness centrality (0.001) - this node is a cross-community bridge._
- **Why does `+controllers package` connect `Community 24` to `Community 56`, `Community 67`?**
  _High betweenness centrality (0.000) - this node is a cross-community bridge._
- **Why does `MibController (main UI controller)` connect `Community 24` to `Community 67`?**
  _High betweenness centrality (0.000) - this node is a cross-community bridge._
- **Are the 14 inferred relationships involving `MibController (main UI controller)` (e.g. with `mib3.m (entry point)` and `MibRibbon (ribbon toolbar controller)`) actually correct?**
  _`MibController (main UI controller)` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `MibModel (application state)` (e.g. with `mib3.m (entry point)` and `MibDataset (open dataset container)`) actually correct?**
  _`MibModel (application state)` has 8 INFERRED edges - model-reasoned connections that need verification._
- **What connects `ViewListner_Callback2`, `findMatchingPairs`, `Alignment` to the rest of the system?**
  _798 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._