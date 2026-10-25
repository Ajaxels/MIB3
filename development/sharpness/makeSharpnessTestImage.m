function makeSharpnessTestImage(outputFile)
% MAKESHARPNESSTESTIMAGE - Write the test stack for the Sharpness and noise tool.
%
% Synthetic gold-on-carbon specimen (the usual SEM resolution sample): gold
% islands of 3-36 nm on a granular carbon film, 512 x 512 pixels of 2 nm. The
% same specimen is "imaged" five times, one slice each:
%
%   1. focused                     - Gaussian probe, sigma 1.2 px
%   2. defocused                   - sigma 3 px
%   3. astigmatic, one focus side  - sigma 3 x 1.2 px, most blurred at 30 deg
%   4. astigmatic, other side      - sigma 3 x 1.2 px, most blurred at 120 deg
%   5. focused with scan-line noise - as 1, plus a random intensity offset per line
%
% Blur is applied in the Fourier domain (an exact Gaussian; a truncated
% spatial kernel would add axis-aligned sidelobes, see plan_sharpness.md).
% Noise imitates shot noise (standard deviation proportional to the square
% root of the signal). The pixel size is written as an MIB BoundingBox in the
% TIFF ImageDescription, which MIB reads back in um.
%
% Example (from the MIB3 folder):
%   makeSharpnessTestImage('mib\assets\misc\sharpness_test_gold_on_carbon.tif')

imageSize = 512;
pixelSize = 0.002;      % um
randomStream = RandStream('mt19937ar', 'Seed', 2026);

% ---- specimen: carbon film
[frequencyX, frequencyY] = meshgrid(ifftshift((0:imageSize-1) - imageSize/2));
radius = hypot(frequencyX, frequencyY);
radius(1, 1) = 1;
carbon = real(ifft2((randn(randomStream, imageSize) + 1i*randn(randomStream, imageSize)) ./ radius.^0.8));
carbon = 0.25 + 0.06 * carbon / std(carbon(:));

% ---- gold islands: spheres with log-normal radii, about 25 % coverage
specimen = carbon;
numberOfParticles = 620;
particleRadius = min(max(exp(log(5) + 0.5*randn(randomStream, numberOfParticles, 1)), 1.5), 18);
particleX = rand(randomStream, numberOfParticles, 1) * imageSize;
particleY = rand(randomStream, numberOfParticles, 1) * imageSize;
for particleId = 1:numberOfParticles
    halfSize = ceil(particleRadius(particleId)) + 1;
    columns = max(1, floor(particleX(particleId)) - halfSize):min(imageSize, ceil(particleX(particleId)) + halfSize);
    rows = max(1, floor(particleY(particleId)) - halfSize):min(imageSize, ceil(particleY(particleId)) + halfSize);
    [patchX, patchY] = meshgrid(columns, rows);
    distance2 = ((patchX - particleX(particleId)).^2 + (patchY - particleY(particleId)).^2) / particleRadius(particleId)^2;
    profile = sqrt(max(1 - distance2, 0));
    % secondary-electron look: bright rim, flatter top
    brightness = (0.75 + 0.25*sqrt(distance2)) .* (profile > 0) + 0.05*profile;
    specimen(rows, columns) = max(specimen(rows, columns), brightness);
end

% ---- imaging conditions: [sigmaMajor sigmaMinor angle], scan-line noise
conditions = {[1.2 1.2 0], false; [3 3 0], false; [3 1.2 30], false; [3 1.2 120], false; [1.2 1.2 0], true};
frequencyXn = ifftshift((0:imageSize-1) - imageSize/2) / imageSize;
frequencyYn = frequencyXn';
specimenSpectrum = fft2(specimen);
description = sprintf('BoundingBox %.6f %.6f %.6f %.6f %.6f %.6f ', ...
    0, pixelSize*(imageSize-1), 0, pixelSize*(imageSize-1), 0, pixelSize*(size(conditions, 1)-1));
if isfile(outputFile); delete(outputFile); end
for sliceId = 1:size(conditions, 1)
    sigma = conditions{sliceId, 1};
    theta = sigma(3)*pi/180;
    alongMajor = frequencyXn*cos(theta) - frequencyYn*sin(theta);   % screen angle, rows down
    alongMinor = frequencyXn*sin(theta) + frequencyYn*cos(theta);
    transferFunction = exp(-2*pi^2*(sigma(1)^2*alongMajor.^2 + sigma(2)^2*alongMinor.^2));
    blurred = real(ifft2(specimenSpectrum .* transferFunction));
    signal = 15 + 200*blurred;
    noisy = signal + 1.6*sqrt(max(signal, 0)) .* randn(randomStream, imageSize);
    if conditions{sliceId, 2}
        noisy = noisy + 6*randn(randomStream, imageSize, 1);
    end
    slice = uint8(min(max(round(noisy), 0), 255));
    if sliceId == 1
        imwrite(slice, outputFile, 'Description', description, 'Compression', 'none');
    else
        imwrite(slice, outputFile, 'WriteMode', 'append', 'Compression', 'none');
    end
end
fprintf('written %s\n', outputFile);
end
