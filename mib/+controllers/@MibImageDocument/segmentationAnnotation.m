function segmentationAnnotation(obj, y, x, z, t, modifier, options)
% function segmentationAnnotation(obj, y, x, z, t, modifier, options)
% Add or remove a text annotation at the given dataset coordinate
%
% Adds a new annotation (empty modifier), removes the closest annotation
% (Ctrl), or interpolates annotations along Z between the last and the
% current position (Shift).
%
% Parameters:
% y: double, y-coordinate of the annotation point in full-dataset pixels
% x: double, x-coordinate of the annotation point in full-dataset pixels
% z: double, z-coordinate (slice index) of the annotation point
% t: double, t-coordinate (time point) of the annotation point
% modifier: cell array of chars or char, modifier keys held during click
% @li empty '' or {} - add annotation to the list
% @li 'control' / {'control'} - remove the closest annotation
% @li 'shift'   / {'shift'}   - interpolate annotations between the last
%   and the current position along Z
% options: [@em optional] struct with additional settings
% @li .samInteractiveModel - [logical] when true, triggers
%   mibSegmentationSAM after adding the annotation; default false
%
% Return values:
%   (none)
%

%|
% @b Examples:
% @code obj.segmentationAnnotation(50, 75, 10, 1, {});  // add annotation @endcode
% @code obj.segmentationAnnotation(50, 75, 10, 1, {'control'});  // remove closest @endcode
% @code obj.segmentationAnnotation(50, 75, 10, 1, {'shift'});    // interpolate @endcode

% Updates
% 28.02.2018, IB, added compatibility with values
% 14.04.2023, IB, added options parameter

if nargin < 7; options = struct(); end
if ~isfield(options, 'samInteractiveModel'); options.samInteractiveModel = false; end

% check for switch that disables segmentation tools
if obj.mibModel.disableSegmentation; return; end

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};

% normalise modifier to logical flags
isCtrl  = false;
isShift = false;
if iscell(modifier)
    isCtrl  = any(strcmp(modifier, 'control'));
    isShift = any(strcmp(modifier, 'shift'));
elseif ischar(modifier)
    isCtrl  = strcmp(modifier, 'control');
    isShift = strcmp(modifier, 'shift');
end

defaultAnnotationText  = dataset.annotations.defaultAnnotationText;
defaultAnnotationValue = dataset.annotations.defaultAnnotationValue;
if isnan(defaultAnnotationValue); defaultAnnotationValue = 1; end

obj.mibModel.backup('annotations', 0);

if ~isCtrl && ~isShift   % ---- add annotation ----
    if obj.mibController.cSegmentation.handles.annShowPrompt.Value
        title = 'Add annotation';
        if obj.mibModel.preferences.SegmTools.Annotations.FocusOnValue
            defAns  = {defaultAnnotationValue, defaultAnnotationText};
            prompts = {'Annotation value:'; 'Annotation text:'};
        else
            defAns  = {defaultAnnotationText, defaultAnnotationValue};
            prompts = {'Annotation text:'; 'Annotation value:'};
        end
        dlgOpt.mibPath = obj.mibModel.mibPath;
        dlgOpt.Focus = 1;
        dlgOpt.WindowWidth = 400;
        answer = utils.dlgs.inputUniversalDlg(obj.view.gui, prompts, defAns, title, dlgOpt);
        if isempty(answer); return; end
        if obj.mibModel.preferences.SegmTools.Annotations.FocusOnValue
            labelText  = answer(2);
            labelValue = answer{1};
        else
            labelText  = answer(1);
            labelValue = answer{2};
        end
    else
        labelText  = {defaultAnnotationText};
        labelValue = defaultAnnotationValue;
    end

    dataset.annotations.addLabels(labelText, [z, x, y, t], labelValue);
    dataset.annotations.defaultAnnotationText  = labelText{1};
    dataset.annotations.defaultAnnotationValue = labelValue;

    % ensure annotations are visible
    obj.mibController.cSelection.handles.showAnnotations.Value = 1;
    obj.mibModel.showAnnotations = 1;

elseif isCtrl   % ---- remove closest annotation ----
    sliceNo = dataset.slices{dataset.orientation}(1);
    sliceNo = [sliceNo - obj.mibModel.preferences.SegmTools.Annotations.ShownExtraDepth, ...
               sliceNo + obj.mibModel.preferences.SegmTools.Annotations.ShownExtraDepth];
    [~, ~, labelPositions] = dataset.getSliceLabels(sliceNo);
    if isempty(labelPositions); return; end

    orientation = dataset.orientation;
    if orientation == 3        % XY (default)
        X1 = [x, y];
        X2 = labelPositions(:, 2:3);
    elseif orientation == 1    % ZX
        X1 = [z, x];
        X2 = labelPositions(:, 1:2);
    elseif orientation == 2    % ZY
        X1 = [z, y];
        X2 = labelPositions(:, [1, 3]);
    end

    % Euclidean distance from clicked point to each annotation
    distVec = sqrt(bsxfun(@plus, sum(X1.^2, 2), sum(X2.^2, 2)') - 2 * (X1 * X2'));
    [~, index] = min(distVec);
    selectedLabelPos = labelPositions(index, :);
    dataset.annotations.removeLabels(selectedLabelPos);

elseif isShift  % ---- interpolate annotations along Z ----
    noLabels = dataset.annotations.getLabelsNumber();
    if noLabels == 0; return; end

    % get data from the last existing annotation
    labelText     = dataset.annotations.labelText{end};
    labelValue    = dataset.annotations.labelValue(end);
    labelPosition = dataset.annotations.labelPosition(end, :);
    timepoint     = labelPosition(4);

    if z == labelPosition(1)
        dataset.annotations.addLabels(labelText, [z, x, y, t], labelValue);
    else
        % range vector between previous Z and current Z
        if labelPosition(1) < z
            z_range = labelPosition(1) : z;
        else
            z_range = labelPosition(1) : -1 : z;
        end

        % linear interpolation of x and y along z_range
        x_interp = interp1([labelPosition(1); z], [labelPosition(2); x], z_range, 'linear');
        y_interp = interp1([labelPosition(1); z], [labelPosition(3); y], z_range, 'linear');

        nNew = numel(z_range) - 1;   % drop the first point (already exists)
        newPositions          = zeros(nNew, 4);
        newPositions(:, 1)    = z_range(2:end);
        newPositions(:, 2)    = x_interp(2:end);
        newPositions(:, 3)    = y_interp(2:end);
        newPositions(:, 4)    = timepoint;
        labelTextArr  = repmat({labelText},  [nNew, 1]);
        labelValueArr = repmat(labelValue,   [nNew, 1]);

        dataset.annotations.addLabels(labelTextArr, newPositions, labelValueArr);
    end
end
notify(obj.mibModel, 'UpdateAnnotations');     % notify about updated annotation

% count user's points
obj.mibModel.preferences.Users.Tiers.numberOfAnnotations = obj.mibModel.preferences.Users.Tiers.numberOfAnnotations + 1;
notify(obj.mibModel, 'UpdateUserScore');

% trigger SAM interactive segmentation if requested
if options.samInteractiveModel
    obj.mibSegmentationSAM();
end
end
