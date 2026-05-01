function newModeOut = switchDatasetMode(obj, newMode, enableSelection, initWithImage)
% SWITCHDATASETMODE - Function to switch between loading datasets to different modes, defined.
%
% Syntax:
%   .. code-block:: matlab
%
%       newModeOut = obj.switchDatasetMode(newMode, enableSelection, initWithImage)
%
% in bj.handles.panels.activeDataset.handles.datasetType as 'Standard', 'Virtual', 'BigData'
%
% Input Arguments:
%   - **newMode** — *(optional)* target dataset mode:
%
%     - ``0`` — memory-resident mode (Standard), images loaded to memory
%     - ``1`` — HDD-resident mode (Virtual), images kept on hard drive
%     - ``2`` — BigData mode, images loaded on demand
%
%   - **enableSelection** — *(optional)* logical switch to enable/disable the selection layer;
%     set based on ``mibModel.preferences.System.EnableSelection``
%   - **initWithImage** — *(optional)* initialise the class with a provided image:
%
%     - for ``'Standard'``: numeric matrix (preloaded image data)
%     - for ``'Virtual'``: cell array with full path(s) to the dataset
%
% Output Arguments:
%   - **newModeOut** — result of the function:
%
%     - ``[]`` — nothing was changed
%     - ``0`` — switched to the memory-resident (Standard) mode
%     - ``1`` — switched to the virtual stacking mode
%     - ``2`` — switched to the BigData mode
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     result = obj.mibModel.I{obj.mibModel.Id}.switchDatasetMode(1, obj.mibModel.preferences.System.EnableSelection);% enable the virtual stacking mode
%

% Updates
%

newModeOut = [];

if nargin < 3; initWithImage = []; end
if nargin < 3; enableSelection = []; end

if isempty(newMode); return; end

% set the virtual mode switch
switch newMode
    case 1 % new dataset type is 'Standard'
        if obj.datasetType(1) == 'V' % current mode is Virtual
            obj.closeVirtualDataset();    % close the virtual datasets
            obj.image.pyramid.levelNames = {};  % clear level names for zarr pyramid
        end
        datasetType = 'Standard';
    case 2 % new dataset type is 'Virtual'
        datasetType = 'Virtual';
        enableSelection = false; % disable segmentation
    case 3 % new dataset type is 'BigData'
        datasetType = 'BigData';
end

% initialize
obj.initialize(initWithImage, [], datasetType, [], enableSelection);

% update the output variable
newModeOut = newMode;

end
