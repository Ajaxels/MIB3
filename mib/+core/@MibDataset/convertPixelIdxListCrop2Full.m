function PixelIdxList = convertPixelIdxListCrop2Full(obj, PixelIdxListCrop, options)
% CONVERTPIXELIDXLISTCROP2FULL - Convert PixelIdxList of a cropped sub-volume to the full dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      PixelIdxList = obj.convertPixelIdxListCrop2Full(PixelIdxListCrop, options)
%
% Input Arguments:
%   - **PixelIdxListCrop** — vector of linear indices within the cropped sub-volume
%     (column-major order: Y varies fastest, then X, then Z)
%   - **options** — struct with crop-region boundaries:
%
%     - ``.y`` — [yMin, yMax] Y-extent of the cropped region (rows)
%     - ``.x`` — [xMin, xMax] X-extent of the cropped region (columns)
%     - ``.z`` — *(optional)* [zMin, zMax] Z-extent; when absent the current
%       slice is used (XY orientation 3 only)
%
% Output Arguments:
%   - **PixelIdxList** — vector of linear indices in the full dataset

if nargin < 3; error('convertPixelIdxListCrop2Full: options struct is required'); end

if ~isfield(options, 'z')
    if obj.orientation ~= 3
        error('convertPixelIdxListCrop2Full: z not provided and dataset is not in XY orientation (3)');
    end
    z1 = obj.getCurrentSliceNumber();
else
    z1 = options.z(1);
end
x1 = options.x(1);
dx = options.x(2) - options.x(1) + 1;
y1 = options.y(1);
dy = options.y(2) - options.y(1) + 1;

PixelIdxList = obj.image.height * obj.image.width * ...
    (z1 + ceil(PixelIdxListCrop/(dx*dy)) - 2) + ...
     obj.image.height * (x1 + ceil((mod(PixelIdxListCrop-1, dy*dx)+1)/dy) - 2) + ...
     y1 + mod(PixelIdxListCrop-1, dy);

end
