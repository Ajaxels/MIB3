function viewPort = getDefaultViewPort(obj)
% GETDEFAULTVIEWPORT - Get default viewport for image intensity stretching and visualization.
%
% Syntax:
%   .. code-block:: matlab
%
%      viewPort = obj.getDefaultViewPort()
%
% Returns a viewport structure with default intensity stretching parameters for each color channel.
% For standard data types, min/max are initialized to ``0`` and ``obj.maxInt``.
% For ``uint32`` images, actual data min/max are computed from the first slice.
%
% Input Arguments:
%   (none)
%
% Output Arguments:
%   - **viewPort** — [struct] viewport with fields:
%
%     - ``.min`` — [numeric] minimum intensity value per channel ``[colors × 1]``
%     - ``.max`` — [numeric] maximum intensity value per channel ``[colors × 1]``
%     - ``.gamma`` — [numeric] gamma correction factor per channel ``[colors × 1]`` (default: ``1.0``)
%
% **Example** — Get and display default viewport:
%
%   .. code-block:: matlab
%
%      vp = img.getDefaultViewPort();
%      disp(vp.min);    % minimum intensity per channel
%      disp(vp.max);    % maximum intensity per channel
%      disp(vp.gamma);  % gamma factors per channel
%

viewPort = struct();
viewPort.min = zeros([obj.colors, 1]);
viewPort.max = zeros([obj.colors, 1]) + obj.maxInt;
viewPort.gamma = zeros([obj.colors, 1]) + 1;
if strcmp(obj.dataClass, 'uint32')
    viewPort.min = zeros([obj.colors, 1]) + double(min(min(min(obj.data(:,:,1,:,1)))));
    viewPort.max = zeros([obj.colors, 1]) + double(max(max(max(obj.data(:,:,1,:,1)))));
end

% update the view port for the class
obj.viewPort = viewPort;

end
