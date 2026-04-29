function lgraph = updateMaxPoolAndTransConvLayers(obj, lgraph, poolSize)
% UPDATEMAXPOOLANDTRANSCONVLAYERS - update maxPool and TransposedConvolution layers depending.
%
% Syntax:
%   function lgraph = updateMaxPoolAndTransConvLayers(obj, lgraph, poolSize)
%
% on network downsampling factor only for U-net and SegNet.
% This function is applied when the network downsampling factor
% is different from 2

    if nargin < 3
        % downsampling factor
        poolSize = obj.view.handles.T_DownsamplingFactor.Value;
    end

    if poolSize ~= 2 && ismember(obj.BatchOpt.Architecture{1}, {'U-net', 'SegNet', 'Z2C + U-net'})
        maxPoolIndices = zeros([numel(lgraph.Layers), 1]);
        transConvIndices = zeros([numel(lgraph.Layers), 1]);
        % find indices of ReLU layers
        for layerId = 1:numel(lgraph.Layers)
            if isa(lgraph.Layers(layerId), 'nnet.cnn.layer.MaxPooling2DLayer') || isa(lgraph.Layers(layerId), 'nnet.cnn.layer.MaxPooling3DLayer')
                maxPoolIndices(layerId) = 1;
            end
            if isa(lgraph.Layers(layerId), 'nnet.cnn.layer.TransposedConvolution2DLayer') || isa(lgraph.Layers(layerId), 'nnet.cnn.layer.TransposedConvolution3DLayer')
                transConvIndices(layerId) = 1;
            end
        end
        maxPoolIndices = find(maxPoolIndices);
        transConvIndices = find(transConvIndices);

        for id=1:numel(maxPoolIndices)
            layerId = maxPoolIndices(id);
            switch obj.BatchOpt.Architecture{1}
                case {'U-net', 'Z2C + U-net'}
                    if strcmp(obj.BatchOpt.Workflow{1}(1:2), '2D') || strcmp(obj.BatchOpt.Workflow{1}(1:2), '2.')
                        layer = maxPooling2dLayer([poolSize, poolSize], 'Stride', [poolSize poolSize], ...
                            'Name', lgraph.Layers(layerId).Name);
                    else
                        layer = maxPooling3dLayer([poolSize, poolSize, poolSize], 'Stride', [poolSize poolSize, poolSize], ...
                            'Name', lgraph.Layers(layerId).Name);
                    end
                case 'SegNet'
                    layer = maxPooling2dLayer([poolSize, poolSize], 'Stride', [poolSize poolSize], ...
                        'Name', lgraph.Layers(layerId).Name, ...
                        'HasUnpoolingOutputs', lgraph.Layers(layerId).HasUnpoolingOutputs);
            end
            lgraph = replaceLayer(lgraph, lgraph.Layers(layerId).Name, layer);
        end

        for id=1:numel(transConvIndices)
            layerId = transConvIndices(id);
            if strcmp(obj.BatchOpt.Workflow{1}(1:2), '2D') || strcmp(obj.BatchOpt.Workflow{1}(1:2), '2.')
                layer = transposedConv2dLayer(poolSize,  lgraph.Layers(layerId).NumFilters, 'Stride', poolSize, ...
                    'Name', lgraph.Layers(layerId).Name);
            else
                layer = transposedConv3dLayer(poolSize,  lgraph.Layers(layerId).NumFilters, 'Stride', [poolSize, poolSize, poolSize], ...
                    'Name', lgraph.Layers(layerId).Name);
            end
            lgraph = replaceLayer(lgraph, lgraph.Layers(layerId).Name, layer);
        end
    end
end

