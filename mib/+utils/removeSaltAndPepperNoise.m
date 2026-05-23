function img = removeSaltAndPepperNoise(img, BatchOpt, cpuParallelLimit)
% REMOVESALTANDPEPPERNOISE - Remove salt and pepper noise from an image.
%
% Syntax:
%   .. code-block:: matlab
%
%       img = utils.removeSaltAndPepperNoise(img, BatchOpt)
%       img = utils.removeSaltAndPepperNoise(img, BatchOpt, cpuParallelLimit)
%
% The image is median-filtered; pixels whose absolute difference between
% the original and the median result exceeds ``BatchOpt.IntensityThreshold{1}``
% are replaced by the median value.
%
% Input Arguments:
%   - **img** — image array ``[height, width, colors, depth]``
%   - **BatchOpt** — *(optional)* structure with filter parameters:
%
%     - ``.HSize`` — ``char`` strel element size for the median filter (default: ``'3'``)
%     - ``.IntensityThreshold`` — ``{value}`` intensity threshold; pixels where
%       ``|original − median| > threshold`` are replaced (default: ``50``)
%     - ``.NoiseType`` — ``{string}`` type of noise to remove; one of
%       ``'salt and pepper'``, ``'salt only'``, ``'pepper only'``
%       (salt = bright pixels, pepper = dark pixels; default: ``'salt and pepper'``)
%     - ``.showWaitbar`` — logical, show progress waitbar (default: ``true``)
%     - ``.UseParallelComputing`` — logical, use parallel computing (default: ``false``)
%   - **cpuParallelLimit** — *(optional)* number of CPU workers for parallel processing
%     (default: ``0``)
%
% Output Arguments:
%   - **img** — denoised image, same class and size as input
%
% **Example** — denoise an image corrupted with salt & pepper noise:
%
%   .. code-block:: matlab
%
%      I = imread('eight.tif');
%      J = imnoise(I, 'salt & pepper', 0.05);
%      BatchOpt.HSize = '3';
%      BatchOpt.IntensityThreshold{1} = 50;
%      BatchOpt.NoiseType{1} = 'salt and pepper';
%      Jfiltered = utils.removeSaltAndPepperNoise(J, BatchOpt);

% Updates
%

if nargin < 3; cpuParallelLimit = 0; end
if nargin < 2; BatchOpt = struct(); end
if ~isfield(BatchOpt, 'HSize'); BatchOpt.HSize = '3'; end
if ~isfield(BatchOpt, 'IntensityThreshold'); BatchOpt.IntensityThreshold{1} = 50; end
if ~isfield(BatchOpt, 'NoiseType'); BatchOpt.NoiseType{1} = 'salt and pepper'; end
if ~isfield(BatchOpt, 'showWaitbar'); BatchOpt.showWaitbar = true; end
if ~isfield(BatchOpt, 'UseParallelComputing'); BatchOpt.UseParallelComputing = false; end

hSize = str2num(BatchOpt.HSize); %#ok<ST2NM>
if numel(hSize) == 1; hSize = [hSize, hSize]; end

[height, width, colors, depth] = size(img);

% create waitbar
if BatchOpt.showWaitbar
    pwb = core.PoolWaitbar(depth, sprintf('Removing salt & pepper noise\nPlease wait...'), [], 'Salt & pepper', true);
else
    pwb = [];   % have to init it for parfor loops
end

% define usage of parallel computing
if BatchOpt.UseParallelComputing
    parforArg = cpuParallelLimit;
    if isempty(gcp('nocreate')); parpool(parforArg); end % create parpool
else
    parforArg = 0;
end

maxVal = intmax(class(img(1)));    % max value for the class

doBlack = ~isempty(strfind(BatchOpt.NoiseType{1}, 'pepper'));    % find dark pepper noise
doWhite = ~isempty(strfind(BatchOpt.NoiseType{1}, 'salt'));      % find white salt noise

%for z = 1:depth
imgClass = class(img(1));
parfor (z = 1:depth, parforArg)    
    for colCh = 1:colors
        I1 = img(:,:,colCh,z);  % get image
        I2 = medfilt2(img(:,:,colCh,z), hSize, 'symmetric');  % median filter        D = zeros([height, width], imgClass);
        D = zeros([height, width], imgClass); 
        
        if doBlack
            D = D + ((maxVal-I1) - (maxVal-I2));  % get hotpixels
        end
        if doWhite
            D = D + (I1-I2);  % get hotpixels
        end
        I1(D > BatchOpt.IntensityThreshold{1}) = I2(D > BatchOpt.IntensityThreshold{1});
        img(:,:,colCh,z) = I1;
    end
    if BatchOpt.showWaitbar == 1; pwb.increment(); end
end
if BatchOpt.showWaitbar == 1; delete(pwb); end
