function [shiftX, shiftY] = calcShifts(I, options)
% CALCSHIFTS - Compute drift / template-matching shifts between slices of a 3D stack.
%
% Syntax:
%   .. code-block:: matlab
%
%      [shiftX, shiftY] = utils.align.calcShifts(I)
%      [shiftX, shiftY] = utils.align.calcShifts(I, options)
%
% Computes per-slice X/Y shifts between consecutive slices using FFT-based
% phase correlation (drift correction) or direct correlation (template matching).
% Shifts are converted to absolute offsets relative to the first slice.
%
% References:
%
% - JC Russ, *The image processing handbook*, CRC Press, Boca Raton, FL, 1994
% - JD Sugar et al., *A Free Matlab Script for Spatial Drift Correction*,
%   Microscopy Today, Volume 22, Number 5, 2014
%
% Input Arguments:
%   - **I** — [numeric] image stack with shape ``[height, width, depth]``.
%   - **options** *(optional)* — struct with fields:
%
%     - ``.method`` — [char] ``'Drift correction'`` (default) or ``'Template matching'``.
%     - ``.refFrame`` — [integer] reference-frame mode (default: ``0``):
%
%       - ``0`` — use the previous slice as reference (cumulative drift).
%       - negative — relative to a frame ``N`` slices back.
%
%     - ``.waitbar`` — [:class:`core.PoolWaitbar`] existing PoolWaitbar handle to
%       reuse for progress reporting; pass ``[]`` or omit to disable progress reporting.
%
% Output Arguments:
%   - **shiftX** — [numeric vector] absolute X-shifts of each slice relative to the first.
%   - **shiftY** — [numeric vector] absolute Y-shifts of each slice relative to the first.
%
% **Example** — drift correction with progress on the parent figure:
%
% .. code-block:: matlab
%
%    pwb = core.PoolWaitbar(size(I,3), 'Calculating drifts...', obj.view.gui, 'Alignment', true);
%    opts.method   = 'Drift correction';
%    opts.refFrame = 0;
%    opts.waitbar  = pwb;
%    [sx, sy] = utils.align.calcShifts(I, opts);
%    pwb.deletePoolWaitbar();

if nargin < 2; options = struct(); end
if ~isfield(options, 'method');   options.method = 'Drift correction'; end
if ~isfield(options, 'refFrame'); options.refFrame = 0; end
if ~isfield(options, 'waitbar');  options.waitbar = []; end

[height, width, depth] = size(I);
shiftX = zeros(depth, 1);
shiftY = zeros(depth, 1);

pwb = options.waitbar;
showProgress = ~isempty(pwb) && isvalid(pwb);
if showProgress
    pwb.updateText(sprintf('Calculating drifts\nPlease wait...'));
    pwb.updateMaxNumberOfIterations(depth);
    pwb.setCurrentIteration(0);
    pwb.setIncrement(floor(depth/10));
end

referenceFFT = fft2(I(:,:,1));
imageCenterX = floor((width / 2) + 1);
imageCenterY = floor((height / 2) + 1);

switch options.method
    case {'Drift correction', 'Template matching'}
        for sliceIdx = 2:depth
            currentFFT = fft2(I(:,:,sliceIdx));
            crossSpectrum = referenceFFT .* conj(currentFFT);
            crossCorrelation = ifft2(crossSpectrum);

            if strcmp(options.method, 'Drift correction')
                [yPeak, xPeak] = find(fftshift(crossCorrelation) == max(crossCorrelation(:)));
                shiftX(sliceIdx) = xPeak(1) - imageCenterX;
                shiftY(sliceIdx) = yPeak(1) - imageCenterY;
                % Resolve FFT periodic-boundary ambiguity
                if abs(shiftX(sliceIdx) - shiftX(sliceIdx-1)) > width / 2
                    shiftX(sliceIdx) = shiftX(sliceIdx) - sign(shiftX(sliceIdx) - shiftX(sliceIdx-1)) * width;
                end
                if abs(shiftY(sliceIdx) - shiftY(sliceIdx-1)) > height / 2
                    shiftY(sliceIdx) = shiftY(sliceIdx) - sign(shiftY(sliceIdx) - shiftY(sliceIdx-1)) * height;
                end
            else
                [shiftY(sliceIdx), shiftX(sliceIdx)] = find(crossCorrelation == max(crossCorrelation(:)));
            end

            if options.refFrame == 0
                referenceFFT = currentFFT;
            elseif options.refFrame < 0 && sliceIdx > abs(options.refFrame)
                referenceFFT = fft2(I(:,:,sliceIdx + options.refFrame + 1));
            end

            if showProgress
                if pwb.getCancelState()
                    shiftX = []; shiftY = [];
                    return;
                end
                if mod(sliceIdx, 10) == 0
                    pwb.increment();
                    pwb.updateText(sprintf('Calculating drifts: %d / %d', sliceIdx, depth));
                end
            end
        end

        % Convert relative shifts to absolute (vs. the first slice)
        if options.refFrame == 0
            shiftX = cumsum(shiftX);
            shiftY = cumsum(shiftY);
        elseif options.refFrame < 0
            shiftXAbs = shiftX;
            shiftYAbs = shiftY;
            step = -options.refFrame;
            referenceIdx = step;
            for j = step+2:length(shiftYAbs)
                if mod(j, step) == 0
                    shiftXAbs(j) = shiftX(j) + shiftXAbs(referenceIdx);
                    referenceIdx = j;
                else
                    shiftXAbs(j) = shiftX(j) + shiftXAbs(referenceIdx-step+1);
                end
            end
            shiftX = round(utils.align.windv(shiftXAbs, step));
            shiftY = round(utils.align.windv(shiftYAbs, step));
        end
end

end
