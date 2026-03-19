function addMaterial(obj, materialName, newMaterialIndex)
% function addMaterial(obj, materialName, newMaterialIndex)
% Add a material to an existing model — low-level data layer
%
% Updates obj.labels.materialNames and obj.labels.materialColors and
% adjusts obj.selectedMaterial / obj.selectedAddToMaterial.
%
% For types 63 and 255 the new name is appended to the end of the
% materialNames list and the corresponding colour row is created if absent.
% If no model exists yet, createModel is called first so that the new
% material is recorded together with an empty (zeroed) model matrix.
%
% For types 65535 and 4294967295 the caller (MibModel.addMaterial) is
% responsible for scanning the dataset and supplying the next unused
% material index via newMaterialIndex.  The name stored in materialNames at
% the currently active row is updated to reflect that index, and a colour
% entry is created when needed.
%
% Parameters:
% materialName: char, name for the new material.
%   @li For types 63 / 255 – the human-readable label appended to the list.
%   @li For types 65535 / 4294967295 – typically the string representation
%       of newMaterialIndex; supplied by MibModel.addMaterial.
% newMaterialIndex: [@em optional] double, next unused 1-based material
%   index; required when modelType >= 65535, ignored for types 63 / 255.
%
% Return values:
%

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.addMaterial('Nucleus');           // type-63 / 255 model @endcode
% @code obj.mibModel.I{obj.mibModel.id}.addMaterial('42', 42);            // large model, index supplied @endcode

% Updates
% 

if nargin < 3; newMaterialIndex = []; end
if nargin < 2; materialName = 'NewMaterial'; end

modelType = obj.labels.maxMaterials;

if modelType < 256  %% Types 63 and 255 -----------------------------------------------

    if ~obj.modelExist
        % Create a new model with this first material already named
        obj.createModel(modelType, {materialName});
        return;
    end

    list = obj.labels.materialNames;
    if isempty(list); list = cell(0, 1); end
    list{end+1, 1} = materialName;
    obj.labels.materialNames = list;

    % Ensure a colour row exists for the new material
    nMats = numel(list);
    if size(obj.labels.materialColors, 1) < nMats
        obj.labels.materialColors(nMats, :) = rand(1, 3);
    end

    obj.selectedMaterial      = nMats + 2;
    obj.selectedAddToMaterial = nMats + 2;

else  %% Types 65535 and 4294967295 -------------------------------------------

    if ~obj.modelExist
        obj.createModel(modelType);
    end

    newIdx = newMaterialIndex;

    % Ensure a colour row exists for this index
    if size(obj.labels.materialColors, 1) < newIdx
        obj.labels.materialColors(newIdx, :) = rand(1, 3);
    end

    % Determine which row of materialNames to update
    if obj.restrictSelectionToMaterial
        matIdx = obj.selectedAddToMaterial - 2;
    else
        matIdx = max(obj.selectedMaterial - 2, 1);
    end
    if matIdx < 1; matIdx = 1; end

    % Grow list to at least matIdx rows
    while numel(obj.labels.materialNames) < matIdx
        obj.labels.materialNames{end+1, 1} = '';
    end
    obj.labels.materialNames{matIdx} = materialName;

    obj.selectedMaterial      = matIdx + 2;
    obj.selectedAddToMaterial = matIdx + 2;
end
end
