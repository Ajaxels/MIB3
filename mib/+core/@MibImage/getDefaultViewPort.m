function viewPort = getDefaultViewPort(obj)
% GETDEFAULTVIEWPORT - get default view port for stretching the image for visualization.
%
% Syntax:
%   function viewPort = getDefaultViewPort(obj)
%

viewPort = struct();
viewPort.min = zeros([obj.colors, 1]);
viewPort.max = zeros([obj.colors, 1]) + obj.maxInt;
viewPort.gamma = zeros([obj.colors, 1]) + 1;
if strcmp(obj.dataClass, 'uint32')
    viewPort.min = zeros([obj.colors, 1]) + double(min(min(min(obj.data{1}(:,:,1,:,1)))));
    viewPort.max = zeros([obj.colors, 1]) + double(max(max(max(obj.data{1}(:,:,1,:,1)))));
end

% update the view port for the class
obj.viewPort = viewPort;

end
