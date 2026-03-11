% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi
% Date: 25.04.2023
% Ported from MIB2 to MIB3 package structure (utils.mibRenderModel)
% Source: MIB2_RENAMED_FOR_MIB3/Tools/mibRenderModel.m

function p = mibRenderModel(Volume, Index, pixSize, boundingBox, color_list, Image, Options)
% function p = mibRenderModel(Volume, Index, pixSize, boundingBox, color_list, Image, Options)
% Render a model using isosurfaces
%
% Parameters:
% Volume: a model, [1:height, 1:width, 1:thickness] with materials
% Index: iso value; if @b 0 or @b NaN generate isosurfaces for all materials
% pixSize: structure with physical dimensions of voxels
%   - .x - physical width
%   - .y - physical height
%   - .z - physical thickness
%   - .units - physical units
% boundingBox: bounding box [xMin, xMax, yMin, yMax, zMin, zMax]
% color_list: [@em optional] list of colors (0-1), [materialIndex][Red, Green, Blue]
% Image: the image layer used to place an orthoslice
% Options: [@em optional] structure with parameters:
% @li .reduce - reduce volume to this width in pixels (0 = no reduction)
% @li .smooth - smoothing 3D kernel width (0 = no smoothing)
% @li .maxFaces - max number of faces (0 = no limit)
% @li .slice - orthoslice number to show (0 or NaN = none)
% @li .exportToImaris - switch to export model to Imaris
% @li .modelMaterialNames - cell array of material names
%
% Return values:
% p: array of triangulated patches with fields 'Faces' and 'Vertices'
%
% Example:
%   @code
%   opts.reduce   = 500;
%   opts.smooth   = 5;
%   opts.maxFaces = 300000;
%   opts.slice    = 0;
%   p = utils.mibRenderModel(modelData, NaN, dataset.pixSize, dataset.boundingBox, ...
%       labels.materialColors, NaN, opts);
%   for i = 1:numel(p)
%       fv = struct('faces', p(i).Faces, 'vertices', p(i).Vertices);
%       stlwrite(sprintf('material_%d.stl', i), fv, 'FaceColor', p(i).FaceColor*255);
%   end
%   @endcode

if nargin < 7
    prompt = {'Reduce the volume down to, width pixels [no volume reduction when 0]?',...
        'Smoothing 3d kernel, width (no smoothing when 0):',...
        'Maximal number of faces (no limit when 0):',...
        'Show orthoslice (enter a number slice number, or NaN, or 0):'};
    dlg_title = 'Isosurface parameters';

    if size(Volume,2) > 500
        resizeText = '500';
    else
        resizeText = '0';
    end

    if isnan(Image(1))
        def = {resizeText,'5','300000','NaN'};
    else
        def = {resizeText,'5','300000','1'};
    end
    answer = inputdlg(prompt,dlg_title,1,def);
    if isempty(answer); return; end

    Options.reduce  = str2double(answer{1});
    Options.smooth  = str2double(answer{2});
    Options.maxFaces = str2double(answer{3});
    Options.slice   = str2double(answer{4});
    Options.modelMaterialNames = repmat(cellstr('Material'), [max(max(max(Volume))), 1]);
    Options.exportToImaris = 0;
    if isnan(Options.slice); Options.slice = 0; end
end
if ~isfield(Options, 'exportToImaris'); Options.exportToImaris = 0; end
if ~isfield(Options, 'modelMaterialNames'); Options.modelMaterialNames = repmat(cellstr('Material'), [max(max(max(Volume))), 1]); end

if nargin < 6
    Image = NaN;
end

if nargin < 5
    for i=1:255
        color_list(i,:) = [rand(1) rand(1) rand(1)];
    end
end

wb = waitbar(0, 'Smoothing the volume...','Name','Isosurface');
if isnan(Index); Index = 0; end
if Index==0
    Index = 1:numel(Options.modelMaterialNames);
end

bb = boundingBox;

if Options.reduce ~= 0
    factorX=ceil(size(Volume,2)/Options.reduce);
    factorY=ceil(factorX*pixSize.x/pixSize.y-.001);
    factorZ=ceil(factorX*pixSize.x/pixSize.z);
else
    factorX=1;
    factorY=1;
    factorZ=1;
end

