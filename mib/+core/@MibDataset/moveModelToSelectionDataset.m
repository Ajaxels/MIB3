function moveModelToSelectionDataset(obj, action_type, options)
% function moveModelToSelectionDataset(obj, action_type, options)
% Move the selected Material to the Selection layer for the full dataset.
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Parameters:
% action_type: a type of the desired action
% @li 'add' - add the selected material (Select from) to selection
% @li 'remove' - remove the selected material (Select from) from selection
% @li 'replace' - replace selection with the selected (Select from) material
% options: a structure with additional parameters
% @li .contSelIndex - index of the Select from material
% @li .contAddIndex - index of the Add to material
% @li .maskedAreaSw - [0/1] limit actions to the masked areas
% @li .level -> [@em optional], index of image level from the image pyramid, default = 1
%
% Return values:

%|
% @b Examples:
% @code
% options.contSelIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex();
% options.contAddIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex('AddTo');
% options.maskedAreaSw = 0;
% obj.mibModel.I{obj.mibModel.id}.moveModelToSelectionDataset('add', options);  // add material to selection
% @endcode
% @attention @b NOT @b sensitive to the blockModeSwitch
% @attention @b NOT @b sensitive to the shown ROI

% Updates
% 

if ~isfield(options, 'contSelIndex'); options.contSelIndex = obj.getSelectedMaterialIndex(); end
if ~isfield(options, 'contAddIndex'); options.contAddIndex = obj.getSelectedMaterialIndex('AddTo'); end
if ~isfield(options, 'maskedAreaSw'); options.maskedAreaSw = obj.restrictSelectionToMask; end
if ~isfield(options, 'level'); options.level = 1; end

isType63 = isa(obj.labels, 'core.MibLabels63');

% compute filtered image if restricting to masked area
useFiltered = false;
filteredImg = [];
if isType63
    D = obj.labels.data{options.level};
    if options.maskedAreaSw == 1
        useFiltered = true;
        filteredImg = bitand(uint8(bitand(D, 63) == options.contSelIndex), bitand(D, 64)/64);
    end
else
    if options.maskedAreaSw == 1
        useFiltered = true;
        filteredImg = bitand(obj.mask.data{options.level}, uint8(obj.labels.data{options.level} == options.contSelIndex));
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
            obj.labels.data{options.level} = D;
        else
            selD = obj.selection.data{options.level};
            if ~useFiltered
                selD(obj.labels.data{options.level} == options.contSelIndex) = 1;
            else
                selD = bitor(selD, filteredImg);
            end
            obj.selection.data{options.level} = selD;
        end

    case 'remove'
        if isType63
            if ~useFiltered
                matMask = uint8(bitand(D, 63) == options.contSelIndex) * 128;
                D = D - bitand(D, matMask);
            else
                D = D - bitand(D, filteredImg * 128);
            end
            obj.labels.data{options.level} = D;
        else
            selD = obj.selection.data{options.level};
            if ~useFiltered
                selD = selD - uint8(obj.labels.data{options.level} == options.contSelIndex);
            else
                selD = selD - filteredImg;
            end
            obj.selection.data{options.level} = selD;
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
            obj.labels.data{options.level} = D;
        else
            if ~useFiltered
                obj.selection.data{options.level} = uint8(obj.labels.data{options.level} == options.contSelIndex);
            else
                selD = zeros(size(obj.selection.data{options.level}), 'uint8');
                selD = bitor(selD, filteredImg);
                obj.selection.data{options.level} = selD;
            end
        end
end
end
