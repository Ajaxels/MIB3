function Lp = projectLinearPart(L, transformType, allowRotation)
% PROJECTLINEARPART - Closest member of a 2D transform group to a linear part.
%
% Syntax:
%   .. code-block:: matlab
%
%      Lp = utils.stitch.projectLinearPart(L, transformType, allowRotation)
%
% Projects a 2x2 linear part onto the requested transform group in the
% Frobenius norm, via the polar decomposition ``L = R * P`` (rotation x
% symmetric stretch, SVD-based). This is the shared projection used by
% :func:`utils.stitch.solveGlobalAffine` (per-tile, after the linear global
% solve) and :func:`utils.stitch.featureShift` (per-edge, when the rotation
% lock is on) - the ``R = I`` branch implements the ``AllowRotation = false``
% constraint (see ``development/stitching/plan_transforms.md``).
%
% Input Arguments:
%   - **L** - [2x2 double] linear part of an affine transform.
%   - **transformType** - [char] ``'Rigid'`` | ``'Similarity'`` | ``'Affine'``
%     (case-insensitive).
%   - **allowRotation** - [logical] ``false`` locks the rotation factor to
%     identity.
%
% Output Arguments:
%   - **Lp** - [2x2 double] the projected linear part:
%
%     - Rigid → ``R`` (or ``I`` when rotation is disallowed)
%     - Similarity → ``s*R`` with ``s = trace(R'*L)/2``, the Frobenius-optimal
%       scalar (or ``s*I`` with ``s = trace(L)/2``)
%     - Affine → ``L`` unchanged when rotation is allowed; the symmetric
%       stretch part ``P`` (scale/shear, no rotation) when disallowed.
%
% **Example** - strip the rotation out of a fitted linear part:
%
%   .. code-block:: matlab
%
%      Lp = utils.stitch.projectLinearPart(tform.A(1:2,1:2), 'Affine', false);

if strcmpi(transformType, 'Affine') && allowRotation
    Lp = L;
    return;
end

[U, Sigma, V] = svd(L);
signCorrection = diag([1, sign(det(U * V'))]);   % guard against reflections
R = U * signCorrection * V';
switch lower(transformType)
    case 'rigid'
        if allowRotation
            Lp = R;
        else
            Lp = eye(2);
        end
    case 'similarity'
        if allowRotation
            rotationBase = R;
        else
            rotationBase = eye(2);
        end
        s = trace(rotationBase' * L) / 2;
        Lp = s * rotationBase;
    otherwise   % Affine with rotation disallowed: keep scale/shear, drop R
        Lp = V * signCorrection * Sigma * V';
end
end
