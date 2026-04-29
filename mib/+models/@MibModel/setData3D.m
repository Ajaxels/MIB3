function result = setData3D(obj, dataset, type, time, orient, col_channel, options)
% SETDATA3D - Set a 3D dataset in the current (or specified) dataset; wrapper around core.MibDataset.setData3D.
%
% Syntax:
%   function result = setData3D(obj, dataset, type, time, orient, col_channel, options)
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.setData3D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.setData3D(...).
% All argument semantics are identical to core.MibDataset.setData3D.
%
% Input Arguments:
%   - **dataset** — 3D image data — matrix or cell array; see ``MibDataset.setData3D``
%   - **type** — type of the dataset layer to update:
%
%     - ``'image'`` — [*default*] the image layer
%     - ``'labels'`` — labels layer with segmentation
%     - ``'mask'`` — mask layer
%     - ``'selection'`` — selection layer
%     - ``'everything'`` — packed model/mask/selection (MibLabels63 only)
%
%   - **time** — *(optional)* time-point index; ``[]`` = current time point
%   - **orient** — *(optional)* orientation; ``[]`` = current orientation
%   - **col_channel** — *(optional)* colour channel(s); ``[]`` = current channels; ``NaN`` = all
%   - **options** — *(optional)* struct with extra parameters:
%
%     - ``.id`` — *(optional)* dataset index 1-9; default = ``obj.id``
%     - ``.blockModeSwitch``, ``.roiId``, ``.fillBg``, ``.x``, ``.y``, ``.z``, ``.PixelIdxList`` — see ``MibDataset.setData3D``
%
% Output Arguments:
%   - **result** — logical; true on success, false on failure
%
% Usage:
%   **Example 1** — update full selection volume
%
%   .. code-block:: matlab
%
%      result = obj.mibModel.setData3D(volume, 'selection');
%
%   **Example 2** — time 5, XY orient
%
%   .. code-block:: matlab
%
%      result = obj.mibModel.setData3D(volume, 'image', 5, 3);
%
%   **Example 3** — fast pixel-list update
%
%   .. code-block:: matlab
%
%      opt.PixelIdxList = pixelIndices;
%      result = obj.mibModel.setData3D(values, 'selection', [], [], NaN, opt);
%

% Updates
%

if nargin < 7; options = struct(); end
if nargin < 6; col_channel = []; end
if nargin < 5; orient = []; end
if nargin < 4; time = []; end
if nargin < 3; type = 'image'; end

if ~isfield(options, 'id'); options.id = obj.id; end
id = options.id;

result = obj.I{id}.setData3D(dataset, type, time, orient, col_channel, options);
end
