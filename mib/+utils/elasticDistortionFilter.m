function [img, DisplacementField, randomSeed] = elasticDistortionFilter(img, BatchOpt, randomSeed, DisplacementField)
% ELASTICDISTORTIONFILTER - Apply elastic deformations to an image.
%
% Syntax:
%   .. code-block:: matlab
%
%       img = utils.elasticDistortionFilter(img, BatchOpt)
%       img = utils.elasticDistortionFilter(img, BatchOpt, randomSeed)
%       [img, DisplacementField, randomSeed] = utils.elasticDistortionFilter(img, BatchOpt, randomSeed, DisplacementField)
%
% Based on: *Best Practices for Convolutional Neural Networks Applied to
% Visual Document Analysis* - Simard, Steinkraus & Platt (2003).
% See also: https://cognitivemedium.com/assets/rmnist/Simard.pdf
%
% Input Arguments:
%   - **img** - image array ``[height, width, colors, depth]``
%   - **BatchOpt** - *(optional)* structure with filter parameters:
%
%     - ``.ScalingFactor`` - ``{value}`` amplitude of the displacement field (default: ``30``)
%     - ``.HSize`` - ``char`` filter size for Gaussian smoothing of the field (default: ``'7'``)
%     - ``.Sigma`` - ``{value}`` sigma for Gaussian smoothing of the field (default: ``4``)
%     - ``.SourceLayer`` - ``{string}`` layer type; non-image layers use nearest-neighbour
%       interpolation (default: ``'image'``)
%     - ``.Mode3D`` - logical, apply 3D distortion (not yet implemented; default: ``false``)
%     - ``.showWaitbar`` - logical, show progress waitbar (default: ``true``)
%     - ``.UseParallelComputing`` - logical, use parallel computing (default: ``false``)
%   - **randomSeed** - *(optional)* integer seed for ``rng`` to make distortions reproducible
%     (default: ``0``)
%   - **DisplacementField** - *(optional)* pre-computed displacement field struct matching
%     ``[height, width, depth]`` of **img**; fields:
%
%     - ``.fdx`` - x-displacement map
%     - ``.fdy`` - y-displacement map
%     - ``.fdz`` - z-displacement map (3D mode)
%
% Output Arguments:
%   - **img** - elastically distorted image, same class and size as input
%   - **DisplacementField** - displacement field applied during filtering
%   - **randomSeed** - random seed used to generate the field (``[]`` when field was supplied)

% Updates
%

if nargin < 4; DisplacementField = struct(); end
if nargin < 3; randomSeed = 0; end
if nargin < 2; BatchOpt = struct; end

if ~isfield(BatchOpt, 'HSize'); BatchOpt.HSize = '7'; end
if ~isfield(BatchOpt, 'ScalingFactor'); BatchOpt.ScalingFactor{1} = 30; end
if ~isfield(BatchOpt, 'Sigma'); BatchOpt.Sigma{1} = 4; end
if ~isfield(BatchOpt, 'Mode3D'); BatchOpt.Mode3D = false; end
if ~isfield(BatchOpt, 'SourceLayer'); BatchOpt.SourceLayer{1} = 'image'; end
if ~isfield(BatchOpt, 'showWaitbar'); BatchOpt.showWaitbar = true; end
if ~isfield(BatchOpt, 'UseParallelComputing'); BatchOpt.UseParallelComputing = false; end

HSize = str2num(BatchOpt.HSize); %#ok<ST2NM>
HSize = HSize - mod(HSize,2) + 1; % should be an odd number
if numel(HSize) == 1; HSize = repmat(HSize, [3,1]); end

% init random generator
rng(randomSeed, 'twister');

interpolationType = 'natural';
if ~strcmp(BatchOpt.SourceLayer{1}, 'image')
    interpolationType = 'nearest';  % for model, selection, mask
end

