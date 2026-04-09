function lgraph = updateActivationLayers(obj, lgraph)
% function lgraph = updateActivationLayers(obj, lgraph)
% update the activation layers depending on settings in
% obj.BatchOpt.T_ActivationLayer and obj.ActivationLayerOpt

% redefine the activation layers
if ~strcmp(obj.BatchOpt.T_ActivationLayer{1}, 'reluLayer')
    ReLUIndices = zeros([numel(lgraph.Layers), 1]);
    % find indices of ReLU layers
    for layerId = 1:numel(lgraph.Layers)
        if isa(lgraph.Layers(layerId), 'nnet.cnn.layer.ReLULayer')
            ReLUIndices(layerId) = 1;
        end
    end
    ReLUIndices = find(ReLUIndices);

    for id=1:numel(ReLUIndices)
        layerId = ReLUIndices(id);
        switch obj.BatchOpt.T_ActivationLayer{1}
            case 'leakyReluLayer'
                layer = leakyReluLayer(obj.ActivationLayerOpt.leakyReluLayer.Scale, 'Name', sprintf('leakyReLU-%d', id));
            case 'clippedReluLayer'
                layer = clippedReluLayer(obj.ActivationLayerOpt.clippedReluLayer.Ceiling, 'Name', sprintf('clippedReLU-%d', id));
            case 'eluLayer'
                layer = eluLayer(obj.ActivationLayerOpt.eluLayer.Alpha, 'Name', sprintf('ELU-%d', id));
            case 'swishLayer'
                layer = swishLayer('Name', sprintf('Swish-%d', id));
            case 'tanhLayer'
                layer = tanhLayer('Name', sprintf('Tahn-%d', id));
                %case 'reluLayer'
                %    layer = reluLayer('Name', sprintf('ReLU-%d', id));
        end
        lgraph = replaceLayer(lgraph, lgraph.Layers(layerId).Name, layer);
    end
end
end

