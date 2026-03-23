function dataset = getData3D(obj, type, time, orient, col_channel, options)
% function dataset = getData3D(obj, type, time, orient, col_channel, options)
% Get a 3D dataset from the current (or specified) dataset; wrapper around core.MibDataset.getData3D
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.getData3D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.getData3D(...).
% All argument semantics are identical to core.MibDataset.getData3D.
%
% Parameters:
% type: type of the dataset layer to retrieve
% @li 'image' - [@b default] the image layer
% @li 'labels' - labels layer with segmentation
% @li 'mask' - mask layer
% @li 'selection' - selection layer
% @li 'everything' - packed model/mask/selection (MibLabels63 only)
% time: [@em optional] time-point index; [] = current time point
% orient: [@em optional] orientation; [] = current orientation
% col_channel: [@em optional] colour channel(s); [] = current channels; NaN = all
% options: [@em optional] struct with extra parameters
% @li .id -> [@em optional] dataset index 1-9; default = obj.id
% @li .blockModeSwitch, .roiId, .fillBg, .x, .y, .z — see MibDataset.getData3D
%
% Return values:
% dataset: cell array {roiId}[height, width, depth(, colors)] — see MibDataset.getData3D

%|
% @b Examples:
% @code dataset = obj.mibModel.getData3D('image');  // current time point, shown orient @endcode
% @code dataset = obj.mibModel.getData3D('image', 5, 3, 2);  // time 5, XY orient, ch 2 @endcode
% @code dataset = obj.mibModel.getData3D('selection', [], [], NaN);  // full selection volume @endcode

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
