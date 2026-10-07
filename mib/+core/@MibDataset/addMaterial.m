function [result, newMaterialIndex] = addMaterial(obj, materialName, newMaterialIndex, wb)
% ADDMATERIAL - Add a material to the model - low-level data layer.
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
% unused index is found by rescanning the pixel data for the highest label
% currently in use (unless the caller supplies it via newMaterialIndex),
% capacity is verified, and the new index is registered. It is written into
% the "Add to" row when selection is restricted to material, otherwise into
% the selected material row; only that row's selection moves, unless the
% Material and Add to columns are linked (``unlinkMaterials`` false), in which
% case the other selection follows it.
%
% In all cases obj.labels.materialsCount is incremented by 1 on success.
%
% Input Arguments:
%   - **materialName** *(optional)* - [char] name for the new material (default: ``'NewMaterial'``):
%
%     - For types 63/255 - human-readable label appended to the list
%     - For types 65535/4294967295 - overridden with string representation of the assigned index
%
%   - **newMaterialIndex** *(optional)* - [double] next unused 1-based material index; when empty
%     the method uses ``obj.labels.countMaterials() + 1``, i.e. one above the highest label
%     present in the data. With 2D objects (``obj.labels.objects3D`` false) it is one above
%     the highest label on the shown XY slice instead, and only that slice is read - the
%     numbering of such a model restarts on every slice. Ignored for types 63/255
%   - **wb** *(optional)* - [uiprogressdlg] handle to a progress dialog for displaying progress;
%     when empty no progress is reported
%
% Output Arguments:
%   - **result** - [logical] ``true`` on success; ``false`` when the model is full (capacity exceeded)
%   - **newMaterialIndex** - [double] material index that was actually assigned; relevant for
%     large model types (65535/4294967295); empty for small types (63/255)
%
% **Example 1** - Add material to a small model (type 63/255):
%
%   .. code-block:: matlab
%
%      obj.addMaterial('Nucleus');
%
% **Example 2** - Add material to a large model with auto-indexing:
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

    % Derive the next free index when not supplied. It has to come from the
    % DATA, not from the cached obj.labels.materialsCount: that field is only
    % recomputed on load/import, while this method writes the index it hands
    % out back into it below. Reading it here would therefore return a new
    % index on every click - walking the maximum up without a single voxel
    % being painted - and would also miss indices painted since the model was
    % loaded. countMaterials() rescans all time points for the highest label
    % in use (same as MIB2 did here), so pressing the button repeatedly keeps
    % offering the same free index until it is actually used.
    %
    % With 2D objects (labels.objects3D false) the numbering restarts on every
    % slice, so "free" means free on the shown XY slice and only that slice is
    % read. The cached count is then only ever raised: it stands for the highest
    % index in the whole model, which a slice cannot lower.
    if isempty(newMaterialIndex)
        if ~isempty(wb) && isvalid(wb)
            wb.Message = 'Looking for the next empty material, please wait...';
        end
        if obj.labels.objects3D
            newMaterialIndex = obj.labels.countMaterials() + 1;
        else
            slice = cell2mat(obj.getData2D('labels', obj.slices{3}(1), 3, NaN, ...
                struct('blockModeSwitch', 0)));
            newMaterialIndex = double(max(slice, [], 'all')) + 1;
        end

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

    if obj.labels.objects3D
        obj.labels.materialsCount = newMaterialIndex;
    else
        obj.labels.materialsCount = max(obj.labels.materialsCount, newMaterialIndex);
    end

    % Move only the selection whose row received the new index; the other one
    % follows it only while the Material and Add to columns are linked. With
    % restrict-to-material on and the columns unlinked, the selected material is
    % the one selection is restricted to and must stay where it is (as in MIB2)
    if obj.restrictSelectionToMaterial
        obj.selectedAddToMaterial = matIdx + 2;
        if ~obj.unlinkMaterials; obj.selectedMaterial = matIdx + 2; end
    else
        obj.selectedMaterial = matIdx + 2;
        if ~obj.unlinkMaterials; obj.selectedAddToMaterial = matIdx + 2; end
    end
end
end
