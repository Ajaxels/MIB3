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
%     - ``.contAddIndex`` — [numeric] index of the "Add to" material
%     - ``.level`` *(optional)* — [numeric] image level index from pyramid (default: ``1``)
%
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
if ~isfield(options, 'level'); options.level = 1; end

isType63 = isa(obj.labels, 'core.MibLabels63');

switch action_type
    case 'add'
        if isType63
            D = obj.labels.data{options.level};
            matMask = uint8(bitand(D, 63) == options.contSelIndex) * 64;
            D = bitor(D, matMask);
            obj.labels.data{options.level} = D;
        else
            maskD = obj.mask.data{options.level};
            maskD(obj.labels.data{options.level} == options.contSelIndex) = 1;
            obj.mask.data{options.level} = maskD;
        end

    case 'remove'
        if isType63
            D = obj.labels.data{options.level};
            matMask = uint8(bitand(D, 63) == options.contSelIndex) * 64;
            D = D - bitand(D, matMask);
            obj.labels.data{options.level} = D;
        else
            maskD = obj.mask.data{options.level};
            maskD = maskD - uint8(obj.labels.data{options.level} == options.contSelIndex);
            obj.mask.data{options.level} = maskD;
        end

    case 'replace'
        if isType63
            D = obj.labels.data{options.level};
            D = bitset(D, 7, 0);                     % clear mask
            matMask = uint8(bitand(D, 63) == options.contSelIndex) * 64;
            D = bitor(D, matMask);
            obj.labels.data{options.level} = D;
        else
            maskD = uint8(obj.labels.data{options.level} == options.contSelIndex);
            obj.mask.data{options.level} = maskD;
        end
end
end
