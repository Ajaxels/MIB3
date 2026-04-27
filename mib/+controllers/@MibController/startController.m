function startController(obj, controllerName, varargin)
% function startController(obj, controllerName, varargin)
% launch a child controller by class name
%
% Delegates to utils.startController, which provides the full implementation.
% Use utils.startController directly when calling from a plugin controller
% that has no access to MibController.
%
% Behaviour:
% @li If the child window is already open, it is brought to the front and
%     its widgets are refreshed.
% @li If a BatchOpt struct is supplied (varargin{2}), the child runs in
%     batch mode (no GUI) and returns immediately.
% @li Lifecycle is managed automatically: a CloseEvent listener is wired
%     on the child and calls utils.purgeChildController on close.
%
% Parameters:
% controllerName: char — fully-qualified child controller class name,
%                 e.g. @b 'controllers.ResampleDataset'
% varargin{1}:   [@em optional] placeholder argument, pass @b [] when supplying BatchOpt
% varargin{2}:   [@em optional] BatchOpt struct to run in batch mode, or
%                @b NaN to trigger returnBatchOpt

%|
% @b Examples:
% @code
% % Open a child controller GUI (interactive):
% obj.startController('controllers.ResampleDataset');
% @endcode
% @code
% % Run a child controller in batch mode (no GUI):
% BatchOpt.ResamplingMode = {'Dimensions'};
% BatchOpt.DimensionX = '256';
% BatchOpt.DimensionY = '256';
% obj.startController('controllers.ResampleDataset', [], BatchOpt);
% @endcode
% @code
% % Same call from a plugin controller that has no MibController handle:
% utils.startController(obj, 'controllers.ResampleDataset', [], BatchOpt);
% @endcode

% Updates
%

utils.startController(obj, controllerName, varargin{:});

end