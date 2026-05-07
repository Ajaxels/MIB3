function smoothedVector = windv(inputVector, windowSize, asInSmooth)
% WINDV - Smooth a vector with a centred symmetric averaging window.
%
% Syntax:
%   .. code-block:: matlab
%
%      smoothedVector = utils.align.windv(inputVector, windowSize)
%      smoothedVector = utils.align.windv(inputVector, windowSize, asInSmooth)
%
% The window has size ``2 * windowSize + 1`` in the interior and is reduced at the
% edges. With ``asInSmooth = true`` the edge handling matches MATLAB's
% ``smooth`` function from the Curve Fitting Toolbox: ``yy(1) = y(1)``,
% ``yy(2) = mean(y(1:3))``, ``yy(3) = mean(y(1:5))`` etc.
%
% Input Arguments:
%   - **inputVector** — [numeric vector] values to smooth.
%   - **windowSize** — [integer] half-width of the averaging window. ``1`` gives a
%     3-point window, ``2`` gives a 5-point window.
%   - **asInSmooth** *(optional)* — [logical] when ``true`` use ``smooth``-style edge
%     handling; when ``false`` use a fixed half-window mean at the edges
%     (default: ``false``).
%
% Output Arguments:
%   - **smoothedVector** — [numeric vector] smoothed result, same size as ``inputVector``.
%
% **Example** — smooth a drift curve:
%
% .. code-block:: matlab
%
%    smoothed = utils.align.windv(shiftX, 25, true);

if nargin < 3; asInSmooth = false; end

vectorLength = length(inputVector);
smoothedVector = inputVector;
for index = 1:windowSize
    smoothedVector(1:vectorLength-index) = smoothedVector(1:vectorLength-index) + inputVector(index+1:vectorLength);
    smoothedVector(index+1:vectorLength) = smoothedVector(index+1:vectorLength) + inputVector(1:vectorLength-index);
end
smoothedVector = smoothedVector ./ (2*windowSize + 1);

if ~asInSmooth
    for index = 1:windowSize
        smoothedVector(index)               = mean(inputVector(1:windowSize+index));
        smoothedVector(vectorLength+1-index) = mean(inputVector(vectorLength+1-index-windowSize:vectorLength));
    end
else
    for index = 1:windowSize
        smoothedVector(index)               = mean(inputVector(1:(index-1)*2+1));
        smoothedVector(vectorLength+1-index) = mean(inputVector(vectorLength-(index-1)*2:vectorLength));
    end
end

end
