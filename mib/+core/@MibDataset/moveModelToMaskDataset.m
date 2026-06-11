function moveModelToMaskDataset(obj, action_type, options)
% MOVEMODELTOMASKDATASET - Move the selected Material to the Mask layer for the full dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.moveModelToMaskDataset(action_type, options)
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Input Arguments:
%   - **action_type** — [char] type of the desired action:
%
%     - ``'add'`` — add the selected material to mask
%     - ``'remove'`` — remove the selected material from mask
%     - ``'replace'`` — replace mask with the selected material
%
%   - **options** — [struct] structure with additional parameters:
%
%     - ``.contSelIndex`` — [numeric] index of the "Select from" material
%     - ``.contAddIndex`` — [numeric] index of the "Add to" material%
% Output Arguments:
%   (none)
%
% **Example** — Move selected material to mask by adding:
%
%   .. code-block:: matlab
%
%      options.contSelIndex = obj.getSelectedMaterialIndex();
%      options.contAddIndex = obj.getSelectedMaterialIndex('AddTo');
%      obj.moveModelToMaskDataset('add', options);
%
%   .. note::
%      This is a fast-path function that operates on complete 4D datasets only.
%      It is **not** sensitive to ``blockModeSwitch`` or visible ROI selections.
%

% Updates
% 

if ~isfield(options, 'contSelIndex'); options.contSelIndex = obj.getSelectedMaterialIndex(); end
if ~isfield(options, 'contAddIndex'); options.contAddIndex = obj.getSelectedMaterialIndex('AddTo'); end
isType63 = isa(obj.labels, 'core.MibLabels63');
% allocate the mask container when it is missing (no-op for MibLabels63);
% also sets mask.exists so reads through getData do not return empty
obj.allocateMask();

switch action_type
    case 'add'
        if isType63
            D = obj.labels.data;
            matMask = uint8(bitand(D, 63) == options.contSelIndex) * 64;
            D = bitor(D, matMask);
            obj.labels.data = D;
        else
            maskD = obj.mask.data;
            maskD(obj.labels.data == options.contSelIndex) = 1;
            obj.mask.data = maskD;
        end

    case 'remove'
        if isType63
            D = obj.labels.data;
            matMask = uint8(bitand(D, 63) == options.contSelIndex) * 64;
            D = D - bitand(D, matMask);
            obj.labels.data = D;
        else
            maskD = obj.mask.data;
            maskD = maskD - uint8(obj.labels.data == options.contSelIndex);
            obj.mask.data = maskD;
        end

    case 'replace'
        if isType63
            D = obj.labels.data;
            D = bitset(D, 7, 0);                     % clear mask
            matMask = uint8(bitand(D, 63) == options.contSelIndex) * 64;
            D = bitor(D, matMask);
            obj.labels.data = D;
        else
            maskD = uint8(obj.labels.data == options.contSelIndex);
            obj.mask.data = maskD;
        end
end
end
