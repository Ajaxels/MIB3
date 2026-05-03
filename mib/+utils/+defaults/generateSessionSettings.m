function sessionSettings = generateSessionSettings()
% GENERATESESSIONSETTINGS - Generate the default MIB session settings structure.
%
% Syntax:
%   .. code-block:: matlab
%
%      sessionSettings = generateSessionSettings()
%
% Output Arguments:
%   - **sessionSettings** — struct with default session settings for MIB
%
% Usage:
%
%   **Example 1** — initialise session settings at startup
%
%   .. code-block:: matlab
%
%      obj.mibModel.sessionSettings = utils.defaults.generateSessionSettings();
%

%% Define session settings structure
% define default parameters for filters
sessionSettings.prevCursorCoordinate = 0; % previous coordinate of mouse over the image axes to calculate mouse travel distance

sessionSettings.ImageFilters.Average.mibBatchTooltip.Info = 'Average filter<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">average</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
sessionSettings.ImageFilters.Average.HSize = '3';
sessionSettings.ImageFilters.Average.mibBatchTooltip.HSize = 'Size of the filter, specified as a positive integer or 2-element (3 element for 3D) vector of positive integers';
sessionSettings.ImageFilters.Average.Padding = {'replicate'};
sessionSettings.ImageFilters.Average.Padding{2} = {'replicate', 'symmetric', 'circular','custom'};
sessionSettings.ImageFilters.Average.mibBatchTooltip.Padding = 'Outside values for "replicate" are equal the nearest array border value; for "symmetric" are computed by mirror-reflecting across the border; for "custom" are defined by the provided value; "circular" - implicitly assuming the input array is periodic';
sessionSettings.ImageFilters.Average.PaddingValue{1} = 0;
sessionSettings.ImageFilters.Average.PaddingValue{2} = [0 Inf];
sessionSettings.ImageFilters.Average.mibBatchTooltip.PaddingValue = 'Padding value for the custom Padding option';
sessionSettings.ImageFilters.Average.FilteringMode = {'corr'};
sessionSettings.ImageFilters.Average.FilteringMode{2} = {'corr', 'conv'};
sessionSettings.ImageFilters.Average.mibBatchTooltip.FilteringMode = 'perform multidimensional filtering using correlation (corr) or convolution (conv)';

sessionSettings.ImageFilters.Disk.mibBatchTooltip.Info = 'Circular averaging filter (pillbox)<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">disk</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>.';
sessionSettings.ImageFilters.Disk.Radius{1} = 3;
sessionSettings.ImageFilters.Disk.Radius{2} = [0 Inf];
sessionSettings.ImageFilters.Disk.mibBatchTooltip.Radius = 'Radius of a disk-shaped filter, specified as a positive number';

sessionSettings.ImageFilters.DistanceMap.mibBatchTooltip.Info = 'Calculate distance map from seeds provided in the "Source Layer" dropdown.<br>The 2D map is calculated using MATLAB <a href="https://www.mathworks.com/help/images/ref/bwdist.html" target="_blank">bwdist</a>, while 3D using <a href="https://se.mathworks.com/matlabcentral/fileexchange/15455-3d-euclidean-distance-transform-for-variable-data-aspect-ratio" target="_blank">bwdistsc</a> by Yuriy Mishchenko';
sessionSettings.ImageFilters.DistanceMap.Method{1} = 'euclidean';
sessionSettings.ImageFilters.DistanceMap.Method{2} = {'chessboard', 'cityblock', 'euclidean', 'quasi-euclidean'};
sessionSettings.ImageFilters.DistanceMap.mibBatchTooltip.Method = 'Method for calculation of distances';
sessionSettings.ImageFilters.DistanceMap.AspectRatio3D = '1 1 1';
sessionSettings.ImageFilters.DistanceMap.mibBatchTooltip.AspectRatio3D = 'Aspect ratio for calculation of distances in 3D, using "1 1 1" gives the fastest results';

sessionSettings.ImageFilters.ElasticDistortion.mibBatchTooltip.Info = 'Elastic distortion filter, see details in <a href="http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.160.8494&rep=rep1&type=pdf" target="_blank">Best Practices for Convolutional Neural Networks Applied to Visual Document Analysis</a> (<a href="https://cognitivemedium.com/assets/rmnist/Simard.pdf" target="_blank">pdf</a>)';
sessionSettings.ImageFilters.ElasticDistortion.ScalingFactor{1} = 30;
sessionSettings.ImageFilters.ElasticDistortion.ScalingFactor{2} = [1 Inf];
sessionSettings.ImageFilters.ElasticDistortion.mibBatchTooltip.ScalingFactor = 'Scaling factor for distortions';
sessionSettings.ImageFilters.ElasticDistortion.HSize = '7';
sessionSettings.ImageFilters.ElasticDistortion.mibBatchTooltip.HSize = 'Size of the filter, specified as a positive integer or 2-element (3 element for 3D) vector of positive integers; HAS TO BE ODD';
sessionSettings.ImageFilters.ElasticDistortion.Sigma{1} = 4;
sessionSettings.ImageFilters.ElasticDistortion.Sigma{2} = [0 Inf];
sessionSettings.ImageFilters.ElasticDistortion.Sigma{3} = 'off';
sessionSettings.ImageFilters.ElasticDistortion.mibBatchTooltip.Sigma = 'Standard deviation of the Gaussian distribution, normally HSize/5';
sessionSettings.ImageFilters.ElasticDistortion.DistortAllLAyers = true;
sessionSettings.ImageFilters.ElasticDistortion.mibBatchTooltip.DistortAllLAyers = 'When ticked the distortions are applied to all layers except selection';

sessionSettings.ImageFilters.Entropy.mibBatchTooltip.Info = 'Local entropy filter, returns an image, where each output pixel contains the entropy (<em>-sum(p.*log2(p))</em>, where <em>p</em> contains the normalized histogram counts) of the defined neighborhood around the corresponding pixel, see details in <a href="https://www.mathworks.com/help/images/ref/entropyfilt.html" target="_blank">entropyfilt</a>.';
sessionSettings.ImageFilters.Entropy.NeighborhoodSize  = '3';
sessionSettings.ImageFilters.Entropy.mibBatchTooltip.NeighborhoodSize = 'Size (y-by-x) of the neighborhood used to estimate the local entropy of the image; can be a single number';
sessionSettings.ImageFilters.Entropy.StrelShape  = {'rectangle'};
sessionSettings.ImageFilters.Entropy.StrelShape{2} = {'rectangle', 'disk'};
sessionSettings.ImageFilters.Entropy.mibBatchTooltip.StrelShape = 'Shape of the strel element to be used';
sessionSettings.ImageFilters.Entropy.NormalizationFactor{1} = 1;
sessionSettings.ImageFilters.Entropy.NormalizationFactor{2} = [0 Inf];
sessionSettings.ImageFilters.Entropy.NormalizationFactor{3} = 'off';
sessionSettings.ImageFilters.Entropy.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

