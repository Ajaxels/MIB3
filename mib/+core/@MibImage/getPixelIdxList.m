function dataset = getPixelIdxList(obj, type, PixelIdxList)
% GETPIXELIDXLIST - Get pixel values at a list of linear indices from MibImage or a subclass.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getPixelIdxList(type, PixelIdxList)
%
% For standard MibImage and MibLabels the raw data are read directly from
% obj.data.  For MibLabels63 (bit-packed) the values are unpacked
% according to the layer type:
% - 'labels'    - material bits (bitand with obj.materialMask: 63 or 16383)
% - 'mask'      - mask bit as uint8 0/1 (bitget obj.maskBit: 7 or 15)
% - 'selection' - selection bit as uint8 0/1 (bitget obj.selectionBit: 8 or 16)
% - 'everything'- raw packed value (no unpacking)
%
% Input Arguments:
%   - **type** - char, layer type to read:
%
%     - ``'image'`` - pixel values from an image layer (MibImage)
%     - ``'labels'`` - material indices from labels layer
%     - ``'mask'`` - mask layer values (0/1)
%     - ``'selection'`` - selection layer values (0/1)
%     - ``'everything'`` - raw packed byte (MibLabels63 only)
%   - **PixelIdxList** - numeric vector of linear pixel indices into obj.data
%     in the XY orientation (standard MATLAB column-major order)
%
% Output Arguments:
%   - **dataset** - numeric column vector of values at the requested indices;
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
%   **Example 2** - Reading from the image layer
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
    % bit-packed container, layout from core.MibLabels63.setLayout: labels in bits
    % 1-6, mask in bit 7, selection in bit 8 (uint8), or 1-14 / 15 / 16 (uint16)
    switch type
        case 'labels'
            dataset = bitand(obj.data(PixelIdxList), obj.materialMask);
        case 'mask'
            dataset = uint8(bitget(obj.data(PixelIdxList), obj.maskBit));
        case 'selection'
            dataset = uint8(bitget(obj.data(PixelIdxList), obj.selectionBit));
        case 'everything'
            dataset = obj.data(PixelIdxList);
        otherwise
            error('getPixelIdxList: unknown type ''%s'' for MibLabels63', type);
    end
else
    % Standard MibImage or MibLabels - raw read
    dataset = obj.data(PixelIdxList);
end
end
