function image = stitchTextureImage(height, width, seed)
% STITCHTEXTUREIMAGE - Deterministic textured image for stitching tests.
%
% Syntax:
%   .. code-block:: matlab
%
%      image = mibtest.helpers.stitchTextureImage(180, 460, 91)
%
% Filtered noise plus smooth gradients: enough high-frequency content for phase
% correlation to have a needle-sharp peak, and enough large-scale structure for
% feature detectors — the same recipe the ``utils.stitch`` test classes use, so
% tiles chopped from it register exactly. Deterministic for a given ``seed``.
%
% Input Arguments:
%   - **height** — [double] image height in pixels
%   - **width** — [double] image width in pixels
%   - **seed** — [double] RNG seed (any two different seeds give unrelated content)
%
% Output Arguments:
%   - **image** — [uint8] ``height``-by-``width`` textured image
%
% See also: StitchingControllerTest, StitchingInspectorControllerTest, StitchCoreTest

rng(seed, 'twister');
noise = randn(height, width);
smoothed = imfilter(noise, fspecial('gaussian', [9 9], 2.0), 'replicate');
[xx, yy] = meshgrid(linspace(0, 1, width), linspace(0, 1, height));
gradient = 0.4 * xx + 0.3 * yy + 0.2 * sin(6 * pi * xx) .* cos(5 * pi * yy);

image = smoothed / max(abs(smoothed(:))) + gradient;
image = image - min(image(:));
image = uint8(200 * image / max(image(:)) + 20);

end
