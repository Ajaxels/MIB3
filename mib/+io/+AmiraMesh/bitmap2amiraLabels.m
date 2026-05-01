function result = bitmap2amiraLabels(filename, bitmap, format, voxel, color_list, modelMaterialNames, overwrite, showWaitbar, extraOptions)
% BITMAP2AMIRALABELS - Convert matrix [1:height, 1:width, 1:no_stacks] to Amira Mesh Labels.
%
% Syntax:
%   .. code-block:: matlab
%
%      result = io.AmiraMesh.bitmap2amiraLabels(filename, bitmap)
%      result = io.AmiraMesh.bitmap2amiraLabels(filename, bitmap, format, voxel, color_list, modelMaterialNames, overwrite, showWaitbar, extraOptions)
%
% Input Arguments:
%   - **filename** — filename for Amira Mesh file
%   - **bitmap** — the dataset [height, width, depth]
%   - **format** — *(optional)* saving format: ``'binaryRLE'``, ``'ascii'``, or ``'binary'``
%     (default: ``'binary'``)
%   - **voxel** — *(optional)* struct with voxel size:
%
%     - ``.x`` — physical width of a voxel
%     - ``.y`` — physical height of a voxel
%     - ``.z`` — physical thickness of a voxel
%     - ``.minx`` — minimal X coordinate of the bounding box
%     - ``.miny`` — minimal Y coordinate of the bounding box
%     - ``.minz`` — minimal Z coordinate of the bounding box
%
%   - **color_list** — *(optional)* matrix with material colours as
%     [materialId, Red, Green, Blue] in range 0–1; can be empty
%   - **modelMaterialNames** — *(optional)* cell array with material name strings; can be empty
%   - **overwrite** — *(optional)* ``1`` = do not check whether file already exists
%   - **showWaitbar** — *(optional)* ``1`` = show the wait bar, ``0`` = hide it
%   - **extraOptions** — *(optional)* struct with fields:
%
%     - ``.TransformationMatrix`` — (char) transformation matrix string
%     - ``.ParentFigure`` — handle to the main MIB UIFigure; when provided, progress bar
%       is shown as a ``uiprogressdlg`` attached to that window; when absent, legacy ``waitbar`` is used
%
% Output Arguments:
%   - **result** — ``1`` = success, ``0`` = failure
%
% **Example 1** — standalone use (no GUI parent):
%
%   .. code-block:: matlab
%
%      pixStr = dataset.pixSize;
%      pixStr.minx = boundingBox(1);
%      pixStr.miny = boundingBox(3);
%      pixStr.minz = boundingBox(5);
%      io.AmiraMesh.bitmap2amiraLabels('/output/Labels.am', labelsData, 'binary', pixStr, materialColors, materialNames, 1, false, struct());
%
% **Example 2** — GUI use (attach progress dialog to MIB window):
%
%   .. code-block:: matlab
%
%      pixStr = dataset.pixSize;
%      pixStr.minx = boundingBox(1);
%      pixStr.miny = boundingBox(3);
%      pixStr.minz = boundingBox(5);
%      extraOpts.ParentFigure = obj.mibModel.mibGUI;   % uiprogressdlg parent
%      io.AmiraMesh.bitmap2amiraLabels('/output/Labels.am', labelsData, 'binary', pixStr, materialColors, materialNames, 1, true, extraOpts);
%

% Updates
% 10.08.2010 - added voxel size
% 02.09.2011 - added minimal coordinates of the bounding box
% 07.07.2016 - added possibility to have color_list and modelMaterialNames empty
% 15.03.2018 - added saving of models with more than 255 materials
% 04.06.2018 - save TransformationMatrix with AmiraMesh
% 11.12.2018 - added auto remove of spaces in material names

result = 0;
minValRLE = 1;
if nargin < 2
    error('Please provide filename, and bitmap matrix!');
end
if nargin < 9;    extraOptions = struct(); end
if nargin < 8
    showWaitbar = 1;
end
if nargin < 7
    overwrite = 0;
end
if nargin < 6;   modelMaterialNames = []; end
if nargin < 5;   color_list = []; end

if nargin < 4
    voxel.x = 1;
    voxel.y = 1;
    voxel.z = 1;
    voxel.minx = 0;
    voxel.miny = 0;
    voxel.minz = 0;
end
if nargin < 3; format = 'binary'; end

