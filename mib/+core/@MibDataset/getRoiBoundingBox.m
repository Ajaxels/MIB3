function bb = getRoiBoundingBox(obj, roiIndex)
% GETROIBOUNDINGBOX - Return the bounding box for a ROI at its native orientation.
%
% Syntax:
%   function bb = getRoiBoundingBox(obj, roiIndex)
%
% Wraps *core.RoiRegion.getBoundingBox* and maps the 4-element
% ``[xmin xmax ymin ymax]`` result to a 6-element vector
% ``[minX maxX minY maxY minZ maxZ]`` consistent with dataset
% pixel coordinates (X = columns, Y = rows, Z = depth).
%
% The mapping depends on the orientation stored in the ROI:
% - **3** (YX plane) — X/Y from bounding box, Z spans 1 to full depth
% - **1** (ZX plane) — ROI X-axis = Z, ROI Y-axis = X; Y spans full height
% - **2** (ZY plane) — ROI X-axis = Z, ROI Y-axis = Y; X spans full width
%
% Input Arguments:
%   - **roiIndex** — *(optional)* index of the ROI to query.
%   - When omitted, *obj.selectedROI* is used.
%   - When negative or empty, returns *[]* immediately.
%
% Output Arguments:
%   - **bb** — ``[minX maxX minY maxY minZ maxZ]`` in pixels, or *[]*
%     when no ROI is selected.
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     bb = obj.mibModel.I{obj.mibModel.id}.getRoiBoundingBox();% call from controller; bounding box of the selected ROI
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     bb = obj.mibModel.I{obj.mibModel.id}.getRoiBoundingBox(2);% call from controller; bounding box of ROI index 2
%

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
