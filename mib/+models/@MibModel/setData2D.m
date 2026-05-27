function result = setData2D(obj, dataset, type, slice_no, orient, col_channel, options)
% SETDATA2D - Set a 2D slice in the current (or specified) dataset; wrapper around core.MibDataset.setData2D.
%
% Syntax:
%   .. code-block:: matlab
%
%       result = obj.setData2D(dataset, type, slice_no, orient, col_channel, options)
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.setData2D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.setData2D(...).
% All argument semantics are identical to core.MibDataset.setData2D.
%
% Input Arguments:
%   - **dataset** — 2D image data — matrix or cell array; see ``MibDataset.setData2D``
%   - **type** — type of the dataset layer to update:
%
%     - ``'image'`` — [*default*] the image layer
%     - ``'labels'`` — labels layer with segmentation
%     - ``'mask'`` — mask layer
%     - ``'selection'`` — selection layer
%     - ``'everything'`` — packed model/mask/selection (MibLabels63 only)
%
%   - **slice_no** — *(optional)* slice index; ``[]`` = current slice
%   - **orient** — *(optional)* orientation; ``[]`` = current orientation
%   - **col_channel** — *(optional)* colour channel(s); ``[]`` = current channels; ``NaN`` = all
%   - **options** — *(optional)* struct with extra parameters:
%
%     - ``.id`` — *(optional)* dataset index 1-9; default = ``obj.id``
%     - ``.blockModeSwitch``, ``.roiId``, ``.fillBg``, ``.x``, ``.y``, ``.t`` — see ``MibDataset.setData2D``
%
% Output Arguments:
%   - **result** — logical; true on success, false on failure
%
% Usage:
%   **Example 1** — update selection on current slice
%
%   .. code-block:: matlab
%
%      result = obj.mibModel.setData2D(slice, 'selection');
%
%   **Example 2** — slice 5, XY orient, ch 2
%
%   .. code-block:: matlab
%
%      result = obj.mibModel.setData2D(slice, 'image', 5, 3, 2);
%

% Updates
%

if nargin < 7; options = struct(); end
if nargin < 6; col_channel = []; end
if nargin < 5; orient = []; end
if nargin < 4; slice_no = []; end
if nargin < 3; type = 'image'; end

if ~isfield(options, 'id'); options.id = obj.id; end
id = options.id;

result = obj.I{id}.setData2D(dataset, type, slice_no, orient, col_channel, options);

% notify MibModel that slice was added, used in Graphcut, moved to moveLayers function
% setDataOpt.type = type;
% setDataOpt.mode = '2D';
% eventdata = core.ToggleEventData(setDataOpt);
% notify(obj, 'SetData', eventdata);

end
