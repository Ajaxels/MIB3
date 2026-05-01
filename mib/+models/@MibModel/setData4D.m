function result = setData4D(obj, dataset, type, orient, col_channel, options)
% SETDATA4D - Set the complete 4D dataset in the current (or specified) dataset; wrapper around core.MibDataset.setData4D.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.setData4D(dataset, type, orient, col_channel, options)
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.setData4D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.setData4D(...).
% All argument semantics are identical to core.MibDataset.setData4D.
%
% Input Arguments:
%   - **dataset** — 4D image data — matrix or cell array; see ``MibDataset.setData4D``
%   - **type** — type of the dataset layer to update:
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
%     - ``.blockModeSwitch``, ``.roiId``, ``.fillBg``, ``.x``, ``.y``, ``.z``, ``.t``, ``.replaceDatasetSwitch``, ``.keepModel`` — see ``MibDataset.setData4D``
%
% Output Arguments:
%   - **result** — logical; true on success, false on failure
%
% Usage:
%   **Example 1** — replace full dataset
%
%   .. code-block:: matlab
%
%      result = obj.mibModel.setData4D(dataset, 'image');
%
%   **Example 2** — XY orient, ch 2
%
%   .. code-block:: matlab
%
%      result = obj.mibModel.setData4D(dataset, 'image', 3, 2);
%

% Updates
%

if nargin < 6; options = struct(); end
if nargin < 5; col_channel = NaN; end
if nargin < 4; orient = NaN; end
if nargin < 3; type = 'image'; end

if ~isfield(options, 'id'); options.id = obj.id; end
id = options.id;

result = obj.I{id}.setData4D(dataset, type, orient, col_channel, options);
end
