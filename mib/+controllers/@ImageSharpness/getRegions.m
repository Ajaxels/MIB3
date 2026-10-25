function regions = getRegions(obj)
% GETREGIONS - Read the image regions to analyse from the current slice of the active dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      regions = obj.getRegions()
%
% Regions come from ``obj.BatchOpt.RegionSource`` and are read from the
% current slice, time point and orientation, for the channel in
% ``obj.BatchOpt.ColorChannel``. Pixels are always read at full resolution
% (``resizeToMagnification = false``): pyramid datasets would otherwise
% return a lower resolution level when zoomed out, and the measured
% resolution would follow the zoom.
%
%   - ``'Shown area'`` - the part of the slice visible in the image view
%   - ``'Whole slice'`` - the full slice
%   - ``'ROIs'`` - one region per ROI of the current orientation, cropped to
%     the ROI bounding box (the Fourier methods need a rectangle; pixels
%     outside a non-rectangular ROI are kept)
%   - ``'Selection layer'`` / ``'Mask layer'`` - one region per 8-connected
%     object of the selection or mask layer on the current slice, cropped to
%     its bounding box; named ``Selection N`` / ``Mask N``
%   - ``'Drawn rectangle'`` - the rectangle from
%     :func:`controllers.ImageSharpness.drawRectangle`; it must belong to the
%     active dataset and the current orientation
%
% Output Arguments:
%   - **regions** - struct array with fields:
%
%     - ``.image`` - [numeric, 2D] region pixels
%     - ``.name`` - [char] region name for the results table
%     - ``.position`` - [double] ``[x1 y1 x2 y2]`` in pixels of the shown
%       orientation; for the shown area taken from ``axesX``/``axesY`` of the
%       dataset and the size of the returned image
%
% Errors:
%   - ``MIB:ImageSharpness:NoRegions`` when the chosen source holds no
%     region (no ROI, no mask, an empty selection or mask on the slice, no
%     rectangle or a rectangle of another dataset or orientation); the
%     message tells the user what to do
%

% Updates
%

id = obj.BatchOpt.id;
dataset = obj.mibModel.I{id};
orientation = dataset.orientation;
channel = str2double(erase(obj.BatchOpt.ColorChannel{1}, 'Ch '));
getDataOptions = struct('id', id, 'resizeToMagnification', false, 'blockModeSwitch', 0);
regions = struct('image', {}, 'name', {}, 'position', {});

switch obj.BatchOpt.RegionSource{1}
    case 'Shown area'
        getDataOptions.blockModeSwitch = 1;
        regionImage = cell2mat(obj.mibModel.getData2D('image', [], [], channel, getDataOptions));
        % visible area in data pixels, for Jump to area
        firstPixel = max(1, ceil([dataset.axesX(1), dataset.axesY(1)]));
        position = [firstPixel, firstPixel + [size(regionImage, 2), size(regionImage, 1)] - 1];
        regions(1) = struct('image', regionImage, 'name', 'Shown area', 'position', position);
    case 'Whole slice'
        regionImage = cell2mat(obj.mibModel.getData2D('image', [], [], channel, getDataOptions));
        regions(1) = struct('image', regionImage, 'name', 'Whole slice', ...
            'position', [1 1 size(regionImage, 2) size(regionImage, 1)]);
    case 'ROIs'
        [numberOfRoi, roiIndices] = dataset.hROI.getNumberOfROI(orientation);
        if numberOfRoi == 0
            error('MIB:ImageSharpness:NoRegions', ...
                'There are no ROIs in this orientation.\nAdd ROIs in the ROI panel, or choose another region.');
        end
        for roiId = 1:numberOfRoi
            roiIndex = roiIndices(roiId);
            getDataOptions.roiId = roiIndex;
            getDataOptions.fillBg = NaN;
            regionImage = cell2mat(obj.mibModel.getData2D('image', [], [], channel, getDataOptions));
            boundingBox = dataset.hROI.getBoundingBox(roiIndex);   % [x1 x2 y1 y2]
            label = string(dataset.hROI.Data(roiIndex).label);
            if isempty(label) || strlength(label(1)) == 0
                regionName = sprintf('ROI %d', roiIndex);
            else
                regionName = sprintf('ROI %s', label(1));
            end
            regions(roiId) = struct('image', regionImage, 'name', regionName, ...
                'position', boundingBox([1 3 2 4]));
        end
    case {'Selection layer', 'Mask layer'}
        if strcmp(obj.BatchOpt.RegionSource{1}, 'Mask layer')
            layerName = 'mask';
            regionPrefix = 'Mask';
            if ~dataset.maskExist
                error('MIB:ImageSharpness:NoRegions', ...
                    'This dataset has no mask.\nCreate a mask with the areas to analyse, or choose another region.');
            end
        else
            layerName = 'selection';
            regionPrefix = 'Selection';
        end
        layerSlice = cell2mat(obj.mibModel.getData2D(layerName, [], [], [], getDataOptions));
        if ~any(layerSlice(:))
            error('MIB:ImageSharpness:NoRegions', ...
                'The %s layer is empty on this slice.\nMark the areas to analyse, for example with the brush or the lasso tool.', layerName);
        end
        sliceImage = cell2mat(obj.mibModel.getData2D('image', [], [], channel, getDataOptions));
        objectProperties = regionprops(layerSlice > 0, 'BoundingBox');
        for objectId = 1:numel(objectProperties)
            boundingBox = objectProperties(objectId).BoundingBox;   % [x y width height], pixel edges at .5
            x1 = ceil(boundingBox(1));
            y1 = ceil(boundingBox(2));
            x2 = x1 + boundingBox(3) - 1;
            y2 = y1 + boundingBox(4) - 1;
            regions(objectId) = struct('image', sliceImage(y1:y2, x1:x2), ...
                'name', sprintf('%s %d', regionPrefix, objectId), 'position', [x1 y1 x2 y2]);
        end
    case 'Drawn rectangle'
        if isempty(obj.drawnRectangle)
            error('MIB:ImageSharpness:NoRegions', 'Press Draw to define the rectangle first.');
        end
        if obj.drawnRectangle.id ~= id || obj.drawnRectangle.orientation ~= orientation
            error('MIB:ImageSharpness:NoRegions', ...
                'The rectangle was drawn on another dataset or orientation.\nPress Draw to define it again.');
        end
        position = obj.drawnRectangle.position;
        getDataOptions.x = position([1 3]);
        getDataOptions.y = position([2 4]);
        regionImage = cell2mat(obj.mibModel.getData2D('image', [], [], channel, getDataOptions));
        regions(1) = struct('image', regionImage, ...
            'name', sprintf('Rect %d-%d, %d-%d', position(1), position(3), position(2), position(4)), ...
            'position', position);
end
end
