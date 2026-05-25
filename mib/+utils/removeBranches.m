function imgOut = removeBranches(img)
% REMOVEBRANCHES - Remove branches from a thinned binary image.
%
% Syntax:
%   .. code-block:: matlab
%
%       imgOut = utils.removeBranches(img)
%
% Finds the longest path through each connected component and discards
% all branches. The input is typically produced by
% ``bwmorph(img, 'thin', Inf)`` or ``bwmorph(img, 'skel', Inf)``.
%
% Based on "Exploring shortest paths — part 5" by Steve Eddins
% (https://blogs.mathworks.com/steve/2011/12/13/exploring-shortest-paths-part-5/)
%
% Input Arguments:
%   - **img** — [uint8 | logical] H×W binary image with thinned curves
%
% Return values:
%   - **imgOut** — [uint8] image with branches removed; only the longest
%     path in each connected component is retained
%

% find connected components
CC    = bwconncomp(img, 8);
STATS = regionprops(CC, 'BoundingBox');
L     = labelmatrix(CC);

imgOut = zeros(size(img), 'uint8');

for objId = 1:CC.NumObjects
    bb = ceil(STATS(objId).BoundingBox);
    % crop label matrix to the object's bounding box
    M2 = L(bb(2):bb(2)+bb(4)-1, bb(1):bb(1)+bb(3)-1);
    M1 = zeros(size(M2), 'logical');
    M1(M2 == objId) = 1;

    E          = bwmorph(M1, 'endpoints');
    EndPoints  = find(E);

    if numel(EndPoints) > 2
        % More than two endpoints: find the pair with the longest geodesic distance
        LongestDistIndex = zeros(numel(EndPoints), 3);   % [endPtIdx, maxDist, farEndPtIdx]
        for pnt = 1:numel(EndPoints)
            D1 = bwdistgeodesic(M1, EndPoints(pnt), 'quasi-euclidean');
            [D1sorted, ind] = sort(D1(EndPoints));
            LongestDistIndex(pnt, :) = [D1sorted(end), pnt, ind(end)];
        end
        [~, ind]     = sort(LongestDistIndex(:, 1));
        LongestDist  = LongestDistIndex(ind(end), :);

        % Keep only the pixels on the longest path
        D1 = bwdistgeodesic(M1, EndPoints(LongestDist(2)), 'quasi-euclidean');
        D2 = bwdistgeodesic(M1, EndPoints(LongestDist(3)), 'quasi-euclidean');
        D  = D1 + D2;
        D  = -D + min(D(:)) + 0.9;
        M1 = zeros(size(M1), 'uint8');
        M1(D > 0) = 1;
    end

    imgOut(bb(2):bb(2)+bb(4)-1, bb(1):bb(1)+bb(3)-1) = ...
        imgOut(bb(2):bb(2)+bb(4)-1, bb(1):bb(1)+bb(3)-1) + uint8(M1);
end

end