sessionSettings.ImageFilters.Frangi.mibBatchTooltip.Info = 'Frangi filter to enhance elongated or tubular structures using Hessian-based multiscale filtering<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/fibermetric.html" target="_blank">fibermetric</a>';
sessionSettings.ImageFilters.Frangi.ThicknessRange  = '1 2 4 6';
sessionSettings.ImageFilters.Frangi.mibBatchTooltip.ThicknessRange = 'Thickness of tubular structures in pixels, specified as a positive integer or vector of positive integers';
sessionSettings.ImageFilters.Frangi.StructureSensitivity{1} = 2.55;
sessionSettings.ImageFilters.Frangi.StructureSensitivity{2} = [0 Inf];
sessionSettings.ImageFilters.Frangi.StructureSensitivity{3} = 'off';
sessionSettings.ImageFilters.Frangi.mibBatchTooltip.StructureSensitivity = 'The structure sensitivity is a threshold for differentiating the tubular structure from the background; calculated as 0.01*diff(getrangefromclass(I)). For example, it is 2.55 for uint8 and 0.01 for the range [0, 1]';
sessionSettings.ImageFilters.Frangi.ObjectPolarity = {'dark'};
sessionSettings.ImageFilters.Frangi.ObjectPolarity{2} = {'dark', 'bright'};
sessionSettings.ImageFilters.Frangi.mibBatchTooltip.ObjectPolarity = 'dark: structures are darker than the background; bright: structures are lighter than the background';
sessionSettings.ImageFilters.Frangi.NormalizationFactor{1} = 1;
sessionSettings.ImageFilters.Frangi.NormalizationFactor{2} = [0 Inf];
sessionSettings.ImageFilters.Frangi.NormalizationFactor{3} = 'off';
sessionSettings.ImageFilters.Frangi.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

sessionSettings.ImageFilters.Gaussian.mibBatchTooltip.Info = 'Rotationally symmetric Gaussian lowpass filter of size (Hsize) with standard deviation (Sigma).<br>The 2D filtering is done with <a href="https://www.mathworks.com/help/images/ref/imgaussfilt.html" target="_blank">imgaussfilt</a> and 3D with <a href="https://www.mathworks.com/help/images/ref/imgaussfilt3.html" target="_blank">imgaussfilt3</a>';
sessionSettings.ImageFilters.Gaussian.HSize = '3';
sessionSettings.ImageFilters.Gaussian.mibBatchTooltip.HSize = 'Size of the filter, specified as a positive integer or 2-element (3 element for 3D) vector of positive integers; HAS TO BE ODD';
sessionSettings.ImageFilters.Gaussian.Sigma{1} = 0.6;
sessionSettings.ImageFilters.Gaussian.Sigma{2} = [0 Inf];
sessionSettings.ImageFilters.Gaussian.Sigma{3} = 'off';
sessionSettings.ImageFilters.Gaussian.mibBatchTooltip.Sigma = 'Standard deviation of the Gaussian distribution, normally = HSize/5';
sessionSettings.ImageFilters.Gaussian.Padding = {'replicate'};
sessionSettings.ImageFilters.Gaussian.Padding{2} = {'replicate', 'symmetric', 'circular','custom'};
sessionSettings.ImageFilters.Gaussian.mibBatchTooltip.Padding = 'Outside values for "replicate" are equal the nearest array border value; for "symmetric" are computed by mirror-reflecting across the border; for "custom" are defined by the provided value; "circular" - implicitly assuming the input array is periodic';
sessionSettings.ImageFilters.Gaussian.PaddingValue{1} = 0;
sessionSettings.ImageFilters.Gaussian.PaddingValue{2} = [0 Inf];
sessionSettings.ImageFilters.Gaussian.mibBatchTooltip.PaddingValue = 'Padding value for the custom Padding option';
sessionSettings.ImageFilters.Gaussian.FilterDomain = {'auto'};
sessionSettings.ImageFilters.Gaussian.FilterDomain{2} = {'auto', 'frequency', 'spatial'};
sessionSettings.ImageFilters.Gaussian.mibBatchTooltip.FilterDomain = 'omain in which to perform filtering; auto: define based on internal heuristics';

sessionSettings.ImageFilters.Gradient.mibBatchTooltip.Info = 'Calculate image gradient<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/gradient.html" target="_blank">gradient</a> function and the acquired X,Y,Z components are converted to the resulting image as <em>sqrt(X<sup>2</sup> + Y<sup>2</sup> + Z<sup>2</sup>)</em>';
sessionSettings.ImageFilters.Gradient.SpacingXYZ = '1';
sessionSettings.ImageFilters.Gradient.mibBatchTooltip.SpacingXYZ = 'Spacing between points in each direction, specified as separate inputs (X,Y,Z) of scalars or a single number';
sessionSettings.ImageFilters.Gradient.NormalizationFactor{1} = 1;
sessionSettings.ImageFilters.Gradient.NormalizationFactor{2} = [0 Inf];
sessionSettings.ImageFilters.Gradient.NormalizationFactor{3} = 'off';
sessionSettings.ImageFilters.Gradient.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

sessionSettings.ImageFilters.LoG.mibBatchTooltip.Info = 'Filter the image using the Laplacian of Gaussian filter, which highlights the edges<br>The resulting image is converted to unsigned integers by its multiplying with the NormalizationFactor and adding half of max class integer value.  The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">log</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
sessionSettings.ImageFilters.LoG.HSize = '5';
sessionSettings.ImageFilters.LoG.mibBatchTooltip.HSize = 'Size of the filter, specified as a positive integer or 2-element (3 element for 3D) vector of positive integers';
sessionSettings.ImageFilters.LoG.Sigma{1} = 1;
sessionSettings.ImageFilters.LoG.Sigma{2} = [0 Inf];
sessionSettings.ImageFilters.LoG.Sigma{3} = 'off';
sessionSettings.ImageFilters.LoG.mibBatchTooltip.Sigma = 'Standard deviation, specified as a positive number';
sessionSettings.ImageFilters.LoG.NormalizationFactor{1} = 1;
sessionSettings.ImageFilters.LoG.NormalizationFactor{2} = [0 Inf];
sessionSettings.ImageFilters.LoG.NormalizationFactor{3} = 'off';
sessionSettings.ImageFilters.LoG.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

