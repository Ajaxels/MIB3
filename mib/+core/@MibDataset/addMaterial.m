function [result, newMaterialIndex] = addMaterial(obj, materialName, newMaterialIndex, wb)
% function [result, newMaterialIndex] = addMaterial(obj, materialName, newMaterialIndex, wb)
% Add a material to the model — low-level data layer
%
% Creates the model when it does not yet exist.  For small model types
% (63/255) the new name is appended to the materialNames list and a colour
% row is generated.  For large model types (65535/4294967295) the next
% unused index is derived from obj.labels.materialsCount (unless the caller
% supplies it via newMaterialIndex), capacity is verified, and the new
% index is registered.
%
% In all cases obj.labels.materialsCount is incremented by 1 on success.
%
% Parameters:
% materialName: [@em optional] char, name for the new material
%   [@em default 'NewMaterial'].
%   @li For types 63 / 255 – the human-readable label appended to the list.
%   @li For types 65535 / 4294967295 – overridden with the string
%       representation of the assigned index.
% newMaterialIndex: [@em optional] double, next unused 1-based material
%   index.  When empty the method uses obj.labels.materialsCount + 1.
%   Ignored for types 63 / 255.
% wb: [@em optional] handle to a uiprogressdlg used for progress display;
%   when empty no progress is reported.
%
% Return values:
% result: logical, true on success, false when the model is full
%   (capacity exceeded).
% newMaterialIndex: double, the material index that was actually assigned;
%   relevant for large model types, empty for small types.
%

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.addMaterial('Nucleus');              // type-63 / 255 model @endcode
% @code [ok, idx] = obj.mibModel.I{obj.mibModel.id}.addMaterial('', [], wb); // large model, auto-index @endcode

% Updates
%

if nargin < 4; wb = []; end
if nargin < 3; newMaterialIndex = []; end
if nargin < 2; materialName = 'NewMaterial'; end

result = true;
modelType = obj.labels.maxMaterials;

if modelType < 256  %% Types 63 and 255 -----------------------------------------------

    if ~obj.modelExist
        obj.createModel(modelType, {materialName});
        return;
    end

    list = obj.labels.materialNames;
    if isempty(list); list = cell(0, 1); end
    nMats = numel(list);

    % Capacity check
    if modelType < nMats + 1
        result = false;
        return;
    end

    list{end+1, 1} = materialName;
    obj.labels.materialNames = list;

    nMats = numel(list);
    if size(obj.labels.materialColors, 1) < nMats
        obj.labels.materialColors(nMats, :) = rand(1, 3);
    end

    obj.labels.materialsCount = nMats;
    obj.selectedMaterial      = nMats + 2;
    obj.selectedAddToMaterial = nMats + 2;
    newMaterialIndex = [];

else  %% Types 65535 and 4294967295 -------------------------------------------

    if ~obj.modelExist
        obj.createModel(modelType);
    end

    % Derive next index from materialsCount when not supplied
    if isempty(newMaterialIndex)
        newMaterialIndex = obj.labels.materialsCount + 1;

        if newMaterialIndex > modelType
            result = false;
            return;
        end
    end

    materialName = num2str(newMaterialIndex);

    % Ensure a colour row exists for this index
    if size(obj.labels.materialColors, 1) < newMaterialIndex
        obj.labels.materialColors(newMaterialIndex, :) = rand(1, 3);
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

    obj.labels.materialsCount = newMaterialIndex;
    obj.selectedMaterial      = matIdx + 2;
    obj.selectedAddToMaterial = matIdx + 2;
end
end
