function moveSelectionToModelDataset(obj, action_type, options)
% MOVESELECTIONTOMODELDATASET - Move the Selection layer to the Model layer for the full dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.moveSelectionToModelDataset(action_type, options)
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Input Arguments:
%   - **action_type** - a type of the desired action:
%
%     - ``'add'`` - add selection to the selected material (Add to)
%     - ``'remove'`` - remove selection from the model
%     - ``'replace'`` - replace the selected (Add to) material with selection
%
%   - **options** - [struct] structure with additional parameters:
%
%     - ``.contSelIndex`` - [numeric] index of the "Select from" material
%     - ``.contAddIndex`` - [numeric] index of the "Add to" material
%     - ``.selected_sw`` - [logical] limit actions to the selected material only (``0`` or ``1``)
%     - ``.maskedAreaSw`` - [logical] limit actions to masked areas only (``0`` or ``1``)%
% Output Arguments:
%   (none)
%
% **Example** - Move selection to model by adding:
%
%   .. code-block:: matlab
%
%      options.contSelIndex = obj.getSelectedMaterialIndex();
%      options.contAddIndex = obj.getSelectedMaterialIndex('AddTo');
%      options.selected_sw = 0;
%      options.maskedAreaSw = 0;
%      obj.moveSelectionToModelDataset('add', options);
%
%   .. note::
%      This is a fast-path function that operates on complete 4D datasets only.
%      It is **not** sensitive to ``blockModeSwitch`` or visible ROI selections.

% Updates
% 

if ~isfield(options, 'contSelIndex'); options.contSelIndex = obj.getSelectedMaterialIndex(); end
if ~isfield(options, 'contAddIndex'); options.contAddIndex = obj.getSelectedMaterialIndex('AddTo'); end
if ~isfield(options, 'selected_sw'); options.selected_sw = obj.restrictSelectionToMaterial; end
if ~isfield(options, 'maskedAreaSw'); options.maskedAreaSw = obj.restrictSelectionToMask; end
isType63 = isa(obj.labels, 'core.MibLabels63');

% compute filtered image based on selected_sw and maskedAreaSw
useFiltered = false;
filteredImg = [];
if isType63
    D = obj.labels.data;
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 0
        useFiltered = true;
        filteredImg = bitand(uint8(bitand(D, 63) == options.contSelIndex), bitand(D, 128)/128);
    elseif options.maskedAreaSw && options.selected_sw == 0
        useFiltered = true;
        filteredImg = bitand(bitand(D, 128)/128, bitand(D, 64)/64);   % intersection of selection and mask
    elseif options.selected_sw && obj.modelExist && options.maskedAreaSw == 1
        useFiltered = true;
        filteredImg = bitand(uint8(bitand(D, 63) == options.contSelIndex), bitand(D, 128)/128);
        filteredImg = bitand(filteredImg, bitand(D, 64)/64);
    end
else
    selD = obj.selection.data;
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 0
        selD(obj.labels.data ~= options.contSelIndex) = 0;
    elseif options.maskedAreaSw && options.selected_sw == 0
        selD = bitand(selD, obj.mask.data);
    elseif options.selected_sw && obj.modelExist && options.maskedAreaSw == 1
        selD = bitand(selD, obj.mask.data);
        selD(obj.labels.data ~= options.contSelIndex) = 0;
    end
    obj.selection.data = selD;
end

contAddIndex = options.contAddIndex;

switch action_type
    case 'add'
        if isType63
            if ~useFiltered
                M = bitand(D, 64);                     % save mask bits
                selMask = D > 127;                     % find selected voxels (bit 8)
                D = bitand(D, 63);                     % clear selection and mask
                D(selMask) = contAddIndex;             % set material where selected
                D = bitor(D, M);                       % restore mask
            else
                M = bitand(D, 64);
                D = bitset(D, 8, 0);                   % clear selection
                D(filteredImg == 1) = contAddIndex;
                D = bitor(D, M);
            end
            obj.labels.data = D;
        else
            labelsD = obj.labels.data;
            labelsD(obj.selection.data == 1) = contAddIndex;
            obj.labels.data = labelsD;
            obj.selection.data(:) = 0;
        end

    case 'remove'
        if isType63
            if ~useFiltered
                M = bitand(D, 64);                     % save mask bits
                selMask = D > 127;                     % find selected voxels
                D = bitand(D, 63);                     % clear selection and mask
                D(selMask) = 0;                        % remove material where selected
                D = bitor(D, M);                       % restore mask
            else
                M = bitand(D, 64);
                D = bitset(D, 8, 0);
                D(filteredImg == 1) = 0;
                D = bitor(D, M);
            end
            obj.labels.data = D;
        else
            labelsD = obj.labels.data;
            labelsD(obj.selection.data == 1) = 0;
            obj.labels.data = labelsD;
            obj.selection.data(:) = 0;
        end

    case 'replace'
        if isType63
            if ~useFiltered
                M = bitand(D, 64);                     % save mask bits
                imgTemp = bitand(D, 63);               % get model only (clear mask+sel)
                selMask = D > 127;                     % find selected voxels
                imgTemp(imgTemp == contAddIndex) = 0;  % clear destination material
                imgTemp(selMask) = contAddIndex;       % populate destination material
                D = bitor(imgTemp, M);                 % restore mask
            else
                M = bitand(D, 64);
                D = bitand(D, 63);                     % clear selection and mask
                D(D == contAddIndex) = 0;              % clear destination material
                D(filteredImg == 1) = contAddIndex;    % populate destination material
                D = bitor(D, M);
            end
            obj.labels.data = D;
        else
            labelsD = obj.labels.data;
            labelsD(labelsD == contAddIndex) = 0;
            labelsD(obj.selection.data == 1) = contAddIndex;
            obj.labels.data = labelsD;
            obj.selection.data(:) = 0;
        end
end
end
