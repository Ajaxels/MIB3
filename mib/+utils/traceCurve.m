function [mask, status] = traceCurve(img, options, mask)
% function [mask, status] = traceCurve(img, options, mask)
% Connect points with search for a minimum gradients
%
% Based on Accurate Fast Marching function by Dirk-Jan Kroon.
% Called from the Membrane Click Tracker segmentation tool.
%
% Parameters:
% img: original image to probe gradients
% options: a structure with parameters
% @li .p1 - coordinates of the starting point, (y;x)
% @li .p2 - coordinates of the target point, (y;x)
% @li .scaleFactor - scale factor for amplifying intensities
% @li .segmTrackBlackChk - switch to define whether the signal is black (1) or white (0)
% @li .colorId - index of the color channel to follow
% mask: [@em optional] an existing mask/selection layer
%
% Return values:
% mask: a bitmap image with a connecting line, to be used as the 'Selection' layer
% status: result of the function run: 0 = fail, 1 = success
%
%|
% @b Examples:
% @code [mask, status] = utils.traceCurve(img, options);     // trace curve between two points @endcode

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
