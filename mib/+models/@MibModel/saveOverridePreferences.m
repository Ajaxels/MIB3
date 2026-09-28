function numberOfSettings = saveOverridePreferences(obj, filename)
% SAVEOVERRIDEPREFERENCES - Save the current preferences as a JSON override file for new users.
%
% Syntax:
%   .. code-block:: matlab
%
%      numberOfSettings = obj.saveOverridePreferences(filename)
%
% Writes the settings of the current session that differ from the MIB defaults
% (:func:`utils.defaults.generatePreferences`) into a JSON file. Saved in the MIB
% program folder as ``mib3_prefs_override.json`` or
% ``mib3_prefs_override_<COMPUTERNAME>.json``, the file is picked up by
% :func:`models.MibModel.initializePreferences` on the first start of every user who
% does not yet have ``mib3.mat``, so new users of a workstation start from the
% settings configured here instead of from the MIB defaults.
%
% Only the differences are written, which makes the file a *partial* override: a
% setting missing from it keeps the MIB default, including defaults changed by later
% MIB releases. A leaf is compared with ``isequaln``; vectors (colors, key shortcuts)
% and cell arrays are written whole when any element differs, and a struct whose
% default has no fields (``DoNotShowDialogs``) is written whole as well.
%
% Left out regardless of their value, because they are the state or history of the
% person who generates the file rather than settings of the workstation:
%
%   - ``Users`` - statistics and tier definitions
%   - ``System.Dirs.LastPath``, ``System.Dirs.RecentDirs``,
%     ``System.Update.SinceLastCheck``
%   - ``System.UserStatsProfile``, ``System.UserStatsPromptShown`` - every user keeps
%     their own statistics and is asked once where to store them
%   - ``Tips.Files``, ``Tips.CurrentTipIndex``
%   - ``ImageArithmetic.Actions``, ``.InputVars``, ``.OutputVars``
%   - ``VolRen.Animation.animationPath``
%   - ``Deep.OriginalTrainingImagesDir``, ``Deep.OriginalPredictionImagesDir``,
%     ``Deep.ResultingImagesDir``
%   - ``Deep.SendReports.SMTP_password`` - the file is readable by every user
%
% Fields of the current preferences that the defaults do not have (left over from an
% older MIB) are not written either.
%
% File layout:
%
% .. code-block:: json
%
%    {
%      "_comment": ["what the file is and how it is used", "..."],
%      "mibVersion": 2026.09,
%      "preferences": {
%        "System": {
%          "_comment": {"MouseWheel": "'scroll' - the wheel changes slices; 'zoom' - ..."},
%          "MouseWheel": "zoom"
%        }
%      }
%    }
%
% Every struct gets a ``"_comment"`` object, keyed by the names of its own fields,
% describing the settings written next to it and their allowed values; a struct
% without any described field gets none. ``jsondecode`` reads the key back as
% ``x_comment``, and ``initializePreferences`` drops it. The descriptions live in the
% local function ``preferenceComments`` at the end of this file: when a preference
% with a restricted set of values is added to ``generatePreferences``, describe it
% there as well. A missing description is harmless, the setting is written without.
%
% JSON has no ``Inf``/``NaN``: ``jsonencode`` would write ``null``, which reads back as
% ``[]``. A non-finite element of a numeric scalar or vector is therefore written as
% the string ``"Inf"``, ``"-Inf"`` or ``"NaN"``, which ``initializePreferences``
% converts back. Non-finite values inside a 2-D matrix are not handled; no preference
% has them. Numeric and logical vectors are collapsed onto one line for readability.
%
% Colors - numeric settings whose name ends with ``Color`` or ``Colors``
% (``Colors.ModelMaterialColors``, ``Colors.SelectionColor``,
% ``VolRen.Viewer.backgroundColor``, ...) - are rounded to 3 decimals. The comparison
% with the default is made before rounding. A step of an 8-bit color channel is
% 1/255 = 0.0039, so the rounding is invisible, while a random material color would
% otherwise be written with 17 significant digits.
%
% ``Colors.ModelMaterialColors`` is written with at most 255 rows. Opening the
% Preferences dialog copies the colors of the current dataset into preferences, and
% a 63-bit model carries 65535 of them, randomly generated; the dialog shows and edits
% only the first 255, and a model with more materials than colors gets the missing
% ones generated anyway.
%
% Input Arguments:
%   - **filename** - [char] full path of the JSON file to write
%
% Output Arguments:
%   - **numberOfSettings** - [double] number of settings written to the file, 0 when
%     the current preferences match the defaults; the file is written in that case too
%
% Usage:
%   **Example 1** - save an override file for all workstations using this MIB installation
%
%   .. code-block:: matlab
%
%      obj.mibModel.saveOverridePreferences(fullfile(obj.mibModel.mibPath, 'mib3_prefs_override.json'));
%
% See also: models.MibModel.initializePreferences, utils.defaults.generatePreferences

