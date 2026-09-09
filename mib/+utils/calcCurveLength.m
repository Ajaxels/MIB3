function STATS = calcCurveLength(slice, pixSize, CC)
% CALCCURVELENGTH - Calculate length of the curve objects in a 2D slice.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      STATS = calcCurveLength(slice)
%      STATS = calcCurveLength(slice, pixSize)
%      STATS = calcCurveLength(slice, pixSize, CC)
%
% Both closed and non-closed curves can be measured. The curves are expected
% to be 1 pixel wide, i.e. the objects should be thinned (``bwmorph(img, 'thin', Inf)``)
% before the call; a non-closed curve with more than two end points is rejected.
%
% Each object is traced with ``bwtraceboundary`` from one of its end points,
% the resulting point list is smoothed with a 3-point window
% (``utils.align.windv``) and the length is taken as the sum of distances
% between the consecutive points.
%
% Input Arguments:
%   - **slice** - one of:
%
%     - [numeric|logical] 2D slice ``[1:height, 1:width]`` with the drawn curves
%     - [struct] connected components structure returned by ``bwconncomp``;
%       in this case it is used instead of ``CC``
%
%   - **pixSize** *(optional)* - struct with physical pixel sizes; required fields
%     ``.x`` and ``.y``. When omitted or not a struct, the length is returned in
%     pixels and placed into the ``CurveLengthInPixels`` field instead of
%     ``CurveLengthInUnits``.
%   - **CC** *(optional)* - [struct] connected components structure returned by
%     ``bwconncomp``. When omitted it is calculated from ``slice`` using
%     8-connectivity.
%
% Output Arguments:
%   - **STATS** - ``[1 x NumObjects]`` struct array with fields:
%
%     - ``.Centroid`` - object centroid, ``[x, y]``
%     - ``.PixelIdxList`` - linear indices of the object pixels
%     - ``.CurveLengthInUnits`` - curve length in physical units; present when
%       ``pixSize`` was provided
%     - ``.CurveLengthInPixels`` - curve length in pixels; present when
%       ``pixSize`` was omitted
%
%     ``NaN`` is returned when one of the objects has more than two end points.
%
% Usage:
%
%   **Example 1** - length of the curves in pixels
%
%   .. code-block:: matlab
%
%      STATS = utils.calcCurveLength(bwmorph(slice, 'thin', Inf));
%
%   **Example 2** - length of the curves in physical units
%
%   .. code-block:: matlab
%
%      pixSize = obj.mibModel.I{obj.mibModel.Id}.pixSize;
%      STATS = utils.calcCurveLength(slice, pixSize);
%
% See also:
%   utils.align.windv
%

% Updates
%

% fill default pixel size
fieldName = 'CurveLengthInUnits';
if nargin < 3
    if isstruct(slice)
        CC = slice;
    else
        CC = bwconncomp(slice, 8);
    end
end
if nargin < 2 || ~isstruct(pixSize)
    pixSize.x = 1;
    pixSize.y = 1;
    fieldName = 'CurveLengthInPixels';
end

STATS = regionprops(CC, 'PixelList', 'PixelIdxList', 'FilledArea', 'Centroid', 'BoundingBox');
labelMatrix = labelmatrix(CC);
for objId = 1:CC.NumObjects
    boundingBox = ceil(STATS(objId).BoundingBox);    % [x, y, width, height]
    % crop the label matrix to the object's bounding box
    croppedLabels = labelMatrix(boundingBox(2):boundingBox(2)+boundingBox(4)-1, ...
        boundingBox(1):boundingBox(1)+boundingBox(3)-1);
    % keep only the selected object
    objectMask = zeros(size(croppedLabels), 'uint8');
    objectMask(croppedLabels == objId) = 1;

    if numel(STATS(objId).PixelIdxList) == STATS(objId).FilledArea  % non-closed line
        % find the ending points of the thinned line
        endPoints = bwmorph(objectMask, 'endpoints');
        [endPointsY, endPointsX] = find(endPoints);
        if numel(endPointsY) > 2
            utils.dlgs.showErrorDialog([], ...
                sprintf(['Object %d has more than two end points, please make sure that each line has only two end points!\n' ...
                'Coordinates X=%d Y=%d\nPlease fix it and try again!'], objId, endPointsX(1), endPointsY(1)), ...
                'Too many end points');
            STATS = NaN;
            return;
        end
        % trace the boundary starting from the 1st end point
        pixelsInObject = sum(objectMask(:));
        if pixelsInObject > 1
            boundaryPoints = bwtraceboundary(objectMask, [endPointsY(1), endPointsX(1)], 'N', 8, pixelsInObject);
        else
            [pointY, pointX] = find(objectMask);
            boundaryPoints = [pointY, pointX];
        end
    else    % closed line
        [startY, startX] = find(objectMask == 1, 1);  % find a starting point
        boundaryPoints = bwtraceboundary(objectMask, [startY, startX], 'N', 8, Inf);
    end

    % smoothing with a 3-point window;
    % windv is used instead of smooth, because smooth is only available in
    % the curve fitting toolbox
    boundaryPoints(:,1) = utils.align.windv(boundaryPoints(:,1), 1, 1);
    boundaryPoints(:,2) = utils.align.windv(boundaryPoints(:,2), 1, 1);

    % convert to the physical coordinates
    boundaryPoints(:,1) = (boundaryPoints(:,1) + boundingBox(2) - 1) * pixSize.y;  % y coordinate
    boundaryPoints(:,2) = (boundaryPoints(:,2) + boundingBox(1) - 1) * pixSize.x;  % x coordinate

    curveLength = sum(sqrt( ...
        (boundaryPoints(2:end,1) - boundaryPoints(1:end-1,1)).^2 + ...
        (boundaryPoints(2:end,2) - boundaryPoints(1:end-1,2)).^2));
    STATS(objId).(fieldName) = curveLength;
end

STATS = rmfield(STATS, {'PixelList', 'FilledArea', 'BoundingBox'});
end
