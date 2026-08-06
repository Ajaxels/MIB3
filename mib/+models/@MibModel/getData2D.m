function dataset = getData2D(obj, type, slice_no, orient, col_channel, options)
% GETDATA2D - Get a 2D slice from the current (or specified) dataset; wrapper around core.MibDataset.getData2D.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getData2D(type, slice_no, orient, col_channel, options)
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.getData2D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.getData2D(...).
% All argument semantics are identical to core.MibDataset.getData2D.
%
% Input Arguments:
%   - **type** - type of the dataset layer to retrieve:
%
%     - ``'image'`` - [*default*] the image layer
%     - ``'labels'`` - labels layer with segmentation
%     - ``'mask'`` - mask layer
%     - ``'selection'`` - selection layer
%     - ``'everything'`` - packed model/mask/selection (MibLabels63 only)
%
%   - **slice_no** - *(optional)* slice index; ``[]`` = current slice
%   - **orient** - *(optional)* orientation; ``[]`` = current orientation
%   - **col_channel** - *(optional)* colour channel(s); ``[]`` = current channels; ``NaN`` = all
%   - **options** - *(optional)* struct with extra parameters:
%
%     - ``.id`` - *(optional)* dataset index 1-9; default = ``obj.id``
%     - ``.blockModeSwitch``, ``.roiId``, ``.fillBg``, ``.x``, ``.y``, ``.t``, ``.level`` - see ``MibDataset.getData2D``
%
% Output Arguments:
%   - **dataset** - cell array {roiId}[height, width(, colors)] - see MibDataset.getData2D
%
% Usage:
%   **Example 1** - current slice, current colour
%
%   .. code-block:: matlab
%
%      slice = obj.mibModel.getData2D('image');
%
%   **Example 2** - slice 5, XY orient, ch 2
%
%   .. code-block:: matlab
%
%      slice = obj.mibModel.getData2D('image', 5, 3, 2);
%
%   **Example 3** - use blockModeSwitch to get the visible area only
%
%   .. code-block:: matlab
%
%      opt.blockModeSwitch = 1;
%      sImage = cell2mat(obj.mibModel.getData2D('image', [], [], col_ch, opt));
%

% Updates
%

if nargin < 6; options = struct(); end
if nargin < 5; col_channel = []; end
if nargin < 4; orient = []; end
if nargin < 3; slice_no = []; end
if nargin < 2; type = 'image'; end

if ~isfield(options, 'id'); options.id = obj.id; end
id = options.id;

dataset = obj.I{id}.getData2D(type, slice_no, orient, col_channel, options);
end
