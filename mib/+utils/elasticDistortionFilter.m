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
% The displacement field is uniform noise in [-1, 1] for X and Y, smoothed by
% a Gaussian of ``Sigma`` pixels (kernel ``2*ceil(2*Sigma)+1``, the
% ``imgaussfilt`` default) and multiplied by ``ScalingFactor``, as in the
% paper. Its spread does not depend on the image size: away from the borders
% (where the replicate padding of ``imgaussfilt`` adds to it) the standard
% deviation of a component is ``ScalingFactor * norm(kernel(:)) / sqrt(3)``,
% 0.170-0.177 ``* ScalingFactor / Sigma`` pixels for a Sigma of 2-16 (1.3 px
% for the defaults 30 and 4), and no displacement exceeds ``ScalingFactor``.
%
% Until 2026-11 the noise was first divided by ``norm`` (its largest
% singular value, about ``(sqrt(H) + sqrt(W)) / sqrt(3)``) and smoothed by
% an ``HSize`` kernel (default 7): the displacements were 0.1 px on a 512 px
% image and shrank with the image, and ``norm`` took 1 s on 2048 x 2048. The
% ``HSize`` field is no longer read.
%
% The image is warped by sampling it at the displaced position of every pixel
% (``interp2``, linear for the image, nearest for model, mask and selection),
% the position clamped to the image so its edge pixels repeat beyond it. Until
% 2026-11 the moved pixels were interpolated as scattered points (``griddata``,
% natural, 0 outside): the same distortion within 2.5 grey levels on average,
% but 200-400 times slower (2.3 s against 0.012 s for 591 x 806, 21.7 s against
% 0.05 s for 2048 x 2048). The BigData path (``ImageFilters/Filter.m``,
% ``localElasticBand``) warps the same way.
%
% Input Arguments:
%   - **img** - image array ``[height, width, colors, depth]``
%   - **BatchOpt** - *(optional)* structure with filter parameters:
%
%     - ``.ScalingFactor`` - ``{value}`` amplitude of the displacement field (default: ``30``)
%     - ``.Sigma`` - ``{value}`` sigma for Gaussian smoothing of the field, pixels (default: ``4``)
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

if ~isfield(BatchOpt, 'ScalingFactor'); BatchOpt.ScalingFactor{1} = 30; end
if ~isfield(BatchOpt, 'Sigma'); BatchOpt.Sigma{1} = 4; end
if ~isfield(BatchOpt, 'Mode3D'); BatchOpt.Mode3D = false; end
if ~isfield(BatchOpt, 'SourceLayer'); BatchOpt.SourceLayer{1} = 'image'; end
if ~isfield(BatchOpt, 'showWaitbar'); BatchOpt.showWaitbar = true; end
if ~isfield(BatchOpt, 'UseParallelComputing'); BatchOpt.UseParallelComputing = false; end

% init random generator
rng(randomSeed, 'twister');

interpolationType = 'linear';
if ~strcmp(BatchOpt.SourceLayer{1}, 'image')
    interpolationType = 'nearest';  % for model, selection, mask
end

% generate displacement field
if ~isfield(DisplacementField, 'fdx')
    if BatchOpt.Mode3D == 0
        % Compute a random displacement field
        dx = -1+2*rand([size(img, 1), size(img, 2)]);
        dy = -1+2*rand([size(img, 1), size(img, 2)]);
        
        % Smoothing the field, not normalized (Simard et al.): the kernel spans
        % 2*ceil(2*Sigma)+1 pixels, the imgaussfilt default; a shorter one
        % leaves the field rough and tears the image
        DisplacementField.fdx = imgaussfilt(dx, BatchOpt.Sigma{1}); % 2-D Gaussian filtering of dx
        DisplacementField.fdy = imgaussfilt(dy, BatchOpt.Sigma{1}); % 2-D Gaussian filtering of dy

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
    % each pixel samples the image at its displaced position, clamped to the
    % image so the edge pixels repeat beyond it
    [y, x] = ndgrid(1:size(img,1), 1:size(img,2));
    sampleX = min(max(x + DisplacementField.fdx, 1), size(img, 2));
    sampleY = min(max(y + DisplacementField.fdy, 1), size(img, 1));
    for colCh=1:size(img, 3)
        img(:,:,colCh) = interp2(double(img(:,:,colCh)), sampleX, sampleY, interpolationType);
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

            
