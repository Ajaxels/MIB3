function Prefs = generatePreferences()
% Prefs = generateDefaultPreferences()
% generate default preferences for MIB
%
% Return values:
% Prefs: a structure with preferences

% %|
% @b Examples:
% @code obj.mibModel.preferences = utils.defaults.generatePreferences();   // generate default preferences for MIB @endcode


%% ----------- USER INTERFACE PANEL -----------
% type of the mouse wheel action, 'scroll': change slices; 'zoom': zoom in/out
Prefs.System.MouseWheel = 'scroll';

% swap the left and right mouse wheel actions, 
% - 'select': pick or draw with the left mouse button; 
% - 'pan': to move the image with the left mouse button
Prefs.System.LeftMouseButton = 'select';

% image resizing method for zooming: 'auto', 'nearest', 'bicubic'
Prefs.System.ImageResizeMethod = 'auto';

% Hold Alt + mouse scroll wheel to change time points (when true)
% Hold Alt + mouse scroll wheel to return back to the slice when Alt+scroll was triggered (when false)
Prefs.System.AltWithScrollWheel = false;

% enable selection with the mouse
Prefs.System.EnableSelection = 1;

% define font structure
Prefs.System.Font.FontName = 'Helvetica';
Prefs.System.Font.FontSize = 12;
Prefs.System.FontSizeDirView = 12;     

