function bb = getRoiBoundingBox(obj, roiIndex)
% function bb = getRoiBoundingBox(obj, roiIndex)
% Return the bounding box for a ROI at its native orientation.
%
% Wraps @em core.RoiRegion.getBoundingBox and maps the 4-element
% @code [xmin xmax ymin ymax] @endcode result to a 6-element vector
% @code [minX maxX minY maxY minZ maxZ] @endcode consistent with dataset
% pixel coordinates (X = columns, Y = rows, Z = depth).
%
% The mapping depends on the orientation stored in the ROI:
% @li @b 3 (YX plane) — X/Y from bounding box, Z spans 1 to full depth
% @li @b 1 (ZX plane) — ROI X-axis = Z, ROI Y-axis = X; Y spans full height
% @li @b 2 (ZY plane) — ROI X-axis = Z, ROI Y-axis = Y; X spans full width
%
% Parameters:
% roiIndex: [@em optional] index of the ROI to query.
% @li When omitted, @em obj.selectedROI is used.
% @li When negative or empty, returns @em [] immediately.
%
% Return values:
% bb: @code [minX maxX minY maxY minZ maxZ] @endcode in pixels, or @em []
%   when no ROI is selected.

%|
% @b Examples:
% @code bb = obj.mibModel.I{obj.mibModel.id}.getRoiBoundingBox();   // call from controller; bounding box of the selected ROI @endcode
% @code bb = obj.mibModel.I{obj.mibModel.id}.getRoiBoundingBox(2);  // call from controller; bounding box of ROI index 2 @endcode

if nargin < 2; roiIndex = obj.selectedROI; end
if isempty(roiIndex) || roiIndex < 0; bb = []; return; end

% Use the first index when selectedROI is a vector
roiIndex = roiIndex(1);

bb4 = obj.hROI.getBoundingBox(roiIndex);   % [xmin xmax ymin ymax]
if isempty(bb4); bb = []; return; end

roiOrient = obj.hROI.Data(roiIndex).orientation;

switch roiOrient
    case 3  % YX plane: ROI x = dataset X, ROI y = dataset Y
        bb(1) = bb4(1);             % minX
        bb(2) = bb4(2);             % maxX
        bb(3) = bb4(3);             % minY
        bb(4) = bb4(4);             % maxY
        bb(5) = 1;                  % minZ
        bb(6) = obj.image.depth;    % maxZ

    case 1  % ZX plane: ROI x-axis = Z, ROI y-axis = dataset X
        bb(1) = bb4(3);             % minX  (ROI y = dataset X)
        bb(2) = bb4(4);             % maxX
        bb(3) = 1;                  % minY  (Y spans full height)
        bb(4) = obj.image.height;   % maxY
        bb(5) = bb4(1);             % minZ  (ROI x = Z)
        bb(6) = bb4(2);             % maxZ

    case 2  % ZY plane: ROI x-axis = Z, ROI y-axis = dataset Y
        bb(1) = 1;                  % minX  (X spans full width)
        bb(2) = obj.image.width;    % maxX
        bb(3) = bb4(3);             % minY  (ROI y = dataset Y)
        bb(4) = bb4(4);             % maxY
        bb(5) = bb4(1);             % minZ  (ROI x = Z)
        bb(6) = bb4(2);             % maxZ

    otherwise
        bb = [];
end
end
