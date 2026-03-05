function dataset = getData(obj, layerType, orient, colChannel, options)
% function dataset = getData(obj, layerType, orient, colChannel, options)
% Override of MibImage.getData for virtual (disk-resident) datasets.
%
% Dispatches to getDataZarr when a pyramid is present, otherwise to
% getDataVirt (BioFormats / HDF5 virtual stack).
%
% Only the 'image' layer is supported in virtual mode; requests for
% 'labels', 'mask', 'selection' or 'everything' return a zero-filled
% array of the appropriate size.
%
% Parameters:
% layerType: char, layer to retrieve — only 'image' is functional;
%            'labels', 'mask', 'selection', 'everything' return zeros
% orient: [@em optional, can be [], default = 3 (YX)]
%   @li 1 — xz view: [y,x,z,c,t] -> [x,z,y,c,t]
%   @li 2 — yz view: [y,x,z,c,t] -> [y,z,x,c,t]
%   @li 3 — yx view: [y,x,z,c,t]  (default, no permutation)
% colChannel: [@em optional, can be []], vector of colour indices;
%             [] means all channels
% options: [@em optional], struct with optional fields:
%   @li .y, .x, .z, .t    — [min, max] coordinate ranges
%   @li .level            — pyramid level index (for zarr, default 1)
%   @li .magFactor        — magnification factor (for zarr, default 1)
%   @li .showWaitbar      — show / suppress the progress waitbar
%
% Return values:
% dataset: 5D array [y, x, z, c, t] (MIB3 convention)
%|
% @b Examples:
% @code dataset = obj.getData([], [], [], struct());     // full YX image @endcode
% @code dataset = obj.getData('image', 3, 2, options);  // channel 2, YX view @endcode

%% Updates
%
if nargin < 5; options = struct(); end
if nargin < 4; colChannel = []; end
if nargin < 3; orient = []; end
if nargin < 2; layerType = 'image'; end

if isempty(orient); orient = 3; end

% only 'image' is readable from a virtual dataset
if ~strcmp(layerType, 'image')
    % return appropriately-sized zeros for unsupported layers
    dataset = zeros([obj.height, obj.width, obj.depth, 1, obj.time], 'uint8');
    return;
end

% dispatch to the appropriate reader
if ~isempty(obj.pyramid.levelNames)
    dataset = obj.getDataZarr(layerType, orient, colChannel, options);
else
    dataset = obj.getDataVirt(layerType, orient, colChannel, options);
end
end
