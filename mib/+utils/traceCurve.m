function [mask, status] = traceCurve(img, options, mask)
% TRACECURVE - Connect two points by searching for a minimum-gradient path.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      [mask, status] = traceCurve(img, options)
%      [mask, status] = traceCurve(img, options, mask)
%
% Based on the Accurate Fast Marching function by Dirk-Jan Kroon.
% Called from the Membrane Click Tracker segmentation tool.
%
% Input Arguments:
%   - **img** - original image used to probe gradients
%   - **options** - struct with algorithm parameters:
%
%     - ``.p1``                   - starting point coordinates ``[y; x]``
%     - ``.p2``                   - target point coordinates ``[y; x]``
%     - ``.scaleFactor``          - scale factor for amplifying intensity differences
%     - ``.segmTrackBlackChk``    - ``1`` when signal is dark (black membrane), ``0`` for bright
%     - ``.colorId``              - index of the colour channel to follow
%
%   - **mask** *(optional)* - existing mask/selection layer to draw into
%
% Output Arguments:
%   - **mask** - [uint8] bitmap image with the connecting line (use as Selection layer)
%   - **status** - [numeric] ``1`` on success, ``0`` on failure
%
% Usage:
%
%   **Example 1** - trace a curve between two points
%
%   .. code-block:: matlab
%
%      options.p1 = [100; 150];
%      options.p2 = [200; 300];
%      options.scaleFactor = 1;
%      options.segmTrackBlackChk = 1;
%      options.colorId = 1;
%      [mask, status] = utils.traceCurve(img, options);
%

% Updates
%

status = 0;
if nargin < 3
    mask = zeros([size(img, 1), size(img, 2)], 'uint8');
end
if nargin < 2; error('not enough parameters'); end
if ~isfield(options, 'colorId'); options.colorId = 1; end
if ~isfield(options, 'segmTrackBlackChk'); options.segmTrackBlackChk = 1; end
if ~isfield(options, 'scaleFactor'); options.scaleFactor = 1; end

maxIntensity = double(intmax(class(img)));
if size(img, 3) > 1; img = img(:,:,options.colorId); end
if options.segmTrackBlackChk
    img = maxIntensity - img;
end
val1 = double(img(options.p1(1), options.p1(2)));
val2 = double(img(options.p2(1), options.p2(2)));
pointsVec = img > min([val1, val2]) - abs(val1 - val2) * options.scaleFactor & ...
             img <= max([val1, val2]) + abs(val1 - val2) * options.scaleFactor;
img = img / 50;
img(pointsVec) = maxIntensity;

DistanceMap = msfm(double(img) * 1000 + 1, options.p2);
ShortestLine = round(shortestpath(DistanceMap, options.p1, options.p2));
for i = 1:size(ShortestLine, 1)
    mask(ShortestLine(i, 1), ShortestLine(i, 2)) = 1;
end

status = 1;
end
