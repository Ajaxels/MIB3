function moveMaskToSelectionDataset(obj, action_type, options)
% function moveMaskToSelectionDataset(obj, action_type, options)
% Move the Mask layer to the Selection layer for the full dataset.
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Parameters:
% action_type: a type of the desired action
% @li 'add' - add mask to selection
% @li 'remove' - remove mask from selection
% @li 'replace' - replace selection with mask
% options: a structure with additional parameters
% @li .contSelIndex - index of the Select from material
% @li .contAddIndex - index of the Add to material
% @li .selected_sw - [0/1] limit actions to the selected material only
% @li .level -> [@em optional], index of image level from the image pyramid, default = 1
%
% Return values:

%|
% @b Examples:
% @code
% options.contSelIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex();
% options.contAddIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex('AddTo');
% options.selected_sw = 0;
% obj.mibModel.I{obj.mibModel.id}.moveMaskToSelectionDataset('add', options);  // add mask to selection
% @endcode
% @attention @b NOT @b sensitive to the blockModeSwitch
% @attention @b NOT @b sensitive to the shown ROI

% Updates
% 

if ~isfield(options, 'contSelIndex'); options.contSelIndex = obj.getSelectedMaterialIndex(); end
if ~isfield(options, 'contAddIndex'); options.contAddIndex = obj.getSelectedMaterialIndex('AddTo'); end
if ~isfield(options, 'selected_sw'); options.selected_sw = obj.restrictSelectionToMaterial; end
if ~isfield(options, 'level'); options.level = 1; end

% swap contSelIndex and contAddIndex when selecting mask with fix selection to material
if options.selected_sw && options.contSelIndex == -1
    if options.contAddIndex == -1
        options.selected_sw = 0;    % Mask/Mask selected — disable
    else
        options.contSelIndex = options.contAddIndex;
    end
end

isType63 = isa(obj.labels, 'core.MibLabels63');

% compute filtered image if restricting to selected material
useFiltered = false;
filteredImg = [];
if isType63
    D = obj.labels.data{options.level};
    if options.selected_sw && obj.modelExist
        useFiltered = true;
        id = bitset(options.contSelIndex, 7, 1);    % generate id with bit 7 = 1 (mask)
        filteredImg = bitset(D, 8, 0);               % model without selection
        filteredImg(filteredImg == id) = 128;          % selection = intersection of material and mask
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
                D = bitor(D, bitand(D, 64)*2);         % copy mask bit to selection bit
            else
                D = bitor(D, filteredImg);
            end
            obj.labels.data{options.level} = D;
        else
            selD = obj.selection.data{options.level};
            if ~useFiltered
                selD = bitor(selD, obj.mask.data{options.level});
            else
                selD = bitor(selD, filteredImg);
            end
            obj.selection.data{options.level} = selD;
        end

    case 'remove'
        if isType63
            if ~useFiltered
                sel = bitget(D, 8);
                sel = sel - bitget(D, 7);               % selection - mask
                D = bitand(D, 127);                      % clear selection
                D = bitor(D, sel*128);                   % set selection
            else
                filteredImg = bitand(D, 128) - filteredImg;
                D = bitand(D, 127);                      % clear selection
                D = bitor(D, filteredImg*128);            % set selection
            end
            obj.labels.data{options.level} = D;
        else
            selD = obj.selection.data{options.level};
            if ~useFiltered
                selD = selD - obj.mask.data{options.level};
            else
                selD = selD - filteredImg;
            end
            obj.selection.data{options.level} = selD;
        end

    case 'replace'
        if isType63
            if ~useFiltered
                sel = bitget(D, 7);                      % get mask
                D = bitand(D, 127);                      % clear selection
                D = bitor(D, sel*128);                   % set selection from mask
            else
                D = bitand(D, 127);                      % clear selection
                D = bitor(D, filteredImg);               % set selection
            end
            obj.labels.data{options.level} = D;
        else
            if ~useFiltered
                obj.selection.data{options.level} = obj.mask.data{options.level};
            else
                obj.selection.data{options.level} = filteredImg;
            end
        end
end
end