sessionSettings.ImageFilters.MathOps.mibBatchTooltip.Info = 'Apply basic mathematical operations to the image';
sessionSettings.ImageFilters.MathOps.Operation = {'Add'};
sessionSettings.ImageFilters.MathOps.Operation{2} = {'Add', 'Subtract', 'Multiply', 'Divide'};
sessionSettings.ImageFilters.MathOps.mibBatchTooltip.Operation = 'Mathematical operation to perform';
sessionSettings.ImageFilters.MathOps.Value = '5';
sessionSettings.ImageFilters.MathOps.mibBatchTooltip.Value = 'Value to apply';
sessionSettings.ImageFilters.MathOps.OutputImageClass = {'Unchanged'};
sessionSettings.ImageFilters.MathOps.OutputImageClass{2} = {'Unchanged', 'uint8', 'uint16', 'uint32'};
sessionSettings.ImageFilters.MathOps.mibBatchTooltip.OutputImageClass = 'Generate the resulting image in this data class';

sessionSettings.ImageFilters.Mode.mibBatchTooltip.Info = 'Mode filter<br>the filtering is done with <a href="https://se.mathworks.com/help/releases/R2020a/images/ref/modefilt.html" target="_blank">modefilt</a> function. Each output pixel contains the mode (most frequently occurring value) in the neighborhood around the corresponding pixel in the input image';
sessionSettings.ImageFilters.Mode.FiltSize = '3 3 3';
sessionSettings.ImageFilters.Mode.mibBatchTooltip.FiltSize = 'Size of filter in pixels as [height, width, depth]';
sessionSettings.ImageFilters.Mode.Padding = {'symmetric'};
sessionSettings.ImageFilters.Mode.Padding{2} = {'symmetric', 'replicate', 'zeros'};
sessionSettings.ImageFilters.Mode.mibBatchTooltip.Padding = 'Padding method; symmetric - a mirror reflection of itself; replicate - repeating border elements; zeros - zero values';

sessionSettings.ImageFilters.Motion.mibBatchTooltip.Info = 'Motion blur filter<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">motion</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
sessionSettings.ImageFilters.Motion.Length{1} = 5;
sessionSettings.ImageFilters.Motion.Length{2} = [1 Inf];
sessionSettings.ImageFilters.Motion.mibBatchTooltip.Length = 'Length of linear motion, specified as a numeric scalar, measured in pixels';
sessionSettings.ImageFilters.Motion.Angle{1} = 0;
sessionSettings.ImageFilters.Motion.Angle{2} = [0 360];
sessionSettings.ImageFilters.Motion.mibBatchTooltip.Angle = 'Angle of the motion, specified as a numeric scalar, measured in degrees, in a counter-clockwise direction; 0 corrsponds to the X-direction';

sessionSettings.ImageFilters.Prewitt.mibBatchTooltip.Info = 'Prewitt filter for edge enhancement<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">prewitt</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
sessionSettings.ImageFilters.Prewitt.Direction = {'X'};
sessionSettings.ImageFilters.Prewitt.Direction{2} = {'X', 'Y', 'Z'};
sessionSettings.ImageFilters.Prewitt.mibBatchTooltip.Direction = 'Gradient direction for the filter, Z is only used for the 3D filter';
sessionSettings.ImageFilters.Prewitt.ReturnPart = {'both'};
sessionSettings.ImageFilters.Prewitt.ReturnPart{2} = {'both', 'negative', 'positive'};
sessionSettings.ImageFilters.Prewitt.mibBatchTooltip.ReturnPart = 'both: the resulting image is the absolute value of the filter; negative/positive: negative or positive part';
sessionSettings.ImageFilters.Prewitt.NormalizationFactor{1} = 1;
sessionSettings.ImageFilters.Prewitt.NormalizationFactor{2} = [0 Inf];
sessionSettings.ImageFilters.Prewitt.NormalizationFactor{3} = 'off';
sessionSettings.ImageFilters.Prewitt.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

sessionSettings.ImageFilters.Range.mibBatchTooltip.Info = 'Local range filter, returns an image, where each output pixel contains the range value (maximum value - minimum value) of the defined neighborhood around the corresponding pixel. See details in <a href="https://www.mathworks.com/help/images/ref/rangefilt.html" target="_blank">rangefilt</a>';
sessionSettings.ImageFilters.Range.NeighborhoodSize  = '3';
sessionSettings.ImageFilters.Range.mibBatchTooltip.NeighborhoodSize = 'Size (y-by-x) of the neighborhood used to estimate the local range of the image; can be a single number';
sessionSettings.ImageFilters.Range.StrelShape  = {'rectangle'};
sessionSettings.ImageFilters.Range.StrelShape{2} = {'rectangle', 'disk'};
sessionSettings.ImageFilters.Range.mibBatchTooltip.StrelShape = 'Shape of the strel element to be used';
sessionSettings.ImageFilters.Range.NormalizationFactor{1} = 1;
sessionSettings.ImageFilters.Range.NormalizationFactor{2} = [0 Inf];
sessionSettings.ImageFilters.Range.NormalizationFactor{3} = 'off';
sessionSettings.ImageFilters.Range.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

