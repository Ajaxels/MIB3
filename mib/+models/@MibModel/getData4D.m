function dataset = getData4D(obj, type, orient, col_channel, options)
% GETDATA4D - Get the complete 4D dataset from the current (or specified) dataset; wrapper around core.MibDataset.getData4D.
%
% Syntax:
%   function dataset = getData4D(obj, type, orient, col_channel, options)
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.getData4D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.getData4D(...).
% All argument semantics are identical to core.MibDataset.getData4D.
%
% Input Arguments:
%   - **type** — type of the dataset layer to retrieve:
%
%     - ``'image'`` — [*default*] the image layer
%     - ``'labels'`` — labels layer with segmentation
%     - ``'mask'`` — mask layer
%     - ``'selection'`` — selection layer
%     - ``'everything'`` — packed model/mask/selection (MibLabels63 only)
%
%   - **orient** — *(optional)* orientation; ``[]`` = current orientation
%   - **col_channel** — *(optional)* colour channel(s); ``[]`` = current channels; ``NaN`` = all
%   - **options** — *(optional)* struct with extra parameters:
%
%     - ``.id`` — *(optional)* dataset index 1-9; default = ``obj.id``
%     - ``.blockModeSwitch``, ``.roiId``, ``.fillBg``, ``.x``, ``.y``, ``.z``, ``.t`` — see ``MibDataset.getData4D``
%
% Output Arguments:
%   - **dataset** — cell array {roiId}[height, width, depth, colors, time] or
%     {roiId}[height, width, depth, time] — see MibDataset.getData4D
%
% Usage:
%   **Example 1** — full dataset in shown orientation
%
%   .. code-block:: matlab
%
%      dataset = obj.mibModel.getData4D('image');
%
%   **Example 2** — XY orient, ch 2
%
%   .. code-block:: matlab
%
%      dataset = obj.mibModel.getData4D('image', 3, 2);
%

% Updates
%

if nargin < 5; options = struct(); end
if nargin < 4; col_channel = []; end
if nargin < 3; orient = []; end
if nargin < 2; type = 'image'; end

if ~isfield(options, 'id'); options.id = obj.id; end
id = options.id;

dataset = obj.I{id}.getData4D(type, orient, col_channel, options);
end
