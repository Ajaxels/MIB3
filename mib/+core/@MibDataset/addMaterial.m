function [result, newMaterialIndex] = addMaterial(obj, materialName, newMaterialIndex, wb)
% ADDMATERIAL - Add a material to the model — low-level data layer.
%
% Syntax:
%   .. code-block:: matlab
%
%      [result, newMaterialIndex] = obj.addMaterial(materialName)
%      [result, newMaterialIndex] = obj.addMaterial(materialName, newMaterialIndex)
%      [result, newMaterialIndex] = obj.addMaterial(materialName, newMaterialIndex, wb)
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
% Input Arguments:
%   - **materialName** *(optional)* — [char] name for the new material (default: ``'NewMaterial'``):
%
%     - For types 63/255 — human-readable label appended to the list
%     - For types 65535/4294967295 — overridden with string representation of the assigned index
%
%   - **newMaterialIndex** *(optional)* — [double] next unused 1-based material index; when empty
%     the method uses ``obj.labels.materialsCount + 1``; ignored for types 63/255
%   - **wb** *(optional)* — [uiprogressdlg] handle to a progress dialog for displaying progress;
%     when empty no progress is reported
%
% Output Arguments:
%   - **result** — [logical] ``true`` on success; ``false`` when the model is full (capacity exceeded)
%   - **newMaterialIndex** — [double] material index that was actually assigned; relevant for
%     large model types (65535/4294967295); empty for small types (63/255)
%
% **Example 1** — Add material to a small model (type 63/255):
%
%   .. code-block:: matlab
%
%      obj.addMaterial('Nucleus');
%
% **Example 2** — Add material to a large model with auto-indexing:
%
%   .. code-block:: matlab
%
%      [ok, idx] = obj.addMaterial('', [], wb);

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
