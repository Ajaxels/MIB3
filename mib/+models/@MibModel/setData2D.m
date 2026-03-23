function result = setData2D(obj, dataset, type, slice_no, orient, col_channel, options)
% function result = setData2D(obj, dataset, type, slice_no, orient, col_channel, options)
% Set a 2D slice in the current (or specified) dataset; wrapper around core.MibDataset.setData2D
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.setData2D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.setData2D(...).
% All argument semantics are identical to core.MibDataset.setData2D.
%
% Parameters:
% dataset: 2D image data — matrix or cell array; see MibDataset.setData2D
% type: type of the dataset layer to update
% @li 'image' - [@b default] the image layer
% @li 'labels' - labels layer with segmentation
% @li 'mask' - mask layer
% @li 'selection' - selection layer
% @li 'everything' - packed model/mask/selection (MibLabels63 only)
% slice_no: [@em optional] slice index; [] = current slice
% orient: [@em optional] orientation; [] = current orientation
% col_channel: [@em optional] colour channel(s); [] = current channels; NaN = all
% options: [@em optional] struct with extra parameters
% @li .id -> [@em optional] dataset index 1-9; default = obj.id
% @li .blockModeSwitch, .roiId, .fillBg, .x, .y, .t — see MibDataset.setData2D
%
% Return values:
% result: logical; true on success, false on failure

%|
% @b Examples:
% @code result = obj.mibModel.setData2D(slice, 'selection');  // update selection on current slice @endcode
% @code result = obj.mibModel.setData2D(slice, 'image', 5, 3, 2);  // slice 5, XY orient, ch 2 @endcode

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
end
