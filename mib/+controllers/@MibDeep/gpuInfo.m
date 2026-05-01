function gpuInfo(obj)
% GPUINFO - display information about the selected GPU.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.gpuInfo()
%

    selectedIndex = find(ismember(obj.view.Figure.GPUDropDown.Items, obj.view.Figure.GPUDropDown.Value));
    switch obj.view.Figure.GPUDropDown.Value
        case 'CPU only'
            msg = sprintf('Use only a single CPU for training or prediction');
        case 'Multi-GPU'
            msg = sprintf('Use multiple GPUs on one machine, using a local parallel pool based on your default cluster profile.\nIf there is no current parallel pool, the software starts a parallel pool with pool size equal to the number of available GPUs.\nThis option is only shown when multiple GPUs are present on the system');
        case 'Parallel'
            msg = sprintf('Use a local or remote parallel pool based on your default cluster profile.\nIf there is no current parallel pool, the software starts one using the default cluster profile.\nIf the pool has access to GPUs, then only workers with a unique GPU perform training computation.\nIf the pool does not have GPUs, then training takes place on all available CPU workers instead');
        otherwise
            D = gpuDevice(selectedIndex);   % choose selected GPU device
            fNames = fieldnames(D);
            msg = '';
            for fId = 1:numel(fNames)
                switch class(D.(fNames{fId}))
                    case 'datetime'
                        msg = sprintf('%s%s:\t\t%s\n', msg, fNames{fId}, D.(fNames{fId}));
                    otherwise
                        msg = sprintf('%s%s:\t\t%s\n', msg, fNames{fId}, num2str(D.(fNames{fId})));
                end
            end
    end

    obj.gpuInfoFig = uifigure('Name', 'GPU Info');
    hGrid = uigridlayout(obj.gpuInfoFig, [3, 1], 'RowHeight', {'1x', '12x', '1x'});
    hl = uilabel(hGrid, 'Text', sprintf('Properties of %s', obj.view.Figure.GPUDropDown.Value));
    h2 = uipanel(hGrid);
    h3 = uibutton(hGrid, 'push', 'Text', 'Close window', 'ButtonPushedFcn', 'closereq');

    hGridMiddle = uigridlayout(h2, [1, 1], 'RowHeight', {'1x'});
    h2b = uitextarea(hGridMiddle, 'Value', msg, ...
        'Editable', false);
end

