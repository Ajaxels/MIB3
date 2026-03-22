function moveModelToMaskDataset(obj, action_type, options)
% function moveModelToMaskDataset(obj, action_type, options)
% Move the selected Material to the Mask layer for the full dataset.
%
% Fast-path function for moving complete datasets between layers without
% ROI or block mode. Operates directly on packed data arrays for maximum
% performance.
%
% Parameters:
% action_type: a type of the desired action
% @li 'add' - add the selected material (Select from) to mask
% @li 'remove' - remove the selected material (Select from) from mask
% @li 'replace' - replace mask with the selected (Select from) material
% options: a structure with additional parameters
% @li .contSelIndex - index of the Select from material
% @li .contAddIndex - index of the Add to material
% @li .level -> [@em optional], index of image level from the image pyramid, default = 1
%
% Return values:

%|
% @b Examples:
% @code
% options.contSelIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex();
% options.contAddIndex = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex('AddTo');
% obj.mibModel.I{obj.mibModel.id}.moveModelToMaskDataset('add', options);  // add material to mask
% @endcode
% @attention @b NOT @b sensitive to the blockModeSwitch
% @attention @b NOT @b sensitive to the shown ROI

% Updates
% 

if ~isfield(options, 'contSelIndex'); options.contSelIndex = obj.getSelectedMaterialIndex(); end
if ~isfield(options, 'contAddIndex'); options.contAddIndex = obj.getSelectedMaterialIndex('AddTo'); end
if ~isfield(options, 'level'); options.level = 1; end

isType63 = isa(obj.labels, 'core.MibLabels63');

switch action_type
    case 'add'
        if isType63
            D = obj.labels.data{options.level};
            matMask = uint8(bitand(D, 63) == options.contSelIndex) * 64;
            D = bitor(D, matMask);
            obj.labels.data{options.level} = D;
        else
            maskD = obj.mask.data{options.level};
            maskD(obj.labels.data{options.level} == options.contSelIndex) = 1;
            obj.mask.data{options.level} = maskD;
        end

    case 'remove'
        if isType63
            D = obj.labels.data{options.level};
            matMask = uint8(bitand(D, 63) == options.contSelIndex) * 64;
            D = D - bitand(D, matMask);
            obj.labels.data{options.level} = D;
        else
            maskD = obj.mask.data{options.level};
            maskD = maskD - uint8(obj.labels.data{options.level} == options.contSelIndex);
            obj.mask.data{options.level} = maskD;
        end

    case 'replace'
        if isType63
            D = obj.labels.data{options.level};
            D = bitset(D, 7, 0);                     % clear mask
            matMask = uint8(bitand(D, 63) == options.contSelIndex) * 64;
            D = bitor(D, matMask);
            obj.labels.data{options.level} = D;
        else
            maskD = uint8(obj.labels.data{options.level} == options.contSelIndex);
            obj.mask.data{options.level} = maskD;
        end
end
end
