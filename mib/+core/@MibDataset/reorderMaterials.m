function reorderMaterials(obj, newOrder, wb)
% function reorderMaterials(obj, newOrder, wb)
% Reorder materials in the model — low-level data layer
%
% Remaps pixel values according to newOrder across every time-point.
% Only supported for small models (maxMaterials < 256).  The mapping is
% built so that pixel value newOrder(k) becomes k for k = 1..N.
% After remapping, material names and colours are reordered via
% obj.labels.reorderMaterials.
%
% Parameters:
% newOrder: double vector, permutation of 1:numel(materialNames)
%   specifying the desired arrangement.  For example [3 1 2] means:
%   old material 3 becomes new material 1, old 1 becomes new 2, old 2
%   becomes new 3.
% wb: [@em optional] handle to a uiprogressdlg for progress display;
%   when empty no progress is reported.
%
% Return values:
%

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.reorderMaterials([3 1 2]);       // rotate materials @endcode
% @code obj.mibModel.I{obj.mibModel.id}.reorderMaterials([2 1 3], wb);   // swap first two, with progress @endcode

% Updates
%

if nargin < 3; wb = []; end

%% Remap pixel data across all time-points
options.blockModeSwitch = false;
numT = obj.image.time;

for t = 1:numT
    M = obj.getData3D('labels', t, 3, NaN, options);
    if ~isempty(M) && ~isempty(M{1})
        img = M{1};
        % Build mapping: 0 stays 0, then newOrder(k) maps to k
        mapping = cast([0, newOrder], class(img));
        newImg = mapping(img + 1);
        obj.setData3D({newImg}, 'labels', t, 3, NaN, options);
    end
    if ~isempty(wb); wb.Value = t / numT * 0.9; end
end

%% Metadata update
obj.labels.reorderMaterials(newOrder);

% Reset selection state
obj.lastSegmSelection = [2, 1];
end
