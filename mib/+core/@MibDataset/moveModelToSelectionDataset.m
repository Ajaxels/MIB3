function moveModelToSelectionDataset(obj, action_type, options)
% MOVEMODELTOSELECTIONDATASET - Move the selected Material to the Selection layer for the full dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.moveModelToSelectionDataset(action_type, options)
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Input Arguments:
%   - **action_type** — [char] type of the desired action:
%
%     - ``'add'`` — add the selected material to selection
%     - ``'remove'`` — remove the selected material from selection
%     - ``'replace'`` — replace selection with the selected material
%
%   - **options** — [struct] structure with additional parameters:
%
%     - ``.contSelIndex`` — [numeric] index of the "Select from" material
%     - ``.contAddIndex`` — [numeric] index of the "Add to" material
%     - ``.maskedAreaSw`` — [logical] limit actions to masked areas only (``0`` or ``1``)%
% Output Arguments:
%   (none)
%
% **Example** — Move selected material to selection by adding:
%
%   .. code-block:: matlab
%
%      options.contSelIndex = obj.getSelectedMaterialIndex();
%      options.contAddIndex = obj.getSelectedMaterialIndex('AddTo');
%      options.maskedAreaSw = 0;
%      obj.moveModelToSelectionDataset('add', options);
%
%   .. note::
%      This is a fast-path function that operates on complete 4D datasets only.
%      It is **not** sensitive to ``blockModeSwitch`` or visible ROI selections.

% Updates
% 

if ~isfield(options, 'contSelIndex'); options.contSelIndex = obj.getSelectedMaterialIndex(); end
if ~isfield(options, 'contAddIndex'); options.contAddIndex = obj.getSelectedMaterialIndex('AddTo'); end
if ~isfield(options, 'maskedAreaSw'); options.maskedAreaSw = obj.restrictSelectionToMask; end
isType63 = isa(obj.labels, 'core.MibLabels63');

% compute filtered image if restricting to masked area
useFiltered = false;
filteredImg = [];
if isType63
    D = obj.labels.data;
    if options.maskedAreaSw == 1
        useFiltered = true;
        filteredImg = bitand(uint8(bitand(D, 63) == options.contSelIndex), bitand(D, 64)/64);
    end
else
    if options.maskedAreaSw == 1
        useFiltered = true;
        filteredImg = bitand(obj.mask.data, uint8(obj.labels.data == options.contSelIndex));
    end
end

switch action_type
    case 'add'
        if isType63
            if ~useFiltered
                matMask = uint8(bitand(D, 63) == options.contSelIndex) * 128;
                D = bitor(D, matMask);
            else
                D = bitor(D, filteredImg * 128);
            end
            obj.labels.data = D;
        else
            selD = obj.selection.data;
            if ~useFiltered
                selD(obj.labels.data == options.contSelIndex) = 1;
            else
                selD = bitor(selD, filteredImg);
            end
            obj.selection.data = selD;
        end

    case 'remove'
        if isType63
            if ~useFiltered
                matMask = uint8(bitand(D, 63) == options.contSelIndex) * 128;
                D = D - bitand(D, matMask);
            else
                D = D - bitand(D, filteredImg * 128);
            end
            obj.labels.data = D;
        else
            selD = obj.selection.data;
            if ~useFiltered
                selD = selD - uint8(obj.labels.data == options.contSelIndex);
            else
                selD = selD - filteredImg;
            end
            obj.selection.data = selD;
        end

    case 'replace'
        if isType63
            D = bitset(D, 8, 0);                    % clear selection
            if ~useFiltered
                matMask = uint8(bitand(D, 63) == options.contSelIndex) * 128;
                D = bitor(D, matMask);
            else
                D = bitor(D, filteredImg * 128);
            end
            obj.labels.data = D;
        else
            if ~useFiltered
                obj.selection.data = uint8(obj.labels.data == options.contSelIndex);
            else
                selD = zeros(size(obj.selection.data), 'uint8');
                selD = bitor(selD, filteredImg);
                obj.selection.data = selD;
            end
        end
end
end
