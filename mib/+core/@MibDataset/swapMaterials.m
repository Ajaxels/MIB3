function swapMaterials(obj, material1, material2, wb)
% SWAPMATERIALS - Swap two materials in the model — low-level data layer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.swapMaterials(material1, material2, wb)
%
% Exchanges all pixel values equal to material1 with material2 and vice
% versa across every time-point, then updates material names and colours
% via obj.labels.swapMaterials (for small models only; large models
% have no meaningful name/colour metadata to swap).
%
% Input Arguments:
%   - **material1** — double, 1-based index of the first material.
%   - **material2** — double, 1-based index of the second material.
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
%     obj.mibModel.I{obj.mibModel.id}.swapMaterials(1, 3);% swap materials 1 and 3
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.swapMaterials(2, 5, wb);% with progress bar
%

% Updates
%

if nargin < 4; wb = []; end
if material1 == material2; return; end

modelType = obj.labels.maxMaterials;

%% Swap pixel data across all time-points
options.blockModeSwitch = false;
numT = obj.image.time;

for t = 1:numT
    M = obj.getData3D('labels', t, 3, NaN, options);
    if ~isempty(M) && ~isempty(M{1})
        img = M{1};
        mat1Typed = cast(material1, class(img));
        mat2Typed = cast(material2, class(img));
        mask1 = (img == mat1Typed);
        img(img == mat2Typed) = mat1Typed;
        img(mask1) = mat2Typed;
        obj.setData3D({img}, 'labels', t, 3, NaN, options);
    end
    if ~isempty(wb); wb.Value = t / numT * 0.9; end
end

%% Metadata update (small models only)
if modelType < 256
    obj.labels.swapMaterials(material1, material2);
end
end
