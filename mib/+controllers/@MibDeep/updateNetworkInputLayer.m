function lgraph = updateNetworkInputLayer(obj, lgraph, inputPatchSize)
% UPDATENETWORKINPUTLAYER - update the input layer settings for lgraph.
%
% Syntax:
%   function lgraph = updateNetworkInputLayer(obj, lgraph, inputPatchSize)
%
% paramters are taken from obj.InputLayerOpt

    selectedWorkflow = obj.BatchOpt.Workflow{1};
    colorDimension = 4;
    if strcmp(selectedWorkflow, '2.5D Semantic') && strcmp(obj.BatchOpt.Architecture{1}(1:3), 'Z2C')
        selectedWorkflow = '2D Z2C';
        colorDimension = 3;
    end

    switch selectedWorkflow
        case {'2D Semantic',  '2D Z2C', '2D Patch-wise'}
            % update the input layer settings
            switch obj.InputLayerOpt.Normalization
                case 'zerocenter'
                    inputLayer = imageInputLayer(inputPatchSize([1 2 colorDimension]), 'Name', 'ImageInputLayer', ...
                        'Normalization', obj.InputLayerOpt.Normalization, ...
                        'Mean', reshape(obj.InputLayerOpt.Mean, [1 1 numel(obj.InputLayerOpt.Mean)]));
                case 'zscore'
                    inputLayer = imageInputLayer(inputPatchSize([1 2 colorDimension]), 'Name', 'ImageInputLayer', ...
                        'Normalization', obj.InputLayerOpt.Normalization, ...
                        'Mean', reshape(obj.InputLayerOpt.Mean, [1 1 numel(obj.InputLayerOpt.Mean)]), ...
                        'StandardDeviation', reshape(obj.InputLayerOpt.StandardDeviation, [1 1 numel(obj.InputLayerOpt.StandardDeviation)]));
                case {'rescale-symmetric', 'rescale-zero-one'}
                    inputLayer = imageInputLayer(inputPatchSize([1 2 colorDimension]), 'Name', 'ImageInputLayer', ...
                        'Normalization', obj.InputLayerOpt.Normalization, ...
                        'Min', reshape(obj.InputLayerOpt.Min, [1 1 numel(obj.InputLayerOpt.Min)]), ...
                        'Max', reshape(obj.InputLayerOpt.Max, [1 1 numel(obj.InputLayerOpt.Max)]));
                case 'none'
                    inputLayer = imageInputLayer(inputPatchSize([1 2 colorDimension]), 'Name', 'ImageInputLayer', ...
                        'Normalization', obj.InputLayerOpt.Normalization);
                otherwise
                    mgsOpt.MsgBoxOnly = true;
                    header = sprintf('Wrong normlization paramter (%s)!\n\nUse one of those:\n - zerocenter\n - zscore\n - rescale-symmetric\n - rescale-zero-one\n - none', obj.InputLayerOpt.Normalization);
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong normalization', mgsOpt);
                    lgraph = [];
                    return;
            end
            switch obj.BatchOpt.Architecture{1}
                case {'U-net', 'DeepLab v3+', 'Z2C + DLv3'}
                    try
                        %inputLayer.Name = 'data';
                        lgraph = replaceLayer(lgraph, lgraph.Layers(1).Name, inputLayer);
                        %lgraph = replaceLayer(lgraph, 'ImageInputLayer', inputLayer);
                    catch err
                        % when deeplabv3plusLayers used to generate
                        % one of the standard networks
                        lgraph = replaceLayer(lgraph, 'input_1', inputLayer);
                    end
                case 'SegNet'
                    lgraph = replaceLayer(lgraph, 'inputImage', inputLayer);
                case {'Resnet18', 'Resnet101'}
                    lgraph = replaceLayer(lgraph, 'data', inputLayer);
                case {'Resnet50', 'Xception'}
                    lgraph = replaceLayer(lgraph, 'input_1', inputLayer);
                case 'U-net +Encoder'
                    lgraph = replaceLayer(lgraph, lgraph.Layers(1).Name, inputLayer);
            end
        case {'3D Semantic', '2.5D Semantic'}   % '2.5D Semantic' and '3D Semantic'
            % update the input layer settings
            switch obj.InputLayerOpt.Normalization
                case 'zerocenter'
                    inputLayer = image3dInputLayer(inputPatchSize, 'Name', 'ImageInputLayer', ...
                        'Normalization', obj.InputLayerOpt.Normalization, ...
                        'Mean', reshape(obj.InputLayerOpt.Mean, [1 1 1 numel(obj.InputLayerOpt.Mean)]));
                case 'zscore'
                    inputLayer = image3dInputLayer(inputPatchSize, 'Name', 'ImageInputLayer', ...
                        'Normalization', obj.InputLayerOpt.Normalization, ...
                        'Mean', reshape(obj.InputLayerOpt.Mean, [1 1 numel(obj.InputLayerOpt.Mean)]),...
                        'StandardDeviation', reshape(obj.InputLayerOpt.StandardDeviation, [1 1 1 numel(obj.InputLayerOpt.StandardDeviation)]));
                case {'rescale-symmetric', 'rescale-zero-one'}
                    inputLayer = image3dInputLayer(inputPatchSize, 'Name', 'ImageInputLayer', ...
                        'Normalization', obj.InputLayerOpt.Normalization, ...
                        'Min', reshape(obj.InputLayerOpt.Min, [1 1 1 numel(obj.InputLayerOpt.Min)]), ...
                        'Max', reshape(obj.InputLayerOpt.Max, [1 1 1 numel(obj.InputLayerOpt.Max)]));
                case 'none'
                    inputLayer = image3dInputLayer(inputPatchSize, 'Name', 'ImageInputLayer', ...
                        'Normalization', obj.InputLayerOpt.Normalization);
                otherwise
                    mgsOpt.MsgBoxOnly = true;
                    header = sprintf('Wrong normlization paramter (%s)!\n\nUse one of those:\n - zerocenter\n - zscore\n - rescale-symmetric\n - rescale-zero-one\n - none', obj.InputLayerOpt.Normalization);
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong normalization', mgsOpt);
                    lgraph = [];
                    return;
            end
            lgraph = replaceLayer(lgraph, lgraph.Layers(1).Name, inputLayer);
    end
end

