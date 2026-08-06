function dataset = getData(obj, layerType, orient, colChannel, options)
% GETDATA - Override of MibImage.getData for virtual (disk-resident) datasets.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getData(layerType, orient, colChannel, options)
%
% Dispatches to getDataZarr when a pyramid is present, otherwise to
% getDataVirt (BioFormats / HDF5 virtual stack).
%
% Only the 'image' layer is supported in virtual mode; requests for
% 'labels', 'mask', 'selection' or 'everything' return a zero-filled
% array of the appropriate size.
%
% Input Arguments:
%   - **layerType** - char, layer to retrieve - only 'image' is functional;
%     'labels', 'mask', 'selection', 'everything' return zeros
%   - **orient** - *(optional)*, can be ``[]``; default ``3`` (YX):
%
%     - ``1`` - XZ view: ``[y,x,z,c,t]`` → ``[x,z,y,c,t]``
%     - ``2`` - YZ view: ``[y,x,z,c,t]`` → ``[y,z,x,c,t]``
%     - ``3`` - YX view: ``[y,x,z,c,t]`` *(default, no permutation)*
%   - **colChannel** - [*optional,* can be []], vector of colour indices;
%     [] means all channels
%   - **options** - *(optional)*, struct with optional fields:
%
%     - ``.y``, ``.x``, ``.z``, ``.t``    - [min, max] coordinate ranges
%     - ``.level``            - pyramid level index (for zarr, default 1)
%     - ``.magFactor``        - magnification factor (for zarr, default 1)
%     - ``.showWaitbar``      - show / suppress the progress waitbar
%
% Output Arguments:
%   - **dataset** - 5D array [y, x, z, c, t] (MIB3 convention)
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     dataset = obj.getData([], [], [], struct());% full YX image
%
%   **Example 2**
%
%   .. code-block:: matlab
%
%
%     dataset = obj.getData('image', 3, 2, options);% channel 2, YX view
%

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