kernelX = Options.smooth;
kernelY = round(kernelX*pixSize.x/pixSize.y) + abs(mod(round(kernelX*pixSize.x/pixSize.y),2)-1);
kernelZ = round(kernelX*pixSize.x/pixSize.z) + abs(mod(round(kernelX*pixSize.x/pixSize.z),2)-1);

fig = figure(12347);
set(gcf, 'Renderer', 'opengl');
clf;
daspect([1 1 1]);
maxIndex = numel(Index);

for contIndex = Index
    subVolume = Volume==contIndex;

    if kernelX ~= 0
        waitbar(0.2*contIndex/maxIndex, wb, sprintf('Material %d: Smoothing the surface...', contIndex));
        subVolume = uint8(smooth3(subVolume, 'box', [kernelX kernelY kernelZ]));
    end
    waitbar(0.4*contIndex/maxIndex, wb, sprintf('Material %d: Reducing the volume...', contIndex));
    [~,~,~,subVolume] = reducevolume(subVolume,[factorX,factorY,factorZ]);
    waitbar(0.6*contIndex/maxIndex, wb, sprintf('Material %d: Generating isosurface...', contIndex));
    [faces, verts] = isosurface(subVolume,0.5);
    if isempty(verts); continue; end

    verts(:,1) = verts(:,1)*pixSize.x*factorX + bb(1) - pixSize.x*factorX;
    verts(:,2) = verts(:,2)*pixSize.y*factorY + bb(3) - pixSize.y*factorY;
    verts(:,3) = verts(:,3)*pixSize.z*factorZ + bb(5) - pixSize.z*factorZ;

    disp(['Object ' num2str(contIndex) ' (before reduction of faces): N faces=' num2str(size(faces,1)) ', N vertices=' num2str(size(verts,1))]);
    waitbar(0.8*contIndex/maxIndex, wb, sprintf('Material %d: Rendering...', contIndex));
    p(contIndex) = patch('Faces',faces, 'Vertices', verts, ...
        'FaceColor', color_list(contIndex,:), 'EdgeColor', 'none'); %#ok<AGROW>
    if Options.maxFaces ~= 0
        waitbar(0.9*contIndex/maxIndex, wb, sprintf('Material %d: Reducing number of faces...', contIndex));
        reducepatch(p(contIndex), Options.maxFaces);
    end
    set(p(contIndex),'AmbientStrength',.3);

    if Options.exportToImaris == 1
        surface.faces    = p(contIndex).Faces;
        surface.vertices = p(contIndex).Vertices;
        imarisOpts.color = color_list(contIndex,:);
        if isfield(Options, 'modelMaterialNames')
            imarisOpts.name = Options.modelMaterialNames{contIndex};
        end
        mibSetImarisSurface(surface, [], imarisOpts);
    end
end

set(gca,'projection','perspective');
lighting gouraud;
camlight('headlight');
axis tight;
grid;
view3d(fig, 'rot');

% add an orthoslice
if Options.slice ~= 0
    Options.slice = max([Options.slice 1]);
    hold on;
    img = zeros([size(subVolume,1), size(subVolume,2), size(Image, 3)], class(Image));
    if size(Image, 4) > 1
        zIndex = Options.slice;
    else
        zIndex = 1;
    end
    for c=1:size(Image, 3)
        img(:,:,c) = imresize(Image(:, :, c, zIndex), [size(subVolume,1) size(subVolume,2)], 'bicubic');
    end

    if size(Image, 3) == 2
        img(:,:,3) = zeros([size(img, 1) size(img, 2)], class(Image));
    elseif size(Image, 3) > 3
        img = img(:,:,1:3);
    end

    xValue = deal(bb(1):(bb(2)-bb(1))/size(img,2):bb(2));
    xValue = xValue(1:end-1);
    yValue = deal(bb(3):(bb(4)-bb(3))/size(img,1):bb(4));
    yValue = yValue(1:end-1);
    [xValue, yValue] = meshgrid(xValue, yValue);

    zValue = Options.slice*pixSize.z+bb(5);
    surf(xValue, yValue, zValue+zeros([size(img, 1) size(img, 2)]), img, 'EdgeColor', 'none')
    colormap('gray');
    hold off;
end

set(gca,'GridAlpha',.5);
set(gca,'color',[1 1 1 0]);
disp('Hint: render image to file with the following command:')
disp('print(''MIB-snapshot.tif'', ''-dtiff'', ''-r600'',''-opengl'');');
delete(wb);
end
