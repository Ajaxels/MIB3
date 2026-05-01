function lgraph = updateSegmentationLayer(obj, lgraph, classNames)
% UPDATESEGMENTATIONLAYER - redefine the segmentation layer of lgraph based on.
%
% Syntax:
%   .. code-block:: matlab
%
%       lgraph = obj.updateSegmentationLayer(lgraph, classNames)
%
% obj.BatchOpt settings
%
% Input Arguments:
%   - **classNames** — cell array with class names, when not provided is 'auto' switch is used
%

    if nargin < 3; classNames = 'auto'; end

    switch obj.BatchOpt.T_SegmentationLayer{1}
        case 'weightedClassificationLayer'
            %                         if previewSwitch == 0
            %                             reset(pxds);
            %                             Labels = read(pxds);
            %                             for classId = 1:numel(obj.BatchOpt.T_NumberOfClasses{1})
            %                                 classWeights(classId) = numel(find(Labels{1}==classNames{classId}));
            %                             end
            %                             classWeights = 1-(classWeights./sum(classWeights));
            %                         else
            %                             classWeights = ones([obj.BatchOpt.T_NumberOfClasses{1} 1])/obj.BatchOpt.T_NumberOfClasses{1};
            %                         end
            classWeights = [0.8251 0.1429 0.0283 0.0038];
            outputLayer = weightedClassificationLayer('Segmentation-Layer', classWeights);
            %if previewSwitch == 0; reset(pxds); end
        case 'dicePixelCustomClassificationLayer'
            if obj.SegmentationLayerOpt.dicePixelCustom.ExcludeExerior
                % exclude the background class from calculation of
                % the loss function
                useClasses = 2:obj.BatchOpt.T_NumberOfClasses{1};
            else
                useClasses = [];
            end
            switch obj.BatchOpt.Workflow{1}
                case '3D Semantic'
                    outputLayerName = 'Custom Dice Segmentation Layer 3D';
                    dataDimension = 3;
                case {'2D Semantic', '2D Patch-wise', '2.5D Semantic'}
                    if strcmp(obj.BatchOpt.Architecture{1}(1:3), 'Z2C') || strcmp(obj.BatchOpt.Workflow{1}(1:2), '2D')
                        outputLayerName = 'Custom Dice Segmentation Layer 2D';
                        dataDimension = 2;
                    else    % '2.5D Semantic'
                        outputLayerName = 'Custom Dice Segmentation Layer 3D';
                        dataDimension = 2.5;
                    end
            end
            outputLayer = dicePixelCustomClassificationLayer(outputLayerName, dataDimension, useClasses);
            outputLayer.Classes = classNames;
            % check layer
            %layer = dicePixelCustomClassificationLayer(outputLayerName);
            %numClasses = 4;
            %validInputSize = [4 4 numClasses];
            %checkLayer(layer,validInputSize, 'ObservationDimension',4)
        case 'focalLossLayer'
            segLayerInitString = sprintf('outputLayer = %s(''Alpha'', %.3f, ''Gamma'', %.3f, ''Classes'', classNames, ''Name'', ''Segmentation-Layer'');', ...
                obj.BatchOpt.T_SegmentationLayer{1}, ...
                obj.SegmentationLayerOpt.focalLossLayer.Alpha, obj.SegmentationLayerOpt.focalLossLayer.Gamma);
            eval(segLayerInitString);
        otherwise
            segLayerInitString = sprintf('outputLayer = %s(''Name'', ''Segmentation-Layer'', ''Classes'', classNames);', obj.BatchOpt.T_SegmentationLayer{1});
            eval(segLayerInitString);
    end

    switch obj.BatchOpt.Workflow{1}
        case {'2D Semantic', '2.5D Semantic'}
            switch obj.BatchOpt.Architecture{1}
                case {'U-net', 'DeepLab v3+', ...
                        '3DC + DLv3 Resnet18', ...
                        'Z2C + U-net', 'Z2C + DLv3'}
                    try
                        lgraph = replaceLayer(lgraph, 'Segmentation-Layer', outputLayer);
                    catch err
                        if contains(lower(lgraph.Layers(end).Name), 'segmentation')
                            lgraph = replaceLayer(lgraph, lgraph.Layers(end).Name, outputLayer);
                        else
                            % when deeplabv3plusLayers used to generate
                            % one of the standard networks
                            lgraph = replaceLayer(lgraph, 'classification', outputLayer);
                        end
                    end
                case 'SegNet'
                    lgraph = replaceLayer(lgraph, 'pixelLabels', outputLayer);
            end
        case '3D Semantic'
            if ismember(obj.BatchOpt.Architecture{1}, {'U-net', 'U-net Anisotropic'})
                try
                    lgraph = replaceLayer(lgraph, 'Segmentation-Layer', outputLayer);
                catch err
                    if contains(lower(lgraph.Layers(end).Name), 'segmentation')
                        lgraph = replaceLayer(lgraph, lgraph.Layers(end).Name, outputLayer);
                    else
                        lgraph = replaceLayer(lgraph, 'classification', outputLayer);
                    end
                end
            end
        case '2D Patch-wise'
            lgraph = replaceLayer(lgraph, 'ClassificationLayer_predictions', outputLayer);
    end
end

