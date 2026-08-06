function fv = isosurfaceMibRendering(Volume, materialIndex, pixSize, boundingBox, options)
% ISOSURFACEMIBRENDERING - Generate an isosurface mesh for one material from a label volume.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      fv = isosurfaceMibRendering(Volume, materialIndex, pixSize, boundingBox)
%      fv = isosurfaceMibRendering(Volume, materialIndex, pixSize, boundingBox, options)
%
% Ported and refactored from utils.mibRenderModel (MIB2).  Unlike the original,
% this function is purely computational - it does not open a figure or call
% view3d.  Intended for headless export pipelines such as STL saving.
%
% Input Arguments:
%   - **Volume** - [uint8/uint16] label array ``[H, W, D]``; each voxel is a material index (0 = exterior)
%   - **materialIndex** - [numeric] scalar index of the material to extract
%   - **pixSize** - struct with physical voxel dimensions:
%
%     - ``.x``     - voxel width
%     - ``.y``     - voxel height
%     - ``.z``     - voxel depth
%     - ``.units`` - physical unit string
%
%   - **boundingBox** - [numeric] ``[xMin xMax yMin yMax zMin zMax]`` - physical coordinates of dataset corners
%   - **options** *(optional)* - struct with mesh generation parameters:
%
%     - ``.reduce``   - target image width in pixels for volume down-sampling before isosurface extraction; ``0`` = no reduction
%     - ``.smooth``   - isotropic Laplacian smoothing kernel width in X (pixels); Y/Z kernel sizes scaled by aspect ratio; ``0`` = no smoothing
%     - ``.maxFaces`` - maximum number of faces in the output mesh; ``0`` = no limit
%
% Output Arguments:
%   - **fv** - struct with mesh data; ``[]`` when the material is absent or produces an empty surface:
%
%     - ``.faces``    - ``[F x 3]`` double, triangle face indices
%     - ``.vertices`` - ``[V x 3]`` double, vertex coordinates in physical space
%
% Usage:
%
%   **Example 1** - extract material 2 as an STL mesh
%
%   .. code-block:: matlab
%
%      opts.reduce   = 500;
%      opts.smooth   = 5;
%      opts.maxFaces = 300000;
%      fv = utils.isosurfaceMibRendering(modelData, 2, dataset.image.pixSize, ...
%          dataset.image.boundingBox, opts);
%      if ~isempty(fv)
%          stlwrite('material_2.stl', fv);
%      end
%

% Updates
%

fv = [];

if nargin < 5; options = struct(); end
if ~isfield(options, 'reduce');   options.reduce   = 0;      end
if ~isfield(options, 'smooth');   options.smooth   = 5;      end
if ~isfield(options, 'maxFaces'); options.maxFaces = 300000; end

bb = boundingBox;

%% Compute sub-sampling factors (isotropic with aspect-ratio correction)
if options.reduce > 0
    factorX = ceil(size(Volume, 2) / options.reduce);
    factorY = ceil(factorX * pixSize.x / pixSize.y - 0.001);
    factorZ = ceil(factorX * pixSize.x / pixSize.z);
else
    factorX = 1;
    factorY = 1;
    factorZ = 1;
end

%% Compute smoothing kernel sizes (must be odd integers)
kernelX = options.smooth;
if kernelX > 0
    kernelY = round(kernelX * pixSize.x / pixSize.y);
    kernelY = kernelY + abs(mod(kernelY, 2) - 1);   % force odd
    kernelZ = round(kernelX * pixSize.x / pixSize.z);
    kernelZ = kernelZ + abs(mod(kernelZ, 2) - 1);   % force odd
    kernelX = kernelX + abs(mod(kernelX, 2) - 1);   % force odd
end

%% Extract binary sub-volume for the requested material
subVolume = uint8(Volume == materialIndex);
if ~any(subVolume(:))
    return;
end

%% Smooth
if kernelX > 0
    subVolume = uint8(smooth3(subVolume, 'box', [kernelX kernelY kernelZ]));
end

%% Reduce (downsample)
if factorX > 1 || factorY > 1 || factorZ > 1
    [~, ~, ~, subVolume] = reducevolume(subVolume, [factorX, factorY, factorZ]);
end

%% Extract isosurface
[faces, verts] = isosurface(subVolume, 0.5);
if isempty(verts)
    return;
end

%% Map vertex coordinates to physical space
verts(:, 1) = verts(:, 1) * pixSize.x * factorX + bb(1) - pixSize.x * factorX;
verts(:, 2) = verts(:, 2) * pixSize.y * factorY + bb(3) - pixSize.y * factorY;
verts(:, 3) = verts(:, 3) * pixSize.z * factorZ + bb(5) - pixSize.z * factorZ;

fprintf('Object %d (before reduction of faces): N faces=%d, N vertices=%d\n', ...
    materialIndex, size(faces, 1), size(verts, 1));

%% Decimate to maxFaces
if options.maxFaces > 0 && size(faces, 1) > options.maxFaces
    fvTmp.faces    = faces;
    fvTmp.vertices = verts;
    fvTmp  = reducepatch(fvTmp, options.maxFaces);
    faces  = fvTmp.faces;
    verts  = fvTmp.vertices;
end

fv.faces    = faces;
fv.vertices = verts;

%% Optional interactive 3-D rendering
if isfield(options, 'showRendering') && options.showRendering
    figTag = 'isosurfaceMibRenderingFig';

    if isfield(options, 'initFigure') && options.initFigure
        % Create or reuse a dedicated figure
        hFig = findall(0, 'Type', 'figure', 'Tag', figTag);
        if isempty(hFig)
            hFig = figure('Tag', figTag, 'Name', 'Model rendering', ...
                'Color', [0.15 0.15 0.15], 'NumberTitle', 'off', ...
                'Renderer', 'opengl');
        else
            hFig = hFig(1);
            figure(hFig);
            cla(gca(hFig));
        end
        ax = axes(hFig);
        ax.Projection = 'perspective';
        hold(ax, 'on');
    else
        hFig = findall(0, 'Type', 'figure', 'Tag', figTag);
        if isempty(hFig)
            hFig = figure('Tag', figTag, 'Name', 'Model rendering', ...
                'Color', [0.15 0.15 0.15], 'NumberTitle', 'off', ...
                'Renderer', 'opengl');
            ax = axes(hFig);
            ax.Projection = 'perspective';
            hold(ax, 'on');
        else
            hFig = hFig(1);
            ax = gca(hFig);
        end
    end

    % Determine face color
    if isfield(options, 'matColor') && ~isempty(options.matColor)
        faceColor = options.matColor;
    else
        faceColor = rand(1, 3);
    end

    patch(ax, 'Faces', faces, 'Vertices', verts, ...
        'FaceColor', faceColor, 'EdgeColor', 'none', ...
        'FaceAlpha', 0.85, 'AmbientStrength', 0.3, ...
        'DiffuseStrength', 0.7, 'SpecularStrength', 0.4);

    if isfield(options, 'finalizeFigure') && options.finalizeFigure
        lighting(ax, 'gouraud');
        camlight(ax, 'headlight');
        material(ax, 'dull');
        axis(ax, 'tight');
        grid(ax, 'on');
        ax.GridAlpha = 0.15;
        ax.Color = [0.1 0.1 0.1];
        ax.XColor = [0.8 0.8 0.8];
        ax.YColor = [0.8 0.8 0.8];
        ax.ZColor = [0.8 0.8 0.8];
        xlabel(ax, 'X'); ylabel(ax, 'Y'); zlabel(ax, 'Z');
        rotate3d(ax, 'on');
        drawnow;
    end
end

end
