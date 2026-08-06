function renameMaterial(obj, index, newName)
% RENAMEMATERIAL - Rename one or all materials in the model metadata.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.renameMaterial(index, newName)
%
% For small models (maxMaterials < 256) the material name at position
% index is replaced with newName.  When index is 0, all materials are
% renamed at once using a comma-separated list in newName.
%
% For large models (maxMaterials >= 256) the name is set at the given
% index; the caller is responsible for supplying a numeric string.
%
% Input Arguments:
%   - **index** - double, 1-based material index to rename.  Use 0 to rename all
%     materials at once (newName must then be a comma-separated list of
%     names matching the number of existing materials).
%   - **newName** - char, new material name (single name) or comma-separated list
%     (when index == 0).
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.labels.renameMaterial(3, 'Nucleus');% rename material 3
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.labels.renameMaterial(0, 'A,B,C');% rename all three materials
%

% Updates
%

if index == 0
    % Rename all materials from a comma-separated list
    newNames = strtrim(strsplit(newName, ','))';
    if numel(newNames) == numel(obj.materialNames)
        obj.materialNames = newNames;
    end
else
    % guard against addressing a non-existing row: for 65535+ models the callers
    % must pass the table slot (1 or 2), not the material index stored in the slot
    if index < 1 || index > numel(obj.materialNames)
        error('MibLabels:renameMaterial:badIndex', ...
            'renameMaterial: material index (%d) is outside of the existing materials (1-%d)!', ...
            index, numel(obj.materialNames));
    end
    obj.materialNames{index} = newName;
end
end
