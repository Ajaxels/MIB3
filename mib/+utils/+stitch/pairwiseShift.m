function [shiftYXZ, quality, debugInfo] = pairwiseShift(cropA, cropB, options)
% PAIRWISESHIFT - Windowed FFT phase correlation between two overlap crops.
%
% Syntax:
%   .. code-block:: matlab
%
%      [shiftYXZ, quality] = utils.stitch.pairwiseShift(cropA, cropB)
%      [shiftYXZ, quality, debugInfo] = utils.stitch.pairwiseShift(cropA, cropB, options)
%
% Estimates the residual translation between two same-size overlap crops taken
% from a pair of neighbouring tiles at their NOMINAL relative position. A Hann
% window is applied to suppress FFT edge effects, then normalised cross-power
% spectrum (phase correlation) locates the peak. Optional parabolic subpixel
% refinement fits a quadratic to the three samples straddling the integer peak on
% each axis. Registration is 2D; ``shiftYXZ(3)`` (dz) is returned as ``0`` in
% Phase 1 (Z handled by the caller via facing-slice / mean-projection crops).
%
% **Sign convention (load-bearing).** If ``cropB`` equals ``cropA`` shifted DOWN
% by ``dy`` rows and RIGHT by ``dx`` columns (i.e. ``cropB(r,c) ≈ cropA(r-dy, c-dx)``),
% then ``shiftYXZ = [dy dx 0]``. Verified in ``tests/utils/StitchCoreTest.m``.
%
% When the crops start at local positions ``bboxA(:,1)`` / ``bboxB(:,1)`` (from
% :func:`utils.stitch.computeOverlapRegion`), the tile displacement follows as
%
%   .. code-block:: matlab
%
%      % P_j - P_i in the shared global frame:
%      measured = (bboxA(:,1) - bboxB(:,1))' - [dy dx]
%
% This composition (including the sign NEGATION of the raw shift) lives in
% ``utils.stitch.measureAllPairs/measureOne``.
%
% Input Arguments:
%   - **cropA** - [numeric] reference crop from tile ``i``, ``[H W]`` or ``[H W C]``.
%   - **cropB** - [numeric] moving crop from tile ``j``, same size as ``cropA``.
%   - **options** *(optional)* - struct with fields:
%
%     - ``.subpixel`` - [logical] enable parabolic subpixel refinement (default: ``true``)
%     - ``.window`` - [logical] apply a separable Hann window (default: ``true``)
%
% Output Arguments:
%   - **shiftYXZ** - [1x3 double] ``[dy dx dz]`` correction to the nominal offset
%     (dz is ``0`` in Phase 1).
%   - **quality** - [double] peak prominence in ``[0, 1]``: the phase-correlation
%     peak height relative to the surrounding field. Textured overlaps score high
%     (``> 0.5``), flat/noise overlaps score low (``< 0.1``).
%
% **Example** - recover a known integer shift:
%
%   .. code-block:: matlab
%
%      cropA = single(imfilter(randn(128), fspecial('gaussian', 9, 2)));
%      cropB = circshift(cropA, [5 -3]);   % down 5, left 3
%      [s, q] = utils.stitch.pairwiseShift(cropA, cropB);
%      % s ≈ [5 -3 0], q > 0.5

if nargin < 3; options = struct(); end
if ~isfield(options, 'subpixel');      options.subpixel = true; end
if ~isfield(options, 'window');        options.window   = true; end
if ~isfield(options, 'padPx');         options.padPx = 0; end
if ~isfield(options, 'expectedShift'); options.expectedShift = [0 0]; end
if ~isfield(options, 'searchRadius');  options.searchRadius = Inf; end

% Reduce to single-channel single-precision 2D images.
A = toGray(cropA);
B = toGray(cropB);

% Match sizes defensively (crops should already be equal-sized).
H = min(size(A, 1), size(B, 1));
W = min(size(A, 2), size(B, 2));
if H < 2 || W < 2
    shiftYXZ = [0 0 0];
    quality  = 0;
    return;
end
A = A(1:H, 1:W);
B = B(1:H, 1:W);

% Remove DC so windowing does not create a huge zero-frequency term.
A = A - mean(A(:));
B = B - mean(B(:));

