function dataset = getData4D(obj, type, orient, col_channel, options)
% function dataset = getData4D(obj, type, orient, col_channel, options)
% Get the complete 4D dataset from the current (or specified) dataset; wrapper around core.MibDataset.getData4D
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.getData4D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.getData4D(...).
% All argument semantics are identical to core.MibDataset.getData4D.
%
% Parameters:
% type: type of the dataset layer to retrieve
% @li 'image' - [@b default] the image layer
% @li 'labels' - labels layer with segmentation
% @li 'mask' - mask layer
% @li 'selection' - selection layer
% @li 'everything' - packed model/mask/selection (MibLabels63 only)
% orient: [@em optional] orientation; [] = current orientation
% col_channel: [@em optional] colour channel(s); [] = current channels; NaN = all
% options: [@em optional] struct with extra parameters
% @li .id -> [@em optional] dataset index 1-9; default = obj.id
% @li .blockModeSwitch, .roiId, .fillBg, .x, .y, .z, .t — see MibDataset.getData4D
%
% Return values:
% dataset: cell array {roiId}[height, width, depth, colors, time] or
%          {roiId}[height, width, depth, time] — see MibDataset.getData4D

%|
% @b Examples:
% @code dataset = obj.mibModel.getData4D('image');  // full dataset in shown orientation @endcode
% @code dataset = obj.mibModel.getData4D('image', 3, 2);  // XY orient, ch 2 @endcode

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
