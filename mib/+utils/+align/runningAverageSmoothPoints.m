function smoothedVector = runningAverageSmoothPoints(inputVector, halfwidth, excludePeaks)
% RUNNINGAVERAGESMOOTHPOINTS - Subtract a running-average drift from a vector.
%
% Syntax:
%   .. code-block:: matlab
%
%      smoothedVector = utils.align.runningAverageSmoothPoints(inputVector, halfwidth, excludePeaks)
%
% The function subtracts a smoothed version of ``inputVector`` from itself,
% leaving the high-frequency component (suitable for residual drift correction).
% Peaks larger than ``excludePeaks`` are split out before smoothing so that
% real jumps survive the filter.
%
% Input Arguments:
%   - **inputVector** - [numeric vector] input values to be smoothed.
%   - **halfwidth** - [integer] half-width of the smoothing window; ``0`` disables smoothing.
%   - **excludePeaks** - [numeric] threshold above which inter-sample differences are
%     treated as real jumps and excluded from the smoothing; ``0`` disables peak handling.
%
% Output Arguments:
%   - **smoothedVector** - [numeric vector] residual after subtracting the running average.

asInSmooth = true;
if halfwidth > 0
    if excludePeaks > 0
        diffVec = diff(inputVector);
        peakIndices = find(abs(diffVec) > excludePeaks);
        adjustedInput = inputVector;
        for peakIdx = 1:numel(peakIndices)
            adjustedInput(peakIndices(peakIdx)+1:end) = adjustedInput(peakIndices(peakIdx)+1:end) - diffVec(peakIndices(peakIdx));
        end
        smoothedVector = adjustedInput - utils.align.windv(adjustedInput, halfwidth, asInSmooth);
        for peakIdx = 1:numel(peakIndices)
            smoothedVector(peakIndices(peakIdx)+1:end) = smoothedVector(peakIndices(peakIdx)+1:end) + diffVec(peakIndices(peakIdx));
        end
    else
        smoothedVector = inputVector - utils.align.windv(inputVector, halfwidth, asInSmooth);
    end
else
    smoothedVector = inputVector;
end

end
