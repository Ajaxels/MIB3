function [patchOut, info, augList, augPars] = augmentAndCrop2dPatchMultiGPU(patchIn, info, inputPatchSize, outputPatchSize, mode, options)
% AUGMENTANDCROP2DPATCHMULTIGPU - Augment 2D training patches using operations in ``options.AugOpt2D``
% and/or crop the response to the network's output size.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      [patchOut, info, augList, augPars] = augmentAndCrop2dPatchMultiGPU( ...
%          patchIn, info, inputPatchSize, outputPatchSize, mode, options)
%
% Input Arguments:
%   - **patchIn** — table with ``InputImage`` and ``ResponsePixelLabelImage`` fields
%     (semantic segmentation) or a matrix (classification)
%   - **info** — additional info struct about the input patch
%   - **inputPatchSize** — [1×4] input patch size as ``[height, width, depth, color]``
%   - **outputPatchSize** — [1×4] output patch size as ``[height, width, depth, classes]``
%   - **mode** — [char] operation mode:
%
%     - ``'show'`` — pass through without augmentation or cropping
%     - ``'crop'`` — crop only, no augmentation
%     - ``'aug'`` — augment, then crop
%
%   - **options** — struct with additional parameters:
%
%     - ``.Workflow`` — [string] workflow name (``obj.BatchOpt.Workflow{1}``)
%     - ``.Aug2DFuncNames`` — copy of ``mibDeepController.Aug2DFuncNames``
%     - ``.AugOpt2D`` — copy of ``mibDeepController.AugOpt2D``
%     - ``.Aug2DFuncProbability`` — copy of ``mibDeepController.Aug2DFuncProbability``;
%       per-function trigger probabilities
%     - ``.T_ConvolutionPadding`` — [string] convolution padding type
%       (``mibDeepController.BatchOpt.T_ConvolutionPadding{1}``)
%
% Output Arguments:
%   - **patchOut** — two-column table as required by ``trainNetwork`` for single-input networks
%   - **info** — additional info struct about the input patch
%   - **augList** — cell array with the names of applied augmentation operations
%   - **augPars** — matrix of applied parameter values (``NaN`` when not used);
%     second column holds the blend parameter for Hue+Sat jitter
%

global mibDeepTrainingProgressStruct

augList = {};    % list of used aug functions
augPars = [];       % array with used parameters

if mibDeepTrainingProgressStruct.emergencyBrake == true   % stop training, return. This function is still called multiple times after stopping the training
    patchOut = [];
    return;
end

% check for the classification type training
if strcmp(options.Workflow, '2D Patch-wise')
    classificationType = true;
    if ~istable(patchIn)
        % convert to table for the same workflow as with
        % semantic segmentation
        patchIn = table({patchIn}, {info.Label}, 'VariableNames', {'InputImage', 'ResponseLabel'});
        fieldId = 'ResponseLabel';
    else
        % when preview augmentation is used
        fieldId = 'ResponseImage';
    end
else
    classificationType = false;
    % update field names
    if ismember('ResponsePixelLabelImage', patchIn.Properties.VariableNames)  % this one for pixelLabelDatastore
        fieldId = 'ResponsePixelLabelImage';
    else    % this one for imageDatastore
        fieldId = 'ResponseImage';
    end
end

% dynamically convert grayscale to RGB
if size(patchIn.InputImage{1}, 3) ~= inputPatchSize(4)
    for id=1:size(patchIn, 1)
        patchIn.InputImage{id} = repmat(patchIn.InputImage{id}, [1, 1, 3]);
    end
end

if strcmp(mode, 'show')
    inpVol = patchIn.InputImage;
    inpResponse = patchIn.(fieldId);
