function choice = promptSizeMismatch(itemLabel, curH, curW, imgH, imgW, boundingBox, options)
% PROMPTSIZEMISMATCH - Ask the user how to resolve a Model/Mask size mismatch.
%
% Syntax:
%   .. code-block:: matlab
%
%       choice = obj.promptSizeMismatch(itemLabel, curH, curW, imgH, imgW, boundingBox, options)
%
% Builds and shows a single ``utils.dlgs.inputUniversalDlg`` with an action
% dropdown and, only for axes that actually mismatch, Y/X offset spinners
% shown alongside it (not a multi-step wizard - the spinner values are
% simply unused by the caller when the chosen action doesn't need them).
%
% Input Arguments:
%   - **itemLabel** - [char] ``'Model'`` or ``'Mask'``, used in dialog text.
%   - **curH**, **curW** - [numeric] height/width of the loaded item.
%   - **imgH**, **imgW** - [numeric] height/width of the open image.
%   - **boundingBox** - [numeric|[]] the loaded model's 6-element
%     ``[xmin xmax ymin ymax zmin zmax]``, or ``[]`` when unavailable
%     (masks never have one). When non-empty, a ``'Use bounding box'``
%     action is offered as the default choice.
%   - **options** - struct with ``.ParentFigure`` and ``.mibPath``.
%
% Output Arguments:
%   - **choice** - struct with fields:
%
%     - ``.action`` - [char] ``'Use bounding box'``, ``'Crop / Place'``, or ``'Resize'``
%     - ``.offsetY``, ``.offsetX`` - [numeric] only meaningful when
%       ``.action == 'Crop / Place'``; ``0`` otherwise
%     - ``.cancelled`` - [logical] true when the dialog was cancelled
%

% Updates

maxOffsetY = abs(imgH - curH);
maxOffsetX = abs(imgW - curW);
hasBoundingBox = ~isempty(boundingBox) && numel(boundingBox) == 6;

actionItems = {'Crop / Place', 'Resize'};
if hasBoundingBox
    actionItems = [{'Use bounding box'}, actionItems];
end

prompts = {'Action:'};
defAns  = {[actionItems, {1}]};
if maxOffsetY > 0
    prompts{end+1} = 'Y offset, rows from top:';
    defAns{end+1}  = struct('Spinner', true, 'Value', 0, 'Limits', [0 maxOffsetY], 'Step', 1, 'Round', true);
end
if maxOffsetX > 0
    prompts{end+1} = 'X offset, columns from left:';
    defAns{end+1}  = struct('Spinner', true, 'Value', 0, 'Limits', [0 maxOffsetX], 'Step', 1, 'Round', true);
end

header = sprintf(['%s size [%d x %d] does not match the image [%d x %d].\n\n' ...
    '"Crop / Place" keeps the original values and positions the %s over the image ' ...
    '(cropping the excess or padding around it); "Resize" stretches/shrinks it to fit exactly.'], ...
    itemLabel, curH, curW, imgH, imgW, lower(itemLabel));

dlgOpt = struct('Icon', 'puffin_warning', 'HeaderLines', 5, 'WindowWidth', 460);
if isfield(options, 'mibPath'); dlgOpt.mibPath = options.mibPath; end

answer = utils.dlgs.inputUniversalDlg(options.ParentFigure, header, prompts, defAns, 'Size mismatch', dlgOpt);

choice = struct('action', 'Crop / Place', 'offsetY', 0, 'offsetX', 0, 'cancelled', isempty(answer));
if choice.cancelled; return; end

choice.action = answer{1};
fieldIndex = 2;
if maxOffsetY > 0
    choice.offsetY = answer{fieldIndex};
    fieldIndex = fieldIndex + 1;
end
if maxOffsetX > 0
    choice.offsetX = answer{fieldIndex};
end
end
