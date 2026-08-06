function continueBtn_Callback(obj, useBatchMode)
% CONTINUEBTN_CALLBACK - Top-level dispatcher for the alignment Apply button.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.continueBtn_Callback()
%      obj.continueBtn_Callback(useBatchMode)
%
% Validates the current dataset, builds the shared ``parameters`` struct from
% ``obj.BatchOpt``, and dispatches to the algorithm-specific method file
% (``DriftCorrection_Alignment``, ``SingleLandmark_Alignment``, ...).
% Algorithms not yet ported in the current phase fall through to a friendly
% error dialog.
%
% Input Arguments:
%   - **useBatchMode** *(optional)* - [logical] ``true`` when the controller
%     was invoked via the batch processor (no GUI). Default ``false``.

if nargin < 2; useBatchMode = false; end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.Alignment.continueBtn_Callback: triggered\n');
end

id = obj.mibModel.getActiveId();

% Parent figure for any dialogs - ``obj.view`` is empty in batch mode
if ~isempty(obj.view) && isvalid(obj.view) && isvalid(obj.view.gui)
    parentFig = obj.view.gui;
else
    parentFig = obj.mibModel.mibGUI;
end

% --- 5D dataset rejection
if obj.mibModel.I{id}.image.time > 1 && obj.mibModel.I{id}.image.depth > 1
    utils.dlgs.showErrorDialog(parentFig, ...
        '5D datasets are not supported by the alignment tool.', 'Alignment');
    return;
end

% --- HDD-mode hard exclusions: only Drift correction & feature-based currently support it
if obj.BatchOpt.HDD_Mode
    allowedHDD = {'Drift correction', 'Template matching', ...
        'Automatic feature-based', 'Automatic feature-based v2'};
    if ~ismember(obj.BatchOpt.Algorithm{1}, allowedHDD)
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('HDD mode is not available for "%s".', obj.BatchOpt.Algorithm{1}), ...
            'Alignment');
        return;
    end
end

% --- Build the shared parameters struct
parameters = struct();
parameters.useBatchMode = logical(useBatchMode);

% Color channel
parameters.colorCh = find(ismember(obj.BatchOpt.ColorChannel{2}, obj.BatchOpt.ColorChannel{1}));
if isempty(parameters.colorCh); parameters.colorCh = 1; end

% Background colour
if strcmp(obj.BatchOpt.BackgroundColor{1}, 'Custom')
    parameters.backgroundColor = obj.BatchOpt.CustomColorValue{1};
else
    parameters.backgroundColor = lower(obj.BatchOpt.BackgroundColor{1});
end

% Reference frame for drift / template-matching
switch obj.BatchOpt.CorrelateWith{1}
    case 'Previous slice'; parameters.refFrame = 0;
    case 'First slice';    parameters.refFrame = 1;
    case 'Relative to';    parameters.refFrame = -obj.BatchOpt.CorrelateStep{1};
end

% Algorithm and transformation
parameters.method               = obj.BatchOpt.Algorithm{1};
parameters.TransformationType   = strrep(obj.BatchOpt.TransformationType{1}, ' ', '');
if strcmp(parameters.TransformationType, 'piecewiselinear'); parameters.TransformationType = 'pwl'; end
parameters.TransformationMode   = obj.BatchOpt.TransformationMode{1};
parameters.transformationDegree = find(ismember(obj.BatchOpt.TransformationDegree{2}, obj.BatchOpt.TransformationDegree{1})) + 1;
parameters.UseParallelComputing = logical(obj.BatchOpt.UseParallelComputing);
parameters.IntensityGradient    = logical(obj.BatchOpt.IntensityGradient);

% Subarea
parameters.Subarea = obj.BatchOpt.Subarea{1};
parameters.minX = obj.BatchOpt.minX{1};
parameters.maxX = obj.BatchOpt.maxX{1};
parameters.minY = obj.BatchOpt.minY{1};
parameters.maxY = obj.BatchOpt.maxY{1};