else
    numAugFunc = numel(options.Aug2DFuncNames);    % number of functions to be used
    inpVol = cell(size(patchIn, 1), 1);
    inpResponse = cell(size(patchIn, 1), 1);
    augList = cell(size(patchIn, 1), 1);
    augPars = nan([size(patchIn, 1), 17]); % allocate space for augmentation parameters

    cropSwitch = 0;
    if ~classificationType
        diffPatchY = (inputPatchSize(1)-outputPatchSize(1))/2;
        diffPatchX = (inputPatchSize(2)-outputPatchSize(2))/2;

        if diffPatchY ~=0 || diffPatchX ~=0
            y1 = diffPatchY+1;
            y2 = inputPatchSize(1)-diffPatchY;
            x1 = diffPatchX+1;
            x2 = inputPatchSize(2)-diffPatchX;
            cropSwitch = 1;   % crop resulting image to match output patch
        end
    end

    for id=1:size(patchIn, 1)
        if strcmp(mode, 'crop')  % do only crop
            if cropSwitch
                inpResponse{id, 1} = patchIn.(fieldId){id}(y1:y2, x1:x2, :, :);
            else
                inpResponse{id, 1} = patchIn.(fieldId){id};
            end
            inpVol{id, 1}= patchIn.InputImage{id};
        else    % augment and crop
            rndIdx = randi(100, 1)/100;
            if rndIdx > options.AugOpt2D.Fraction   % if index lower than options.AugOpt2D.Fraction -> augment the data
                out =  patchIn.InputImage{id};
                respOut = patchIn.(fieldId){id};
                augList{id} = {'Original'};
            else
                % find augmentations, based on probability
                % the code above was always returning an
                % augmented patch despite the fact that the probability was too low
                randVector = rand([2, numAugFunc]);
                randVector(2,:) = options.Aug2DFuncProbability;
                [~, index] = min(randVector, [], 1);
                augFuncIndeces = find(index == 1);

                if isempty(augFuncIndeces)
                    out =  patchIn.InputImage{id};
                    respOut = patchIn.(fieldId){id};
                    augList{id} = {'Original'};
                else
                    augList{id} = options.Aug2DFuncNames(augFuncIndeces);
                    out = patchIn.InputImage{id};
                    respOut = patchIn.(fieldId){id};
                    for augId = 1:numel(augList{id})
                        switch augList{id}{augId}
                            case 'RandXReflection'
                                out = fliplr(out);
                                if ~classificationType; respOut = fliplr(respOut); end
                            case 'RandYReflection'
                                out = flipud(out);
                                if ~classificationType; respOut = flipud(respOut); end
                            case 'Rotation90'
                                if randi(2) == 1
                                    out = rot90(out);
                                    if ~classificationType; respOut = rot90(respOut); end
                                else
                                    out = rot90(out,3);
                                    if ~classificationType; respOut = rot90(respOut,3); end
                                end
                            case 'ReflectedRotation90'
                                out = rot90(fliplr(out));
                                if ~classificationType; respOut = rot90(fliplr(respOut)); end
                            case 'RandRotation'
                                augPars(id,augId) = options.AugOpt2D.RandRotation.Min + (options.AugOpt2D.RandRotation.Max-options.AugOpt2D.RandRotation.Min)*rand;
                                tform = randomAffine2d('Rotation', [augPars(id,augId) augPars(id,augId)]);
                                outputView = affineOutputView([size(out,1) size(out,2)], tform);
                                out = imwarp(out, tform, 'cubic', 'OutputView', outputView, 'FillValues', options.AugOpt2D.FillValue);
                                if ~classificationType; respOut = imwarp(respOut, tform, 'nearest', 'OutputView', outputView); end
                            case 'RandScale'
