function imgOut = channelWisePreProcess(obj, imgIn)
    % function imgOut = channelWisePreProcess(obj, imgIn)
    % Normalize images
    % As input has 4 channels (modalities), remove the mean and divide by the
    % standard deviation of each modality independently.
    %
    % Parameters:
    % imgIn: input image, as matrix [heigth, width, color, depth]
    %
    % Return values:
    % imgOut: resulting image, stretched between 0 and 1

    imgIn = single(imgIn);

    %             % zscore normalization
    %             chn_Mean = mean(imgIn, [1 2 4]);
    %             chn_Std = std(imgIn,0, [1 2 4]);
    %             imgOut = (imgIn - chn_Mean)./chn_Std;
    %
    %             rangeMin = -5;
    %             rangeMax = 5;
    %
    %             imgOut(imgOut > rangeMax) = rangeMax;     % remove outliers
    %             imgOut(imgOut < rangeMin) = rangeMin;
    %
    %             % Rescale the data to the range [0, 1].
    %             imgOut = (imgOut - rangeMin) / (rangeMax - rangeMin);

    % rescale-zeroone normalization
    chn_Min = min(imgIn, [], [1 2 4]);
    chn_Max = max(imgIn, [], [1 2 4]);
    imgOut = (imgIn - chn_Min) / (chn_Max - chn_Min);
end

