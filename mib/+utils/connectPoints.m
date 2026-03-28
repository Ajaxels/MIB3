function img = connectPoints(img, pnts, options)
% function img = connectPoints(img, pnts, options)
% Generate a bitmap image with lines that connect points (pnts)
%
% Parameters:
% img: image where the lines should be added
% pnts: matrix with coordinates of the points, [pointNo, [x, y]]
% options: [@em optional] structure with extra parameters
% @li .close - when @b 1 the shape will be closed
% @li .fill - when @b 1 fill the shape
%
% Return values:
% img: a bitmap image with drawn lines
%
%|
% @b Examples:
% @code img = utils.connectPoints(img, pnts);     // draw lines connecting points @endcode

% Updates
%

if nargin < 3
    options.close = 0;
    options.fill = 0;
end
if nargin < 2; error('not enough parameters'); end
pnts = ceil(pnts);
if options.close == 1
    max_index = size(pnts, 1) + 1;
else
    max_index = size(pnts, 1);
end

xMin = min(pnts(:,1));
xMax = max(pnts(:,1));
yMin = min(pnts(:,2));
yMax = max(pnts(:,2));
cropImg = zeros([yMax - yMin + 1, xMax - xMin + 1], 'uint8');

for pnt = 2:max_index
    if pnt <= size(pnts, 1)
        p1 = [pnts(pnt-1, 2)-yMin+1, pnts(pnt-1, 1)-xMin+1];   % yx
        p2 = [pnts(pnt, 2)-yMin+1, pnts(pnt, 1)-xMin+1];       % yx
    else
        p1 = [pnts(pnt-1, 2)-yMin+1, pnts(pnt-1, 1)-xMin+1];   % yx
        p2 = [pnts(1, 2)-yMin+1, pnts(1, 1)-xMin+1];           % yx
    end

    dv = p2 - p1;
    nPnts = max(abs(dv)) + 1;
    linSpacing = linspace(0, 1, nPnts);
    for i = 1:nPnts
        cropImg(round(p1(1) + linSpacing(i)*dv(1)), round(p1(2) + linSpacing(i)*dv(2))) = 1;
    end
end
if options.fill == 1
    cropImg = imfill(cropImg, 4);
end

% coordinates on the original image
x1 = max([1, xMin]);
x2 = min([size(img, 2), xMax]);
y1 = max([1, yMin]);
y2 = min([size(img, 1), yMax]);

% coordinates on the cropped image
x1c = -min([xMin, 1]) + 2;
x2c = x1c + (x2 - x1);
y1c = -min([yMin, 1]) + 2;
y2c = y1c + (y2 - y1);
img(y1:y2, x1:x2) = cropImg(y1c:y2c, x1c:x2c) | img(y1:y2, x1:x2);
end
