function out = morphBallOp(BW, op, se, useBwdist, R)
% MORPHBALLOP - Flat ball/disk dilation or erosion with a distance-transform fast path.
%
% Syntax:
%   .. code-block:: matlab
%
%       out = utils.morphBallOp(BW, op, se, useBwdist, R)
%
% A raw (non-decomposed) structuring element passed to ``imdilate``/``imerode``
% runs the brute-force morphology kernel whose cost scales with the number of
% set voxels in the element (~R^2 in 2D, ~R^3 in 3D). For large radii this
% becomes extremely slow and memory-heavy. When ``useBwdist`` is true the
% operation is instead computed as a threshold of the Euclidean distance
% transform, which is O(N) regardless of R and bit-identical to a Euclidean
% ball/disk element:
%
%   - dilation : ``bwdist(BW)  <= R``
%   - erosion  : ``bwdist(~BW) >  R``
%
% The distance transform is isotropic, so the fast path is only valid for a
% spherical/circular element (equal XY and Z / X and Y radii). Anisotropic
% (ellipsoidal) elements must use the ``imdilate``/``imerode`` path.
%
% Input Arguments:
%   - **BW** — [numeric|logical] binary image or volume (2D or 3D); any nonzero
%     value is treated as foreground
%   - **op** — char, ``'dilate'`` or ``'erode'``
%   - **se** — structuring element used when ``useBwdist`` is false; pass ``[]``
%     when the fast path is used
%   - **useBwdist** — logical, use the distance-transform fast path
%   - **R** — numeric, ball/disk radius in pixels (only used when ``useBwdist`` is true)
%
% Output Arguments:
%   - **out** — same class as ``BW``, the transformed binary image/volume
%
% Usage:
%   **Example 1** — fast large-radius 3D dilation of a logical volume
%
%   .. code-block:: matlab
%
%      dilated = utils.morphBallOp(BW, 'dilate', [], true, 25);
%
%   **Example 2** — classic small-radius erosion with a prebuilt element
%
%   .. code-block:: matlab
%
%      eroded = utils.morphBallOp(BW, 'erode', se, false, []);
%

% Updates
%

if useBwdist
    switch op
        case 'dilate'
            out = bwdist(BW) <= R;
        case 'erode'
            out = bwdist(~BW) > R;
        otherwise
            error('MIB:morphBallOp:badOp', 'unsupported op; use dilate or erode');
    end
    out = cast(out, 'like', BW);
else
    switch op
        case 'dilate'
            out = imdilate(BW, se);
        case 'erode'
            out = imerode(BW, se);
        otherwise
            error('MIB:morphBallOp:badOp', 'unsupported op; use dilate or erode');
    end
end
end
