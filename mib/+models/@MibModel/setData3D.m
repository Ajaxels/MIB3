function result = setData3D(obj, dataset, type, time, orient, col_channel, options)
% function result = setData3D(obj, dataset, type, time, orient, col_channel, options)
% Set a 3D dataset in the current (or specified) dataset; wrapper around core.MibDataset.setData3D
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.setData3D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.setData3D(...).
% All argument semantics are identical to core.MibDataset.setData3D.
%
% Parameters:
% dataset: 3D image data — matrix or cell array; see MibDataset.setData3D
% type: type of the dataset layer to update
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
% @li .blockModeSwitch, .roiId, .fillBg, .x, .y, .z, .PixelIdxList — see MibDataset.setData3D
%
% Return values:
% result: logical; true on success, false on failure

%|
% @b Examples:
% @code result = obj.mibModel.setData3D(volume, 'selection');  // update full selection volume @endcode
% @code result = obj.mibModel.setData3D(volume, 'image', 5, 3);  // time 5, XY orient @endcode
% @code
% opt.PixelIdxList = pixelIndices;
% result = obj.mibModel.setData3D(values, 'selection', [], [], NaN, opt);  // fast pixel-list update
% @endcode

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