sessionSettings.ImageFilters.SaltAndPepper.mibBatchTooltip.Info = 'Remove salt & pepper noise from image<br>The images are filtered using the median filter, after that a difference between the original and the median filtered images is taken. Pixels that have threshold higher than IntensityThreshold are considered as noise and removed';
sessionSettings.ImageFilters.SaltAndPepper.HSize = '3';
sessionSettings.ImageFilters.SaltAndPepper.mibBatchTooltip.HSize = 'Size of the strel element for median filter';
sessionSettings.ImageFilters.SaltAndPepper.IntensityThreshold{1} = 50;
sessionSettings.ImageFilters.SaltAndPepper.IntensityThreshold{2} = [0 Inf];
sessionSettings.ImageFilters.SaltAndPepper.mibBatchTooltip.IntensityThreshold = 'Noise intensity threshold, pixels that have intensity variation of original image -minus- median filtered image higher than this number will be removed. See <em>mibRemoveSaltAndPepperNoise.m</em> function for details.';
sessionSettings.ImageFilters.SaltAndPepper.NoiseType = {'salt and pepper'};
sessionSettings.ImageFilters.SaltAndPepper.NoiseType{2} = {'salt and pepper', 'salt only', 'pepper only'};
sessionSettings.ImageFilters.SaltAndPepper.mibBatchTooltip.NoiseType = 'Noise type, salt - white noise pixels, pepper - dark noise pixels';

sessionSettings.ImageFilters.Sobel.mibBatchTooltip.Info = 'Sobel filter for edge enhancement<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "sobel" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
sessionSettings.ImageFilters.Sobel.Direction = {'X'};
sessionSettings.ImageFilters.Sobel.Direction{2} = {'X', 'Y', 'Z'};
sessionSettings.ImageFilters.Sobel.mibBatchTooltip.Direction = 'Gradient direction for the filter, Z is only used for the 3D filter';
sessionSettings.ImageFilters.Sobel.ReturnPart = {'both'};
sessionSettings.ImageFilters.Sobel.ReturnPart{2} = {'both', 'negative', 'positive'};
sessionSettings.ImageFilters.Sobel.mibBatchTooltip.ReturnPart = 'both: the resulting image is the absolute value of the filter; negative/positive: negative or positive part';
sessionSettings.ImageFilters.Sobel.NormalizationFactor{1} = 1;
sessionSettings.ImageFilters.Sobel.NormalizationFactor{2} = [0 Inf];
sessionSettings.ImageFilters.Sobel.NormalizationFactor{3} = 'off';
sessionSettings.ImageFilters.Sobel.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

sessionSettings.ImageFilters.Std.mibBatchTooltip.Info = 'Local standard deviation of image. The value of each output pixel is the standard deviation of a neighborhood around the corresponding input pixel. The borders are extimated via symmetric padding: i.e. the values of padding pixels are a mirror reflection of the border pixels. See details in <a href="https://www.mathworks.com/help/images/ref/stdfilt.html" target="_blank">stdfilt</a>';
sessionSettings.ImageFilters.Std.NeighborhoodSize  = '3';
sessionSettings.ImageFilters.Std.mibBatchTooltip.NeighborhoodSize = 'Size (y-by-x) of the neighborhood used to estimate the local standard deviation of the image; can be a single number';
sessionSettings.ImageFilters.Std.StrelShape  = {'rectangle'};
sessionSettings.ImageFilters.Std.StrelShape{2} = {'rectangle', 'disk'};
sessionSettings.ImageFilters.Std.mibBatchTooltip.StrelShape = 'Shape of the strel element to be used';
sessionSettings.ImageFilters.Std.NormalizationFactor{1} = 1;
sessionSettings.ImageFilters.Std.NormalizationFactor{2} = [0 Inf];
sessionSettings.ImageFilters.Std.NormalizationFactor{3} = 'off';
sessionSettings.ImageFilters.Std.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

% add common fields
fieldNames = {'Padding', 'PaddingValue', 'FilteringMode'}; % define fields that should be copied from sessionSettings.ImageFilters.Average
addToFilter = {'Disk', 'LoG','Motion','Prewitt','Sobel'}; % define filters to which these fields should be copied
for filterId = 1:numel(addToFilter)
    for fieldId = 1:numel(fieldNames)
        sessionSettings.ImageFilters.(addToFilter{filterId}).(fieldNames{fieldId}) = sessionSettings.ImageFilters.Average.(fieldNames{fieldId});
        sessionSettings.ImageFilters.(addToFilter{filterId}).mibBatchTooltip.(fieldNames{fieldId}) = sessionSettings.ImageFilters.Average.mibBatchTooltip.(fieldNames{fieldId});
    end
end

sessionSettings.ImageFilters.DesiredFilterName = [];   % name of the last used filter
sessionSettings.ImageFilters.Bilateral.mibBatchTooltip.Info = 'Edge preserving bilateral filtering of images with Gaussian kernels<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imbilatfilt.html" target="_blank">imbilatfilt</a>';
sessionSettings.ImageFilters.Bilateral.degreeOfSmoothing = num2str(255^2*.01);
sessionSettings.ImageFilters.Bilateral.mibBatchTooltip.degreeOfSmoothing = 'Degree of smoothing, specified as a positive number. The recommended value is calculated as 0.01*diff(GetRangeFromClass(I)).^2';
sessionSettings.ImageFilters.Bilateral.spatialSigma{1} = 1;
sessionSettings.ImageFilters.Bilateral.spatialSigma{2} = [0 Inf];
sessionSettings.ImageFilters.Bilateral.spatialSigma{3} = 'off';
sessionSettings.ImageFilters.Bilateral.mibBatchTooltip.spatialSigma = 'Standard deviation of spatial Gaussian smoothing kernel, specified as a positive number';
sessionSettings.ImageFilters.Bilateral.NeighborhoodSize = num2str(2*ceil(2*sessionSettings.ImageFilters.Bilateral.spatialSigma{1})+1);
sessionSettings.ImageFilters.Bilateral.mibBatchTooltip.NeighborhoodSize = 'Neighborhood size, an odd-valued positive integer. By default, the neighborhood size is 2*ceil(2*SpatialSigma)+1 pixels';
sessionSettings.ImageFilters.Bilateral.Padding = {'replicate'};
sessionSettings.ImageFilters.Bilateral.Padding{2} = {'replicate', 'symmetric', 'custom'};
sessionSettings.ImageFilters.Bilateral.mibBatchTooltip.Padding = 'Outside values for "replicate" are equal the nearest array border value; for "symmetric" are computed by mirror-reflecting across the border; for "custom" are defined by the provided value';
sessionSettings.ImageFilters.Bilateral.PaddingValue{1} = 0;
sessionSettings.ImageFilters.Bilateral.PaddingValue{2} = [0 Inf];
sessionSettings.ImageFilters.Bilateral.mibBatchTooltip.PaddingValue = 'Padding value for the custom Padding option';

