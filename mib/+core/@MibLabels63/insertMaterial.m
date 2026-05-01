function insertMaterial(obj, index, name, wb)
% INSERTMATERIAL - Insert a material at the specified position (type-63 bit-packed model).
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.insertMaterial(index, name, wb)
%
% For the bit-packed format (maxMaterials = 63), the model occupies bits
% 1-6 of each uint8 element.  When inserting in the middle, all model
% values >= index are incremented by 1 while preserving mask (bit 7) and
% selection (bit 8) bits.  When appending at the end, only the name and
% colour are added.
%
% Input Arguments:
%   - **index** — double, 1-based position where the new material is inserted.
%   - **name** — char, name for the new material.
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
%     obj.mibModel.I{obj.mibModel.id}.labels.insertMaterial(3, 'Nucleus');% insert at position 3
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.labels.insertMaterial(5, 'New', wb);% with progress bar
%

% Updates
%

if nargin < 4; wb = []; end

nMats = numel(obj.materialNames);

if index == nMats + 1
    % Appending at the end — no pixel shift needed
    obj.materialNames{end+1, 1} = name;
else
    % Shift model indices in bit-packed data: extract bits 1-6, increment
    % where >= index, repack with preserved mask/selection bits
    numT = obj.time;
    for t = 1:numT
        packed = obj.data{1}(:,:,:,1,t);
        modelData = bitand(packed, uint8(63));          % bits 1-6
        otherBits = bitand(packed, uint8(192));          % bits 7-8 (mask + selection)

        mask = modelData >= uint8(index);
        modelData(mask) = modelData(mask) + 1;

        obj.data{1}(:,:,:,1,t) = bitor(otherBits, modelData);
        if ~isempty(wb); wb.Value = t / numT * 0.9; end
    end

    % Shift material names
    if index == 1
        obj.materialNames = [{name}; obj.materialNames];
    else
        obj.materialNames = [obj.materialNames(1:index-1); {name}; obj.materialNames(index:end)];
    end
end

% Add a new colour entry if needed
if size(obj.materialColors, 1) < numel(obj.materialNames)
    obj.materialColors(end+1, :) = rand(1, 3);
end

obj.materialsCount = numel(obj.materialNames);
end
