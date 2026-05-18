function index = getSelectedMaterialIndex(obj, target)
% GETSELECTEDMATERIALINDEX - return the index of the currently selected material in the mibView.handles.materialsTable.
%
% Syntax:
%   .. code-block:: matlab
%
%       index = obj.getSelectedMaterialIndex(target)
%
% Input Arguments:
%   - **target** — a string specifying the target column of the materials table:
%
%     - ``'Material'`` — *(default)* the selected row in the material column
%     - ``'AddTo'`` — the selected row in the AddTo column
%
% Output Arguments:
%   - **index** — index of the currently selected material:
%
%     - ``-1`` — Mask
%     - ``0`` — Exterior
%     - ``1`` — 1st material of the model
%     - ``2``, ``3``, ... — 2nd, 3rd, ... material of the model
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     selcontour = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex();% call from mibController class; return the index of the currently selected material
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     selcontour = obj.mibModel.I{obj.mibModel.id}.getSelectedMaterialIndex('AddTo');% call from mibController class; return the index of the currently selected material in the AddTo column
%

if nargin < 2; target = 'Material'; end

switch target
    case 'Material'
        index = obj.selectedMaterial;
    case 'AddTo'
        index = obj.selectedAddToMaterial;
end

if obj.labels.maxMaterials < 256
    index = index - 2;
else
    index = index - 2;
    if index > 0 && index <= numel(obj.labels.materialNames)
        index = str2double(obj.labels.materialNames{index});
    elseif index > numel(obj.labels.materialNames)
        index = 0;  % selection points past the registered slots; treat as Exterior
    end
end
end