sessionSettings.ImageFilters.AnisotropicDiffusion.mibBatchTooltip.Info = 'Edge preserving anisotropic diffusion filtering of images with Perona-Malik algorithm<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imdiffusefilt.html" target="_blank">imdiffusefilt</a>';
sessionSettings.ImageFilters.AnisotropicDiffusion.GradientThreshold{1} = 10;
sessionSettings.ImageFilters.AnisotropicDiffusion.GradientThreshold{2} = [0 Inf];
sessionSettings.ImageFilters.AnisotropicDiffusion.mibBatchTooltip.GradientThreshold = 'In percentage of the image class range, controls the conduction process by classifying gradient values as an actual edge or as noise. Increasing the value of GradientThreshold smooths the image more';
sessionSettings.ImageFilters.AnisotropicDiffusion.NumberOfIterations{1} = 5;
sessionSettings.ImageFilters.AnisotropicDiffusion.NumberOfIterations{2} = [0 Inf];
sessionSettings.ImageFilters.AnisotropicDiffusion.mibBatchTooltip.NumberOfIterations = 'Number of iterations to use in the diffusion process';
sessionSettings.ImageFilters.AnisotropicDiffusion.Connectivity = {'maximal'};
sessionSettings.ImageFilters.AnisotropicDiffusion.Connectivity{2} = {'maximal', 'minimal'};
sessionSettings.ImageFilters.AnisotropicDiffusion.mibBatchTooltip.Connectivity = 'Connectivity of a pixel to its neighbors, maximal for 8 and minimal for 4';
sessionSettings.ImageFilters.AnisotropicDiffusion.ConductionMethod = {'exponential'};
sessionSettings.ImageFilters.AnisotropicDiffusion.ConductionMethod{2} = {'exponential', 'quadratic'};
sessionSettings.ImageFilters.AnisotropicDiffusion.mibBatchTooltip.ConductionMethod = 'Exponential diffusion favors high-contrast edges over low-contrast edges. Quadratic diffusion favors wide regions over smaller regions';

sessionSettings.ImageFilters.DNNdenoise.mibBatchTooltip.Info = 'Denoise image using deep neural network<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/denoiseimage.html" target="_blank">denoiseImage</a>';
sessionSettings.ImageFilters.DNNdenoise.NetworkName = {'DnCNN'};
sessionSettings.ImageFilters.DNNdenoise.NetworkName{2} = {'DnCNN'};
sessionSettings.ImageFilters.DNNdenoise.mibBatchTooltip.NetworkName = 'Name of pretrained denoising deep neural network';
sessionSettings.ImageFilters.DNNdenoise.GPUblock{1} = 512;
sessionSettings.ImageFilters.DNNdenoise.GPUblock{2} = [0 Inf];
sessionSettings.ImageFilters.DNNdenoise.mibBatchTooltip.GPUblock = 'Width of the image block to be denoised at once on GPU, decrease if getting out of GPU memory errors';

sessionSettings.ImageFilters.Median.mibBatchTooltip.Info = 'Median filtering of images in 2D or 3D. Each output pixel contains the median value in the specified neighborhood<br>The 2D filtering is done with <a href="https://www.mathworks.com/help/images/ref/medfilt2.html" target="_blank">medfilt2</a> and 3D with <a href="https://www.mathworks.com/help/images/ref/medfilt3.html" target="_blank">medfilt3</a>';
sessionSettings.ImageFilters.Median.NeighborhoodSize  = '3';
sessionSettings.ImageFilters.Median.mibBatchTooltip.NeighborhoodSize = 'Size (y-by-x-by-z) of the neighborhood used to calculate the median value';
sessionSettings.ImageFilters.Median.Padding  = {'symmetric'};
sessionSettings.ImageFilters.Median.Padding{2} = {'symmetric','zeros'};
sessionSettings.ImageFilters.Median.mibBatchTooltip.Padding = 'symmetric: symmetrically extend the image at the boundaries; zeros: pad the image with 0s';

sessionSettings.ImageFilters.NonLocalMeans.mibBatchTooltip.Info = 'Non-local means filter<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imnlmfilt.html" target="_blank">imnlmfilt</a>';
sessionSettings.ImageFilters.NonLocalMeans.DegreeOfSmoothing = '';
sessionSettings.ImageFilters.NonLocalMeans.mibBatchTooltip.DegreeOfSmoothing = 'Degree of smoothing (a positive number). As this value increases, the smoothing in the resulting image increases. When empty, the DegreeOfSmoothing is estimated as the standard deviation of noise from the image';
sessionSettings.ImageFilters.NonLocalMeans.SearchWindowSize = '21';
sessionSettings.ImageFilters.NonLocalMeans.mibBatchTooltip.SearchWindowSize = 'Search window size (an odd-valued positive integer). SearchWindowSize affects the performance linearly in terms of time. SearchWindowSize cannot be larger than the size of the input image';
sessionSettings.ImageFilters.NonLocalMeans.ComparisonWindowSize = '5';
sessionSettings.ImageFilters.NonLocalMeans.mibBatchTooltip.ComparisonWindowSize = 'Comparison window size (an odd-valued positive integer). ComparisonWindowSize must be less than or equal to SearchWindowSize';

sessionSettings.ImageFilters.Wiener.mibBatchTooltip.Info = 'Noise remove from images using a pixel-wise adaptive low-pass Wiener filter based on statistics estimated from a local neighborhood of each pixel<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/wiener2.html" target="_blank">wiener2</a>';
sessionSettings.ImageFilters.Wiener.NeighborhoodSize  = '3';
sessionSettings.ImageFilters.Wiener.mibBatchTooltip.NeighborhoodSize = 'Size (m-by-n) of the neighborhood used to estimate the local image mean and standard deviation; can be a single number';
sessionSettings.ImageFilters.Wiener.AdditiveNoise  = '';
sessionSettings.ImageFilters.Wiener.mibBatchTooltip.AdditiveNoise = 'Additive noise, specified as a numeric array. If you do not specify noise, wiener2 calculates the mean of the local variance, mean2(localVar)';

