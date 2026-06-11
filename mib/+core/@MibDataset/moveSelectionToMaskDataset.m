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
%   - **action_type** — [char] type of the desired action:
%
%     - ``'add'`` — add selection to mask
%     - ``'remove'`` — remove selection from mask
%     - ``'replace'`` — replace mask with selection
%
%   - **options** — [struct] structure with additional parameters:
%
%     - ``.contSelIndex`` — [numeric] index of the "Select from" material
%     - ``.contAddIndex`` — [numeric] index of the "Add to" material
%     - ``.selected_sw`` — [logical] limit actions to the selected material only (``0`` or ``1``)
%     - ``.maskedAreaSw`` — [logical] limit actions to masked areas only (``0`` or ``1``)%
% Output Arguments:
%   (none)
%
% **Example** — Move selection to mask by adding:
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

% compute filtered image based on selected_sw and maskedAreaSw
useFiltered = false;
filteredImg = [];
if isType63
    D = obj.labels.data;
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 0
        useFiltered = true;
        filteredImg = bitand(uint8(bitand(D, 63) == options.contSelIndex), bitand(D, 128)/128);
    elseif options.maskedAreaSw && options.selected_sw == 0
        if strcmp(action_type, 'add'); return; end
        if strcmp(action_type, 'replace')
            useFiltered = true;
            filteredImg = bitand(bitand(D, 64)/64, bitand(D, 128)/128);
        end
    elseif options.selected_sw && obj.modelExist && options.maskedAreaSw == 1
        if strcmp(action_type, 'add'); return; end
        useFiltered = true;
        filteredImg = bitand(uint8(bitand(D, 63) == options.contSelIndex), bitand(D, 128)/128);
        filteredImg = bitand(filteredImg, bitand(D, 64)/64);
    end
else
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 0
        useFiltered = true;
        filteredImg = uint8(obj.labels.data == options.contSelIndex);
        filteredImg = bitand(obj.selection.data, filteredImg);
    end
    if options.maskedAreaSw && options.selected_sw == 0
        if strcmp(action_type, 'add'); return; end
        if strcmp(action_type, 'replace')
            useFiltered = true;
            filteredImg = bitand(obj.selection.data, obj.mask.data);
        end
    end
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 1
        if strcmp(action_type, 'add'); return; end
        useFiltered = true;
        filteredImg = uint8(obj.labels.data == options.contSelIndex);
        filteredImg = bitand(bitand(filteredImg, obj.mask.data), obj.selection.data);
    end
end

switch action_type
    case 'add'
        if isType63
            if ~useFiltered
                D = bitor(D, bitand(D, 128)/2);      % copy selection to mask
            else
                D = bitor(D, filteredImg * 64);
            end
            D = bitand(D, 127);                       % clear selection
            obj.labels.data = D;
        else
            maskD = obj.mask.data;
            selD = obj.selection.data;
            if ~useFiltered
                maskD = bitor(selD, maskD);
            else
                maskD = bitor(maskD, filteredImg);
            end
            selD(:) = 0;
            obj.mask.data = maskD;
            obj.selection.data = selD;
        end

    case 'remove'
        if isType63
            if ~useFiltered
                msk = bitget(D, 7);
                msk = msk - bitget(D, 8);             % mask - selection
                D = bitand(D, 63);                     % clear selection and mask
                D = bitor(D, msk * 64);                % set mask
            else
                filteredImg = bitand(D, 64)/64 - filteredImg;
                D = bitand(D, 63);                     % clear selection and mask
                D = bitor(D, filteredImg * 64);        % set mask
            end
            obj.labels.data = D;
        else
            maskD = obj.mask.data;
            if ~useFiltered
                maskD = maskD - obj.selection.data;
            else
                maskD = maskD - filteredImg;
            end
            obj.mask.data = maskD;
            obj.selection.data(:) = 0;
        end

    case 'replace'
        if isType63
            if ~useFiltered
                sel = bitget(D, 8);
                D = bitand(D, 63);                     % clear selection and mask
                D = bitor(D, sel * 64);                % set mask from selection
            else
                D = bitand(D, 63);                     % clear selection and mask
                D = bitor(D, filteredImg * 64);        % set mask
            end
            obj.labels.data = D;
        else
            if ~useFiltered
                obj.mask.data = obj.selection.data;
            else
                obj.mask.data = filteredImg;
            end
            obj.selection.data(:) = 0;
        end
end
obj.maskExist = 1;
end
