function choice = promptSizeMismatch(itemLabel, itemSize, imageSize, boundingBox, options)
% PROMPTSIZEMISMATCH - Ask the user how to resolve a Model/Mask size mismatch.
%
% Syntax:
%   .. code-block:: matlab
%
%       choice = obj.promptSizeMismatch(itemLabel, itemSize, imageSize, boundingBox, options)
%
% Builds and shows a single ``utils.dlgs.inputUniversalDlg`` with an action
% dropdown and, only for axes that actually mismatch, Y/X/Z offset spinners
% shown alongside it (not a multi-step wizard - the spinner values are
% simply unused by the caller when the chosen action doesn't need them).
%
% An offset is the number of pixels between the starts of the two grids on
% that axis: where the cropped part starts inside the item when the item is
% bigger than the image, or where the item is placed inside the image when it
% is smaller. Either way it is limited to ``[0, abs(imageSize - itemSize)]``,
% so the smaller of the two stays fully inside the bigger one.
%
% Input Arguments:
%   - **itemLabel** - [char] ``'Model'`` or ``'Mask'``, used in dialog text.
%   - **itemSize** - [1x3 numeric] ``[height, width, depth]`` of the loaded item.
%   - **imageSize** - [1x3 numeric] ``[height, width, depth]`` of the open image.
%   - **boundingBox** - [numeric|[]] the loaded model's 6-element
%     ``[xmin xmax ymin ymax zmin zmax]``, or ``[]`` when unavailable or not
%     usable (masks never have one; ``loadModel`` also passes ``[]`` when the
%     model pixel size differs from the image). When non-empty, a
%     ``'Use bounding box'`` action is offered as the default choice; the
%     caller computes its offsets, the box itself is not read here.
%   - **options** - struct with ``.ParentFigure`` and ``.mibPath``, and
%     optionally ``.defaultOffsetZ`` - [numeric, {0}] initial value of the Z
%     offset spinner (``loadModel`` passes the current slice so that a thin
%     model lands where the user is looking, as in batch mode).
%
% Output Arguments:
%   - **choice** - struct with fields:
%
%     - ``.action`` - [char] ``'Use bounding box'``, ``'Crop / Place'``, or ``'Resize'``
%     - ``.offsetY``, ``.offsetX``, ``.offsetZ`` - [numeric] spinner values;
%       ``0`` for an axis without a mismatch (``.offsetZ`` is the clamped
%       ``.defaultOffsetZ`` when depth mismatches). Used by the caller for
%       ``'Crop / Place'``; ``.offsetZ`` also for ``'Resize'``, which scales
%       height and width only
%     - ``.cancelled`` - [logical] true when the dialog was cancelled
%

% Updates

itemSize(end+1:3) = 1;
imageSize(end+1:3) = 1;
maxOffset = abs(imageSize(1:3) - itemSize(1:3));   % [Y X Z]
hasBoundingBox = ~isempty(boundingBox) && numel(boundingBox) == 6;

defaultOffsetZ = 0;
if isfield(options, 'defaultOffsetZ') && ~isempty(options.defaultOffsetZ)
    defaultOffsetZ = min(max(round(options.defaultOffsetZ), 0), maxOffset(3));
end

actionItems = {'Crop / Place', 'Resize'};
if hasBoundingBox
    actionItems = [{'Use bounding box'}, actionItems];
end

prompts = {'Action:'};
defAns  = {[actionItems, {1}]};
offsetPrompts = {'Y offset, rows:', 'X offset, columns:', 'Z offset, slices:'};
offsetDefaults = [0 0 defaultOffsetZ];
for axisIndex = 1:3
    if maxOffset(axisIndex) > 0
        prompts{end+1} = offsetPrompts{axisIndex}; %#ok<AGROW>
        defAns{end+1}  = struct('Spinner', true, 'Value', offsetDefaults(axisIndex), ...
            'Limits', [0 maxOffset(axisIndex)], 'Step', 1, 'Round', true); %#ok<AGROW>
    end
end

itemName = lower(itemLabel);
optionLines = {};
if hasBoundingBox
    optionLines{end+1} = sprintf('- Use bounding box: place the %s by the coordinates saved with it', itemName);
end
optionLines{end+1} = sprintf(['- Crop / Place: keep the values and shift the %s by the offsets below, ' ...
    'cropping what does not fit or padding around it'], itemName);
optionLines{end+1} = sprintf('- Resize: stretch or shrink the %s in height and width to fit the image', itemName);

header = sprintf('%s size [%d x %d x %d] does not match the image [%d x %d x %d].\n\n%s', ...
    itemLabel, itemSize(1:3), imageSize(1:3), strjoin(optionLines, newline));
if maxOffset(3) > 0
    header = sprintf('%s\n\nThe Z offset places the slices for every action except "Use bounding box".', header);
end

dlgOpt = struct('Icon', 'puffin_warning', 'HeaderLines', 8 + 2 * (maxOffset(3) > 0), 'WindowWidth', 520);
if isfield(options, 'mibPath'); dlgOpt.mibPath = options.mibPath; end

answer = utils.dlgs.inputUniversalDlg(options.ParentFigure, header, prompts, defAns, 'Size mismatch', dlgOpt);

choice = struct('action', 'Crop / Place', 'offsetY', 0, 'offsetX', 0, 'offsetZ', 0, ...
    'cancelled', isempty(answer));
if maxOffset(3) > 0; choice.offsetZ = defaultOffsetZ; end
if choice.cancelled; return; end

choice.action = answer{1};
offsetFields = {'offsetY', 'offsetX', 'offsetZ'};
fieldIndex = 2;
for axisIndex = 1:3
    if maxOffset(axisIndex) > 0
        choice.(offsetFields{axisIndex}) = answer{fieldIndex};
        fieldIndex = fieldIndex + 1;
    end
end
end