% generate displacement field
if ~isfield(DisplacementField, 'fdx')
    if BatchOpt.Mode3D == 0
        % Compute a random displacement field
        dx = -1+2*rand([size(img, 1), size(img, 2)]);
        dy = -1+2*rand([size(img, 1), size(img, 2)]);
        
        % Normalizing the field
        nx = norm(dx);
        ny = norm(dy);
        dx = dx./nx; % Normalization: norm(dx) = 1
        dy = dy./ny; % Normalization: norm(dy) = 1
        
        % Smoothing the field
        DisplacementField.fdx = imgaussfilt(dx, BatchOpt.Sigma{1}, 'FilterSize', HSize(1)); % 2-D Gaussian filtering of dx
        DisplacementField.fdy = imgaussfilt(dy, BatchOpt.Sigma{1}, 'FilterSize', HSize(2)); % 2-D Gaussian filtering of dy
        
        % scale the field
        DisplacementField.fdx = BatchOpt.ScalingFactor{1} * DisplacementField.fdx; 
        DisplacementField.fdy = BatchOpt.ScalingFactor{1} * DisplacementField.fdy; 
        
%         % preview
%         [y, x] = ndgrid(1:size(img,1), 1:size(img,2));
%         figure;
%         imagesc(img(:,:,1,:)); colormap gray; axis image; axis tight;
%         hold on;
%         quiver(x,y,DisplacementField.fdx, DisplacementField.fdy, 0, 'r');
    else
%         % Compute a random displacement field
%         dx = -1+2*rand([size(img, 1), size(img, 2), size(img, 4)]);
%         dy = -1+2*rand([size(img, 1), size(img, 2), size(img, 4)]);
%         dz = -1+2*rand([size(img, 1), size(img, 2), size(img, 4)]);
%         
%         % Smoothing the field
%         DisplacementField.fdx = imgaussfilt(dx, BatchOpt.Sigma{1}, 'FilterSize', HSize(1)); % 2-D Gaussian filtering of dx
%         DisplacementField.fdy = imgaussfilt(dy, BatchOpt.Sigma{1}, 'FilterSize', HSize(2)); % 2-D Gaussian filtering of dy
%         DisplacementField.fdz = imgaussfilt(dz, BatchOpt.Sigma{1}, 'FilterSize', HSize(3)); % 2-D Gaussian filtering of dz
%         
%         n=sum((DisplacementField.fdx(:).^2 + DisplacementField.fdy(:).^2 + DisplacementField.fdz(:).^2));
%         
%         % scale the field
%         DisplacementField.fdx = BatchOpt.ScalingFactor{1} * DisplacementField.fdx./n; 
%         DisplacementField.fdy = BatchOpt.ScalingFactor{1} * DisplacementField.fdy./n; 
%         DisplacementField.fdz = BatchOpt.ScalingFactor{1} * DisplacementField.fdz./n; 
    end
end

if BatchOpt.Mode3D == 0     % 2D
    [y, x] = ndgrid(1:size(img,1), 1:size(img,2));
    for colCh=1:size(img, 3)
        %currImg = double(img(:,:,colCh));
        %filteredImage = griddata(x-DisplacementField.fdx, y-DisplacementField.fdy, currImg, x, y, interpolationType);
        %filteredImage(isnan(filteredImage)) = currImg(isnan(filteredImage));
        
        filteredImage = griddata(x-DisplacementField.fdx, y-DisplacementField.fdy, double(img(:,:,colCh)), x, y, interpolationType);
        filteredImage(isnan(filteredImage)) = 0;
        img(:,:,colCh) = filteredImage;
    end    
else
%     [y, x, z] = ndgrid(1:size(img,1), 1:size(img,2), 1:size(img,4));
%     for colCh=1:size(img, 3)
%         filteredImage = griddata(x-DisplacementField.fdx, y-DisplacementField.fdy, z-DisplacementField.fdz,...
%             double(squeeze(img(:,:,colCh,:))), x, y, z, interpolationType);
%         filteredImage(isnan(filteredImage)) = 0;
%         img(:,:,colCh,:) = permute(filteredImage, [1 2 4 3]);
%     end
end




end

            
