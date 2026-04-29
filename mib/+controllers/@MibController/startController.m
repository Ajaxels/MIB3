function startController(obj, controllerName, varargin)
% STARTCONTROLLER - launch a child controller by class name.
%
% Syntax:
%   function startController(obj, controllerName, varargin)
%
% Delegates to utils.startController, which provides the full implementation.
% Use utils.startController directly when calling from a plugin controller
% that has no access to MibController.
%
% Behaviour:
%   - If the child window is already open, it is brought to the front and
% its widgets are refreshed.
%   - If a BatchOpt struct is supplied (varargin{2}), the child runs in
% batch mode (no GUI) and returns immediately.
%   - Lifecycle is managed automatically: a CloseEvent listener is wired
% on the child and calls utils.purgeChildController on close.
%
% Input Arguments:
%   - **controllerName** — char — fully-qualified child controller class name,
%     e.g. **'controllers.ResampleDataset'**
%   - **varargin{1}** — *(optional)* placeholder argument, pass **[]** when supplying BatchOpt
%   - **varargin{2}** — *(optional)* BatchOpt struct to run in batch mode, or
%     **NaN** to trigger returnBatchOpt
%
% Usage:
%   Example 1 - Open a child controller GUI (interactive)::
%
%     % Open a child controller GUI (interactive):
%     obj.startController('controllers.ResampleDataset');
%
%   Example 2 - Run a child controller in batch mode (no GUI)::
%
%     % Run a child controller in batch mode (no GUI):
%     BatchOpt.ResamplingMode = {'Dimensions'};
%     BatchOpt.DimensionX = '256';
%     BatchOpt.DimensionY = '256';
%     obj.startController('controllers.ResampleDataset', [], BatchOpt);
%
%   Example 3 - Same call from a plugin controller that has no MibController handle::
%
%     % Same call from a plugin controller that has no MibController handle:
%     utils.startController(obj, 'controllers.ResampleDataset', [], BatchOpt);
%

% Updates
%

utils.startController(obj, controllerName, varargin{:});

end
