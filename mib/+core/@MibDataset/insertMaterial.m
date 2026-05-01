function insertMaterial(obj, materialIndex, materialName, wb)
% INSERTMATERIAL - Insert a new material at the specified position — MibDataset wrapper.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.insertMaterial(materialIndex, materialName, wb)
%
% Delegates to obj.labels.insertMaterial which handles both the pixel
% data shifting (via direct obj.data{1} access) and the metadata
% update (names, colours, materialsCount).
%
% Input Arguments:
%   - **materialIndex** — double, 1-based position where the new material is
%     inserted.
%   - **materialName** — char, name of the new material (used for small models;
%     ignored for large models).
%   - **wb** — *(optional)* handle to a uiprogressdlg for progress display;
%     when empty no progress is reported.
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.insertMaterial(3, 'Nucleus');% insert at position 3
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.insertMaterial(5, 'New', wb);% with progress bar
%

% Updates
%

if nargin < 4; wb = []; end

obj.labels.insertMaterial(materialIndex, materialName, wb);
end
