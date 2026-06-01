function flipDataset(obj, mode, parentFigure, showWaitbar)
% FLIPDATASET - Flip the dataset and all layers horizontally, vertically, along Z, or along T.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.flipDataset(mode, parentFigure, showWaitbar)
%
% Ported from MIB2 ``@mibModel/flipDataset.m``.
%
% Input Arguments:
%   - **mode** — [char] flipping mode:
%
%     - ``'Flip horizontally'`` — flip along the X (width) axis
%     - ``'Flip vertically'`` — flip along the Y (height) axis
%     - ``'Flip Z'`` — flip along the Z (depth) axis
%     - ``'Flip T'`` — reverse the time-point order
%
%   - **parentFigure** *(optional)* — handle to the parent figure for the progress dialog;
%     pass ``[]`` to suppress the progress dialog
%   - **showWaitbar** *(optional)* — logical, ``true`` to show a progress dialog (default: ``true``)
%
% Output Arguments:
%   none
%
% Usage:
%   **Example 1** — flip horizontally from a MibModel context
%
%   .. code-block:: matlab
%
%      id = obj.mibModel.getActiveId();
%      obj.mibModel.I{id}.flipDataset('Flip horizontally', obj.mibModel.mibGUI, true);
%

% Updates
%

if nargin < 4; showWaitbar = true; end
if nargin < 3; parentFigure = []; end

if obj.image.depth == 1 && strcmp(mode, 'Flip Z'); return; end
tic

options.blockModeSwitch = 0;
timePoints = obj.image.time;

if showWaitbar && ~isempty(parentFigure)
    waitbar = uiprogressdlg(parentFigure, 'Value', 0, ...
        'Message', sprintf('Flipping image\nPlease wait...'), ...
        'Title', 'Flip dataset');
else
    showWaitbar = false;
    waitbar = [];
end

if strcmp(mode, 'Flip T')
    % Collect all time-points in forward order, then write in reverse.
    % Works directly on data{1}: [H,W,Z,C,T] for image, [H,W,Z,1,T] for layers.
    obj.image.data = flip(obj.image.data, 5);
    if showWaitbar; waitbar.Value = 0.4; end

    % Flip other layers
    if isa(obj.labels, 'core.MibLabels63') && obj.enableSelection
        if showWaitbar; waitbar.Value = 0.5; waitbar.Message = sprintf('Flipping other layers\nPlease wait...'); end
        obj.labels.data = flip(obj.labels.data, 5);
    elseif obj.enableSelection
        obj.selection.data = flip(obj.selection.data, 5);
        if showWaitbar; waitbar.Value = 0.6; end
        if obj.maskExist
            obj.mask.data = flip(obj.mask.data, 5);
            if showWaitbar; waitbar.Value = 0.75; end
        end
        if obj.modelExist
            obj.labels.data = flip(obj.labels.data, 5);
        end
    end
    if showWaitbar; waitbar.Value = 1; waitbar.Message = sprintf('Finishing...'); end
    obj.image.updateActionLog(['Flip: mode=' mode]);
    if showWaitbar; delete(waitbar); end
    toc;
    return;
end

% Flip image (Flip horizontally / Flip vertically / Flip Z) using data{1} directly.
% Image layout: [H,W,Z,C,T] — Flip H=dim1, W=dim2, Z=dim3.
obj.image.data = flipDimension(obj.image.data, mode);
if showWaitbar; waitbar.Value = 0.5; end

% Flip other layers. Layer layout: [H,W,Z,1,T] — same dims 1/2/3 as image.
if isa(obj.labels, 'core.MibLabels63') && obj.enableSelection
    if showWaitbar; waitbar.Value = 0.6; waitbar.Message = sprintf('Flipping other layers\nPlease wait...'); end
    obj.labels.data = flipDimension(obj.labels.data, mode);
elseif obj.enableSelection
    obj.selection.data = flipDimension(obj.selection.data, mode);
    if showWaitbar; waitbar.Value = 0.7; end
    if obj.maskExist
        obj.mask.data = flipDimension(obj.mask.data, mode);
        if showWaitbar; waitbar.Value = 0.8; end
    end
    if obj.modelExist
        obj.labels.data = flipDimension(obj.labels.data, mode);
    end
end

if showWaitbar; waitbar.Value = 1; waitbar.Message = sprintf('Finishing...'); end
obj.image.updateActionLog(['Flip: mode=' mode]);
if showWaitbar; delete(waitbar); end
toc
end


function data = flipDimension(data, mode)
% Flip array along the correct dimension.
% Image [H,W,Z,C,T] and layer [H,W,Z,1,T] share dims 1 (H), 2 (W), 3 (Z).
switch mode
    case 'Flip Z'
        data = flip(data, 3);
    case 'Flip horizontally'
        data = flip(data, 2);
    case 'Flip vertically'
        data = flip(data, 1);
end
end
