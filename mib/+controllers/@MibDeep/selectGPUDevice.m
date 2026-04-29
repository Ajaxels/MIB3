function selectGPUDevice(obj)
% SELECTGPUDEVICE - select environment for computations.
%
% Syntax:
%   function selectGPUDevice(obj)
%
    selectedIndex = find(ismember(obj.view.Figure.GPUDropDown.Items, obj.view.Figure.GPUDropDown.Value));
    if ismember(obj.view.Figure.GPUDropDown.Value, {'CPU only', 'Multi-GPU', 'Parallel'})
        if numel(obj.view.Figure.GPUDropDown.Items) > 2 % i.e. GPU is present
            gpuDevice([]);  % CPU only mode
        end
    else
        g = gpuDevice(selectedIndex);   % choose selected GPU device
        reset(g);
    end
end

