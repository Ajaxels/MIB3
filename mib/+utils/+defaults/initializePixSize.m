function pixSize = initializePixSize(~)
% INITIALIZEPIXSIZE - Initialize the pixSize structure with default voxel dimensions.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      pixSize = initializePixSize()
%
% Physical units default to micrometres; temporal units to seconds.
%
% Output Arguments:
%   - **pixSize** — struct with default voxel dimensions:
%
%     - ``.x``      — [numeric] pixel width (default: ``1``)
%     - ``.y``      — [numeric] pixel height (default: ``1``)
%     - ``.z``      — [numeric] slice thickness (default: ``1``)
%     - ``.units``  — [char] physical units (default: ``'um'``)
%     - ``.t``      — [numeric] time between frames (default: ``1``)
%     - ``.tunits`` — [char] time units (default: ``'s'``)
%
% Usage:
%
%   **Example 1** — create and customise a pixSize struct
%
%   .. code-block:: matlab
%
%      pixSize = utils.defaults.initializePixSize();
%      pixSize.x = 0.065;
%      pixSize.units = 'um';
%

pixSize.x = 1;
pixSize.y = 1;
pixSize.z = 1;
pixSize.units = 'um';
pixSize.t = 1;
pixSize.tunits = 's';
end