%                                 minScaleRand = -1/options.AugOpt2D.RandScale.Min*rand;
%                                 maxScaleRand = options.AugOpt2D.RandScale.Max*rand;
%                                 meanVal = (minScaleRand+maxScaleRand)/2;
%                                 if meanVal < 0; randomNumber = -1/(meanVal-1); else; randomNumber = meanVal+1; end
%                                 augPars(id, augId) = randomNumber;
                                augPars(id, augId) = exp((log(options.AugOpt2D.RandScale.Max) - log(options.AugOpt2D.RandScale.Min)) * rand + log(options.AugOpt2D.RandScale.Min));
                                %augPars(id,augId) = options.AugOpt2D.RandScale.Min + (options.AugOpt2D.RandScale.Max-options.AugOpt2D.RandScale.Min)*rand;
                                tform = randomAffine2d('Scale', [augPars(id,augId) augPars(id,augId)]);
                                outputView = affineOutputView([size(out,1) size(out,2)], tform);
                                out = imwarp(out, tform, 'cubic', 'OutputView', outputView, 'FillValues', options.AugOpt2D.FillValue);
                                if ~classificationType; respOut = imwarp(respOut, tform, 'nearest', 'OutputView', outputView); end
                            case 'RandXScale'
                                augPars(id, augId) = exp((log(options.AugOpt2D.RandXScale.Max) - log(options.AugOpt2D.RandXScale.Min)) * rand + log(options.AugOpt2D.RandXScale.Min));
                                %augPars(id,augId) = options.AugOpt2D.RandXScale.Min + (options.AugOpt2D.RandXScale.Max-options.AugOpt2D.RandXScale.Min)*rand;
                                T = [augPars(id,augId) 0 0; 0 1 0; 0 0 1];
                                tform = affine2d(T);
                                outputView = affineOutputView([size(out,1) size(out,2)], tform);
                                out = imwarp(out, tform, 'cubic', 'OutputView', outputView, 'FillValues', options.AugOpt2D.FillValue);
                                if ~classificationType; respOut = imwarp(respOut, tform, 'nearest', 'OutputView', outputView); end
                            case 'RandYScale'
                                augPars(id, augId) = exp((log(options.AugOpt2D.RandYScale.Max) - log(options.AugOpt2D.RandYScale.Min)) * rand + log(options.AugOpt2D.RandYScale.Min));
                                %augPars(id,augId) = options.AugOpt2D.RandYScale.Min + (options.AugOpt2D.RandYScale.Max-options.AugOpt2D.RandYScale.Min)*rand;
                                T = [1 0 0; 0 augPars(id,augId) 0; 0 0 1];
                                tform = affine2d(T);
                                outputView = affineOutputView([size(out,1) size(out,2)], tform);
                                out = imwarp(out, tform, 'cubic', 'OutputView', outputView, 'FillValues', options.AugOpt2D.FillValue);
                                if ~classificationType; respOut = imwarp(respOut, tform, 'nearest', 'OutputView', outputView); end
                            case 'RandXShear'
                                augPars(id,augId) = options.AugOpt2D.RandXShear.Min + (options.AugOpt2D.RandXShear.Max-options.AugOpt2D.RandXShear.Min)*rand;
                                tform = randomAffine2d('XShear', [augPars(id,augId) augPars(id,augId)]);
                                outputView = affineOutputView([size(out,1) size(out,2)], tform);
                                out = imwarp(out, tform, 'cubic', 'OutputView', outputView, 'FillValues', options.AugOpt2D.FillValue);
                                if ~classificationType; respOut = imwarp(respOut, tform, 'nearest', 'OutputView', outputView); end
                            case 'RandYShear'
                                augPars(id,augId) = options.AugOpt2D.RandYShear.Min + (options.AugOpt2D.RandYShear.Max-options.AugOpt2D.RandYShear.Min)*rand;
                                tform = randomAffine2d('YShear', [augPars(id,augId) augPars(id,augId)]);
                                outputView = affineOutputView([size(out,1) size(out,2)], tform);
                                out = imwarp(out, tform, 'cubic', 'OutputView', outputView, 'FillValues', options.AugOpt2D.FillValue);
                                if ~classificationType; respOut = imwarp(respOut, tform, 'nearest', 'OutputView', outputView); end
                            case 'GaussianNoise'
                                augPars(id,augId) = options.AugOpt2D.GaussianNoise.Min + (options.AugOpt2D.GaussianNoise.Max-options.AugOpt2D.GaussianNoise.Min)*rand;
                                out =  imnoise(out, 'gaussian', 0, augPars(id,augId));
                                %respOut = patchIn.(fieldId){id};
                            case 'PoissonNoise'
                                out =  imnoise(out, 'poisson');
                                %respOut = patchIn.(fieldId){id};
                            case 'HueJitter'
                                if size(out, 3) == 3
                                    augPars(id,augId) = options.AugOpt2D.HueJitter.Min + (options.AugOpt2D.HueJitter.Max-options.AugOpt2D.HueJitter.Min)*rand;
                                    out = jitterColorHSV(out, 'Hue', [augPars(id,augId) augPars(id,augId)]);
                                end
                                %respOut = patchIn.(fieldId){id};
                            case 'SaturationJitter'
                                if size(out, 3) == 3
                                    augPars(id,augId) = options.AugOpt2D.SaturationJitter.Min + (options.AugOpt2D.SaturationJitter.Max-options.AugOpt2D.SaturationJitter.Min)*rand;
                                    out = jitterColorHSV(out, 'Saturation', [augPars(id,augId) augPars(id,augId)]);
                                end
                                %respOut = patchIn.(fieldId){id};
                            case 'BrightnessJitter'
                                augPars(id,augId) = options.AugOpt2D.BrightnessJitter.Min + (options.AugOpt2D.BrightnessJitter.Max-options.AugOpt2D.BrightnessJitter.Min)*rand;
                                if size(out, 3) == 3
                                    out = jitterColorHSV(out, 'Brightness', [augPars(id,augId) augPars(id,augId)]);
                                else
                                    out = out + augPars(id,augId)*255;
                                end
                                %respOut = patchIn.(fieldId){id};
                            case 'ContrastJitter'
                                augPars(id,augId) = options.AugOpt2D.ContrastJitter.Min + (options.AugOpt2D.ContrastJitter.Max-options.AugOpt2D.ContrastJitter.Min)*rand;
                                if size(out, 3) == 3
                                    out = jitterColorHSV(out, 'Contrast', [augPars(id,augId) augPars(id,augId)]);
                                else
                                    out = out.*augPars(id,augId);
                                end
                                %respOut = patchIn.(fieldId){id};
                            case 'ImageBlur'
                                augPars(id,augId) = options.AugOpt2D.ImageBlur.Min + (options.AugOpt2D.ImageBlur.Max-options.AugOpt2D.ImageBlur.Min)*rand;
                                out =  imgaussfilt(out, augPars(id,augId));
                                %respOut = patchIn.(fieldId){id};
                        end
                    end
                end
            end
            
            if cropSwitch
                inpResponse{id, 1} = respOut(y1:y2, x1:x2, :, :);
            else
                inpResponse{id, 1} = respOut;
            end
            inpVol{id, 1} = out;

        end
    end
