function dataset = getData3D(obj, type, time, orient, col_channel, options)
% GETDATA3D - Get a 3D dataset from the current (or specified) dataset; wrapper around core.MibDataset.getData3D.
%
% Syntax:
%   .. code-block:: matlab
%
%       dataset = obj.getData3D(type, time, orient, col_channel, options)
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.getData3D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.getData3D(...).
% All argument semantics are identical to core.MibDataset.getData3D.
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
%   - **time** - *(optional)* time-point index; ``[]`` = current time point
%   - **orient** - *(optional)* orientation; ``[]`` = current orientation
%   - **col_channel** - *(optional)* colour channel(s); ``[]`` = current channels; ``NaN`` = all
%   - **options** - *(optional)* struct with extra parameters:
%
%     - ``.id`` - *(optional)* dataset index 1-9; default = ``obj.id``
%     - ``.blockModeSwitch``, ``.roiId``, ``.fillBg``, ``.x``, ``.y``, ``.z`` - see ``MibDataset.getData3D``
%
% Output Arguments:
%   - **dataset** - cell array {roiId}[height, width, depth(, colors)] - see MibDataset.getData3D
%
% Usage:
%   **Example 1** - current time point, shown orientation
%
%   .. code-block:: matlab
%
%      dataset = obj.mibModel.getData3D('image');
%
%   **Example 2** - time 5, XY orient, ch 2
%
%   .. code-block:: matlab
%
%      dataset = obj.mibModel.getData3D('image', 5, 3, 2);
%
%   **Example 3** - full selection volume (all colour channels)
%
%   .. code-block:: matlab
%
%      dataset = obj.mibModel.getData3D('selection', [], [], NaN);
%

% Updates
%

if nargin < 6; options = struct(); end
if nargin < 5; col_channel = []; end
if nargin < 4; orient = []; end
if nargin < 3; time = []; end
if nargin < 2; type = 'image'; end

if ~isfield(options, 'id'); options.id = obj.id; end
id = options.id;

dataset = obj.I{id}.getData3D(type, time, orient, col_channel, options);
end
