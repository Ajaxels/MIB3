function newModeOut = switchDatasetMode(obj, newMode, enableSelection, initWithImage)
% function newMode = switchDatasetMode(obj, newMode, enableSelection, initWithImage)
% Function to switch between loading datasets to different modes, defined
% in bj.handles.panels.activeDataset.handles.datasetType as 'Standard', 'Virtual', 'BigData'
%
% Parameters:
% newMode: [@em optional],
%    @li when @b 0 - uses the memory-resident mode, i.e. when the images loaded to memory
%    @li when @b 1 - uses the HDD-resident mode (virtual stacking), i.e. when the images kept on a hard drive
%    @li when @b 2 - uses the BigData mode, the images are loaded on demand
% enableSelection: [@em optional] a switch to set enableSelection based on mibModel.preferences.System.EnableSelection
% initWithImage: [@em optional] init the class with this provided image,
%   @li for "Standard", [numeric matrix] it should be preloaded loaded image,
%   @li for 'Virtual', [cell array]it is a full path to the dataset
%
% Return values:
% newModeOut: result of the function,
% @li [] - nothing was changed
% @li 0 - switched to the memory-resident mode
% @li 1 - switched to the virtual stacking mode
% @li 2 - switched to the BigData mode

%|
% @b Examples:
% @code result = obj.mibModel.I{obj.mibModel.Id}.switchDatasetMode(1, obj.mibModel.preferences.System.EnableSelection);  // enable the virtual stacking mode @endcode

% Updates
%

newModeOut = [];

if nargin < 3; initWithImage = []; end
if nargin < 3; enableSelection = []; end

if isempty(newMode); return; end

% set the virtual mode switch
switch newMode
    case 1 % new dataset type is 'Standard'
        if ~isempty(enableSelection); obj.enableSelection = enableSelection; end
        if obj.datasetType(1) == 'V' % current mode is Virtual
            obj.closeVirtualDataset();    % close the virtual datasets
            obj.image.pyramid.levelNames = {};  % clear level names for zarr pyramid
        end
        datasetType = 'Standard';
    case 2 % new dataset type is 'Virtual'
        datasetType = 'Virtual';
        obj.enableSelection = false; % disable segmentation
    case 3 % new dataset type is 'BigData'
        datasetType = 'BigData';
end

% initialize
obj.initialize(initWithImage, [], datasetType);

% update the output variable
newModeOut = newMode;

end