useMaterialNames = 1;
if isa(bitmap, 'uint16') || isa(bitmap, 'uint32')
    useMaterialNames = 0;
end

if useMaterialNames
    if isempty(color_list)
        maxColor = max(max(max(bitmap)));
        if maxColor == 1
            color_list = squeeze(label2rgb(1:maxColor))';
        else
            color_list = squeeze(label2rgb(1:maxColor));
        end
        color_list = color_list/255;
    end

    if isempty(modelMaterialNames)
        maxColor = max(max(max(bitmap)));
        for color=1:maxColor
            modelMaterialNames(color) = cellstr(num2str(color));
        end
    else
        for i=1:numel(modelMaterialNames)
            matName = strtrim(modelMaterialNames{i});
            spaceIndices = ismember(matName, ' ');
            matName(spaceIndices) = [];
            modelMaterialNames{i} = matName;
        end
    end

    if max(max(color_list)) > 1
        color_list = color_list/max(max(color_list));
    end
end

if overwrite == 0
    if exist(filename,'file') == 2
        button = questdlg(sprintf('!!! Warning !!!\n\nThe file\n%s already exists!\nOverwrite?', filename),'Overwrite?','Overwrite','Cancel','Cancel');
        if strcmp(button, 'Cancel'); return; end
    end
end
wb = [];
if showWaitbar
    if nargin >= 9 && isstruct(extraOptions) && isfield(extraOptions,'ParentFigure') && ~isempty(extraOptions.ParentFigure)
        try
            wb = uiprogressdlg(extraOptions.ParentFigure, 'Title', sprintf('Saving Amira Mesh [%s]...', format), ...
                'Message', sprintf('%s\nPlease wait...', filename));
        catch; wb = []; end
    else
        wb = waitbar(0, sprintf('%s\nPlease wait...', filename), 'Name', sprintf('Saving Amira Mesh [%s]...', format));
    end
end

fid = fopen(filename, 'w');

if strcmp(format,'binary') || strcmp(format,'binaryRLE')
    fprintf(fid,'# AmiraMesh BINARY-LITTLE-ENDIAN 2.1\n\n\n');
elseif strcmp(format,'ascii')
    fprintf(fid,'# AmiraMesh 3D ASCII 2.0\n\n\n');
else
    fclose(fid);
    error('Wrong format!');
end

fprintf(fid,'define Lattice %d %d %d\n\n',size(bitmap,2),size(bitmap,1),size(bitmap,3));
fprintf(fid,'Parameters {\n');
if useMaterialNames
    fprintf(fid,'    Materials {\n');
    fprintf(fid,'        Exterior {\n');
    fprintf(fid,'        }\n');
    for contour=1:max(max(max(bitmap)))
        if isnan(str2double(modelMaterialNames{contour}))
            fprintf(fid,'        %s {\n', modelMaterialNames{contour});
        else
            fprintf(fid,'        Material_%s {\n', modelMaterialNames{contour});
        end
        fprintf(fid,'            Id %d,\n', contour);
        fprintf(fid,'            Color %f %f %f 0 \n', color_list(contour,1),color_list(contour,2),color_list(contour,3));
        fprintf(fid,'        }\n');
    end
    fprintf(fid,'    }\n');
end

classText = 'byte';
switch class(bitmap)
    case 'uint8'
        classText = 'byte';
    case 'uint16'
        classText = 'ushort';
    case 'uint32'
        classText = 'int';
end

fprintf(fid,'    Content "%dx%dx%d %s, uniform coordinates",\n',size(bitmap,2),size(bitmap,1),size(bitmap,3), classText);

fprintf(fid,'    BoundingBox %f %f %f %f %f %f,\n',...
    voxel.minx, voxel.minx+(size(bitmap,2)-1)*voxel.x,...
    voxel.miny, voxel.miny+(size(bitmap,1)-1)*voxel.y,...
    voxel.minz, voxel.minz+(size(bitmap,3)-1)*voxel.z);
fprintf(fid,'    CoordType "uniform"');

if isfield(extraOptions, 'TransformationMatrix')
    fprintf(fid,'\tTransformationMatrix %s\n', extraOptions.TransformationMatrix);
else
    fprintf(fid,'\n');
end

fprintf(fid,'}\n\n');
bitmap = reshape(permute(bitmap,[2 1 3]),1,[])';
if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=0.1; else; waitbar(0.1,wb); end; end