% --- BigData mode: alignment writes a NEW aligned zarr3 store (never in-place)
parameters.isBigData = ~isempty(obj.isBigData) && obj.isBigData;
if parameters.isBigData
    % Analysis pyramid level: parse the leading index from the dropdown item
    % (e.g. '2: 12000 x 9000'); '<auto>' -> level nearest ~3000 px wide.
    levelStr = obj.BatchOpt.BigData_PyramidLevel{1};
    levelTok = regexp(levelStr, '^\s*(\d+)\s*:', 'tokens', 'once');
    if isempty(levelTok)
        levelSizes = obj.mibModel.I{id}.image.pyramid.levelImageSizes;
        [~, parameters.pyramidLevel] = min(abs(levelSizes(:, 2) - 3000));
    else
        parameters.pyramidLevel = str2double(levelTok{1});
    end
    parameters.outputPath = obj.BatchOpt.BigData_OutputPath;

    if isempty(parameters.outputPath)
        utils.dlgs.showErrorDialog(parentFig, ...
            'BigData alignment requires an output store path (BigData_OutputPath).', 'Alignment');
        return;
    end
end

% --- Pre-loaded coefficients (loadShiftsCheck): preview + confirm before running,
% warning if their type does not match the selected algorithm. GUI only - the
% batch path has no load hook, so obj.shiftsX is never pre-loaded there.
if ~useBatchMode && ~isempty(obj.shiftsX) ...
        && ~isempty(obj.view) && isvalid(obj.view) && isfield(obj.view.handles, 'loadShiftsCheck') ...
        && obj.view.handles.loadShiftsCheck.Value
    if ~previewConfirmLoadedShifts(obj, parameters, parentFig)
        return;   % user cancelled or coefficient/algorithm mismatch
    end
end

% --- Dispatch on algorithm
switch obj.BatchOpt.Algorithm{1}
    case {'Drift correction', 'Template matching'}
        if parameters.isBigData
            obj.DriftCorrectionBigData_Alignment(parameters);
        elseif obj.BatchOpt.HDD_Mode
            obj.alignDriftCorrectionHDD_Alignment(parameters);
        else
            obj.DriftCorrection_Alignment(parameters);
        end

    case 'Single landmark point'
        if parameters.isBigData
            obj.LandmarksBigData_Alignment(parameters);
        else
            obj.SingleLandmark_Alignment(parameters);
        end

    case 'Three landmark points'
        if parameters.isBigData
            obj.LandmarksBigData_Alignment(parameters);
        else
            obj.ThreeLandmarks_Alignment(parameters);
        end

    case 'Landmarks, multi points'
        if parameters.isBigData
            obj.LandmarksBigData_Alignment(parameters);
        else
            obj.LandmarkMultiPoint_Alignment(parameters);
        end

    case 'Color channels, multi points'
        if parameters.isBigData
            utils.dlgs.showErrorDialog(parentFig, ...
                'The "Color channels, multi points" mode is not supported in BigData mode.', 'Alignment');
            return;
        end
        obj.LandmarkMultiPointColor_Alignment(parameters);

    case 'Automatic feature-based'
        if parameters.isBigData
            utils.dlgs.showErrorDialog(parentFig, ...
                ['"Automatic feature-based" (v1) is not supported in BigData mode. ' ...
                 'Use "Automatic feature-based v2" instead.'], 'Alignment');
            return;
        elseif obj.BatchOpt.HDD_Mode
            obj.AutomaticFeatureBasedHDD_Alignment(parameters);
        else
            obj.AutomaticFeatureBased_Alignment(parameters);
        end

    case 'Automatic feature-based v2'
        if parameters.isBigData
            obj.AutomaticFeatureBasedV2BigData_Alignment(parameters);
        elseif obj.BatchOpt.HDD_Mode
            obj.AutomaticFeatureBasedHDDV2_Alignment(parameters);
        else
            obj.AutomaticFeatureBasedV2_Alignment(parameters);
        end

    case 'AMST: median-smoothed template'
        if parameters.isBigData
            utils.dlgs.showErrorDialog(parentFig, ...
                'AMST (median-smoothed template) is not supported in BigData mode.', 'Alignment');
            return;
        end
        obj.AlignMedianSmoothTemplate_Alignment(parameters);

    otherwise
        utils.dlgs.showErrorDialog(parentFig, ...
            sprintf('Unknown algorithm: "%s".', obj.BatchOpt.Algorithm{1}), 'Alignment');
        return;
end

% Headless batch mode: report BatchOpt back to the batch controller
if useBatchMode; obj.returnBatchOpt(); end

end
