function moveSelectionToModelDataset(obj, action_type, options)
% function moveSelectionToModelDataset(obj, action_type, options)
% Move the Selection layer to the Model layer for the full dataset.
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Parameters:
% action_type: a type of the desired action
% @li 'add' - add selection to the selected material (Add to)
% @li 'remove' - remove selection from the model
% @li 'replace' - replace the selected (Add to) material with selection
% options: a structure with additional parameters
% @li .contSelIndex - index of the Select from material
% @li .contAddIndex - index of the Add to material
% @li .selected_sw - [0/1] limit actions to the selected material only
% @li .maskedAreaSw - [0/1] limit actions to the masked areas
% @li .level -> [@em optional], index of image level from the image pyramid, default = 1
%
% Return values:

%|
% @b Examples:
% @code
% options.contSelIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex();
% options.contAddIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex('AddTo');
% options.selected_sw = 0;
% options.maskedAreaSw = 0;
% obj.mibModel.I{obj.mibModel.id}.moveSelectionToModelDataset('add', options);  // add selection to model
% @endcode
% @attention @b NOT @b sensitive to the blockModeSwitch
% @attention @b NOT @b sensitive to the shown ROI

% Updates
% 

if ~isfield(options, 'contSelIndex'); options.contSelIndex = obj.getSelectedMaterialIndex(); end
if ~isfield(options, 'contAddIndex'); options.contAddIndex = obj.getSelectedMaterialIndex('AddTo'); end
if ~isfield(options, 'selected_sw'); options.selected_sw = obj.restrictSelectionToMaterial; end
if ~isfield(options, 'maskedAreaSw'); options.maskedAreaSw = obj.restrictSelectionToMask; end
if ~isfield(options, 'level'); options.level = 1; end

isType63 = isa(obj.labels, 'core.MibLabels63');

% compute filtered image based on selected_sw and maskedAreaSw
useFiltered = false;
filteredImg = [];
if isType63
    D = obj.labels.data{options.level};
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
    selD = obj.selection.data{options.level};
    if options.selected_sw && obj.modelExist && options.maskedAreaSw == 0
        selD(obj.labels.data{options.level} ~= options.contSelIndex) = 0;
    elseif options.maskedAreaSw && options.selected_sw == 0
        selD = bitand(selD, obj.mask.data{options.level});
    elseif options.selected_sw && obj.modelExist && options.maskedAreaSw == 1
        selD = bitand(selD, obj.mask.data{options.level});
        selD(obj.labels.data{options.level} ~= options.contSelIndex) = 0;
    end
    obj.selection.data{options.level} = selD;
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
            obj.labels.data{options.level} = D;
        else
            labelsD = obj.labels.data{options.level};
            labelsD(obj.selection.data{options.level} == 1) = contAddIndex;
            obj.labels.data{options.level} = labelsD;
            obj.selection.data{options.level}(:) = 0;
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
            obj.labels.data{options.level} = D;
        else
            labelsD = obj.labels.data{options.level};
            labelsD(obj.selection.data{options.level} == 1) = 0;
            obj.labels.data{options.level} = labelsD;
            obj.selection.data{options.level}(:) = 0;
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
            obj.labels.data{options.level} = D;
        else
            labelsD = obj.labels.data{options.level};
            labelsD(labelsD == contAddIndex) = 0;
            labelsD(obj.selection.data{options.level} == 1) = contAddIndex;
            obj.labels.data{options.level} = labelsD;
            obj.selection.data{options.level}(:) = 0;
        end
end
end
