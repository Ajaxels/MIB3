function result = setPixelIdxList(obj, type, dataset, PixelIdxList)
% function result = setPixelIdxList(obj, type, dataset, PixelIdxList)
% Write pixel values at a list of linear indices into MibImage or a subclass.
%
% For standard MibImage and MibLabels the raw data are written directly to
% obj.data{1}.  For MibLabels63 (bit-packed) the values are packed into the
% appropriate bits:
% @li 'labels'    — bits 1-6: clear old label (bitand 192) then bitor new value
% @li 'mask'      — bit 7:   bitset position 7
% @li 'selection' — bit 8:   bitset position 8
% @li 'everything'— overwrite raw byte without any masking
%
% Parameters:
% type: char, layer type to write
%   @li 'image'     - pixel values of an image layer (MibImage)
%   @li 'labels'    - material indices into labels layer
%   @li 'mask'      - mask layer values (0/1)
%   @li 'selection' - selection layer values (0/1)
%   @li 'everything'- raw packed byte (MibLabels63 only)
% dataset: numeric vector of values to write; must match numel(PixelIdxList)
% PixelIdxList: numeric vector of linear pixel indices into obj.data{1}
%   in the XY orientation (standard MATLAB column-major order)
%
% Return values:
% result: logical @b true on success, @b false on error

%|
% @b Examples:
% @code
% CC = bwconncomp(mask3D, 26);
% val = zeros(numel(CC.PixelIdxList{1}), 1, 'uint8') + 1;
% obj.labels.setPixelIdxList('selection', val, CC.PixelIdxList{1});
% @endcode
% @code
% % Clearing the selection layer at specific pixels:
% obj.labels.setPixelIdxList('selection', zeros(numel(idx),1,'uint8'), idx);
% @endcode

% Updates
%

result = false;
if nargin < 4; error('setPixelIdxList: PixelIdxList is required'); end

if isa(obj, 'core.MibLabels63')
    % bit-packed container: labels in bits 1-6, mask in bit 7, selection in bit 8
    switch type
        case 'labels'
            obj.data{1}(PixelIdxList) = bitand(obj.data{1}(PixelIdxList), uint8(192)); % clear bits 1-6
            obj.data{1}(PixelIdxList) = bitor(obj.data{1}(PixelIdxList), dataset);
        case 'mask'
            obj.data{1}(PixelIdxList) = bitset(obj.data{1}(PixelIdxList), 7, dataset);
        case 'selection'
            obj.data{1}(PixelIdxList) = bitset(obj.data{1}(PixelIdxList), 8, dataset);
        case 'everything'
            obj.data{1}(PixelIdxList) = dataset;
        otherwise
            error('setPixelIdxList: unknown type ''%s'' for MibLabels63', type);
    end
else
    % Standard MibImage or MibLabels — raw write
    obj.data{1}(PixelIdxList) = dataset;
end

result = true;
end
