function moveMaskToSelectionDataset(obj, action_type, options)
% MOVEMASKTOSELECTIONDATASET - Move the Mask layer to the Selection layer for the full dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.moveMaskToSelectionDataset(action_type, options)
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Input Arguments:
%   - **action_type** - a type of the desired action:
%
%     - ``'add'`` - add mask to selection
%     - ``'remove'`` - remove mask from selection
%     - ``'replace'`` - replace selection with mask
%
%   - **options** - a structure with additional parameters
%
%     - ``.contSelIndex`` - index of the Select from material
%     - ``.contAddIndex`` - index of the Add to material
%     - ``.selected_sw`` - [0/1] limit actions to the selected material only
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     options.contSelIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex();
%     options.contAddIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex('AddTo');
%     options.selected_sw = 0;
%     obj.mibModel.I{obj.mibModel.id}.moveMaskToSelectionDataset('add', options);% add mask to selection
%
%
%   **Attention:** **NOT** **sensitive** to the blockModeSwitch
%
%   **Attention:** **NOT** **sensitive** to the shown ROI
%

% Updates
% 

if ~isfield(options, 'contSelIndex'); options.contSelIndex = obj.getSelectedMaterialIndex(); end
if ~isfield(options, 'contAddIndex'); options.contAddIndex = obj.getSelectedMaterialIndex('AddTo'); end
if ~isfield(options, 'selected_sw'); options.selected_sw = obj.restrictSelectionToMaterial; end
% swap contSelIndex and contAddIndex when selecting mask with fix selection to material
if options.selected_sw && options.contSelIndex == -1
    if options.contAddIndex == -1
        options.selected_sw = 0;    % Mask/Mask selected - disable
    else
        options.contSelIndex = options.contAddIndex;
    end
end

isType63 = isa(obj.labels, 'core.MibLabels63');

% compute filtered image if restricting to selected material
useFiltered = false;
filteredImg = [];
if isType63
    D = obj.labels.data;
    % packed bit layout: uint8 (63 materials) or uint16 (16383 instances)
    materialMask   = obj.labels.materialMask;
    maskValue      = obj.labels.maskValue;
    selectionValue = obj.labels.selectionValue;
    if options.selected_sw && obj.modelExist
        useFiltered = true;
        % binary 0/1: intersection of the material and the mask
        filteredImg = bitand(cast(bitand(D, materialMask) == options.contSelIndex, 'like', D), bitand(D, maskValue)/maskValue);
    end
else
    if options.selected_sw && obj.modelExist
        useFiltered = true;
        filteredImg = uint8(obj.labels.data == options.contSelIndex);
        filteredImg = bitand(obj.mask.data, filteredImg);
    end
end

switch action_type
    case 'add'
        if isType63
            if ~useFiltered
                D = bitor(D, bitand(D, maskValue)*2);  % copy mask bit to selection bit
            else
                D = bitor(D, filteredImg* cast(selectionValue, 'like', D));
            end
            obj.labels.data = D;
        else
            selD = obj.selection.data;
            if ~useFiltered
                selD = bitor(selD, obj.mask.data);
            else
                selD = bitor(selD, filteredImg);
            end
            obj.selection.data = selD;
        end

    case 'remove'
        if isType63
            if ~useFiltered
                sel = bitget(D, obj.labels.selectionBit);
                sel = sel - bitget(D, obj.labels.maskBit);   % selection - mask
                D = bitand(D, selectionValue - 1);            % clear selection
                D = bitor(D, sel* cast(selectionValue, 'like', D));             % set selection
            else
                filteredImg = bitand(D, selectionValue)/selectionValue - filteredImg;
                D = bitand(D, selectionValue - 1);            % clear selection
                D = bitor(D, filteredImg* cast(selectionValue, 'like', D));     % set selection
            end
            obj.labels.data = D;
        else
            selD = obj.selection.data;
            if ~useFiltered
                selD = selD - obj.mask.data;
            else
                selD = selD - filteredImg;
            end
            obj.selection.data = selD;
        end

    case 'replace'
        if isType63
            if ~useFiltered
                sel = bitget(D, obj.labels.maskBit);          % get mask
                D = bitand(D, selectionValue - 1);            % clear selection
                D = bitor(D, sel* cast(selectionValue, 'like', D));             % set selection from mask
            else
                D = bitand(D, selectionValue - 1);            % clear selection
                D = bitor(D, filteredImg* cast(selectionValue, 'like', D));     % set selection
            end
            obj.labels.data = D;
        else
            if ~useFiltered
                obj.selection.data = obj.mask.data;
            else
                obj.selection.data = filteredImg;
            end
        end
end
end
