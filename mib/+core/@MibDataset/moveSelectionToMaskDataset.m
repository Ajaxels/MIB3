function moveSelectionToMaskDataset(obj, action_type, options)
% MOVESELECTIONTOMASKDATASET - Move the Selection layer to the Mask layer for the full dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.moveSelectionToMaskDataset(action_type, options)
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Input Arguments:
%   - **action_type** - [char] type of the desired action:
%
%     - ``'add'`` - add selection to mask
%     - ``'remove'`` - remove selection from mask
%     - ``'replace'`` - replace mask with selection
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
%       selection. Ignored for ``'replace'``, which also clears the mask outside
%       the selection. Default: ``[]``, the whole dataset.
%
% Output Arguments:
%   (none)
%
% **Example** - Move selection to mask by adding:
%
%   .. code-block:: matlab
%
%      options.contSelIndex = obj.getSelectedMaterialIndex();
%      options.contAddIndex = obj.getSelectedMaterialIndex('AddTo');
%      options.selected_sw = 0;
%      options.maskedAreaSw = 0;
%      obj.moveSelectionToMaskDataset('add', options);
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
% allocate the mask container when it is missing (no-op for MibLabels63);
% also sets mask.exists so reads through getData do not return empty
obj.allocateMask();

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
        if strcmp(action_type, 'add'); return; end
        if strcmp(action_type, 'replace')
            useFiltered = true;
            filteredImg = bitand(bitand(D, maskValue)/maskValue, bitand(D, selectionValue)/selectionValue);
        end
    elseif options.selected_sw && obj.modelExist && options.maskedAreaSw == 1
        if strcmp(action_type, 'add'); return; end
        useFiltered = true;
        filteredImg = bitand(cast(bitand(D, materialMask) == options.contSelIndex, 'like', D), bitand(D, selectionValue)/selectionValue);
        filteredImg = bitand(filteredImg, bitand(D, maskValue)/maskValue);
    end
else
    selD = readLayer(obj.selection, boxIndex);
    maskD = readLayer(obj.mask, boxIndex);
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 0
        useFiltered = true;
        filteredImg = uint8(readLayer(obj.labels, boxIndex) == options.contSelIndex);
        filteredImg = bitand(selD, filteredImg);
    end
    if options.maskedAreaSw && options.selected_sw == 0
        if strcmp(action_type, 'add'); return; end
        if strcmp(action_type, 'replace')
            useFiltered = true;
            filteredImg = bitand(selD, maskD);
        end
    end
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 1
        if strcmp(action_type, 'add'); return; end
        useFiltered = true;
        filteredImg = uint8(readLayer(obj.labels, boxIndex) == options.contSelIndex);
        filteredImg = bitand(bitand(filteredImg, maskD), selD);
    end
end

switch action_type
    case 'add'
        if isType63
            if ~useFiltered
                D = bitor(D, bitand(D, selectionValue)/2);      % copy selection to mask
            else
                D = bitor(D, filteredImg * cast(maskValue, 'like', D));
            end
            D = bitand(D, selectionValue - 1);                  % clear selection
            writeLayer(obj.labels, D, boxIndex);
        else
            if ~useFiltered
                maskD = bitor(selD, maskD);
            else
                maskD = bitor(maskD, filteredImg);
            end
            selD(:) = 0;
            writeLayer(obj.mask, maskD, boxIndex);
            writeLayer(obj.selection, selD, boxIndex);
        end

    case 'remove'
        if isType63
            if ~useFiltered
                msk = bitget(D, obj.labels.maskBit);
                msk = msk - bitget(D, obj.labels.selectionBit);   % mask - selection
                D = bitand(D, materialMask);           % clear selection and mask
                D = bitor(D, msk * cast(maskValue, 'like', D));         % set mask
            else
                filteredImg = bitand(D, maskValue)/maskValue - filteredImg;
                D = bitand(D, materialMask);           % clear selection and mask
                D = bitor(D, filteredImg * cast(maskValue, 'like', D)); % set mask
            end
            writeLayer(obj.labels, D, boxIndex);
        else
            if ~useFiltered
                maskD = maskD - selD;
            else
                maskD = maskD - filteredImg;
            end
            selD(:) = 0;
            writeLayer(obj.mask, maskD, boxIndex);
            writeLayer(obj.selection, selD, boxIndex);
        end

    case 'replace'
        if isType63
            if ~useFiltered
                sel = bitget(D, obj.labels.selectionBit);
                D = bitand(D, materialMask);           % clear selection and mask
                D = bitor(D, sel * cast(maskValue, 'like', D));         % set mask from selection
            else
                D = bitand(D, materialMask);           % clear selection and mask
                D = bitor(D, filteredImg * cast(maskValue, 'like', D)); % set mask
            end
            writeLayer(obj.labels, D, boxIndex);
        else
            if ~useFiltered
                maskD = selD;
            else
                maskD = filteredImg;
            end
            selD(:) = 0;
            writeLayer(obj.mask, maskD, boxIndex);
            writeLayer(obj.selection, selD, boxIndex);
        end
end
obj.maskExist = 1;
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
