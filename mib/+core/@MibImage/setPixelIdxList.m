function result = setPixelIdxList(obj, type, dataset, PixelIdxList)
% SETPIXELIDXLIST - Write pixel values at a list of linear indices into MibImage or a subclass.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.setPixelIdxList(type, dataset, PixelIdxList)
%
% For standard MibImage and MibLabels the raw data are written directly to
% obj.data.  For MibLabels63 (bit-packed) the values are packed into the
% appropriate bits of the layout (core.MibLabels63.setLayout); dataset is
% cast to the container class first:
% - 'labels'    - clear old label (bitand obj.flagsMask) then bitor new value
% - 'mask'      - bitset position obj.maskBit (7 or 15)
% - 'selection' - bitset position obj.selectionBit (8 or 16)
% - 'everything'- overwrite the raw packed value without any masking
%
% Input Arguments:
%   - **type** - char, layer type to write:
%
%     - ``'image'`` - pixel values of an image layer (MibImage)
%     - ``'labels'`` - material indices into labels layer
%     - ``'mask'`` - mask layer values (0/1)
%     - ``'selection'`` - selection layer values (0/1)
%     - ``'everything'`` - raw packed byte (MibLabels63 only)
%   - **dataset** - numeric vector of values to write; must match numel(PixelIdxList)
%   - **PixelIdxList** - numeric vector of linear pixel indices into obj.data
%     in the XY orientation (standard MATLAB column-major order)
%
% Output Arguments:
%   - **result** - logical **true** on success, **false** on error
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     CC = bwconncomp(mask3D, 26);
%     val = zeros(numel(CC.PixelIdxList{1}), 1, 'uint8') + 1;
%     obj.labels.setPixelIdxList('selection', val, CC.PixelIdxList{1});
%
%   **Example 2** - Clearing the selection layer at specific pixels
%
%   .. code-block:: matlab
%
%
%     % Clearing the selection layer at specific pixels:
%     obj.labels.setPixelIdxList('selection', zeros(numel(idx),1,'uint8'), idx);
%

% Updates
%

result = false;
if nargin < 4; error('setPixelIdxList: PixelIdxList is required'); end

if isa(obj, 'core.MibLabels63')
    % bit-packed container, layout from core.MibLabels63.setLayout: labels in bits
    % 1-6, mask in bit 7, selection in bit 8 (uint8), or 1-14 / 15 / 16 (uint16)
    if ~isa(dataset, obj.containerClass); dataset = cast(dataset, obj.containerClass); end
    switch type
        case 'labels'
            obj.data(PixelIdxList) = bitand(obj.data(PixelIdxList), obj.flagsMask); % clear the material bits
            obj.data(PixelIdxList) = bitor(obj.data(PixelIdxList), dataset);
        case 'mask'
            obj.data(PixelIdxList) = bitset(obj.data(PixelIdxList), obj.maskBit, dataset);
        case 'selection'
            obj.data(PixelIdxList) = bitset(obj.data(PixelIdxList), obj.selectionBit, dataset);
        case 'everything'
            obj.data(PixelIdxList) = dataset;
        otherwise
            error('setPixelIdxList: unknown type ''%s'' for MibLabels63', type);
    end
else
    % Standard MibImage or MibLabels - raw write
    obj.data(PixelIdxList) = dataset;
end

result = true;
end
