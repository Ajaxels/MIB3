function dataset = getPixelIdxList(obj, type, PixelIdxList)
% GETPIXELIDXLIST - Get pixel values at a list of linear indices from MibImage or a subclass.
%
% Syntax:
%   function dataset = getPixelIdxList(obj, type, PixelIdxList)
%
% For standard MibImage and MibLabels the raw data are read directly from
% obj.data{1}.  For MibLabels63 (bit-packed) the values are unpacked
% according to the layer type:
% - 'labels'    — lower 6 bits  (bitand with 63)
% - 'mask'      — bit 7         (bitget position 7)
% - 'selection' — bit 8         (bitget position 8)
% - 'everything'— raw byte      (no unpacking)
%
% Input Arguments:
%   - **type** — char, layer type to read:
%
%     - ``'image'`` — pixel values from an image layer (MibImage)
%     - ``'labels'`` — material indices from labels layer
%     - ``'mask'`` — mask layer values (0/1)
%     - ``'selection'`` — selection layer values (0/1)
%     - ``'everything'`` — raw packed byte (MibLabels63 only)
%   - **PixelIdxList** — numeric vector of linear pixel indices into obj.data{1}
%     in the XY orientation (standard MATLAB column-major order)
%
% Output Arguments:
%   - **dataset** — numeric column vector of values at the requested indices;
%     [] when the layer does not exist (e.g. modelExist == 0)
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     CC = bwconncomp(mask3D, 26);
%     vals = obj.labels.getPixelIdxList('selection', CC.PixelIdxList{1});
%
%   **Example 2** — Reading from the image layer
%
%   .. code-block:: matlab
%
%
%     % Reading from the image layer:
%     pixVals = obj.image.getPixelIdxList('image', idx);
%

% Updates
%

dataset = [];
if nargin < 3; error('getPixelIdxList: PixelIdxList is required'); end
if nargin < 2; type = 'image'; end

if isa(obj, 'core.MibLabels63')
    % bit-packed container: labels in bits 1-6, mask in bit 7, selection in bit 8
    switch type
        case 'labels'
            dataset = bitand(obj.data{1}(PixelIdxList), 63);
        case 'mask'
            dataset = bitget(obj.data{1}(PixelIdxList), 7);
        case 'selection'
            dataset = bitget(obj.data{1}(PixelIdxList), 8);
        case 'everything'
            dataset = obj.data{1}(PixelIdxList);
        otherwise
            error('getPixelIdxList: unknown type ''%s'' for MibLabels63', type);
    end
else
    % Standard MibImage or MibLabels — raw read
    dataset = obj.data{1}(PixelIdxList);
end
end
