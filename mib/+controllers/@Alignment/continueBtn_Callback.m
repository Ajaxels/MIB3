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
%   - **useBatchMode** *(optional)* — [logical] ``true`` when the controller
%     was invoked via the batch processor (no GUI). Default ``false``.

if nargin < 2; useBatchMode = false; end

id = obj.mibModel.getActiveId();

% --- 5D dataset rejection
if obj.mibModel.I{id}.image.time > 1 && obj.mibModel.I{id}.image.depth > 1
    utils.dlgs.showErrorDialog(obj.view.gui, ...
        '5D datasets are not supported by the alignment tool.', 'Alignment');
    return;
end

% --- HDD-mode hard exclusions: only Drift correction & feature-based currently support it
if obj.BatchOpt.HDD_Mode
    allowedHDD = {'Drift correction', 'Template matching', ...
        'Automatic feature-based', 'Automatic feature-based v2'};
    if ~ismember(obj.BatchOpt.Algorithm{1}, allowedHDD)
        utils.dlgs.showErrorDialog(obj.view.gui, ...
            sprintf('HDD mode is not available for "%s".', obj.BatchOpt.Algorithm{1}), ...
            'Alignment');
        return;
    end
end

% --- Pre-load shifts if requested in batch mode (GUI mode handles this in loadShiftsCheck_Callback)
if useBatchMode && isfield(obj.view.handles, 'loadShiftsCheck')
    % no-op: already loaded by loadShiftsCheck_Callback
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

% --- Dispatch on algorithm
switch obj.BatchOpt.Algorithm{1}
    case {'Drift correction', 'Template matching'}
        if obj.BatchOpt.HDD_Mode
            notYetPorted(obj, 'HDD-mode drift / template matching');
            return;
        else
            obj.DriftCorrection_Alignment(parameters);
        end

    case 'Single landmark point'
        obj.SingleLandmark_Alignment(parameters);

    case 'Three landmark points'
        notYetPorted(obj, 'Three landmark points');
        return;

    case 'Landmarks, multi points'
        notYetPorted(obj, 'Landmarks, multi points');
        return;

    case 'Color channels, multi points'
        notYetPorted(obj, 'Color channels, multi points');
        return;

    case {'Automatic feature-based', 'Automatic feature-based v2'}
        notYetPorted(obj, obj.BatchOpt.Algorithm{1});
        return;

    case 'AMST: median-smoothed template'
        notYetPorted(obj, 'AMST: median-smoothed template');
        return;

    otherwise
        utils.dlgs.showErrorDialog(obj.view.gui, ...
            sprintf('Unknown algorithm: "%s".', obj.BatchOpt.Algorithm{1}), 'Alignment');
        return;
end

% Headless batch mode: report BatchOpt back to the batch controller
if useBatchMode; obj.returnBatchOpt(); end

end

function notYetPorted(obj, name)
% NOTYETPORTED - Local helper that emits a "not yet ported" error dialog.
parent = [];
if ~isempty(obj.view) && isvalid(obj.view.gui)
    parent = obj.view.gui;
end
utils.dlgs.showErrorDialog(parent, ...
    sprintf(['The "%s" algorithm has not been ported to MIB3 yet.\n\n' ...
            'Phase 1 of the port supports Drift correction, Template matching, ' ...
            'and Single landmark point.'], name), 'Alignment');
end