if options.window
    winY = hannWindow(H);
    winX = hannWindow(W);
    win  = winY * winX';        % separable 2D Hann
    A = A .* win;
    B = B .* win;
end

% Zero-pad to remove circular-correlation ambiguity: without padding, shifts with
% |shift| > extent/2 alias to the wrong sign (extent - |shift|). Border-clamped
% overlap crops routinely need raw shifts near -expandPx, so the caller passes
% padPx ~ expandPx to keep those alias-free.
padPx = ceil(options.padPx);
paddedH = H + padPx;
paddedW = W + padPx;
if padPx > 0
    paddedA = zeros(paddedH, paddedW, 'single');
    paddedB = zeros(paddedH, paddedW, 'single');
    paddedA(1:H, 1:W) = A;
    paddedB(1:H, 1:W) = B;
    A = paddedA;
    B = paddedB;
end

Fa = fft2(A);
Fb = fft2(B);

% Cross-power spectrum. The phase-correlation peak of Fa .* conj(Fb) lands at the
% displacement that maps A onto B; we negate below so the returned shift follows
% the documented convention (cropB(r,c) ~= cropA(r-dy, c-dx)).
crossPower = Fa .* conj(Fb);
magnitude  = abs(crossPower);
magnitude(magnitude < eps('single')) = 1;    % avoid divide-by-zero on flat spectra
crossPowerNorm = crossPower ./ magnitude;

correlation = real(ifft2(crossPowerNorm));    % phase-correlation surface, peak at the shift

