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
%   - **action_type** — a type of the desired action:
%
%     - ``'add'`` — add mask to the selected material (Add to)
%     - ``'remove'`` — remove mask from the model
%     - ``'replace'`` — replace the selected (Add to) material with mask
%
%   - **options** — a structure with additional parameters
%
%     - ``.contSelIndex`` — index of the Select from material
%     - ``.contAddIndex`` — index of the Add to material
%     - ``.selected_sw`` — [0/1] limit actions to the selected material only
%     - ``.level`` *(optional)*, index of image level from the image pyramid, default = 1
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
if ~isfield(options, 'level'); options.level = 1; end

if obj.modelExist == 0
    error('moveMaskToModelDataset: the model is not yet created');
end

isType63 = isa(obj.labels, 'core.MibLabels63');

% compute filtered image if restricting to selected material
useFiltered = false;
filteredImg = [];
if isType63
    D = obj.labels.data{options.level};
    if options.selected_sw && obj.modelExist
        useFiltered = true;
        filteredImg = bitand(uint8(bitand(D, 63) == options.contSelIndex), bitand(D, 64)/64);
    end
else
    if options.selected_sw && obj.modelExist
        useFiltered = true;
        filteredImg = uint8(obj.labels.data{options.level} == options.contSelIndex);
        filteredImg = bitand(obj.mask.data{options.level}, filteredImg);
    end
end

switch action_type
    case 'add'
        if isType63
            if ~useFiltered
                maskIdx = bitand(D, 64) == 64;
                D(maskIdx) = bitand(D(maskIdx), 192);                % clear model bits where mask
                D(maskIdx) = bitor(D(maskIdx), options.contAddIndex); % set material
            else
                D(filteredImg == 1) = bitand(D(filteredImg == 1), 192);
                D(filteredImg == 1) = bitor(D(filteredImg == 1), options.contAddIndex);
            end
            obj.labels.data{options.level} = D;
        else
            labelsD = obj.labels.data{options.level};
            if ~useFiltered
                labelsD(obj.mask.data{options.level} == 1) = options.contAddIndex;
            else
                labelsD(filteredImg == 1) = options.contAddIndex;
            end
            obj.labels.data{options.level} = labelsD;
        end

    case 'remove'
        if isType63
            if ~useFiltered
                maskIdx = bitand(D, 64) == 64;
                D(maskIdx) = bitand(D(maskIdx), 192);    % clear model bits where mask (192 = 11000000)
            else
                D(filteredImg == 1) = bitand(D(filteredImg == 1), 192);
            end
            obj.labels.data{options.level} = D;
        else
            labelsD = obj.labels.data{options.level};
            if ~useFiltered
                labelsD(obj.mask.data{options.level} == 1) = 0;
            else
                labelsD(filteredImg == 1) = 0;
            end
            obj.labels.data{options.level} = labelsD;
        end

    case 'replace'
        if isType63
            if ~useFiltered
                M = bitshift(bitshift(D, -6), 6);     % store mask and selection bits
                D(bitand(D, 63) == options.contAddIndex) = ...
                    bitand(D(bitand(D, 63) == options.contAddIndex), 192);  % clear destination material
                D(bitand(M, 64) == 64) = options.contAddIndex;              % set material where mask
                D = bitor(D, M);                                             % restore mask and selection
            else
                M = bitshift(bitshift(D, -6), 6);     % store mask and selection bits
                D(bitand(D, options.contAddIndex) == options.contAddIndex) = ...
                    bitand(D(bitand(D, options.contAddIndex) == options.contAddIndex), 192);
                D(filteredImg == 1) = options.contAddIndex;
                D = bitor(D, M);
            end
            obj.labels.data{options.level} = D;
        else
            labelsD = obj.labels.data{options.level};
            if ~useFiltered
                labelsD(labelsD == options.contAddIndex) = 0;
                labelsD(obj.mask.data{options.level} == 1) = options.contAddIndex;
            else
                labelsD(filteredImg == 1) = 0;
                labelsD(filteredImg == 1) = options.contAddIndex;
            end
            obj.labels.data{options.level} = labelsD;
        end
end
end