end

%             global counter
%             figure(1)
%             imshow(inpVol{1, 1});
%             for ii=1:numel(inpVol)
%                 fn = sprintf('d:\\Matlab\\Data\\DeepMIB_patch_Test\\PatchOut\\Case1\\patch_%.2d.tif', counter);
%                 imwrite(inpVol{1, 1}, fn, 'tif');
%                 counter = counter + 1
%             end

%             if counter == 26
%                 counter = 1;
%                 figure(1)
%                 imds = imageDatastore('d:\\Matlab\\Data\\DeepMIB_patch_Test\\PatchOut\\Case1\\');
%                 montage(imds, 'BackgroundColor', [1 1 1], 'BorderSize', [8 8]);
%                 error('');
%             end

if options.O_PreviewImagePatches && rand < options.O_FractionOfPreviewPatches
    if isfield(mibDeepTrainingProgressStruct, 'UIFigure') && isvalid(mibDeepTrainingProgressStruct.UIFigure)
        if size(inpVol{1}, 3) == 3 || size(inpVol{1}, 3) == 1
            image(mibDeepTrainingProgressStruct.imgPatch, inpVol{1}, 'CDataMapping', 'scaled');
        elseif size(inpVol{1}, 3) == 2
            out2 = inpVol{1};
            out2(:,:,3) = zeros([size(inpVol{1},1) size(inpVol{1},2)]);
            out2 = uint8(out2 * (255/double(max(out2(:)))));
            image(mibDeepTrainingProgressStruct.imgPatch, out2);
        end
        if ~classificationType
            if strcmp(options.T_ConvolutionPadding, 'valid')
                padSize = ceil((size(inpVol{1},1)- size(inpResponse{1},1))/2);
                previewLabel = padarray(uint8(inpResponse{1}),[padSize, padSize], 0, 'both');
                imagesc(mibDeepTrainingProgressStruct.labelPatch, previewLabel, [0 options.T_NumberOfClasses]);
            else
                imagesc(mibDeepTrainingProgressStruct.labelPatch, uint8(inpResponse{1}), [0 options.T_NumberOfClasses]);
            end
        else
            mibDeepTrainingProgressStruct.labelPatch.Text = inpResponse{1};
        end
        drawnow;
    end
    %figure(112345)
    %imshowpair(out, uint8(respOut), 'montage');
end

patchOut = table(inpVol, inpResponse);
% imtool(patchOut.inpVol{1}(:,:,32,1), [])
end