% Locate the integer peak; when the caller knows the expected shift (from the
% crop start offsets), restrict the search to expectedShift +- searchRadius so a
% stray sidelobe outside the physically possible range can never win.
if isfinite(options.searchRadius)
    expectedRaw = -options.expectedShift;      % returned shift = -raw peak shift
    rowShifts = 0:(paddedH - 1);
    rowShifts(rowShifts > floor(paddedH / 2)) = rowShifts(rowShifts > floor(paddedH / 2)) - paddedH;
    colShifts = 0:(paddedW - 1);
    colShifts(colShifts > floor(paddedW / 2)) = colShifts(colShifts > floor(paddedW / 2)) - paddedW;
    validMask = (abs(rowShifts' - expectedRaw(1)) <= options.searchRadius) & ...
                (abs(colShifts  - expectedRaw(2)) <= options.searchRadius);
    searchSurface = correlation;
    searchSurface(~validMask) = -Inf;
    [peakValue, linearIdx] = max(searchSurface(:));
    if ~isfinite(peakValue)   % degenerate mask - fall back to the global peak
        validMask = true(paddedH, paddedW);
        [peakValue, linearIdx] = max(correlation(:));
    end
else
    validMask = true(paddedH, paddedW);
    [peakValue, linearIdx] = max(correlation(:));
end
[peakRow, peakCol] = ind2sub([paddedH, paddedW], linearIdx);

% Convert wrapped FFT indices to signed shifts.
dyInt = wrapIndex(peakRow, paddedH);
dxInt = wrapIndex(peakCol, paddedW);

% Quality: peak prominence = (peak - meanBackground) / stdBackground, mapped to
% [0,1]. Background excludes a small neighbourhood around the peak and, when the
% search is restricted, only samples the physically possible shift region - a
% spurious sidelobe outside that region must not degrade the score of a genuine
% in-window peak.
[quality, rawPsr] = peakProminence(correlation, peakRow, peakCol, peakValue, validMask);
debugInfo = struct('psr', rawPsr, 'peakValue', peakValue);

dy = dyInt;
dx = dxInt;
if options.subpixel
    dy = dy + parabolicOffset(correlation, peakRow, peakCol, 1);   % along rows
    dx = dx + parabolicOffset(correlation, peakRow, peakCol, 2);   % along cols
end

% Negate so shiftYXZ follows the documented convention: if cropB is cropA shifted
% DOWN dy / RIGHT dx (cropB(r,c) ≈ cropA(r-dy, c-dx)), then shiftYXZ = [dy dx 0].
% The raw peak of Fa.*conj(Fb) sits at the A→B map, whose negative is that offset.
shiftYXZ = [-dy, -dx, 0];
end

% =====================================================================
function g = toGray(img)
% TOGRAY - Collapse to a single-precision 2D image (mean over channels).
img = single(img);
if size(img, 3) > 1
    img = mean(img, 3);
end
g = img(:, :, 1);
end

% =====================================================================
function w = hannWindow(n)
% HANNWINDOW - Symmetric Hann window of length n as a single column vector.
if n == 1
    w = single(1);
    return;
end
k = (0:n-1)';
w = single(0.5 - 0.5 * cos(2 * pi * k / (n - 1)));
end

% =====================================================================
function shift = wrapIndex(idx, n)
% WRAPINDEX - Map a 1-based FFT peak index to a signed shift in [-n/2, n/2).
shift = idx - 1;
if shift > floor(n / 2)
    shift = shift - n;
end
end

% =====================================================================
function offset = parabolicOffset(correlation, peakRow, peakCol, dim)
% PARABOLICOFFSET - Subpixel offset from a 1D parabolic fit around the peak.
%
% Fits y = a*d^2 + b*d + c to the three samples at d = -1, 0, +1 along the given
% dimension (1 = rows, 2 = cols) with circular neighbour indexing, then returns
% the vertex offset -b/(2a) clamped to (-1, 1).
[H, W] = size(correlation);
if dim == 1
    prevIdx = wrapMod(peakRow - 1, H);
    nextIdx = wrapMod(peakRow + 1, H);
    yPrev = correlation(prevIdx, peakCol);
    yHere = correlation(peakRow, peakCol);
    yNext = correlation(nextIdx, peakCol);
else
    prevIdx = wrapMod(peakCol - 1, W);
    nextIdx = wrapMod(peakCol + 1, W);
    yPrev = correlation(peakRow, prevIdx);
    yHere = correlation(peakRow, peakCol);
    yNext = correlation(peakRow, nextIdx);
end
denom = (yPrev - 2 * yHere + yNext);
if abs(denom) < eps
    offset = 0;
    return;
end
offset = 0.5 * (yPrev - yNext) / denom;
if ~isfinite(offset); offset = 0; end
offset = max(min(offset, 1), -1);
end

% =====================================================================
function idx = wrapMod(idx, n)
% WRAPMOD - 1-based circular index into 1:n.
idx = mod(idx - 1, n) + 1;
end

% =====================================================================
function [quality, psr] = peakProminence(correlation, peakRow, peakCol, peakValue, validMask)
% PEAKPROMINENCE - Normalised peak prominence in [0,1].
%
% Compares the peak height against the mean+std of the surface with a small
% window around the peak masked out, then squashes the resulting z-score into
% [0,1]. A tall isolated peak (well-registered textured overlap) approaches 1;
% a flat correlation surface (featureless or noise crops) stays near 0. When
% ``validMask`` marks a restricted search region, only that region contributes
% to the background statistics.
[H, W] = size(correlation);
% Exclusion window around the primary peak: wide enough to cover the whole
% correlation lobe even for smooth (low high-frequency) content, whose lobe can
% span tens of pixels.
rWin = 17;
peakMask = false(H, W);
peakMask(wrapMod((peakRow - rWin):(peakRow + rWin), H), ...
         wrapMod((peakCol - rWin):(peakCol + rWin), W)) = true;

searchRegion = true(H, W);
if nargin >= 5 && ~isempty(validMask)
    searchRegion = validMask;
end

background = correlation(searchRegion & ~peakMask);
if isempty(background) || std(background) < eps
    quality = 0;
    psr = 0;
    return;
end
mu = mean(background);
psr = (peakValue - mu) / std(background);

% Peak-to-second-peak ratio: the tallest competing sample inside the search
% region but outside the primary lobe. A genuine registration peak clearly beats
% every competitor (ratio >~ 1.5); for unrelated content the "peak" is just the
% max order statistic of noise and the runner-up is nearly as tall (ratio ~1).
secondValue = max(background);
ratio = (peakValue - mu) / max(secondValue - mu, eps);
quality = (ratio - 1.35) / 0.65;      % ratio 1.35 -> 0 (noise ~1.3), ratio 2.0 -> 1
quality = max(min(double(quality), 1), 0);
end
