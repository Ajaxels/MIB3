function result = setData4D(obj, dataset, type, orient, col_channel, options)
% function result = setData4D(obj, dataset, type, orient, col_channel, options)
% Set the complete 4D dataset in the current (or specified) dataset; wrapper around core.MibDataset.setData4D
%
% This is a thin convenience wrapper so controllers can call
% obj.mibModel.setData4D(...) instead of
% obj.mibModel.I{obj.mibModel.id}.setData4D(...).
% All argument semantics are identical to core.MibDataset.setData4D.
%
% Parameters:
% dataset: 4D image data — matrix or cell array; see MibDataset.setData4D
% type: type of the dataset layer to update
% @li 'image' - [@b default] the image layer
% @li 'labels' - labels layer with segmentation
% @li 'mask' - mask layer
% @li 'selection' - selection layer
% @li 'everything' - packed model/mask/selection (MibLabels63 only)
% orient: [@em optional] orientation; [] = current orientation
% col_channel: [@em optional] colour channel(s); [] = current channels; NaN = all
% options: [@em optional] struct with extra parameters
% @li .id -> [@em optional] dataset index 1-9; default = obj.id
% @li .blockModeSwitch, .roiId, .fillBg, .x, .y, .z, .t,
%     .replaceDatasetSwitch, .keepModel — see MibDataset.setData4D
%
% Return values:
% result: logical; true on success, false on failure

%|
% @b Examples:
% @code result = obj.mibModel.setData4D(dataset, 'image');  // replace full dataset @endcode
% @code result = obj.mibModel.setData4D(dataset, 'image', 3, 2);  // XY orient, ch 2 @endcode

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
