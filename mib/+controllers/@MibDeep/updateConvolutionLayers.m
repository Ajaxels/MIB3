function lgraph = updateConvolutionLayers(obj, lgraph)
    % update the convolution layers by providing new set of weight
    % initializers

    weightsInitializer = 'glorot';
    % redefine the activation layers
    if ~strcmp(weightsInitializer, 'he')
        convIndices = zeros([numel(lgraph.Layers), 1]);
        % find indices of ReLU layers
        for layerId = 1:numel(lgraph.Layers)
            if isa(lgraph.Layers(layerId), 'nnet.cnn.layer.Convolution2DLayer')
                convIndices(layerId) = 1;
            end
        end
        convIndices = find(convIndices);

        for id=1:numel(convIndices)
            layerId = convIndices(id);
            if strcmp(lgraph.Layers(layerId).PaddingMode, 'same')
                layer = convolution2dLayer(lgraph.Layers(layerId).FilterSize, lgraph.Layers(layerId).NumFilters, ...
                    'Padding', 'same', ...
                    'Stride', lgraph.Layers(layerId).Stride, ...
                    'DilationFactor', lgraph.Layers(layerId).DilationFactor, ...
                    'NumChannels', lgraph.Layers(layerId).NumChannels, ...
                    'WeightsInitializer', weightsInitializer);
            else
                layer = convolution2dLayer(lgraph.Layers(layerId).FilterSize, lgraph.Layers(layerId).NumFilters, ...
                    'Stride', lgraph.Layers(layerId).Stride, ...
                    'DilationFactor', lgraph.Layers(layerId).DilationFactor, ...
                    'Padding', lgraph.Layers(layerId).PaddingSize, ...
                    'PaddingValue', lgraph.Layers(layerId).PaddingValue, ...
                    'NumChannels', lgraph.Layers(layerId).NumChannels, ...
                    'WeightsInitializer', weightsInitializer);
            end

            lgraph = replaceLayer(lgraph, lgraph.Layers(layerId).Name, layer);
        end
    end
end