sessionSettings.ImageFilters.BMxD.mibBatchTooltip.Info = 'Filtering image using the block-matching and 3D collaborative algorithm, please note that this filter is only licensed to be used in non-profit organizations';
sessionSettings.ImageFilters.BMxD.Sigma{1} = 6;
sessionSettings.ImageFilters.BMxD.Sigma{2} = [0 Inf];
sessionSettings.ImageFilters.BMxD.Sigma{3} = 'off';
sessionSettings.ImageFilters.BMxD.mibBatchTooltip.Sigma = 'Estimation of the noise in image intensities';
sessionSettings.ImageFilters.BMxD.Profile = {'lc'};
sessionSettings.ImageFilters.BMxD.Profile{2} = {'lc', 'np'};
sessionSettings.ImageFilters.BMxD.mibBatchTooltip.Profile = 'lc: fast profile (faster); np: normal profile (slower)';

%%
sessionSettings.ImageFilters.AddNoise.mibBatchTooltip.Info = 'Add noise to image<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imnoise.html" target="_blank">imnoise</a>';
sessionSettings.ImageFilters.AddNoise.Mode = {'gaussian'};
sessionSettings.ImageFilters.AddNoise.Mode{2} = {'gaussian', 'poisson', 'salt & pepper', 'speckle'};
sessionSettings.ImageFilters.AddNoise.mibBatchTooltip.Mode = 'Type of the noise to add';
sessionSettings.ImageFilters.AddNoise.Mean = '0';
sessionSettings.ImageFilters.AddNoise.mibBatchTooltip.Mean = '[Gaussian only] Noise mean';
sessionSettings.ImageFilters.AddNoise.Variance = '0.01';
sessionSettings.ImageFilters.AddNoise.mibBatchTooltip.Variance = '[Gaussian, Speckle only] Noise variance for gaussian, speckle';
sessionSettings.ImageFilters.AddNoise.Density{1} = 0.05;
sessionSettings.ImageFilters.AddNoise.Density{2} = [0 1];
sessionSettings.ImageFilters.AddNoise.Density{3} = 'off';
sessionSettings.ImageFilters.AddNoise.mibBatchTooltip.Density = '[Salt & pepper only] Noise density for salt & pepper';

sessionSettings.ImageFilters.FastLocalLaplacian.mibBatchTooltip.Info = 'Fast local Laplacian filtering of images to enhance contrast, remove noise or smooth image details<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/locallapfilt.html" target="_blank">locallapfilt</a>';
sessionSettings.ImageFilters.FastLocalLaplacian.EdgeAmplitude{1} = 0.1;
sessionSettings.ImageFilters.FastLocalLaplacian.EdgeAmplitude{2} = [0 1];
sessionSettings.ImageFilters.FastLocalLaplacian.EdgeAmplitude{3} = 'off';
sessionSettings.ImageFilters.FastLocalLaplacian.mibBatchTooltip.EdgeAmplitude = 'Amplitude of edges [0-1]';
sessionSettings.ImageFilters.FastLocalLaplacian.Smoothing{1} = 0.1;
sessionSettings.ImageFilters.FastLocalLaplacian.Smoothing{2} = [0 100];
sessionSettings.ImageFilters.FastLocalLaplacian.Smoothing{3} = 'off';
sessionSettings.ImageFilters.FastLocalLaplacian.mibBatchTooltip.Smoothing = 'Smoothing of details, typical in range [0.01-10]. When below 1 - increases the details, effectively enhancing the local contrast of the image without affecting edges; when higher than 1 - smooths details in the input image while preserving crisp edges';
sessionSettings.ImageFilters.FastLocalLaplacian.DynamicRange{1} = 1;
sessionSettings.ImageFilters.FastLocalLaplacian.DynamicRange{2} = [0 10];
sessionSettings.ImageFilters.FastLocalLaplacian.DynamicRange{3} = 'off';
sessionSettings.ImageFilters.FastLocalLaplacian.mibBatchTooltip.DynamicRange = 'Dynamic range, typically in range [0-5]. When below 1 - Reduces the amplitude of edges in the image; above 1 - expands the dynamic range of the image';
sessionSettings.ImageFilters.FastLocalLaplacian.ColorMode = {'luminance'};
sessionSettings.ImageFilters.FastLocalLaplacian.ColorMode{2} = {'luminance', 'separate'};
sessionSettings.ImageFilters.FastLocalLaplacian.mibBatchTooltip.ColorMode = 'Only for RGB images; luminance: converts RGB to grayscale before filtering and reintroduces color after filtering; separate: filters each color channel independently';
sessionSettings.ImageFilters.FastLocalLaplacian.NumIntensityLevels = 'auto';
sessionSettings.ImageFilters.FastLocalLaplacian.mibBatchTooltip.NumIntensityLevels = 'Number of intensity samples in the dynamic range of the input image, auto or a positive integer;  A higher number of samples gives results closer to exact local Laplacian filtering. A lower number increases the execution speed. Typical values are in the range [10, 100]';
sessionSettings.ImageFilters.FastLocalLaplacian.useRGB = false;
sessionSettings.ImageFilters.FastLocalLaplacian.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

sessionSettings.ImageFilters.FlatfieldCorrection.mibBatchTooltip.Info = 'Flat-field correction to the grayscale or RGB image. The correction uses Gaussian smoothing with a standard deviation of sigma to approximate the shading component of the image<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imflatfield.html" target="_blank">imflatfield</a>';
sessionSettings.ImageFilters.FlatfieldCorrection.Sigma = '30';
sessionSettings.ImageFilters.FlatfieldCorrection.mibBatchTooltip.Sigma = 'Standard deviation of the Gaussian smoothing filter, specified as a positive number or a 2-element vector of positive numbers';
%sessionSettings.ImageFilters.FlatfieldCorrection.useMask = false;
%sessionSettings.ImageFilters.FlatfieldCorrection.mibBatchTooltip.useMask = 'When checked, apply the flat-field correction to the image only in the masked areas';
sessionSettings.ImageFilters.FlatfieldCorrection.FilterHalfSize = '';
sessionSettings.ImageFilters.FlatfieldCorrection.mibBatchTooltip.FilterHalfSize = 'Halfwidth size of the Gaussian filter, specified as a scalar or 2-element vector; when empty calculated from Sigma as "ceil(Sigma*2)"';
sessionSettings.ImageFilters.FlatfieldCorrection.useRGB = false;
sessionSettings.ImageFilters.FlatfieldCorrection.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

