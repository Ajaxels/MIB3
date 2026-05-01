function insertMaterial(obj, index, name, wb)
% INSERTMATERIAL - Insert a material at the specified position.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.insertMaterial(index, name, wb)
%
% For small models (maxMaterials < 256):
% - When appending at the end (index == nMats+1): only adds the name
% and a colour entry, no pixel shift is needed.
% - When inserting in the middle: shifts all pixel values >= index
% upward by 1 across every time-point in obj.data{1}, then inserts
% the name at the correct position and appends a colour if the
% colour array is shorter than the name list.
%
% For large models (maxMaterials >= 256):
% Shifts pixel values >= index upward by 1, then increments
% obj.materialsCount.  No name/colour changes (large models use only
% placeholder names).
%
% Input Arguments:
%   - **index** — double, 1-based position where the new material is inserted.
%   - **name** — char, name of the new material (used for small models; ignored
%     for large models).
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

modelType = obj.maxMaterials;

if modelType < 256
    %% Small models
    nMats = numel(obj.materialNames);

    if index == nMats + 1
        % Appending at the end — no pixel shift needed
        obj.materialNames{end+1, 1} = name;
    else
        % Shift pixel data: values >= index get incremented by 1
        numT = obj.time;
        for t = 1:numT
            img = obj.data{1}(:,:,:,1,t);
            mask = img >= cast(index, class(img));
            img(mask) = img(mask) + 1;
            obj.data{1}(:,:,:,1,t) = img;
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
else
    %% Large models — pixel shift only, no name/colour changes
    numT = obj.time;
    for t = 1:numT
        img = obj.data{1}(:,:,:,1,t);
        mask = img >= cast(index, class(img));
        img(mask) = img(mask) + 1;
        obj.data{1}(:,:,:,1,t) = img;
        if ~isempty(wb); wb.Value = t / numT * 0.9; end
    end
    obj.materialsCount = obj.materialsCount + 1;
end
end