arguments (Input)
    obj models.MibModel
    filename (1,:) char
end

excludedSettings = {'Users', ...
    'System.Dirs.LastPath', 'System.Dirs.RecentDirs', 'System.Update.SinceLastCheck', ...
    'System.UserStatsProfile', 'System.UserStatsPromptShown', ...
    'Tips.Files', 'Tips.CurrentTipIndex', ...
    'ImageArithmetic.Actions', 'ImageArithmetic.InputVars', 'ImageArithmetic.OutputVars', ...
    'VolRen.Animation.animationPath', ...
    'Deep.OriginalTrainingImagesDir', 'Deep.OriginalPredictionImagesDir', 'Deep.ResultingImagesDir', ...
    'Deep.SendReports.SMTP_password'};

defaultPreferences = utils.defaults.generatePreferences();
comments = preferenceComments();
[changedPreferences, numberOfSettings] = collectChanges(obj.preferences, defaultPreferences, '', ...
    excludedSettings, comments);

overrideFile = struct();
overrideFile.x_comment = {
    sprintf('MIB preferences override file, generated by MIB %s on %s at %s', ...
        obj.mibVersion, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')), utils.identifyComputerName())
    'The settings below replace the MIB defaults when MIB starts for the first time for a user who does not have mib3.mat yet'
    'Settings that are not listed keep their MIB default value; remove the lines of the settings that should not be overridden'
    'Location: the folder with mib3.m (MIB for MATLAB) or the installation folder (standalone MIB)'
    'Name: mib3_prefs_override.json - for all computers using this MIB installation; mib3_prefs_override_COMPUTERNAME.json - for one computer only'
    'The _comment entries are ignored by MIB, they describe the neighbouring settings and their allowed values'
    'Non-finite numbers are written as the strings "Inf", "-Inf" and "NaN"'};
overrideFile.mibVersion = utils.getMibVersionNumberic(obj.mibVersion);
overrideFile.preferences = changedPreferences;

jsonText = jsonencode(overrideFile, 'PrettyPrint', true);
% a struct field cannot start with an underscore, restore the intended key name
jsonText = strrep(jsonText, '"x_comment":', '"_comment":');
% put numeric and logical vectors on a single line: "[1, 1, 0]" instead of 5 lines
numberPattern = '(?:-?\d[\d.eE+-]*|true|false|"-?Inf"|"NaN")';
[textParts, vectorParts] = regexp(jsonText, ['\[\s*' numberPattern '(?:,\s*' numberPattern ')*\s*\]'], 'split', 'match');
vectorParts = cellfun(@(vectorText) strrep(regexprep(vectorText, '\s+', ''), ',', ', '), vectorParts, 'UniformOutput', false);
textParts = [textParts; [vectorParts, {''}]];
jsonText = [textParts{:}];

fileId = fopen(filename, 'w', 'n', 'UTF-8');
if fileId == -1
    error('MIB:saveOverridePreferences', 'The file could not be opened for writing:\n%s', filename);
end
closeFile = onCleanup(@() fclose(fileId));
fwrite(fileId, jsonText, 'char');

end

%% ------------------------------------------------------------------------
function [changed, numberOfSettings] = collectChanges(current, defaults, parentPath, excludedSettings, comments)
% collect the fields of the current structure that differ from the defaults,
% recursing into nested structures; returns a struct with a leading x_comment field
% when any of the collected fields is described in comments
changed = struct();
numberOfSettings = 0;
commentStruct = struct();

defaultFields = fieldnames(defaults);
for fieldId = 1:numel(defaultFields)
    fieldName = defaultFields{fieldId};
    settingPath = fieldName;
    if ~isempty(parentPath); settingPath = [parentPath '.' fieldName]; end
    if ~isfield(current, fieldName) || any(strcmp(settingPath, excludedSettings)); continue; end

    currentValue = current.(fieldName);
    defaultValue = defaults.(fieldName);
    if strcmp(settingPath, 'Colors.ModelMaterialColors')
        % rows beyond 255 are random colors generated for a 63-bit model, not
        % colors anybody chose; the Preferences dialog shows only the first 255
        currentValue = currentValue(1:min(255, end), :);
    end
    if isstruct(currentValue) && isscalar(currentValue) && isstruct(defaultValue) && ...
            isscalar(defaultValue) && ~isempty(fieldnames(defaultValue))
        [subChanged, subNumber] = collectChanges(currentValue, defaultValue, settingPath, excludedSettings, comments);
        if subNumber == 0; continue; end
        changed.(fieldName) = subChanged;
        numberOfSettings = numberOfSettings + subNumber;
    elseif ~isequaln(currentValue, defaultValue)
        if isfloat(currentValue) && ~isempty(regexp(fieldName, 'Colors?$', 'once', 'ignorecase'))
            % RGB values 0-1: 3 decimals are below a step of the 8-bit color
            % and keep the table readable
            currentValue = round(currentValue, 3);
        end
        changed.(fieldName) = encodeNonFinite(currentValue);
        numberOfSettings = numberOfSettings + 1;
    else
        continue;
    end
    if isKey(comments, settingPath)
        commentStruct.(fieldName) = comments(settingPath);
    end
end

if ~isempty(fieldnames(commentStruct))
    changed = cell2struct([{commentStruct}; struct2cell(changed)], [{'x_comment'}; fieldnames(changed)], 1);
end
end

%% ------------------------------------------------------------------------
function value = encodeNonFinite(value)
% replace Inf, -Inf and NaN of a numeric scalar or vector with strings, which
% jsonencode keeps; jsonencode would write them as null
if ~isnumeric(value) || isempty(value) || ~isvector(value) || all(isfinite(value)); return; end
nonFiniteText = @(number) char(string(number));     % "Inf", "-Inf", "NaN"
if isscalar(value)
    value = nonFiniteText(value);
    return;
end
value = num2cell(value);
for elementId = 1:numel(value)
    if ~isfinite(value{elementId}); value{elementId} = nonFiniteText(value{elementId}); end
end
end

%% ------------------------------------------------------------------------
function comments = preferenceComments()
% descriptions of the settings written into the "_comment" objects of the override
% file, keyed by the path of the setting in the preferences structure; a key naming a
% structure describes the structure as a whole
comments = dictionary( ...
    "System.MouseWheel", "'scroll' - the mouse wheel changes slices; 'zoom' - the mouse wheel zooms in and out", ...
    "System.LeftMouseButton", "'select' - the left mouse button draws and picks; 'pan' - the left mouse button moves the image", ...
    "System.ImageResizeMethod", "interpolation of the image when zoomed: 'auto', 'nearest' or 'bicubic'", ...
    "System.AltWithScrollWheel", "true - Alt + mouse wheel changes the time point; false - Alt + mouse wheel returns to the slice where Alt + scroll started", ...
    "System.EnableSelection", "1 - the selection layer is enabled; 0 - disabled, which saves memory", ...
    "System.Font", "font of the MIB panels: FontName and FontSize in points", ...
    "System.FontSizeDirView", "font size of the Directory contents panel, in points", ...
    "System.cpuParallelLimit", "number of CPU workers for parallel processing, limited to the number available on the computer", ...
    "System.GUI", "scaling factors of the dialogs", ...
    "System.Dirs", "RecentDirsNumber - number of the recent directories to remember", ...
    "System.Update", "RecheckPeriod - interval between the automatic checks for a new version of MIB, in days", ...
    "System.RenderingEngine", "'Viewer3d, R2022b' or 'Volshow, R2018b'", ...
    "System.DeveloperMode", "true - tooltips start with the handle of the widget", ...
    "Colors.ModelMaterialColors", "colors of the model materials, one [R, G, B] row per material, values 0-1", ...
    "Colors.LUTColors", "colors of the color channels in the LUT mode, one [R, G, B] row per channel, values 0-1", ...
    "Colors.SelectionColor", "[R, G, B] color of the selection layer, values 0-1", ...
    "Colors.MaskColor", "[R, G, B] color of the mask layer, values 0-1", ...
    "Colors.CursorMaterialColor", "true - the brush cursor has the color of the material it paints into; false - dark green", ...
    "Colors.Theme", "'System' - follow the MATLAB theme, 'Light' or 'Dark'", ...
    "Colors.SelectionTransparency", "transparency of the selection layer, 0-1", ...
    "Colors.MaskTransparency", "transparency of the mask layer, 0-1", ...
    "Colors.ModelTransparency", "transparency of the model layer, 0-1", ...
    "Styles.Contour", "ThicknessRendering - 'quality' or 'performance' (touching objects share one contour); ThicknessModels, ThicknessMasks - line thickness in pixels; ThicknessMethodMasks - 'inwards' or 'outwards'", ...
    "Styles.Labels", "ShowAsContours: true - models are shown as contours; false - as filled shapes", ...
    "Styles.Masks", "ShowAsContours: true - masks are shown as contours; false - as filled shapes", ...
    "Undo.Enable", "1 - undo is enabled; 0 - disabled", ...
    "Undo.MaxUndoHistory", "number of the undo steps", ...
    "Undo.Max3dUndoHistory", "number of the undo steps that store the whole dataset", ...
    "ExternalDirs", "paths to the external software; usually specific to each computer, [] when not installed", ...
    "ExternalDirs.PythonExecutionMode", "'OutOfProcess' or 'InProcess', execution mode of the Python interpreter", ...
    "ExternalDirs.BioFormatsMemoizerMemoDir", "folder for the cache files of the BioFormats memoizer", ...
    "IO.Zarr.Library", "'native' - bundled Zarr engine; 'python' - zarr-python of the environment in ExternalDirs.PythonInstallationPath", ...
    "IO.Zarr.Smoothing", "true - smooth the label boundaries when an edit made at a coarse zoom level is propagated to the finer levels", ...
    "IO.Zarr.ChunkCacheMB", "memory for the cache of the decoded Zarr chunks, in MB; 0 disables the cache", ...
    "IO.BioFormats.Library", "'mib' - bundled Bio-Formats reader; 'matlab' - MATLAB bioformatsread and openslideread", ...
    "KeyShortcuts", "element i of Key, shift, control and alt defines the shortcut of element i of Action; all the arrays must have the same length", ...
    "SegmTools.Annotations.Color", "[R, G, B] color of the annotations, values 0-1", ...
    "SegmTools.Annotations.FontSize", "1 (8 pt), 2 (10 pt), 3 (12 pt), 4 (14 pt), 5 (16 pt), 6 (18 pt) or 7 (20 pt)", ...
    "SegmTools.Annotations.ShownExtraDepth", "annotations of this number of slices above and below the current slice are also shown", ...
    "SegmTools.Annotations.Precision", "number of decimals of the annotation values", ...
    "SegmTools.Annotations.DisplayAs", "'Label + Value', 'Marker', 'Label' or 'Value'", ...
    "SegmTools.Interpolation.Type", "'shape' or 'line'", ...
    "SegmTools.FavoriteTools", "[A, B] indices of the two selection tools toggled with the D key", ...
    "SegmTools.Brush", "EraserRadiusFactor - radius of the eraser relative to the brush radius", ...
    "SegmTools.SAM", "samVersion - 'SAM1' or 'SAM2'", ...
    "SegmTools.SAM1.backbone", "'vit_h (2.5Gb)', 'vit_l (1.2Gb)' or 'vit_b (0.4Gb)'", ...
    "SegmTools.SAM1.environment", "'cuda' or 'cpu'", ...
    "SegmTools.SAM2.backbone", "'sam2_hiera_t (0.15Gb)', 'sam2_hiera_s (0.18Gb)', 'sam2_hiera_base_plus (0.32Gb)' or 'sam2_hiera_l (0.90Gb)'", ...
    "SegmTools.SAM2.environment", "'cuda' or 'cpu'", ...
    "SegmTools.Presets", "three presets, Set1-Set3, of the segmentation tools", ...
    "SegmTools.FavoriteToolA", "segmentation tool selected with Shift+D", ...
    "SegmTools.FavoriteToolB", "segmentation tool selected with Ctrl+D", ...
    "ImageArithmetic", "NoStoredActions - number of the recent expressions to remember", ...
    "VolRen.Viewer.rotationMode", "'orbit' - rotate around the center of the volume; 'cursor' - rotate around the clicked point", ...
    "Deep.TrainingOpt.GradientThreshold", "positive number or ""Inf""", ...
    "Deep.TrainingOpt.GradientThresholdMethod", "'l2norm', 'global-l2norm' or 'absolute-value'", ...
    "Deep.TrainingOpt.ValidationPatience", "positive integer or ""Inf""", ...
    "Deep.ScoreExportOpt", "Precision - 8 or 16 bit; IncludeExterior - false excludes the scores of the exterior from the output files", ...
    "Deep.DynamicMaskOpt", "Method - 'Keep above threshold' or 'Keep below threshold'", ...
    "Deep.SendReports", "email reports of DeepMIB training; SMTP_password is never written to this file", ...
    "DoNotShowDialogs", "dialogs switched off with 'Do not show again', true - the dialog is not shown", ...
    "Tips.ShowTips", "true - show a tip of the day on startup");
end
