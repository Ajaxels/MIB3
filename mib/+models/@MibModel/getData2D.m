function dataset = getData2D(obj, type, slice_no, orient, col_channel, options)
% function dataset = getData2D(obj, type, slice_no, orient, col_channel, options)
% Get a 2D slice from the current (or specified) dataset; wrapper around core.MibDataset.getData2D
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.getData2D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.getData2D(...).
% All argument semantics are identical to core.MibDataset.getData2D.
%
% Parameters:
% type: type of the dataset layer to retrieve
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
% @li .blockModeSwitch, .roiId, .fillBg, .x, .y, .t, .level — see MibDataset.getData2D
%
% Return values:
% dataset: cell array {roiId}[height, width(, colors)] — see MibDataset.getData2D

%|
% @b Examples:
% @code slice = obj.mibModel.getData2D('image');  // current slice, current colour @endcode
% @code slice = obj.mibModel.getData2D('image', 5, 3, 2);  // slice 5, XY orient, ch 2 @endcode
% @code
% opt.blockModeSwitch = 1;
% sImage = cell2mat(obj.mibModel.getData2D('image', [], [], col_ch, opt));
% @endcode

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
