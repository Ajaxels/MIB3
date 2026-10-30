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
%     - ``.maskedAreaSw`` - [logical] limit actions to masked areas only (``0`` or ``1``)
%     - ``.box`` *(optional)* - [1x8 double] ``[y1 y2 x1 x2 z1 z2 t1 t2]`` that
%       holds every selected voxel, as returned by ``getSelectionBoundingBox``;
%       only this box is read and written, which gives the same result as the
%       whole-volume pass because 'add' and 'remove' change nothing outside the
%       selection. Ignored for ``'replace'``, which also clears the destination
%       material outside the selection. Default: ``[]``, the whole dataset.
%
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

% subscripts of the box that holds the selection; {} = the whole dataset
boxIndex = {};
if isfield(options, 'box') && ~isempty(options.box) && ~strcmp(action_type, 'replace')
    box = options.box;
    boxIndex = {box(1):box(2), box(3):box(4), box(5):box(6), 1, box(7):box(8)};
end

% compute filtered image based on selected_sw and maskedAreaSw
useFiltered = false;
filteredImg = [];
if isType63
    D = readLayer(obj.labels, boxIndex);
    % packed bit layout: uint8 (63 materials) or uint16 (16383 instances)
    materialMask   = obj.labels.materialMask;
    maskValue      = obj.labels.maskValue;
    selectionValue = obj.labels.selectionValue;
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 0
        useFiltered = true;
        filteredImg = bitand(cast(bitand(D, materialMask) == options.contSelIndex, 'like', D), bitand(D, selectionValue)/selectionValue);
    elseif options.maskedAreaSw && options.selected_sw == 0
        useFiltered = true;
        filteredImg = bitand(bitand(D, selectionValue)/selectionValue, bitand(D, maskValue)/maskValue);   % intersection of selection and mask
    elseif options.selected_sw && obj.modelExist && options.maskedAreaSw == 1
        useFiltered = true;
        filteredImg = bitand(cast(bitand(D, materialMask) == options.contSelIndex, 'like', D), bitand(D, selectionValue)/selectionValue);
        filteredImg = bitand(filteredImg, bitand(D, maskValue)/maskValue);
    end
else
    selD = readLayer(obj.selection, boxIndex);
    labelsD = readLayer(obj.labels, boxIndex);
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 0
        selD(labelsD ~= options.contSelIndex) = 0;
    elseif options.maskedAreaSw && options.selected_sw == 0
        selD = bitand(selD, readLayer(obj.mask, boxIndex));
    elseif options.selected_sw && obj.modelExist && options.maskedAreaSw == 1
        selD = bitand(selD, readLayer(obj.mask, boxIndex));
        selD(labelsD ~= options.contSelIndex) = 0;
    end
end

contAddIndex = options.contAddIndex;

switch action_type
    case 'add'
        if isType63
            if ~useFiltered
                M = bitand(D, maskValue);                     % save mask bits
                selMask = D >= selectionValue;                 % find selected voxels (selection bit)
                D = bitand(D, materialMask);                  % clear selection and mask
                D(selMask) = contAddIndex;             % set material where selected
                D = bitor(D, M);                       % restore mask
            else
                M = bitand(D, maskValue);
                D = bitset(D, obj.labels.selectionBit, 0);                   % clear selection
                D(filteredImg == 1) = contAddIndex;
                D = bitor(D, M);
            end
            writeLayer(obj.labels, D, boxIndex);
        else
            labelsD(selD == 1) = contAddIndex;
            writeLayer(obj.labels, labelsD, boxIndex);
            selD(:) = 0;
            writeLayer(obj.selection, selD, boxIndex);
        end

    case 'remove'
        if isType63
            if ~useFiltered
                M = bitand(D, maskValue);                     % save mask bits
                selMask = D >= selectionValue;                 % find selected voxels
                D = bitand(D, materialMask);                  % clear selection and mask
                D(selMask) = 0;                        % remove material where selected
                D = bitor(D, M);                       % restore mask
            else
                M = bitand(D, maskValue);
                D = bitset(D, obj.labels.selectionBit, 0);
                D(filteredImg == 1) = 0;
                D = bitor(D, M);
            end
            writeLayer(obj.labels, D, boxIndex);
        else
            labelsD(selD == 1) = 0;
            writeLayer(obj.labels, labelsD, boxIndex);
            selD(:) = 0;
            writeLayer(obj.selection, selD, boxIndex);
        end

    case 'replace'
        if isType63
            if ~useFiltered
                M = bitand(D, maskValue);                     % save mask bits
                imgTemp = bitand(D, materialMask);             % get model only (clear mask+sel)
                selMask = D >= selectionValue;                 % find selected voxels
                imgTemp(imgTemp == contAddIndex) = 0;  % clear destination material
                imgTemp(selMask) = contAddIndex;       % populate destination material
                D = bitor(imgTemp, M);                 % restore mask
            else
                M = bitand(D, maskValue);
                D = bitand(D, materialMask);                  % clear selection and mask
                D(D == contAddIndex) = 0;              % clear destination material
                D(filteredImg == 1) = contAddIndex;    % populate destination material
                D = bitor(D, M);
            end
            writeLayer(obj.labels, D, boxIndex);
        else
            labelsD(labelsD == contAddIndex) = 0;
            labelsD(selD == 1) = contAddIndex;
            writeLayer(obj.labels, labelsD, boxIndex);
            selD(:) = 0;
            writeLayer(obj.selection, selD, boxIndex);
        end
end
end

function data = readLayer(layer, boxIndex)
% the whole array when there is no box: indexing it with a cell of colons
% would copy it
if isempty(boxIndex)
    data = layer.data;
else
    data = layer.data(boxIndex{:});
end
end

function writeLayer(layer, data, boxIndex)
if isempty(boxIndex)
    layer.data = data;
else
    layer.data(boxIndex{:}) = data;
end
end
