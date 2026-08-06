function [img, img_info, viewPort] = getImarisDataset_StandardConnection(vImarisApp)
% GETIMARISDATASET_STANDARDCONNECTION - Get a dataset opened in Imaris and corresponding meta-data.
%
% Syntax:
%   function [img, img_info, viewPort] = getImarisDataset_StandardConnection(vImarisApp)
%
% Input Arguments:
%   - **vImarisApp** - *(optional)* a handle to Imaris
%
% Output Arguments:
%   - **img** - 4D dataset
%   - **img_info** - ``containers.Map`` with meta data
%   - **viewPort** - a structure with the viewPort parameters:
%
%     - ``.min`` - a vector with minimal intensities for contrast adjustment
%     - ``.max`` - a vector with maximal intensities for contrast adjustment
%     - ``.gamma`` - a vector with gamma factor for contrast adjustment
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     [img, img_info] = io.imaris.getImarisDataset_StandardConnection();
%

% Updates
% 

if nargin < 1; vImarisApp = []; end

% get instance of Imaris
if isempty(vImarisApp)
    vImarisLib = ImarisLib;
    vObjectId = 0; 
    vImarisApp = vImarisLib.GetApplication(vObjectId);

    if isequal(vImarisApp, [])
      disp('Could not connect to Imaris')
      return;
    end
end

img = NaN;
img_info = NaN;
frameNumber = NaN;

vImage = vImarisApp.GetDataSet();   % get handle to a dataset; class IDataSet
if isequal(vImage, [])
	disp('getImarisDataset_StandardConnection error! a volume should be opened in Imaris')
    return;
end

% Get size of the dataset in pixels
vSizeX = vImage.GetSizeX;   % get in pixels
vSizeY = vImage.GetSizeY;   % get in pixels
vSizeZ = vImage.GetSizeZ;   % get in pixels
vSizeC = vImage.GetSizeC;   % get in pixels
vSizeT = vImage.GetSizeT;   % get in pixels
if vSizeZ > 1 && vSizeT > 1
    answer = utils.dlgs.inputUniversalDlg([], '!!! Warning !!!', ...
        {sprintf('MIB can''t open 5D datasets!\nPlease enter a time point to open:')}, {'1'}, ...
        'Time point', struct());
    if isempty(answer)
        return;
    end
    frameNumber = str2double(answer{1});    % frame number to open for 5D datasets
end

img_info = containers.Map;
img_info('Width') = vSizeX;
img_info('Height') = vSizeY;
if vSizeZ >= 1 && vSizeT == 1
    img_info('Depth') = vSizeZ;    % open as Z-stack
else
    img_info('Depth') = vSizeT;    % open as a movie
end
if vSizeC == 1
    img_info('ColorType') = 'grayscale';
else
    img_info('ColorType') = 'multichannel';
end

% Get the extents of the image, Bounding Box in image units
minX = vImage.GetExtendMinX;     % get X min in units
minY = vImage.GetExtendMinY;     % get Y min in units
minZ = vImage.GetExtendMinZ;     % get Z min in units
maxX = vImage.GetExtendMaxX;     % get X max in units
maxY = vImage.GetExtendMaxY;     % get Y max in units
maxZ = vImage.GetExtendMaxZ;     % get Z max in units

img_info('ImageDescription') = sprintf('BoundingBox %.5f %.5f %.5f %.5f %.5f %.5f |',...
    minX, maxX, minY, maxY, minZ, maxZ);

% Get details of contrast and gamma
datasetJavaClass = vImage.GetType();     % get type of data
datasetJavaClass = char(datasetJavaClass.toString); 
switch datasetJavaClass
    case 'eTypeUInt8'
        datasetClass = 'uint8';
    case 'eTypeUInt16'
        datasetClass = 'uint16';
    case 'eTypeFloat'
        datasetClass = 'single';
end
max_int = double(intmax(datasetClass));

% update viewPort structure
for colId = 1:vSizeC
    viewPort.min(colId) = double(vImage.GetChannelRangeMin(colId-1))/max_int;   % convert to 0-1
    viewPort.max(colId) = double(vImage.GetChannelRangeMax(colId-1))/max_int;   % convert to 0-1
    viewPort.gamma(colId) = double(vImage.GetChannelGamma(colId-1));
end

if isnan(frameNumber)   % open 4D dataset
    img = vImage.GetDataBytes();    % [time, color, width, height, z]
    img = permute(img,[4,3,2,5,1]);     % permute
    img = squeeze(img);     % squeeze
    
%     % Get the stack
%     switch char(iDataSet.GetType())
%         case 'eTypeUInt8',
%             % Java does not have unsigned ints
%             arr = iDataSet.GetDataVolumeAs1DArrayBytes(channel, timepoint);
%             stack(:) = typecast(arr, 'uint8');
%         case 'eTypeUInt16',
%             % Java does not have unsigned ints
%             arr = iDataSet.GetDataVolumeAs1DArrayShorts(channel, timepoint);
%             stack(:) = typecast(arr, 'uint16');
%         case 'eTypeFloat',
%             stack(:) = ...
%                 iDataSet.GetDataVolumeAs1DArrayFloats(channel, timepoint);
%         otherwise,
%             error('Bad value for iDataSet.GetType().');
%     end
%     
else
    
end

end