sessionSettings.ImageFilters.LocalBrighten.mibBatchTooltip.Info = 'Brighten low-light image<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imlocalbrighten.html" target="_blank">imlocalbrighten</a>';
sessionSettings.ImageFilters.LocalBrighten.Amount{1} = 1;
sessionSettings.ImageFilters.LocalBrighten.Amount{2} = [0 1];
sessionSettings.ImageFilters.LocalBrighten.Amount{3} = 'off';
sessionSettings.ImageFilters.LocalBrighten.mibBatchTooltip.Amount = 'Amount of the image brightening [0 1]. When the value is 1, brightens the low-light areas of A as much as possible';
sessionSettings.ImageFilters.LocalBrighten.AlphaBlend = true;
sessionSettings.ImageFilters.LocalBrighten.mibBatchTooltip.AlphaBlend = 'When true, the filter alpha blends the input image with the enhanced image to preserve brighter areas of the input image';
sessionSettings.ImageFilters.LocalBrighten.useRGB = false;
sessionSettings.ImageFilters.LocalBrighten.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

sessionSettings.ImageFilters.LocalContrast.mibBatchTooltip.Info = 'Edge-aware local contrast manipulation of images<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/localcontrast.html" target="_blank">localcontrast</a>';
sessionSettings.ImageFilters.LocalContrast.EdgeThreshold{1} = 0.3;
sessionSettings.ImageFilters.LocalContrast.EdgeThreshold{2} = [0 1];
sessionSettings.ImageFilters.LocalContrast.EdgeThreshold{3} = 'off';
sessionSettings.ImageFilters.LocalContrast.mibBatchTooltip.EdgeThreshold = 'Amplitude of strong edges to leave intact';
sessionSettings.ImageFilters.LocalContrast.Amount{1} = 0.25;
sessionSettings.ImageFilters.LocalContrast.Amount{2} = [-1 1];
sessionSettings.ImageFilters.LocalContrast.Amount{3} = 'off';
sessionSettings.ImageFilters.LocalContrast.mibBatchTooltip.Amount = 'Amount of enhancement or smoothing desired, in the range [-1,1]. Negative values specify edge-aware smoothing, while positive values specify edge-aware enhancement';
sessionSettings.ImageFilters.LocalContrast.useRGB = false;
sessionSettings.ImageFilters.LocalContrast.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

sessionSettings.ImageFilters.ReduceHaze.mibBatchTooltip.Info = 'Reduce atmospheric haze<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imreducehaze.html" target="_blank">imreducehaze</a>';
sessionSettings.ImageFilters.ReduceHaze.Amount{1} = 1;
sessionSettings.ImageFilters.ReduceHaze.Amount{2} = [0 1];
sessionSettings.ImageFilters.ReduceHaze.Amount{3} = 'off';
sessionSettings.ImageFilters.ReduceHaze.mibBatchTooltip.Amount = 'Amount of haze to remove [0-1]. When the value is 1, the filter reduces the maximum amount of haze';
sessionSettings.ImageFilters.ReduceHaze.Method = {'simpledcp'};
sessionSettings.ImageFilters.ReduceHaze.Method{2} = {'simpledcp', 'approxdcp'};
sessionSettings.ImageFilters.ReduceHaze.mibBatchTooltip.Method = 'simpledcp: simple dark channel prior method; approxdcp: approximate dark channel prior method';
sessionSettings.ImageFilters.ReduceHaze.AtmosphericLight = '0.5';
sessionSettings.ImageFilters.ReduceHaze.mibBatchTooltip.AtmosphericLight = 'Maximum value to be treated as haze [0-1], a number or a 3-element vector for RGB';
sessionSettings.ImageFilters.ReduceHaze.ContrastEnhancement = {'global'};
sessionSettings.ImageFilters.ReduceHaze.ContrastEnhancement{2} = {'global','boost','none'};
sessionSettings.ImageFilters.ReduceHaze.mibBatchTooltip.ContrastEnhancement = 'Contrast enhancement technique';
sessionSettings.ImageFilters.ReduceHaze.useRGB = false;
sessionSettings.ImageFilters.ReduceHaze.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

sessionSettings.ImageFilters.UnsharpMask.mibBatchTooltip.Info = 'Sharpen image using unsharp masking: when an image is sharpened by subtracting a blurred (unsharp) version of the image from itself<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imsharpen.html" target="_blank">imsharpen</a>';
sessionSettings.ImageFilters.UnsharpMask.Radius{1} = 1.5;
sessionSettings.ImageFilters.UnsharpMask.Radius{2} = [0 Inf];
sessionSettings.ImageFilters.UnsharpMask.Radius{3} = 'off';
sessionSettings.ImageFilters.UnsharpMask.mibBatchTooltip.Radius = 'Standard deviation of the Gaussian lowpass filter, specified as a positive number. This value controls the size of the region around the edge pixels that is affected by sharpening. A large value sharpens wider regions around the edges, whereas a small value sharpens narrower regions around edges';
sessionSettings.ImageFilters.UnsharpMask.Amount{1} = 0.8;
sessionSettings.ImageFilters.UnsharpMask.Amount{2} = [0 Inf];
sessionSettings.ImageFilters.UnsharpMask.Amount{3} = 'off';
sessionSettings.ImageFilters.UnsharpMask.mibBatchTooltip.Amount = 'Strength of the sharpening effect, specified as a numeric scalar. A higher value leads to larger increase in the contrast of the sharpened pixels. Typical values for this parameter are within the range [0 2]';
sessionSettings.ImageFilters.UnsharpMask.Threshold{1} = 0;
sessionSettings.ImageFilters.UnsharpMask.Threshold{2} = [0 1];
sessionSettings.ImageFilters.UnsharpMask.Threshold{3} = 'off';
sessionSettings.ImageFilters.UnsharpMask.mibBatchTooltip.Threshold = 'Minimum contrast required for a pixel to be considered an edge pixel. Higher values (closer to 1) allow sharpening only in high-contrast regions, such as strong edges, while leaving low-contrast regions unaffected. Lower values (closer to 0) additionally allow sharpening in relatively smoother regions of the image. This parameter is useful in avoiding sharpening noise in the output image';
sessionSettings.ImageFilters.UnsharpMask.useRGB = false;
sessionSettings.ImageFilters.UnsharpMask.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

