function insertMaterial(obj, materialIndex, materialName, wb)
% function insertMaterial(obj, materialIndex, materialName, wb)
% Insert a new material at the specified position — MibDataset wrapper
%
% Delegates to obj.labels.insertMaterial which handles both the pixel
% data shifting (via direct obj.data{1} access) and the metadata
% update (names, colours, materialsCount).
%
% Parameters:
% materialIndex: double, 1-based position where the new material is
%   inserted.
% materialName: char, name of the new material (used for small models;
%   ignored for large models).
% wb: [@em optional] handle to a uiprogressdlg for progress display;
%   when empty no progress is reported.
%
% Return values:
%

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.insertMaterial(3, 'Nucleus');       // insert at position 3 @endcode
% @code obj.mibModel.I{obj.mibModel.id}.insertMaterial(5, 'New', wb);       // with progress bar @endcode

% Updates
%

if nargin < 4; wb = []; end

obj.labels.insertMaterial(materialIndex, materialName, wb);
end
