function [profileOut, lineLength, samplePointsX, samplePointsY] = imageProfileIntegrate(img, x1, y1, x2, y2, integrationWidth)
% IMAGEPROFILEINTEGRATE - Compute laterally-integrated intensity profile for a line ROI.
%
% Syntax:
%   .. code-block:: matlab
%
%       [profileOut, lineLength, samplePointsX, samplePointsY] = ...
%           utils.imageProfileIntegrate(img, x1, y1, x2, y2, integrationWidth)
%
% Samples ``integrationWidth`` parallel scan lines across the rectangle
% defined by the line ``(x1,y1)–(x2,y2)`` and averages their intensity
% profiles, yielding a width-integrated result.
%
% Based on code by Damien from MATLAB Central file exchange #11568.
%
% Input Arguments:
%   - **img** — [H × W × C] numeric image array
%   - **x1** — [double] x-coordinate of line start point
%   - **y1** — [double] y-coordinate of line start point
%   - **x2** — [double] x-coordinate of line end point
%   - **y2** — [double] y-coordinate of line end point
%   - **integrationWidth** — [double] number of parallel scan lines (rectangle width in pixels)
%
% Output Arguments:
%   - **profileOut** — [C × nPoints] averaged intensity matrix (one row per colour channel)
%   - **lineLength** — [double] length of the line in pixels
%   - **samplePointsX** — [integrationWidth × nPoints] x-coordinates of all scan points
%   - **samplePointsY** — [integrationWidth × nPoints] y-coordinates of all scan points
%
% Usage:
%   **Example 1** — single-channel profile with 5-pixel integration width
%
%   .. code-block:: matlab
%
%       [profile, len] = utils.imageProfileIntegrate(grayImg, 10, 20, 80, 60, 5);
%       plot(profile);
%

% line length = rectangle length
lineLength = sqrt((x2 - x1)^2 + (y2 - y1)^2);

% rotation angle so the rectangle aligns with the line direction
if y2 < y1
    angle = acos((x2 - x1) / lineLength);
elseif y2 > y1
    angle = -acos((x2 - x1) / lineLength);
else
    angle = 0.000001;
end

rotationMatrix = [cos(angle), -sin(angle); sin(angle), cos(angle)];

% midpoint of the line (rotation centre)
centerX = (x2 - x1) / 2;
centerY = (y2 - y1) / 2;

% rectangle vertices in centred coordinates [length × width]
rectangleVertices = [ ...
    -lineLength/2, -integrationWidth/2; ...
     lineLength/2, -integrationWidth/2; ...
    -lineLength/2,  integrationWidth/2; ...
     lineLength/2,  integrationWidth/2];

% rotate vertices
rotatedRectangle = rectangleVertices * rotationMatrix;

% translate back to image coordinates
rotatedRectangle(:, 1) = rotatedRectangle(:, 1) + x1 + centerX;
rotatedRectangle(:, 2) = rotatedRectangle(:, 2) + y1 + centerY;

% slope and intercepts of the two long sides of the rotated rectangle
slope = (rotatedRectangle(3, 2) - rotatedRectangle(1, 2)) / ...
        (rotatedRectangle(3, 1) - rotatedRectangle(1, 1));
intercept1 = rotatedRectangle(1, 2) - slope * rotatedRectangle(1, 1);
intercept2 = rotatedRectangle(2, 2) - slope * rotatedRectangle(2, 1);

% Pre-run improfile on the central axis to get the exact number of sample points;
% all scan lines have the same length, so the count is identical for every scanLineIdx.
channelCount = size(img, 3);
[initCoordX, ~, ~] = improfile(img(:, :, 1), [x1, x2], [y1, y2]);
nProfilePoints = numel(initCoordX);

samplePointsX       = zeros(integrationWidth, nProfilePoints);
samplePointsY       = zeros(integrationWidth, nProfilePoints);
lineProfile         = zeros(channelCount, nProfilePoints);
accumulatedProfiles = zeros(integrationWidth, channelCount, nProfilePoints);

for scanLineIdx = 0:integrationWidth - 1
    scanX1 = rotatedRectangle(1, 1) + ...
        ((rotatedRectangle(3, 1) - rotatedRectangle(1, 1)) / (integrationWidth - 1)) * scanLineIdx;
    scanX2 = rotatedRectangle(2, 1) + ...
        ((rotatedRectangle(4, 1) - rotatedRectangle(2, 1)) / (integrationWidth - 1)) * scanLineIdx;

    scanY1 = slope * scanX1 + intercept1;
    scanY2 = slope * scanX2 + intercept2;

    for channelIdx = 1:channelCount
        if channelIdx == 1
            [scanCoordX, scanCoordY, lineProfile(channelIdx, :)] = ...
                improfile(img(:, :, channelIdx), [scanX1, scanX2], [scanY1, scanY2]);
            samplePointsX(scanLineIdx + 1, :) = scanCoordX;
            samplePointsY(scanLineIdx + 1, :) = scanCoordY;
        else
            lineProfile(channelIdx, :) = improfile(img(:, :, channelIdx), [scanX1, scanX2], [scanY1, scanY2]);
        end
    end

    accumulatedProfiles(scanLineIdx + 1, :, :) = lineProfile;
end

% average across the integration width; result is [C × nPoints]
profileOut = shiftdim(mean(accumulatedProfiles, 1), 1);
end