% define GUI scaling settings for guide apps
Prefs.System.GUI.scaling = 1;   % scaling factor
Prefs.System.GUI.systemscaling = 1;   % scaling factor for the operating system (on Windows->Screen resolution->Make text and other items larger or smaller->
Prefs.System.GUI.uipanel = 1;   % scaling uipanel
Prefs.System.GUI.uibuttongroup = 1;   % scaling uibuttongroup
Prefs.System.GUI.uitab = 1;   % scaling uitab
Prefs.System.GUI.uitabgroup = 1;   % scaling uitabgroup
Prefs.System.GUI.axes = 1;   % scaling axes
Prefs.System.GUI.uitable = 1;   % scaling uicontrol
Prefs.System.GUI.uicontrol = 1;   % scaling uicontrol

% last used path from previous session
Prefs.System.Dirs.LastPath = '';

% ------- List of recent dirs from where images were loaded
Prefs.System.Dirs.RecentDirs = {};
Prefs.System.Dirs.RecentDirsNumber = 14;

% time in days since the previous update check
Prefs.System.Update.SinceLastCheck = 0; 
% Recheck period for the update, in days
Prefs.System.Update.RecheckPeriod = 30; 

Prefs.System.RenderingEngine = 'Viewer3d, R2022b';   % default rendering engine from R2022b, alternative is "Volshow, R2018b"
% Developer mode
Prefs.System.DeveloperMode = true;   % logical switch to turn on the developer mode, in this mode, the tooltip starts with the handle of the widget

%% ----------- COLORS PANEL -----------

% default colors for the materials of models
Prefs.Colors.ModelMaterialColors = ...
    [0.6510    0.2627    0.1294;
     0.3098    0.4196    0.6706;
     1.0000    0.8000    0.4000;
     0.5882    0.6627    0.8353;
     0.2784    0.6980    0.4941;
     0.1020    0.2000    0.4353];

% Default LUT for color channels
Prefs.Colors.LUTColors = [
    1 0 0     % red
    0 1 0     % green
    0 0 1     % blue
    1 0 1     % purple
    1 1 0     % yellow
    1 .65 0]; % orange

% color for the selection layer
Prefs.Colors.SelectionColor = [0 1 0];

% color for the mask layer
Prefs.Colors.MaskColor = [1 0 1];    % color for the mask layer

% color for annotations, see below in the preferences.SegmTools.Annotations

% Transparency
Prefs.Colors.SelectionTransparency = 0.75;  % Selection layer transparency
Prefs.Colors.MaskTransparency = 0;          % Mask layer transparency
Prefs.Colors.ModelTransparency = 0.75;      % Model layer transparency

% ---------- Contours settings ----------
% fast or slow method for generating contours, 
% in the "performance" method when two objects are touching each other the contour is rendered using color of an earlier material
Prefs.Styles.Contour.ThicknessRendering = 'quality'; % 'performance' or 'quality'
Prefs.Styles.Contour.ThicknessModels = 1;  % thickness of contour lines for materials of the model
Prefs.Styles.Contour.ThicknessMasks = 1;  % thickness of contour lines for masks 
Prefs.Styles.Contour.ThicknessMethodMasks = 'inwards';  % mode for making the thicker contours, 'inwards' and 'outwards'

Prefs.Styles.Masks.ShowAsContours = true;  % show masks as contours, when false as filled shapes

%% ----------- BACKUP AND UNDO PANEL -----------

% enable undo
Prefs.Undo.Enable = 1;

% total number of steps for the Undo history
Prefs.Undo.MaxUndoHistory = 8;

% number of steps for the Undo history for whole dataset
Prefs.Undo.Max3dUndoHistory = 3;

%% ----------- EXTERNAL DIRECTORIES PANEL -----------
% these paths should be updated on each workstation individually
Prefs.ExternalDirs.FijiInstallationPath = [];       % Fiji
Prefs.ExternalDirs.OmeroInstallationPath = [];      % Omero
Prefs.ExternalDirs.ImarisInstallationPath = [];     % Imaris
Prefs.ExternalDirs.bm3dInstallationPath = [];       % BM3D
Prefs.ExternalDirs.bm4dInstallationPath = [];       % BM4D
Prefs.ExternalDirs.DeepMIBDir = tempdir;            % DeepMIB network architectures
Prefs.ExternalDirs.PythonInstallationPath = [];     % DeepMIB network architectures
Prefs.ExternalDirs.BioFormatsMemoizerMemoDir = [];  % Bioformats Memoizer
% setting up directory for memoizer
Prefs.ExternalDirs.BioFormatsMemoizerMemoDir = fullfile(tempdir, 'mibVirtual'); 
% override default directory to c:\temp to easier find it later
if ispc
    if isfolder('c:\temp')
        if ~isfolder('c:\temp\mibVirtual')
            try
                mkdir('c:\temp\mibVirtual');
                Prefs.ExternalDirs.BioFormatsMemoizerMemoDir = 'c:\temp\mibVirtual';
            catch
                
            end
        else
            Prefs.ExternalDirs.BioFormatsMemoizerMemoDir = 'c:\temp\mibVirtual';
        end
    end
else
    Prefs.ExternalDirs.BioFormatsMemoizerMemoDir = fullfile(tempdir, 'mibVirtual');
    if ~isfolder(Prefs.ExternalDirs.BioFormatsMemoizerMemoDir)
        mkdir(Prefs.ExternalDirs.BioFormatsMemoizerMemoDir);
    end
end

%% ----------- KEY SHORTCUTS PANEL -----------
Prefs.KeyShortcuts = utils.defaults.generateKeyShortcuts();

%% ----------- SEGMENTATION TOOLS PANEL -------

% ---------- Annotations ----------
% Annotations color
Prefs.SegmTools.Annotations.Color = [1 1 0];
% Annotations font size
Prefs.SegmTools.Annotations.FontSize = 2;
Prefs.SegmTools.Annotations.ShownExtraDepth = 0;    % show annotation of previous and following slices, when above 0
Prefs.SegmTools.Annotations.FocusOnValue = false;    % focus on value when entering annotations
Prefs.SegmTools.Annotations.Precision = 3;    % precision of annotation values, an integer from 0 and above
Prefs.SegmTools.Annotations.DisplayAs = 'Label + Value';    % default visualization of annotations

% ---------- Interpolation ----------
% Interpolation type
Prefs.SegmTools.Interpolation.Type = 'shape';     % 'shape', 'line'
% Interpolation number of points
Prefs.SegmTools.Interpolation.NoPoints = 200;
% Interpolation line width for the line type
Prefs.SegmTools.Interpolation.LineWidth = 4;

% ---------- Previous segmentation tool ----------
% fast access to the selection type tools with the 'd' shortcut
Prefs.SegmTools.PreviousTool = [3, 4];

% ----------  Brush tool   ----------
% Brush eraser factor
Prefs.SegmTools.Brush.EraserRadiusFactor = 1.6;

% ---------- Superpixels preferences ----------
Prefs.SegmTools.Superpixels.NoWatershed = 15;
Prefs.SegmTools.Superpixels.InvertWatershed = 1;
Prefs.SegmTools.Superpixels.NoSLIC = 230;
Prefs.SegmTools.Superpixels.CompactSLIC = 99;

% ---------- Segment-anything preferences ----------
Prefs.SegmTools.SAM.samVersion = 'SAM 2'; % use "SAM 1" or "SAM 2"
Prefs.SegmTools.SAM.linksFile = ['assets', filesep, 'sam_links.json'];     % location of sam_links.json file with SAM links settings, relative to MIB path!
Prefs.SegmTools.SAM.backbone = 'vit_b (0.4Gb)';     % 'vit_h (2.5Gb)', 'vit_l (1.2Gb)', 'vit_b (0.4Gb)'
Prefs.SegmTools.SAM.environment = 'cuda';     % 'cuda', 'cpu'
Prefs.SegmTools.SAM.points_per_side = 32;
Prefs.SegmTools.SAM.points_per_batch = 64;
Prefs.SegmTools.SAM.pred_iou_thresh =  0.88;
Prefs.SegmTools.SAM.stability_score_thresh = 0.95;
Prefs.SegmTools.SAM.box_nms_thresh = 0.7;
Prefs.SegmTools.SAM.crop_n_layers = 0;
Prefs.SegmTools.SAM.crop_nms_thresh = 0.7;
Prefs.SegmTools.SAM.crop_overlap_ratio = 0.3413; % 512/1500
Prefs.SegmTools.SAM.crop_n_points_downscale_factor = 1;
% Prefs.SegmTools.SAM.point_grids: Optional[List[np.ndarray]] = None;
Prefs.SegmTools.SAM.min_mask_region_area = 0;
% The form masks are returned in. Can be 'binary_mask', 'uncompressed_rle', or 'coco_rle'. 
% 'coco_rle' requires pycocotools. For large resolutions, 'binary_mask' may consume 
% large amounts of memory
% Prefs.SegmTools.SAM.output_mode = "binary_mask";
Prefs.SegmTools.SAM.sam_installation_path = [];
Prefs.SegmTools.SAM.showProgressBar = false;     % show or not the progress bar dialog when doing SAM segmentation with points

% define separate settings for SAM2
Prefs.SegmTools.SAM2.linksFile = ['assets', filesep, 'sam2_links.json'];     % location of sam_links.json file with SAM links settings, relative to MIB path!
Prefs.SegmTools.SAM2.backbone = 'sam2_hiera_t (0.15Gb)';     % 'sam2_hiera_t (0.15Gb), sam2_hiera_s (0.18Gb), sam2_hiera_base_plus (0.32Gb), sam2_hiera_l (0.90Gb)'
Prefs.SegmTools.SAM2.environment = 'cuda';     % 'cuda', 'cpu'
Prefs.SegmTools.SAM2.sam_installation_path = [];
Prefs.SegmTools.SAM2.showProgressBar = false;     

Prefs.SegmTools.SAM2.points_per_side = 32;
Prefs.SegmTools.SAM2.points_per_batch = 64;
Prefs.SegmTools.SAM2.pred_iou_thresh = 0.8;
Prefs.SegmTools.SAM2.stability_score_thresh = 0.95;
Prefs.SegmTools.SAM2.stability_score_offset = 1.0;
Prefs.SegmTools.SAM2.crop_n_layers = 0;
Prefs.SegmTools.SAM2.box_nms_thresh = 0.7;
Prefs.SegmTools.SAM2.crop_n_points_downscale_factor = 1;
Prefs.SegmTools.SAM2.min_mask_region_area = 0;
Prefs.SegmTools.SAM2.use_m2m = false;

% ------------- Presets -------------
Prefs.SegmTools.Presets.Annotations.Set1.ShowPrompt = true;
Prefs.SegmTools.Presets.Annotations.Set1.FocusOnValue = false;
Prefs.SegmTools.Presets.Annotations.Set1.Size = 2;     % '1 (pt 8)', '2 (pt 10)', '3 (pt 12)', '4 (pt 14)', '5 (pt 16)', '6 (pt 18)', '7 (pt 20)'
Prefs.SegmTools.Presets.Annotations.Set1.Color = [1 1 0];
Prefs.SegmTools.Presets.Annotations.Set1.ExtraSlices = 0;
Prefs.SegmTools.Presets.Annotations.Set1.DisplayAs = 'Label + Value'; % 'Label + Value', 'Marker', 'Label', 'Value'
Prefs.SegmTools.Presets.Annotations.Set2.ShowPrompt = true;
Prefs.SegmTools.Presets.Annotations.Set2.FocusOnValue = false;
Prefs.SegmTools.Presets.Annotations.Set2.Size = 4;
Prefs.SegmTools.Presets.Annotations.Set2.Color = [1 1 0];
Prefs.SegmTools.Presets.Annotations.Set2.ExtraSlices = 0;
Prefs.SegmTools.Presets.Annotations.Set2.DisplayAs = 'Label + Value'; % 'Label + Value', 'Marker', 'Label', 'Value'
Prefs.SegmTools.Presets.Annotations.Set3.ShowPrompt = true;
Prefs.SegmTools.Presets.Annotations.Set3.FocusOnValue = false;
Prefs.SegmTools.Presets.Annotations.Set3.Size = 7;
Prefs.SegmTools.Presets.Annotations.Set3.Color = [1 1 0];
Prefs.SegmTools.Presets.Annotations.Set3.ExtraSlices = 0;
Prefs.SegmTools.Presets.Annotations.Set3.DisplayAs = 'Label + Value'; % 'Label + Value', 'Marker', 'Label', 'Value'

Prefs.SegmTools.Presets.Lines3D.Set1.Click = 'Add node';
Prefs.SegmTools.Presets.Lines3D.Set1.ShiftClick = 'New tree';
Prefs.SegmTools.Presets.Lines3D.Set1.CtrlClick = 'Assign active node';
Prefs.SegmTools.Presets.Lines3D.Set1.AltClick = 'Modify active node';
Prefs.SegmTools.Presets.Lines3D.Set2.Click = 'Add node';
Prefs.SegmTools.Presets.Lines3D.Set2.ShiftClick = 'New tree';
Prefs.SegmTools.Presets.Lines3D.Set2.CtrlClick = 'Assign active node';
Prefs.SegmTools.Presets.Lines3D.Set2.AltClick = 'Modify active node';
Prefs.SegmTools.Presets.Lines3D.Set3.Click = 'Add node';
Prefs.SegmTools.Presets.Lines3D.Set3.ShiftClick = 'New tree';
Prefs.SegmTools.Presets.Lines3D.Set3.CtrlClick = 'Assign active node';
Prefs.SegmTools.Presets.Lines3D.Set3.AltClick = 'Modify active node';

Prefs.SegmTools.Presets.Brush.Set1.Radius = '2';
Prefs.SegmTools.Presets.Brush.Set1.Watershed = false;
Prefs.SegmTools.Presets.Brush.Set1.SLIC = false;
Prefs.SegmTools.Presets.Brush.Set1.Eraser = '1.5';
Prefs.SegmTools.Presets.Brush.Set2.Radius = '8';
Prefs.SegmTools.Presets.Brush.Set2.Watershed = false;
Prefs.SegmTools.Presets.Brush.Set2.SLIC = false;
Prefs.SegmTools.Presets.Brush.Set2.Eraser = '1.5';
Prefs.SegmTools.Presets.Brush.Set3.Radius = '50';
Prefs.SegmTools.Presets.Brush.Set3.Watershed = false;
Prefs.SegmTools.Presets.Brush.Set3.SLIC = false;
Prefs.SegmTools.Presets.Brush.Set3.Eraser = '1.5';

Prefs.SegmTools.Presets.BWThresholding.Set1.Adaptive = false;
Prefs.SegmTools.Presets.BWThresholding.Set1.BlackOnWhite = 'black-on-white';
Prefs.SegmTools.Presets.BWThresholding.Set1.Switch3D = false;
Prefs.SegmTools.Presets.BWThresholding.Set1.Invert = false;
Prefs.SegmTools.Presets.BWThresholding.Set1.ParameterLo = '0';
Prefs.SegmTools.Presets.BWThresholding.Set1.ParameterHi = '255';
Prefs.SegmTools.Presets.BWThresholding.Set1.SliderStep = 3;
Prefs.SegmTools.Presets.BWThresholding.Set2.Adaptive = false;
Prefs.SegmTools.Presets.BWThresholding.Set2.BlackOnWhite = 'black-on-white';
Prefs.SegmTools.Presets.BWThresholding.Set2.Switch3D = false;
Prefs.SegmTools.Presets.BWThresholding.Set2.Invert = false;
Prefs.SegmTools.Presets.BWThresholding.Set2.ParameterLo = '0';
Prefs.SegmTools.Presets.BWThresholding.Set2.ParameterHi = '128';
Prefs.SegmTools.Presets.BWThresholding.Set2.SliderStep = 3;
Prefs.SegmTools.Presets.BWThresholding.Set3.Adaptive = false;
Prefs.SegmTools.Presets.BWThresholding.Set3.BlackOnWhite = 'black-on-white';
Prefs.SegmTools.Presets.BWThresholding.Set3.Switch3D = false;
Prefs.SegmTools.Presets.BWThresholding.Set3.Invert = false;
Prefs.SegmTools.Presets.BWThresholding.Set3.ParameterLo = '128';
Prefs.SegmTools.Presets.BWThresholding.Set3.ParameterHi = '255';
Prefs.SegmTools.Presets.BWThresholding.Set3.SliderStep = 3;

Prefs.SegmTools.Presets.DragNDrop.Set1.Shift= '1';
Prefs.SegmTools.Presets.DragNDrop.Set1.Layer= 'selection'; % 'selection', 'mask', 'model'
Prefs.SegmTools.Presets.DragNDrop.Set2.Shift= '4';
Prefs.SegmTools.Presets.DragNDrop.Set2.Layer= 'selection';
Prefs.SegmTools.Presets.DragNDrop.Set3.Shift= '10';
Prefs.SegmTools.Presets.DragNDrop.Set3.Layer= 'selection';

Prefs.SegmTools.Presets.MagicWand.Set1.Method= 'Magic Wand'; % 'Magic Wand' or 'Region Grow'
Prefs.SegmTools.Presets.MagicWand.Set1.VariationLo = '6';
Prefs.SegmTools.Presets.MagicWand.Set1.VariationHi = '6';
Prefs.SegmTools.Presets.MagicWand.Set1.Radius = '0';
Prefs.SegmTools.Presets.MagicWand.Set1.Connect = 8; % 8 or 4
Prefs.SegmTools.Presets.MagicWand.Set2.Method = 'Magic Wand'; % 'Magic Wand' or 'Region Grow'
Prefs.SegmTools.Presets.MagicWand.Set2.VariationLo = '12';
Prefs.SegmTools.Presets.MagicWand.Set2.VariationHi = '12';
Prefs.SegmTools.Presets.MagicWand.Set2.Radius = '0';
Prefs.SegmTools.Presets.MagicWand.Set2.Connect = 8; % 8 or 4
Prefs.SegmTools.Presets.MagicWand.Set3.Method = 'Region Grow'; % 'Magic Wand' or 'Region Grow'
Prefs.SegmTools.Presets.MagicWand.Set3.VariationLo = '24';
Prefs.SegmTools.Presets.MagicWand.Set3.VariationHi = '24';
Prefs.SegmTools.Presets.MagicWand.Set3.Radius = '0';
Prefs.SegmTools.Presets.MagicWand.Set3.Connect = 8; % 8 or 4

Prefs.SegmTools.Presets.MembraClickTracker.Set1.Scale = '0.2';
Prefs.SegmTools.Presets.MembraClickTracker.Set1.Width = '2';
Prefs.SegmTools.Presets.MembraClickTracker.Set1.StraightLine = false;
Prefs.SegmTools.Presets.MembraClickTracker.Set1.BlackSignal = true;
Prefs.SegmTools.Presets.MembraClickTracker.Set1.RecenterView= true;
Prefs.SegmTools.Presets.MembraClickTracker.Set2.Scale = '0.2';
Prefs.SegmTools.Presets.MembraClickTracker.Set2.Width = '4';
Prefs.SegmTools.Presets.MembraClickTracker.Set2.StraightLine = false;
Prefs.SegmTools.Presets.MembraClickTracker.Set2.BlackSignal = true;
Prefs.SegmTools.Presets.MembraClickTracker.Set2.RecenterView= true;
Prefs.SegmTools.Presets.MembraClickTracker.Set3.Scale = '0.2';
Prefs.SegmTools.Presets.MembraClickTracker.Set3.Width = '4';
Prefs.SegmTools.Presets.MembraClickTracker.Set3.StraightLine = true;
Prefs.SegmTools.Presets.MembraClickTracker.Set3.BlackSignal = true;
Prefs.SegmTools.Presets.MembraClickTracker.Set3.RecenterView= true;

Prefs.SegmTools.Presets.SAM.Set1.Method = 'Interactive';
Prefs.SegmTools.Presets.SAM.Set1.Dataset = '2D, Slice'; % '2D, Slice', '3D, Stack', 4D, Dataset'
Prefs.SegmTools.Presets.SAM.Set1.Destination = 'selection'; % 'selection', 'mask', 'model'
Prefs.SegmTools.Presets.SAM.Set1.Mode = 'replace'; % 'replace', 'add', 'subtract', 'add, +next material'
Prefs.SegmTools.Presets.SAM.Set2.Method = 'Interactive';
Prefs.SegmTools.Presets.SAM.Set2.Dataset = '3D, Stack'; % '2D, Slice', '3D, Stack', 4D, Dataset'
Prefs.SegmTools.Presets.SAM.Set2.Destination = 'model'; % 'selection', 'mask', 'model'
Prefs.SegmTools.Presets.SAM.Set2.Mode = 'add'; % 'replace', 'add', 'subtract', 'add, +next material'
Prefs.SegmTools.Presets.SAM.Set3.Method = 'Landmarks';
Prefs.SegmTools.Presets.SAM.Set3.Dataset = '3D, Stack'; % '2D, Slice', '3D, Stack', 4D, Dataset'
Prefs.SegmTools.Presets.SAM.Set3.Destination = 'selection'; % 'selection', 'mask', 'model'
Prefs.SegmTools.Presets.SAM.Set3.Mode = 'replace'; % 'replace', 'add', 'subtract', 'add, +next material'

% two favorite tools available via Ctrl+D and Shift+D key shortcuts
Prefs.SegmTools.FavoriteToolA = 'Brush';    % Shift+D, one of tools within the Segmentation panel
Prefs.SegmTools.FavoriteToolB = 'Segment-anything model'; % Ctrl+D, one of tools within the Segmentation panel

%% -------------  IMAGE PROCESSING TOOLS ----------

% ---------  Image Arithmetics ---------------------
% a cell array with the recent image arithmetic functions
Prefs.ImageArithmetic.Actions = {'I = I*2'};
% a cell array with the input variables for the corresponding operation
Prefs.ImageArithmetic.InputVars = {'I'};
% a cell array with the output variables for the corresponding operation
Prefs.ImageArithmetic.OutputVars = {'I'};
% Number of stored actions
Prefs.ImageArithmetic.NoStoredActions = 10;

%% ------------- VolRen -------------
Prefs.VolRen.Viewer.backgroundColor = [0 0.329 0.529]; 
Prefs.VolRen.Viewer.gradientColor = [0 0.561 1];
Prefs.VolRen.Viewer.backgroundGradient = 'on';
Prefs.VolRen.Viewer.lighting = 'on';
Prefs.VolRen.Viewer.lightColor = [1 1 1];
Prefs.VolRen.Viewer.showScaleBar = true;
Prefs.VolRen.Viewer.scaleBarUnits = 'um';
Prefs.VolRen.Viewer.showOrientationAxes = true;
Prefs.VolRen.Viewer.showBox = true;
Prefs.VolRen.Viewer.AmbientLight = 0.4;
Prefs.VolRen.Viewer.DiffuseLight = 0.4;

% 'orbit' - rotation is done around the center of the volume
% 'cursor' - rotation around the clicked object
Prefs.VolRen.Viewer.rotationMode = 'orbit'; 

Prefs.VolRen.Volume.renderer = 'VolumeRendering';
Prefs.VolRen.Volume.gradientOpacityValue = 0.3;
Prefs.VolRen.Volume.volumeAlphaCurve.x = [0 .3 .7 1];
Prefs.VolRen.Volume.volumeAlphaCurve.y = [1 1 0 0];
Prefs.VolRen.Volume.isosurfaceValue = 0.5;
Prefs.VolRen.Volume.colormapName = 'gray';
Prefs.VolRen.Volume.colormapInvert = true;
Prefs.VolRen.Volume.colormapBlackPoint = 0;
Prefs.VolRen.Volume.colormapWhitePoint = 255;
Prefs.VolRen.Volume.markerSize = 15;

Prefs.VolRen.Animation.noFrames = 120;  % default number of frames
Prefs.VolRen.Animation.animationPath = struct();

%% ------------- DeepMIB -------------
Prefs.Deep.OriginalTrainingImagesDir = '';
Prefs.Deep.OriginalPredictionImagesDir = '';
Prefs.Deep.ImageFilenameExtension = {'AM'};
Prefs.Deep.ResultingImagesDir = '';
Prefs.Deep.CompressProcessedImages = false;
Prefs.Deep.CompressProcessedModels = true;
Prefs.Deep.ValidationFraction = 0.25;
Prefs.Deep.MiniBatchSize = 1;
Prefs.Deep.RandomGeneratorSeed = 2;
Prefs.Deep.RelativePaths = false;

Prefs.Deep.TrainingOpt.solverName = 'adam';
Prefs.Deep.TrainingOpt.MaxEpochs = 500;
Prefs.Deep.TrainingOpt.Shuffle = 'every-epoch';
Prefs.Deep.TrainingOpt.InitialLearnRate = 0.001;
Prefs.Deep.TrainingOpt.LearnRateSchedule = 'piecewise';
Prefs.Deep.TrainingOpt.LearnRateDropPeriod = 50;
Prefs.Deep.TrainingOpt.LearnRateDropFactor = 0.9;
Prefs.Deep.TrainingOpt.L2Regularization = 0.0001;
Prefs.Deep.TrainingOpt.Momentum = 0.9;
Prefs.Deep.TrainingOpt.GradientDecayFactor = 0.9;    % new in version 2.71
Prefs.Deep.TrainingOpt.SquaredGradientDecayFactor = 0.999; % new in version 2.71
Prefs.Deep.TrainingOpt.ValidationFrequency = 0.2;
Prefs.Deep.TrainingOpt.ValidationPatience = Inf;   % new in version 2.71
Prefs.Deep.TrainingOpt.Plots = 'training-progress';  
Prefs.Deep.TrainingOpt.OutputNetwork = 'last-iteration';     % new in v 2.82, requires R2021b
Prefs.Deep.TrainingOpt.CheckpointFrequency = 200;              % new in v 2.83, requires R2022a

Prefs.Deep.InputLayerOpt.Normalization = 'none';
Prefs.Deep.InputLayerOpt.Mean = [];
Prefs.Deep.InputLayerOpt.StandardDeviation = [];
Prefs.Deep.InputLayerOpt.Min = [];
Prefs.Deep.InputLayerOpt.Max = [];

Prefs.Deep.ActivationLayerOpt.clippedReluLayer.Ceiling = 10;
Prefs.Deep.ActivationLayerOpt.leakyReluLayer.Scale = 0.01;
Prefs.Deep.ActivationLayerOpt.eluLayer.Alpha = 1;

Prefs.Deep.SegmentationLayerOpt.focalLossLayer.Alpha = 0.25;
Prefs.Deep.SegmentationLayerOpt.focalLossLayer.Gamma = 2;
Prefs.Deep.SegmentationLayerOpt.dicePixelCustom.ExcludeExerior = false;     % exclude exterior class from calculation of the loss function

Prefs.Deep.AugOpt2D = utils.deepmib.generateDefaultAugmentations('2D');
Prefs.Deep.AugOpt3D = utils.deepmib.generateDefaultAugmentations('3D');

Prefs.Deep.ScoreExportOpt.Precision = 8;   % define precision for the output scores, '8' or '16' bit
Prefs.Deep.ScoreExportOpt.IncludeExterior = true;  % when false scores for exterior material are excluded from file output

Prefs.Deep.DynamicMaskOpt.Method = 'Keep above threshold';  % 'Keep above threshold' or 'Keep below threshold'
Prefs.Deep.DynamicMaskOpt.ThresholdValue = 0;
Prefs.Deep.DynamicMaskOpt.InclusionThreshold = 0;     % Inclusion threshold for mask blocks

Prefs.Deep.Metrics.Accuracy = true;  % parameters for metrics evaluation
Prefs.Deep.Metrics.BFscore = false;
Prefs.Deep.Metrics.GlobalAccuracy = true;
Prefs.Deep.Metrics.IOU = true;
Prefs.Deep.Metrics.WeightedIOU = true; 

% Settings for sending 
Prefs.Deep.SendReports.T_SendReports = false;   % main switch send or not the reports
Prefs.Deep.SendReports.TO_email = 'user@gmail.com';
Prefs.Deep.SendReports.SMTP_server = 'smtp-relay.brevo.com';
Prefs.Deep.SendReports.SMTP_port = '587';
Prefs.Deep.SendReports.SMTP_auth = true;
Prefs.Deep.SendReports.SMTP_starttls = true;
Prefs.Deep.SendReports.SMTP_username = 'user@gmail.com';
Prefs.Deep.SendReports.SMTP_password = '';
Prefs.Deep.SendReports.sendWhenFinished = false;
Prefs.Deep.SendReports.sendDuringRun = false;

%% ----------- TIP OF THE DAY --------------
% index of the next tip to show
Prefs.Tips.CurrentTipIndex = 1;

% show or not the tips during startup
Prefs.Tips.ShowTips = false;

% List of files with tips, have to be initiated on the target workstation
Prefs.Tips.Files = [];

%%  ----------- USER SETTINGS --------------
Prefs.Users.Tiers.logStartDate = datetime('now');
Prefs.Users.Tiers.collectedPoints = 0;    % user points accumulated to unlock tiers in MIB
Prefs.Users.Tiers.mouseTravelDistance = 0;    % in meters, movement of mouse over the screen without painting in meters, directly translated into points
Prefs.Users.Tiers.brushTravelDistance = 0;    % in meters, movement of mouse during use of brush tool, translated into points as distance x10
Prefs.Users.Tiers.tierLevel = 1;

% specific tools counts
Prefs.Users.Tiers.numberOfLoadedDatasets = 0;   
Prefs.Users.Tiers.numberOfImageFilterings = 0;  
Prefs.Users.Tiers.numberOfBatchProcessings = 0; 
Prefs.Users.Tiers.numberOfSnapAndMovies = 0; 
Prefs.Users.Tiers.numberOfBall3D = 0;   
Prefs.Users.Tiers.numberOfLine3D = 0;   
Prefs.Users.Tiers.numberOfAnnotations = 0; 
Prefs.Users.Tiers.numberOfBWThresholdings = 0; 
Prefs.Users.Tiers.numberOfDragDropMaterials = 0;    
Prefs.Users.Tiers.numberOfLassos = 0;   
Prefs.Users.Tiers.numberOfMagicWands = 0; 
Prefs.Users.Tiers.numberOfObjectPickers = 0;    
Prefs.Users.Tiers.numberOfMembraneClickTrackers = 0; 
Prefs.Users.Tiers.numberOfSAMclicks = 0;    
Prefs.Users.Tiers.numberOfSpots = 0;    
Prefs.Users.Tiers.numberOfGraphcuts = 0;    
Prefs.Users.Tiers.numberOfTrainedDeepNetworks = 0; 
Prefs.Users.Tiers.numberOfInferencedDeepNetworks = 0; 
Prefs.Users.Tiers.numberOfMeasurements = 0; 
Prefs.Users.Tiers.numberOfGetStats = 0;    
Prefs.Users.Tiers.numberOfKeyShortcuts = 0; % key shortcuts

Prefs.Users.singleToolScores = 0.5;   % score awarded for a single standard tool use (i.e. Ball3D or spot)
Prefs.Users.tierPointsCoef = 500;  % for points calculations, as nextTier = tierPointsCoef * 2^[userTier];
% requires to move brush for
% (500*2^1)/10 meters to reach level 2, i.e. 1 brush meter is equeal to 10 mouse move meters
% requires to move mouse for (500*2^1)/1 meters to reach level 2
Prefs.Users.tierLevelRanks = {...
    '1 - Microbe Enthusiast', ...
    '2 - Bacterial Boss', ...
    '3 - Organelle Magician', ...
    '4 - Mitochondria Navigator', ...
    '5 - Nucleus Ninja', ...
    '6 - Synapse Surfer', ...
    '7 - Cell Explorer', ...
    '8 - Magnification Maestro', ...
    '9 - Microscopy Mastermind', ...
    '10 - MIB Guru' };

%% ------------  SAVE TO MAT FILE   ------------
% outputPath = fileparts(which('mib3.m'));
% outputPath = fullfile(outputPath, 'assets', 'mibDefaultPrefs.mat');
% save(outputPath, 'Prefs');

end