if strcmp(format,'binary')
    fprintf(fid,'Lattice { %s Labels } @1\n\n', classText);
    fprintf(fid,'# Data section follows\n');
    fprintf(fid,'@1\n');
    fwrite(fid, bitmap, class(bitmap), 0, 'ieee-le');
elseif strcmp(format,'ascii')
    fprintf(fid,'Lattice { %s Labels } @1\n\n', classText);
    fprintf(fid,'# Data section follows\n');
    fprintf(fid,'@1\n');
    maxVal = numel(bitmap);
    waitbarScale = round(maxVal/10);
    for ind = 1:maxVal
        if ~isempty(wb) && mod(ind, waitbarScale)==1; if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=ind/maxVal; else; waitbar(ind/maxVal,wb); end; end
        fprintf(fid,'%d \n',bitmap(ind));
    end
elseif strcmp(format,'binaryRLE')
    maxVal = numel(bitmap)-1;
    indexBlockStart = 1;
    lastCharacter = NaN;
    bytesCounter = 0;
    if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=0.2; else; waitbar(0.2,wb); end; end

    while indexBlockStart < maxVal
        blockOut = zeros([127 1])*NaN;
        commulativeIndex = 0;

        for blockCounter=1:127
            if indexBlockStart + blockCounter == maxVal
                blockOut = blockOut(1:end);
                indexBlockStart = maxVal+2;
                lastCharacter = bitmap(end);
                break;
            end
            currId = indexBlockStart+blockCounter-1;
            nextId = indexBlockStart+blockCounter;
            if bitmap(currId) ~= bitmap(nextId)
                if commulativeIndex < minValRLE
                    blockOut(blockCounter) = bitmap(currId);
                else
                    commulativeIndex = commulativeIndex + 1;
                    indexBlockStart = nextId;
                    break;
                end
            else
                commulativeIndex = commulativeIndex + 1;
                if commulativeIndex < minValRLE
                    blockOut(blockCounter) = bitmap(currId);
                else
                    if commulativeIndex < blockCounter
                        blockOut = blockOut(1:blockCounter-commulativeIndex);
                        indexBlockStart = nextId-commulativeIndex;
                        commulativeIndex = 0;
                        break;
                    else
                        blockOut = bitmap(indexBlockStart);
                    end
                end
            end
            if commulativeIndex == 127
                indexBlockStart = indexBlockStart + 127;
            end
        end

        if isscalar(blockOut) && commulativeIndex ~= 0
            counter = uint8(commulativeIndex);
            bitmap(bytesCounter+1) = counter;
            bitmap(bytesCounter+2) = blockOut;
            bytesCounter = bytesCounter + 2;
        else
            counter = bitset(uint8(numel(blockOut)), 8, 1);
            bitmap(bytesCounter+1) = counter;
            bitmap(bytesCounter+2:bytesCounter+1+numel(blockOut)) = blockOut;
            bytesCounter = bytesCounter + numel(blockOut) + 1;
        end
    end

    if indexBlockStart == maxVal
        lastCharacter = bitmap(end);
    end
    if ~isnan(lastCharacter)
        bitmap(bytesCounter+1) = uint8(1);
        bitmap(bytesCounter+2) = lastCharacter;
        bytesCounter = bytesCounter + 2;
    end
    fprintf(fid,'Lattice { %s Labels } @1(HxByteRLE,%d)\n\n', classText, bytesCounter);
    fprintf(fid,'# Data section follows\n');
    fprintf(fid,'@1\n');
    if ~isempty(wb); if isa(wb,'matlab.ui.dialog.ProgressDialog'); wb.Value=0.8; else; waitbar(0.8,wb); end; end
    switch class(bitmap)
        case 'uint8'
            fwrite(fid, bitmap(1:bytesCounter), '*uint8', 0, 'ieee-le');
        case 'uint16'
            fwrite(fid, bitmap(1:bytesCounter), '*uint16', 0, 'ieee-le');
        case 'uint32'
            fwrite(fid, bitmap(1:bytesCounter), '*uint32', 0, 'ieee-le');
    end
end
fprintf(fid,'\n');
fclose(fid);
if ~isempty(wb); delete(wb); end
disp(['bitmap2amiraLabels: ' filename ' was created!']);
result = 1;
end