%% Binarization
sessionSettings.ImageFilters.Edge.mibBatchTooltip.Info = 'Find edges in intensity image;<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/edge.html" target="_blank">edge</a>';
sessionSettings.ImageFilters.Edge.DestinationLayer{1} = 'selection';
sessionSettings.ImageFilters.Edge.DestinationLayer{2} = {'selection', 'mask'};
sessionSettings.ImageFilters.Edge.mibBatchTooltip.DestinationLayer = 'The detected edges will be assigned to this layer';
sessionSettings.ImageFilters.Edge.Method{1} = 'Canny';
sessionSettings.ImageFilters.Edge.Method{2} = {'approxcanny', 'Canny', 'LaplacianOfGaussian', 'Prewitt', 'Roberts', 'Sobel'};
sessionSettings.ImageFilters.Edge.mibBatchTooltip.Method = 'Edge detection method';
sessionSettings.ImageFilters.Edge.Threshold = '';
sessionSettings.ImageFilters.Edge.mibBatchTooltip.Threshold = 'Sensitivity threshold [0-1], when empty calculated automatically. For "Canny" and "approxcanny" can also be two numbers [0-1] for low and high thresholds';
sessionSettings.ImageFilters.Edge.Direction{1} = 'both';
sessionSettings.ImageFilters.Edge.Direction{2} = {'both', 'horizontal', 'vertical'};
sessionSettings.ImageFilters.Edge.mibBatchTooltip.Direction = '[Prewitt, Roberts, Sobel only] direction of edges to detect';
sessionSettings.ImageFilters.Edge.Sigma = '1.5';
sessionSettings.ImageFilters.Edge.mibBatchTooltip.Sigma = '[Canny, LaplacianOfGaussian only] standard deviation of Sigma"';

sessionSettings.ImageFilters.SlicClustering.mibBatchTooltip.Info = 'Cluster together pixels of similar intensity using the <a href="https://www.epfl.ch/labs/ivrl/research/slic-superpixels" target="_blank">SLIC (Simple Linear Iterative Clustering) algorithm</a>';
sessionSettings.ImageFilters.SlicClustering.DestinationLayer{1} = 'model';
sessionSettings.ImageFilters.SlicClustering.DestinationLayer{2} = {'model'};
sessionSettings.ImageFilters.SlicClustering.mibBatchTooltip.DestinationLayer = 'The detected edges will be assigned to this layer';
sessionSettings.ImageFilters.SlicClustering.ClusterSize{1} = 500;
sessionSettings.ImageFilters.SlicClustering.ClusterSize{2} = [1 Inf];
sessionSettings.ImageFilters.SlicClustering.mibBatchTooltip.ClusterSize = 'Tentative size of clusters in pixels';
sessionSettings.ImageFilters.SlicClustering.Compactness{1} = 99;
sessionSettings.ImageFilters.SlicClustering.Compactness{2} = [1 Inf];
sessionSettings.ImageFilters.SlicClustering.mibBatchTooltip.Compactness = 'Compactness factor, increasing the value will make clusters more square';
sessionSettings.ImageFilters.SlicClustering.ChopX{1} = 1;
sessionSettings.ImageFilters.SlicClustering.ChopX{2} = [1 Inf];
sessionSettings.ImageFilters.SlicClustering.mibBatchTooltip.ChopX = '[Only for 3D] Chopping factor for large datasets, when this value is higher than one, the dataset is chopped into number of subvolumes that are processed separetly';
sessionSettings.ImageFilters.SlicClustering.ChopY{1} = 1;
sessionSettings.ImageFilters.SlicClustering.ChopY{2} = [1 Inf];
sessionSettings.ImageFilters.SlicClustering.mibBatchTooltip.ChopY = '[Only for 3D] Chop factor for the Y-dimension';

sessionSettings.ImageFilters.WatershedClustering.mibBatchTooltip.Info = 'Cluster together pixels based on presence of ridges using the <a href="https://se.mathworks.com/help/images/ref/watershed.html" target="_blank">watershed algorithm</a>.';
sessionSettings.ImageFilters.WatershedClustering.DestinationLayer{1} = 'model';
sessionSettings.ImageFilters.WatershedClustering.DestinationLayer{2} = {'model', 'mask', 'selection'};
sessionSettings.ImageFilters.WatershedClustering.mibBatchTooltip.DestinationLayer = 'The detected edges will be assigned to this layer';
sessionSettings.ImageFilters.WatershedClustering.ClusterSize{1} = 10;
sessionSettings.ImageFilters.WatershedClustering.ClusterSize{2} = [0 Inf];
sessionSettings.ImageFilters.WatershedClustering.mibBatchTooltip.ClusterSize = 'Define size of clusters';
sessionSettings.ImageFilters.WatershedClustering.TypeOfSignal = {'black-on-white'};
sessionSettings.ImageFilters.WatershedClustering.TypeOfSignal{2} = {'black-on-white', 'white-on-black'};
sessionSettings.ImageFilters.WatershedClustering.mibBatchTooltip.TypeOfSignal = 'Type of signal, black-on-white means black ridges over the bright background, white-on-black - is other way around';
sessionSettings.ImageFilters.WatershedClustering.GapPolicy{1} = 'keep gaps';
sessionSettings.ImageFilters.WatershedClustering.GapPolicy{2} = {'keep gaps', 'remove gaps'};
sessionSettings.ImageFilters.WatershedClustering.mibBatchTooltip.GapPolicy = 'Keep or remove gaps between superpixels';
sessionSettings.ImageFilters.WatershedClustering.ResultingShape{1} = 'clusters';
sessionSettings.ImageFilters.WatershedClustering.ResultingShape{2} = {'clusters', 'ridges'};
sessionSettings.ImageFilters.WatershedClustering.mibBatchTooltip.ResultingShape = 'Define desired result - clusters or ridges that separate clusters';

% add CLAHE to session settings
sessionSettings.CLAHE.Mode = 'Current stack (3D)';
sessionSettings.CLAHE.NumTiles = [8 8];
sessionSettings.CLAHE.ClipLimit = 0.01;
sessionSettings.CLAHE.NBins = 256;
sessionSettings.CLAHE.Distribution = 'uniform';
sessionSettings.CLAHE.Alpha = 0.4;

% add physical pixel size in meters
pixelsPerInch = get(0, 'ScreenPixelsPerInch');
sessionSettings.metersPerPixel = 0.0254/pixelsPerInch;

% structure to keep list of dialogs that should not be shown again
sessionSettings.DoNotShowDialogs = struct;


end
