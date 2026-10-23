function moveMaskToModelDataset(obj, action_type, options)
% MOVEMASKTOMODELDATASET - Move the Mask layer to the Model layer for the full dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.moveMaskToModelDataset(action_type, options)
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Input Arguments:
%   - **action_type** - a type of the desired action:
%
%     - ``'add'`` - add mask to the selected material (Add to)
%     - ``'remove'`` - remove mask from the model
%     - ``'replace'`` - replace the selected (Add to) material with mask
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
%     obj.mibModel.I{obj.mibModel.id}.moveMaskToModelDataset('add', options);% add mask to model
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
if obj.modelExist == 0
    error('moveMaskToModelDataset: the model is not yet created');
end

isType63 = isa(obj.labels, 'core.MibLabels63');

% compute filtered image if restricting to selected material
useFiltered = false;
filteredImg = [];
if isType63
    D = obj.labels.data;
    % packed bit layout: uint8 (63 materials) or uint16 (16383 instances)
    materialMask = obj.labels.materialMask;
    maskValue    = obj.labels.maskValue;
    flagsMask    = obj.labels.flagsMask;
    if options.selected_sw && obj.modelExist
        useFiltered = true;
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
                maskIdx = bitand(D, maskValue) == maskValue;
                D(maskIdx) = bitand(D(maskIdx), flagsMask);          % clear model bits where mask
                D(maskIdx) = bitor(D(maskIdx), options.contAddIndex); % set material
            else
                D(filteredImg == 1) = bitand(D(filteredImg == 1), flagsMask);
                D(filteredImg == 1) = bitor(D(filteredImg == 1), options.contAddIndex);
            end
            obj.labels.data = D;
        else
            labelsD = obj.labels.data;
            if ~useFiltered
                labelsD(obj.mask.data == 1) = options.contAddIndex;
            else
                labelsD(filteredImg == 1) = options.contAddIndex;
            end
            obj.labels.data = labelsD;
        end

    case 'remove'
        if isType63
            if ~useFiltered
                maskIdx = bitand(D, maskValue) == maskValue;
                D(maskIdx) = bitand(D(maskIdx), flagsMask);    % clear model bits where mask
            else
                D(filteredImg == 1) = bitand(D(filteredImg == 1), flagsMask);
            end
            obj.labels.data = D;
        else
            labelsD = obj.labels.data;
            if ~useFiltered
                labelsD(obj.mask.data == 1) = 0;
            else
                labelsD(filteredImg == 1) = 0;
            end
            obj.labels.data = labelsD;
        end

    case 'replace'
        if isType63
            if ~useFiltered
                M = bitand(D, flagsMask);              % store mask and selection bits
                D(bitand(D, materialMask) == options.contAddIndex) = ...
                    bitand(D(bitand(D, materialMask) == options.contAddIndex), flagsMask);  % clear destination material
                D(bitand(M, maskValue) == maskValue) = options.contAddIndex;    % set material where mask
                D = bitor(D, M);                                             % restore mask and selection
            else
                M = bitand(D, flagsMask);              % store mask and selection bits
                D(bitand(D, materialMask) == options.contAddIndex) = ...
                    bitand(D(bitand(D, materialMask) == options.contAddIndex), flagsMask);   % clear destination material
                D(filteredImg == 1) = options.contAddIndex;
                D = bitor(D, M);
            end
            obj.labels.data = D;
        else
            labelsD = obj.labels.data;
            if ~useFiltered
                labelsD(labelsD == options.contAddIndex) = 0;
                labelsD(obj.mask.data == 1) = options.contAddIndex;
            else
                labelsD(filteredImg == 1) = 0;
                labelsD(filteredImg == 1) = options.contAddIndex;
            end
            obj.labels.data = labelsD;
        end
end
end
