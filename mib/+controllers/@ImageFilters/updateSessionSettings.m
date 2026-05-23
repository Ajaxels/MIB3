function updateSessionSettings(obj)
% UPDATESESSIONSETTINGS - Populate default session settings for all image filters.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updateSessionSettings()
%
% Builds ``obj.mibModel.sessionSettings.ImageFilters`` — a struct with one
% sub-struct per filter name.  Each sub-struct holds:
%
%   - default parameter values (scalars, cell arrays, strings)
%   - ``mibBatchTooltip`` sub-struct with tooltip/help strings for batch UI
%
% Called once from the constructor when ``sessionSettings.ImageFilters`` does
% not yet exist.  Also callable manually to reset all filter defaults.
%
% Input Arguments:
%   - **obj** — ``controllers.ImageFilters`` instance
%
% Output Arguments:
%   (none) — results written to ``obj.mibModel.sessionSettings.ImageFilters``

mibPath = obj.mibModel.mibPath;
ImageFilters = struct();

% preload an image used for filter previews
ImageFilters.TestImg = imread(fullfile(mibPath, 'assets', 'images', 'test_img_for_previews.png'));

ImageFilters.Average.mibBatchTooltip.Info = 'Average filter<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">average</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
ImageFilters.Average.HSize = '3';
ImageFilters.Average.mibBatchTooltip.HSize = 'Size of the filter, specified as a positive integer or 2-element (3 element for 3D) vector of positive integers';
ImageFilters.Average.Padding = {'replicate'};
ImageFilters.Average.Padding{2} = {'replicate', 'symmetric', 'circular','custom'};
ImageFilters.Average.mibBatchTooltip.Padding = 'Outside values for "replicate" are equal the nearest array border value; for "symmetric" are computed by mirror-reflecting across the border; for "custom" are defined by the provided value; "circular" - implicitly assuming the input array is periodic';
ImageFilters.Average.PaddingValue{1} = 0;
ImageFilters.Average.PaddingValue{2} = [0 Inf];
ImageFilters.Average.mibBatchTooltip.PaddingValue = 'Padding value for the custom Padding option';
ImageFilters.Average.FilteringMode = {'corr'};
ImageFilters.Average.FilteringMode{2} = {'corr', 'conv'};
ImageFilters.Average.mibBatchTooltip.FilteringMode = 'perform multidimensional filtering using correlation (corr) or convolution (conv)';

ImageFilters.Disk.mibBatchTooltip.Info = 'Circular averaging filter (pillbox)<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">disk</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>.';
ImageFilters.Disk.Radius{1} = 3;
ImageFilters.Disk.Radius{2} = [0 Inf];
ImageFilters.Disk.mibBatchTooltip.Radius = 'Radius of a disk-shaped filter, specified as a positive number';

ImageFilters.DistanceMap.mibBatchTooltip.Info = 'Calculate distance map from seeds provided in the "Source Layer" dropdown.<br>The 2D map is calculated using MATLAB <a href="https://www.mathworks.com/help/images/ref/bwdist.html" target="_blank">bwdist</a>, while 3D using <a href="https://se.mathworks.com/matlabcentral/fileexchange/15455-3d-euclidean-distance-transform-for-variable-data-aspect-ratio" target="_blank">bwdistsc</a> by Yuriy Mishchenko';
ImageFilters.DistanceMap.Method{1} = 'euclidean';
ImageFilters.DistanceMap.Method{2} = {'chessboard', 'cityblock', 'euclidean', 'quasi-euclidean'};
ImageFilters.DistanceMap.mibBatchTooltip.Method = 'Method for calculation of distances';
ImageFilters.DistanceMap.AspectRatio3D = '1 1 1';
ImageFilters.DistanceMap.mibBatchTooltip.AspectRatio3D = 'Aspect ratio for calculation of distances in 3D, using "1 1 1" gives the fastest results';

ImageFilters.ElasticDistortion.mibBatchTooltip.Info = 'Elastic distortion filter, see details in <a href="http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.160.8494&rep=rep1&type=pdf" target="_blank">Best Practices for Convolutional Neural Networks Applied to Visual Document Analysis</a> (<a href="https://cognitivemedium.com/assets/rmnist/Simard.pdf" target="_blank">pdf</a>)';
ImageFilters.ElasticDistortion.ScalingFactor{1} = 30;
ImageFilters.ElasticDistortion.ScalingFactor{2} = [1 Inf];
ImageFilters.ElasticDistortion.mibBatchTooltip.ScalingFactor = 'Scaling factor for distortions';
ImageFilters.ElasticDistortion.HSize = '7';
ImageFilters.ElasticDistortion.mibBatchTooltip.HSize = 'Size of the filter, specified as a positive integer or 2-element (3 element for 3D) vector of positive integers; HAS TO BE ODD';
ImageFilters.ElasticDistortion.Sigma{1} = 4;
ImageFilters.ElasticDistortion.Sigma{2} = [0 Inf];
ImageFilters.ElasticDistortion.Sigma{3} = 'off';
ImageFilters.ElasticDistortion.mibBatchTooltip.Sigma = 'Standard deviation of the Gaussian distribution, normally HSize/5';
ImageFilters.ElasticDistortion.DistortAllLAyers = true;
ImageFilters.ElasticDistortion.mibBatchTooltip.DistortAllLAyers = 'When ticked the distortions are applied to all layers except selection';

ImageFilters.Entropy.mibBatchTooltip.Info = 'Local entropy filter, returns an image, where each output pixel contains the entropy (<em>-sum(p.*log2(p))</em>, where <em>p</em> contains the normalized histogram counts) of the defined neighborhood around the corresponding pixel, see details in <a href="https://www.mathworks.com/help/images/ref/entropyfilt.html" target="_blank">entropyfilt</a>.';
ImageFilters.Entropy.NeighborhoodSize  = '3';
ImageFilters.Entropy.mibBatchTooltip.NeighborhoodSize = 'Size (y-by-x) of the neighborhood used to estimate the local entropy of the image; can be a single number';
ImageFilters.Entropy.StrelShape  = {'rectangle'};
ImageFilters.Entropy.StrelShape{2} = {'rectangle', 'disk'};
ImageFilters.Entropy.mibBatchTooltip.StrelShape = 'Shape of the strel element to be used';
ImageFilters.Entropy.NormalizationFactor{1} = 1;
ImageFilters.Entropy.NormalizationFactor{2} = [0 Inf];
ImageFilters.Entropy.NormalizationFactor{3} = 'off';
ImageFilters.Entropy.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

ImageFilters.Frangi.mibBatchTooltip.Info = 'Frangi filter to enhance elongated or tubular structures using Hessian-based multiscale filtering<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/fibermetric.html" target="_blank">fibermetric</a>';
ImageFilters.Frangi.ThicknessRange  = '1 2 4 6';
ImageFilters.Frangi.mibBatchTooltip.ThicknessRange = 'Thickness of tubular structures in pixels, specified as a positive integer or vector of positive integers';
ImageFilters.Frangi.StructureSensitivity{1} = 2.55;
ImageFilters.Frangi.StructureSensitivity{2} = [0 Inf];
ImageFilters.Frangi.StructureSensitivity{3} = 'off';
ImageFilters.Frangi.mibBatchTooltip.StructureSensitivity = 'The structure sensitivity is a threshold for differentiating the tubular structure from the background; calculated as 0.01*diff(getrangefromclass(I)). For example, it is 2.55 for uint8 and 0.01 for the range [0, 1]';
ImageFilters.Frangi.ObjectPolarity = {'dark'};
ImageFilters.Frangi.ObjectPolarity{2} = {'dark', 'bright'};
ImageFilters.Frangi.mibBatchTooltip.ObjectPolarity = 'dark: structures are darker than the background; bright: structures are lighter than the background';
ImageFilters.Frangi.NormalizationFactor{1} = 1;
ImageFilters.Frangi.NormalizationFactor{2} = [0 Inf];
ImageFilters.Frangi.NormalizationFactor{3} = 'off';
ImageFilters.Frangi.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

ImageFilters.Gaussian.mibBatchTooltip.Info = 'Rotationally symmetric Gaussian lowpass filter of size (Hsize) with standard deviation (Sigma).<br>The 2D filtering is done with <a href="https://www.mathworks.com/help/images/ref/imgaussfilt.html" target="_blank">imgaussfilt</a> and 3D with <a href="https://www.mathworks.com/help/images/ref/imgaussfilt3.html" target="_blank">imgaussfilt3</a>';
ImageFilters.Gaussian.HSize = '3';
ImageFilters.Gaussian.mibBatchTooltip.HSize = 'Size of the filter, specified as a positive integer or 2-element (3 element for 3D) vector of positive integers; HAS TO BE ODD';
ImageFilters.Gaussian.Sigma{1} = 0.6;
ImageFilters.Gaussian.Sigma{2} = [0 Inf];
ImageFilters.Gaussian.Sigma{3} = 'off';
ImageFilters.Gaussian.mibBatchTooltip.Sigma = 'Standard deviation of the Gaussian distribution, normally = HSize/5';
ImageFilters.Gaussian.Padding = {'replicate'};
ImageFilters.Gaussian.Padding{2} = {'replicate', 'symmetric', 'circular','custom'};
ImageFilters.Gaussian.mibBatchTooltip.Padding = 'Outside values for "replicate" are equal the nearest array border value; for "symmetric" are computed by mirror-reflecting across the border; for "custom" are defined by the provided value; "circular" - implicitly assuming the input array is periodic';
ImageFilters.Gaussian.PaddingValue{1} = 0;
ImageFilters.Gaussian.PaddingValue{2} = [0 Inf];
ImageFilters.Gaussian.mibBatchTooltip.PaddingValue = 'Padding value for the custom Padding option';
ImageFilters.Gaussian.FilterDomain = {'auto'};
ImageFilters.Gaussian.FilterDomain{2} = {'auto', 'frequency', 'spatial'};
ImageFilters.Gaussian.mibBatchTooltip.FilterDomain = 'omain in which to perform filtering; auto: define based on internal heuristics';

ImageFilters.Gradient.mibBatchTooltip.Info = 'Calculate image gradient<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/gradient.html" target="_blank">gradient</a> function and the acquired X,Y,Z components are converted to the resulting image as <em>sqrt(X<sup>2</sup> + Y<sup>2</sup> + Z<sup>2</sup>)</em>';
ImageFilters.Gradient.SpacingXYZ = '1';
ImageFilters.Gradient.mibBatchTooltip.SpacingXYZ = 'Spacing between points in each direction, specified as separate inputs (X,Y,Z) of scalars or a single number';
ImageFilters.Gradient.NormalizationFactor{1} = 1;
ImageFilters.Gradient.NormalizationFactor{2} = [0 Inf];
ImageFilters.Gradient.NormalizationFactor{3} = 'off';
ImageFilters.Gradient.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

ImageFilters.LoG.mibBatchTooltip.Info = 'Filter the image using the Laplacian of Gaussian filter, which highlights the edges<br>The resulting image is converted to unsigned integers by its multiplying with the NormalizationFactor and adding half of max class integer value.  The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">log</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
ImageFilters.LoG.HSize = '5';
ImageFilters.LoG.mibBatchTooltip.HSize = 'Size of the filter, specified as a positive integer or 2-element (3 element for 3D) vector of positive integers';
ImageFilters.LoG.Sigma{1} = 1;
ImageFilters.LoG.Sigma{2} = [0 Inf];
ImageFilters.LoG.Sigma{3} = 'off';
ImageFilters.LoG.mibBatchTooltip.Sigma = 'Standard deviation, specified as a positive number';
ImageFilters.LoG.NormalizationFactor{1} = 1;
ImageFilters.LoG.NormalizationFactor{2} = [0 Inf];
ImageFilters.LoG.NormalizationFactor{3} = 'off';
ImageFilters.LoG.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

ImageFilters.MathOps.mibBatchTooltip.Info = 'Apply basic mathematical operations to the image';
ImageFilters.MathOps.Operation = {'Add'};
ImageFilters.MathOps.Operation{2} = {'Add', 'Subtract', 'Multiply', 'Divide'};
ImageFilters.MathOps.mibBatchTooltip.Operation = 'Mathematical operation to perform';
ImageFilters.MathOps.Value = '5';
ImageFilters.MathOps.mibBatchTooltip.Value = 'Value to apply';
ImageFilters.MathOps.OutputImageClass = {'Unchanged'};
ImageFilters.MathOps.OutputImageClass{2} = {'Unchanged', 'uint8', 'uint16', 'uint32'};
ImageFilters.MathOps.mibBatchTooltip.OutputImageClass = 'Generate the resulting image in this data class';

ImageFilters.Mode.mibBatchTooltip.Info = 'Mode filter<br>the filtering is done with <a href="https://se.mathworks.com/help/releases/R2020a/images/ref/modefilt.html" target="_blank">modefilt</a> function. Each output pixel contains the mode (most frequently occurring value) in the neighborhood around the corresponding pixel in the input image';
ImageFilters.Mode.FiltSize = '3 3 3';
ImageFilters.Mode.mibBatchTooltip.FiltSize = 'Size of filter in pixels as [height, width, depth]';
ImageFilters.Mode.Padding = {'symmetric'};
ImageFilters.Mode.Padding{2} = {'symmetric', 'replicate', 'zeros'};
ImageFilters.Mode.mibBatchTooltip.Padding = 'Padding method; symmetric - a mirror reflection of itself; replicate - repeating border elements; zeros - zero values';

ImageFilters.Motion.mibBatchTooltip.Info = 'Motion blur filter<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">motion</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
ImageFilters.Motion.Length{1} = 5;
ImageFilters.Motion.Length{2} = [1 Inf];
ImageFilters.Motion.mibBatchTooltip.Length = 'Length of linear motion, specified as a numeric scalar, measured in pixels';
ImageFilters.Motion.Angle{1} = 0;
ImageFilters.Motion.Angle{2} = [0 360];
ImageFilters.Motion.mibBatchTooltip.Angle = 'Angle of the motion, specified as a numeric scalar, measured in degrees, in a counter-clockwise direction; 0 corrsponds to the X-direction';

ImageFilters.Prewitt.mibBatchTooltip.Info = 'Prewitt filter for edge enhancement<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "<span style="color:red;">prewitt</span>" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
ImageFilters.Prewitt.Direction = {'X'};
ImageFilters.Prewitt.Direction{2} = {'X', 'Y', 'Z'};
ImageFilters.Prewitt.mibBatchTooltip.Direction = 'Gradient direction for the filter, Z is only used for the 3D filter';
ImageFilters.Prewitt.ReturnPart = {'both'};
ImageFilters.Prewitt.ReturnPart{2} = {'both', 'negative', 'positive'};
ImageFilters.Prewitt.mibBatchTooltip.ReturnPart = 'both: the resulting image is the absolute value of the filter; negative/positive: negative or positive part';
ImageFilters.Prewitt.NormalizationFactor{1} = 1;
ImageFilters.Prewitt.NormalizationFactor{2} = [0 Inf];
ImageFilters.Prewitt.NormalizationFactor{3} = 'off';
ImageFilters.Prewitt.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

ImageFilters.Range.mibBatchTooltip.Info = 'Local range filter, returns an image, where each output pixel contains the range value (maximum value - minimum value) of the defined neighborhood around the corresponding pixel. See details in <a href="https://www.mathworks.com/help/images/ref/rangefilt.html" target="_blank">rangefilt</a>';
ImageFilters.Range.NeighborhoodSize  = '3';
ImageFilters.Range.mibBatchTooltip.NeighborhoodSize = 'Size (y-by-x) of the neighborhood used to estimate the local range of the image; can be a single number';
ImageFilters.Range.StrelShape  = {'rectangle'};
ImageFilters.Range.StrelShape{2} = {'rectangle', 'disk'};
ImageFilters.Range.mibBatchTooltip.StrelShape = 'Shape of the strel element to be used';
ImageFilters.Range.NormalizationFactor{1} = 1;
ImageFilters.Range.NormalizationFactor{2} = [0 Inf];
ImageFilters.Range.NormalizationFactor{3} = 'off';
ImageFilters.Range.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

ImageFilters.SaltAndPepper.mibBatchTooltip.Info = 'Remove salt & pepper noise from image<br>The images are filtered using the median filter, after that a difference between the original and the median filtered images is taken. Pixels that have threshold higher than IntensityThreshold are considered as noise and removed';
ImageFilters.SaltAndPepper.HSize = '3';
ImageFilters.SaltAndPepper.mibBatchTooltip.HSize = 'Size of the strel element for median filter';
ImageFilters.SaltAndPepper.IntensityThreshold{1} = 50;
ImageFilters.SaltAndPepper.IntensityThreshold{2} = [0 Inf];
ImageFilters.SaltAndPepper.mibBatchTooltip.IntensityThreshold = 'Noise intensity threshold, pixels that have intensity variation of original image -minus- median filtered image higher than this number will be removed. See <em>mibRemoveSaltAndPepperNoise.m</em> function for details.';
ImageFilters.SaltAndPepper.NoiseType = {'salt and pepper'};
ImageFilters.SaltAndPepper.NoiseType{2} = {'salt and pepper', 'salt only', 'pepper only'};
ImageFilters.SaltAndPepper.mibBatchTooltip.NoiseType = 'Noise type, salt - white noise pixels, pepper - dark noise pixels';

ImageFilters.Sobel.mibBatchTooltip.Info = 'Sobel filter for edge enhancement<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/imfilter.html" target="_blank">imfilter</a> function and the "sobel" predefined filter from <a href="https://www.mathworks.com/help/images/ref/fspecial.html" target="_blank">fspecial</a>';
ImageFilters.Sobel.Direction = {'X'};
ImageFilters.Sobel.Direction{2} = {'X', 'Y', 'Z'};
ImageFilters.Sobel.mibBatchTooltip.Direction = 'Gradient direction for the filter, Z is only used for the 3D filter';
ImageFilters.Sobel.ReturnPart = {'both'};
ImageFilters.Sobel.ReturnPart{2} = {'both', 'negative', 'positive'};
ImageFilters.Sobel.mibBatchTooltip.ReturnPart = 'both: the resulting image is the absolute value of the filter; negative/positive: negative or positive part';
ImageFilters.Sobel.NormalizationFactor{1} = 1;
ImageFilters.Sobel.NormalizationFactor{2} = [0 Inf];
ImageFilters.Sobel.NormalizationFactor{3} = 'off';
ImageFilters.Sobel.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

ImageFilters.Std.mibBatchTooltip.Info = 'Local standard deviation of image. The value of each output pixel is the standard deviation of a neighborhood around the corresponding input pixel. The borders are extimated via symmetric padding: i.e. the values of padding pixels are a mirror reflection of the border pixels. See details in <a href="https://www.mathworks.com/help/images/ref/stdfilt.html" target="_blank">stdfilt</a>';
ImageFilters.Std.NeighborhoodSize  = '3';
ImageFilters.Std.mibBatchTooltip.NeighborhoodSize = 'Size (y-by-x) of the neighborhood used to estimate the local standard deviation of the image; can be a single number';
ImageFilters.Std.StrelShape  = {'rectangle'};
ImageFilters.Std.StrelShape{2} = {'rectangle', 'disk'};
ImageFilters.Std.mibBatchTooltip.StrelShape = 'Shape of the strel element to be used';
ImageFilters.Std.NormalizationFactor{1} = 1;
ImageFilters.Std.NormalizationFactor{2} = [0 Inf];
ImageFilters.Std.NormalizationFactor{3} = 'off';
ImageFilters.Std.mibBatchTooltip.NormalizationFactor = 'Normalization factor for scaling the resulting image';

% add common fields
fieldNames = {'Padding', 'PaddingValue', 'FilteringMode'}; % define fields that should be copied from ImageFilters.Average
addToFilter = {'Disk', 'LoG','Motion','Prewitt','Sobel'}; % define filters to which these fields should be copied
for filterId = 1:numel(addToFilter)
    for fieldId = 1:numel(fieldNames)
        ImageFilters.(addToFilter{filterId}).(fieldNames{fieldId}) = ImageFilters.Average.(fieldNames{fieldId});
        ImageFilters.(addToFilter{filterId}).mibBatchTooltip.(fieldNames{fieldId}) = ImageFilters.Average.mibBatchTooltip.(fieldNames{fieldId});
    end
end

ImageFilters.DesiredFilterName = [];   % name of the last used filter
ImageFilters.Bilateral.mibBatchTooltip.Info = 'Edge preserving bilateral filtering of images with Gaussian kernels<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imbilatfilt.html" target="_blank">imbilatfilt</a>';
ImageFilters.Bilateral.degreeOfSmoothing = num2str(255^2*.01);
ImageFilters.Bilateral.mibBatchTooltip.degreeOfSmoothing = 'Degree of smoothing, specified as a positive number. The recommended value is calculated as 0.01*diff(GetRangeFromClass(I)).^2';
ImageFilters.Bilateral.spatialSigma{1} = 1;
ImageFilters.Bilateral.spatialSigma{2} = [0 Inf];
ImageFilters.Bilateral.spatialSigma{3} = 'off';
ImageFilters.Bilateral.mibBatchTooltip.spatialSigma = 'Standard deviation of spatial Gaussian smoothing kernel, specified as a positive number';
ImageFilters.Bilateral.NeighborhoodSize = num2str(2*ceil(2*ImageFilters.Bilateral.spatialSigma{1})+1);
ImageFilters.Bilateral.mibBatchTooltip.NeighborhoodSize = 'Neighborhood size, an odd-valued positive integer. By default, the neighborhood size is 2*ceil(2*SpatialSigma)+1 pixels';
ImageFilters.Bilateral.Padding = {'replicate'};
ImageFilters.Bilateral.Padding{2} = {'replicate', 'symmetric', 'custom'};
ImageFilters.Bilateral.mibBatchTooltip.Padding = 'Outside values for "replicate" are equal the nearest array border value; for "symmetric" are computed by mirror-reflecting across the border; for "custom" are defined by the provided value';
ImageFilters.Bilateral.PaddingValue{1} = 0;
ImageFilters.Bilateral.PaddingValue{2} = [0 Inf];
ImageFilters.Bilateral.mibBatchTooltip.PaddingValue = 'Padding value for the custom Padding option';

ImageFilters.AnisotropicDiffusion.mibBatchTooltip.Info = 'Edge preserving anisotropic diffusion filtering of images with Perona-Malik algorithm<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imdiffusefilt.html" target="_blank">imdiffusefilt</a>';
ImageFilters.AnisotropicDiffusion.GradientThreshold{1} = 10;
ImageFilters.AnisotropicDiffusion.GradientThreshold{2} = [0 Inf];
ImageFilters.AnisotropicDiffusion.mibBatchTooltip.GradientThreshold = 'In percentage of the image class range, controls the conduction process by classifying gradient values as an actual edge or as noise. Increasing the value of GradientThreshold smooths the image more';
ImageFilters.AnisotropicDiffusion.NumberOfIterations{1} = 5;
ImageFilters.AnisotropicDiffusion.NumberOfIterations{2} = [0 Inf];
ImageFilters.AnisotropicDiffusion.mibBatchTooltip.NumberOfIterations = 'Number of iterations to use in the diffusion process';
ImageFilters.AnisotropicDiffusion.Connectivity = {'maximal'};
ImageFilters.AnisotropicDiffusion.Connectivity{2} = {'maximal', 'minimal'};
ImageFilters.AnisotropicDiffusion.mibBatchTooltip.Connectivity = 'Connectivity of a pixel to its neighbors, maximal for 8 and minimal for 4';
ImageFilters.AnisotropicDiffusion.ConductionMethod = {'exponential'};
ImageFilters.AnisotropicDiffusion.ConductionMethod{2} = {'exponential', 'quadratic'};
ImageFilters.AnisotropicDiffusion.mibBatchTooltip.ConductionMethod = 'Exponential diffusion favors high-contrast edges over low-contrast edges. Quadratic diffusion favors wide regions over smaller regions';

ImageFilters.DNNdenoise.mibBatchTooltip.Info = 'Denoise image using deep neural network<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/denoiseimage.html" target="_blank">denoiseImage</a>';
ImageFilters.DNNdenoise.NetworkName = {'DnCNN'};
ImageFilters.DNNdenoise.NetworkName{2} = {'DnCNN'};
ImageFilters.DNNdenoise.mibBatchTooltip.NetworkName = 'Name of pretrained denoising deep neural network';
ImageFilters.DNNdenoise.GPUblock{1} = 512;
ImageFilters.DNNdenoise.GPUblock{2} = [0 Inf];
ImageFilters.DNNdenoise.mibBatchTooltip.GPUblock = 'Width of the image block to be denoised at once on GPU, decrease if getting out of GPU memory errors';

ImageFilters.Median.mibBatchTooltip.Info = 'Median filtering of images in 2D or 3D. Each output pixel contains the median value in the specified neighborhood<br>The 2D filtering is done with <a href="https://www.mathworks.com/help/images/ref/medfilt2.html" target="_blank">medfilt2</a> and 3D with <a href="https://www.mathworks.com/help/images/ref/medfilt3.html" target="_blank">medfilt3</a>';
ImageFilters.Median.NeighborhoodSize  = '3';
ImageFilters.Median.mibBatchTooltip.NeighborhoodSize = 'Size (y-by-x-by-z) of the neighborhood used to calculate the median value';
ImageFilters.Median.Padding  = {'symmetric'};
ImageFilters.Median.Padding{2} = {'symmetric','zeros'};
ImageFilters.Median.mibBatchTooltip.Padding = 'symmetric: symmetrically extend the image at the boundaries; zeros: pad the image with 0s';

ImageFilters.NonLocalMeans.mibBatchTooltip.Info = 'Non-local means filter<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imnlmfilt.html" target="_blank">imnlmfilt</a>';
ImageFilters.NonLocalMeans.DegreeOfSmoothing = '';
ImageFilters.NonLocalMeans.mibBatchTooltip.DegreeOfSmoothing = 'Degree of smoothing (a positive number). As this value increases, the smoothing in the resulting image increases. When empty, the DegreeOfSmoothing is estimated as the standard deviation of noise from the image';
ImageFilters.NonLocalMeans.SearchWindowSize = '21';
ImageFilters.NonLocalMeans.mibBatchTooltip.SearchWindowSize = 'Search window size (an odd-valued positive integer). SearchWindowSize affects the performance linearly in terms of time. SearchWindowSize cannot be larger than the size of the input image';
ImageFilters.NonLocalMeans.ComparisonWindowSize = '5';
ImageFilters.NonLocalMeans.mibBatchTooltip.ComparisonWindowSize = 'Comparison window size (an odd-valued positive integer). ComparisonWindowSize must be less than or equal to SearchWindowSize';

ImageFilters.Wiener.mibBatchTooltip.Info = 'Noise remove from images using a pixel-wise adaptive low-pass Wiener filter based on statistics estimated from a local neighborhood of each pixel<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/wiener2.html" target="_blank">wiener2</a>';
ImageFilters.Wiener.NeighborhoodSize  = '3';
ImageFilters.Wiener.mibBatchTooltip.NeighborhoodSize = 'Size (m-by-n) of the neighborhood used to estimate the local image mean and standard deviation; can be a single number';
ImageFilters.Wiener.AdditiveNoise  = '';
ImageFilters.Wiener.mibBatchTooltip.AdditiveNoise = 'Additive noise, specified as a numeric array. If you do not specify noise, wiener2 calculates the mean of the local variance, mean2(localVar)';

ImageFilters.BMxD.mibBatchTooltip.Info = 'Filtering image using the block-matching and 3D collaborative algorithm, please note that this filter is only licensed to be used in non-profit organizations';
ImageFilters.BMxD.Sigma{1} = 6;
ImageFilters.BMxD.Sigma{2} = [0 Inf];
ImageFilters.BMxD.Sigma{3} = 'off';
ImageFilters.BMxD.mibBatchTooltip.Sigma = 'Estimation of the noise in image intensities';
ImageFilters.BMxD.Profile = {'lc'};
ImageFilters.BMxD.Profile{2} = {'lc', 'np'};
ImageFilters.BMxD.mibBatchTooltip.Profile = 'lc: fast profile (faster); np: normal profile (slower)';

%%
ImageFilters.AddNoise.mibBatchTooltip.Info = 'Add noise to image<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imnoise.html" target="_blank">imnoise</a>';
ImageFilters.AddNoise.Mode = {'gaussian'};
ImageFilters.AddNoise.Mode{2} = {'gaussian', 'poisson', 'salt & pepper', 'speckle'};
ImageFilters.AddNoise.mibBatchTooltip.Mode = 'Type of the noise to add';
ImageFilters.AddNoise.Mean = '0';
ImageFilters.AddNoise.mibBatchTooltip.Mean = '[Gaussian only] Noise mean';
ImageFilters.AddNoise.Variance = '0.01';
ImageFilters.AddNoise.mibBatchTooltip.Variance = '[Gaussian, Speckle only] Noise variance for gaussian, speckle';
ImageFilters.AddNoise.Density{1} = 0.05;
ImageFilters.AddNoise.Density{2} = [0 1];
ImageFilters.AddNoise.Density{3} = 'off';
ImageFilters.AddNoise.mibBatchTooltip.Density = '[Salt & pepper only] Noise density for salt & pepper';

ImageFilters.FastLocalLaplacian.mibBatchTooltip.Info = 'Fast local Laplacian filtering of images to enhance contrast, remove noise or smooth image details<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/locallapfilt.html" target="_blank">locallapfilt</a>';
ImageFilters.FastLocalLaplacian.EdgeAmplitude{1} = 0.1;
ImageFilters.FastLocalLaplacian.EdgeAmplitude{2} = [0 1];
ImageFilters.FastLocalLaplacian.EdgeAmplitude{3} = 'off';
ImageFilters.FastLocalLaplacian.mibBatchTooltip.EdgeAmplitude = 'Amplitude of edges [0-1]';
ImageFilters.FastLocalLaplacian.Smoothing{1} = 0.1;
ImageFilters.FastLocalLaplacian.Smoothing{2} = [0 100];
ImageFilters.FastLocalLaplacian.Smoothing{3} = 'off';
ImageFilters.FastLocalLaplacian.mibBatchTooltip.Smoothing = 'Smoothing of details, typical in range [0.01-10]. When below 1 - increases the details, effectively enhancing the local contrast of the image without affecting edges; when higher than 1 - smooths details in the input image while preserving crisp edges';
ImageFilters.FastLocalLaplacian.DynamicRange{1} = 1;
ImageFilters.FastLocalLaplacian.DynamicRange{2} = [0 10];
ImageFilters.FastLocalLaplacian.DynamicRange{3} = 'off';
ImageFilters.FastLocalLaplacian.mibBatchTooltip.DynamicRange = 'Dynamic range, typically in range [0-5]. When below 1 - Reduces the amplitude of edges in the image; above 1 - expands the dynamic range of the image';
ImageFilters.FastLocalLaplacian.ColorMode = {'luminance'};
ImageFilters.FastLocalLaplacian.ColorMode{2} = {'luminance', 'separate'};
ImageFilters.FastLocalLaplacian.mibBatchTooltip.ColorMode = 'Only for RGB images; luminance: converts RGB to grayscale before filtering and reintroduces color after filtering; separate: filters each color channel independently';
ImageFilters.FastLocalLaplacian.NumIntensityLevels = 'auto';
ImageFilters.FastLocalLaplacian.mibBatchTooltip.NumIntensityLevels = 'Number of intensity samples in the dynamic range of the input image, auto or a positive integer;  A higher number of samples gives results closer to exact local Laplacian filtering. A lower number increases the execution speed. Typical values are in the range [10, 100]';
ImageFilters.FastLocalLaplacian.useRGB = false;
ImageFilters.FastLocalLaplacian.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

ImageFilters.FlatfieldCorrection.mibBatchTooltip.Info = 'Flat-field correction to the grayscale or RGB image. The correction uses Gaussian smoothing with a standard deviation of sigma to approximate the shading component of the image<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imflatfield.html" target="_blank">imflatfield</a>';
ImageFilters.FlatfieldCorrection.Sigma = '30';
ImageFilters.FlatfieldCorrection.mibBatchTooltip.Sigma = 'Standard deviation of the Gaussian smoothing filter, specified as a positive number or a 2-element vector of positive numbers';
%ImageFilters.FlatfieldCorrection.useMask = false;
%ImageFilters.FlatfieldCorrection.mibBatchTooltip.useMask = 'When checked, apply the flat-field correction to the image only in the masked areas';
ImageFilters.FlatfieldCorrection.FilterHalfSize = '';
ImageFilters.FlatfieldCorrection.mibBatchTooltip.FilterHalfSize = 'Halfwidth size of the Gaussian filter, specified as a scalar or 2-element vector; when empty calculated from Sigma as "ceil(Sigma*2)"';
ImageFilters.FlatfieldCorrection.useRGB = false;
ImageFilters.FlatfieldCorrection.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

ImageFilters.LocalBrighten.mibBatchTooltip.Info = 'Brighten low-light image<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imlocalbrighten.html" target="_blank">imlocalbrighten</a>';
ImageFilters.LocalBrighten.Amount{1} = 1;
ImageFilters.LocalBrighten.Amount{2} = [0 1];
ImageFilters.LocalBrighten.Amount{3} = 'off';
ImageFilters.LocalBrighten.mibBatchTooltip.Amount = 'Amount of the image brightening [0 1]. When the value is 1, brightens the low-light areas of A as much as possible';
ImageFilters.LocalBrighten.AlphaBlend = true;
ImageFilters.LocalBrighten.mibBatchTooltip.AlphaBlend = 'When true, the filter alpha blends the input image with the enhanced image to preserve brighter areas of the input image';
ImageFilters.LocalBrighten.useRGB = false;
ImageFilters.LocalBrighten.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

ImageFilters.LocalContrast.mibBatchTooltip.Info = 'Edge-aware local contrast manipulation of images<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/localcontrast.html" target="_blank">localcontrast</a>';
ImageFilters.LocalContrast.EdgeThreshold{1} = 0.3;
ImageFilters.LocalContrast.EdgeThreshold{2} = [0 1];
ImageFilters.LocalContrast.EdgeThreshold{3} = 'off';
ImageFilters.LocalContrast.mibBatchTooltip.EdgeThreshold = 'Amplitude of strong edges to leave intact';
ImageFilters.LocalContrast.Amount{1} = 0.25;
ImageFilters.LocalContrast.Amount{2} = [-1 1];
ImageFilters.LocalContrast.Amount{3} = 'off';
ImageFilters.LocalContrast.mibBatchTooltip.Amount = 'Amount of enhancement or smoothing desired, in the range [-1,1]. Negative values specify edge-aware smoothing, while positive values specify edge-aware enhancement';
ImageFilters.LocalContrast.useRGB = false;
ImageFilters.LocalContrast.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

ImageFilters.ReduceHaze.mibBatchTooltip.Info = 'Reduce atmospheric haze<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imreducehaze.html" target="_blank">imreducehaze</a>';
ImageFilters.ReduceHaze.Amount{1} = 1;
ImageFilters.ReduceHaze.Amount{2} = [0 1];
ImageFilters.ReduceHaze.Amount{3} = 'off';
ImageFilters.ReduceHaze.mibBatchTooltip.Amount = 'Amount of haze to remove [0-1]. When the value is 1, the filter reduces the maximum amount of haze';
ImageFilters.ReduceHaze.Method = {'simpledcp'};
ImageFilters.ReduceHaze.Method{2} = {'simpledcp', 'approxdcp'};
ImageFilters.ReduceHaze.mibBatchTooltip.Method = 'simpledcp: simple dark channel prior method; approxdcp: approximate dark channel prior method';
ImageFilters.ReduceHaze.AtmosphericLight = '0.5';
ImageFilters.ReduceHaze.mibBatchTooltip.AtmosphericLight = 'Maximum value to be treated as haze [0-1], a number or a 3-element vector for RGB';
ImageFilters.ReduceHaze.ContrastEnhancement = {'global'};
ImageFilters.ReduceHaze.ContrastEnhancement{2} = {'global','boost','none'};
ImageFilters.ReduceHaze.mibBatchTooltip.ContrastEnhancement = 'Contrast enhancement technique';
ImageFilters.ReduceHaze.useRGB = false;
ImageFilters.ReduceHaze.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

ImageFilters.UnsharpMask.mibBatchTooltip.Info = 'Sharpen image using unsharp masking: when an image is sharpened by subtracting a blurred (unsharp) version of the image from itself<br>The filtering is done with <a href="https://www.mathworks.com/help/images/ref/imsharpen.html" target="_blank">imsharpen</a>';
ImageFilters.UnsharpMask.Radius{1} = 1.5;
ImageFilters.UnsharpMask.Radius{2} = [0 Inf];
ImageFilters.UnsharpMask.Radius{3} = 'off';
ImageFilters.UnsharpMask.mibBatchTooltip.Radius = 'Standard deviation of the Gaussian lowpass filter, specified as a positive number. This value controls the size of the region around the edge pixels that is affected by sharpening. A large value sharpens wider regions around the edges, whereas a small value sharpens narrower regions around edges';
ImageFilters.UnsharpMask.Amount{1} = 0.8;
ImageFilters.UnsharpMask.Amount{2} = [0 Inf];
ImageFilters.UnsharpMask.Amount{3} = 'off';
ImageFilters.UnsharpMask.mibBatchTooltip.Amount = 'Strength of the sharpening effect, specified as a numeric scalar. A higher value leads to larger increase in the contrast of the sharpened pixels. Typical values for this parameter are within the range [0 2]';
ImageFilters.UnsharpMask.Threshold{1} = 0;
ImageFilters.UnsharpMask.Threshold{2} = [0 1];
ImageFilters.UnsharpMask.Threshold{3} = 'off';
ImageFilters.UnsharpMask.mibBatchTooltip.Threshold = 'Minimum contrast required for a pixel to be considered an edge pixel. Higher values (closer to 1) allow sharpening only in high-contrast regions, such as strong edges, while leaving low-contrast regions unaffected. Lower values (closer to 0) additionally allow sharpening in relatively smoother regions of the image. This parameter is useful in avoiding sharpening noise in the output image';
ImageFilters.UnsharpMask.useRGB = false;
ImageFilters.UnsharpMask.mibBatchTooltip.useRGB = 'When checked the image is treated as an RGB image, otherwise as grayscale';

%% Binarization
ImageFilters.Edge.mibBatchTooltip.Info = 'Find edges in intensity image;<br>the filtering is done with <a href="https://www.mathworks.com/help/images/ref/edge.html" target="_blank">edge</a>';
ImageFilters.Edge.DestinationLayer{1} = 'selection';
ImageFilters.Edge.DestinationLayer{2} = {'selection', 'mask'};
ImageFilters.Edge.mibBatchTooltip.DestinationLayer = 'The detected edges will be assigned to this layer';
ImageFilters.Edge.Method{1} = 'Canny';
ImageFilters.Edge.Method{2} = {'approxcanny', 'Canny', 'LaplacianOfGaussian', 'Prewitt', 'Roberts', 'Sobel'};
ImageFilters.Edge.mibBatchTooltip.Method = 'Edge detection method';
ImageFilters.Edge.Threshold = '';
ImageFilters.Edge.mibBatchTooltip.Threshold = 'Sensitivity threshold [0-1], when empty calculated automatically. For "Canny" and "approxcanny" can also be two numbers [0-1] for low and high thresholds';
ImageFilters.Edge.Direction{1} = 'both';
ImageFilters.Edge.Direction{2} = {'both', 'horizontal', 'vertical'};
ImageFilters.Edge.mibBatchTooltip.Direction = '[Prewitt, Roberts, Sobel only] direction of edges to detect';
ImageFilters.Edge.Sigma = '1.5';
ImageFilters.Edge.mibBatchTooltip.Sigma = '[Canny, LaplacianOfGaussian only] standard deviation of Sigma"';

ImageFilters.SlicClustering.mibBatchTooltip.Info = 'Cluster together pixels of similar intensity using the <a href="https://www.epfl.ch/labs/ivrl/research/slic-superpixels" target="_blank">SLIC (Simple Linear Iterative Clustering) algorithm</a>';
ImageFilters.SlicClustering.DestinationLayer{1} = 'labels';
ImageFilters.SlicClustering.DestinationLayer{2} = {'labels'};
ImageFilters.SlicClustering.mibBatchTooltip.DestinationLayer = 'The detected edges will be assigned to this layer';
ImageFilters.SlicClustering.ClusterSize{1} = 500;
ImageFilters.SlicClustering.ClusterSize{2} = [1 Inf];
ImageFilters.SlicClustering.mibBatchTooltip.ClusterSize = 'Tentative size of clusters in pixels';
ImageFilters.SlicClustering.Compactness{1} = 99;
ImageFilters.SlicClustering.Compactness{2} = [1 Inf];
ImageFilters.SlicClustering.mibBatchTooltip.Compactness = 'Compactness factor, increasing the value will make clusters more square';
ImageFilters.SlicClustering.ChopX{1} = 1;
ImageFilters.SlicClustering.ChopX{2} = [1 Inf];
ImageFilters.SlicClustering.mibBatchTooltip.ChopX = '[Only for 3D] Chopping factor for large datasets, when this value is higher than one, the dataset is chopped into number of subvolumes that are processed separetly';
ImageFilters.SlicClustering.ChopY{1} = 1;
ImageFilters.SlicClustering.ChopY{2} = [1 Inf];
ImageFilters.SlicClustering.mibBatchTooltip.ChopY = '[Only for 3D] Chop factor for the Y-dimension';

ImageFilters.WatershedClustering.mibBatchTooltip.Info = 'Cluster together pixels based on presence of ridges using the <a href="https://se.mathworks.com/help/images/ref/watershed.html" target="_blank">watershed algorithm</a>.';
ImageFilters.WatershedClustering.DestinationLayer{1} = 'labels';
ImageFilters.WatershedClustering.DestinationLayer{2} = {'labels', 'mask', 'selection'};
ImageFilters.WatershedClustering.mibBatchTooltip.DestinationLayer = 'The detected edges will be assigned to this layer';
ImageFilters.WatershedClustering.ClusterSize{1} = 10;
ImageFilters.WatershedClustering.ClusterSize{2} = [0 Inf];
ImageFilters.WatershedClustering.mibBatchTooltip.ClusterSize = 'Define size of clusters';
ImageFilters.WatershedClustering.TypeOfSignal = {'black-on-white'};
ImageFilters.WatershedClustering.TypeOfSignal{2} = {'black-on-white', 'white-on-black'};
ImageFilters.WatershedClustering.mibBatchTooltip.TypeOfSignal = 'Type of signal, black-on-white means black ridges over the bright background, white-on-black - is other way around';
ImageFilters.WatershedClustering.GapPolicy{1} = 'keep gaps';
ImageFilters.WatershedClustering.GapPolicy{2} = {'keep gaps', 'remove gaps'};
ImageFilters.WatershedClustering.mibBatchTooltip.GapPolicy = 'Keep or remove gaps between superpixels';
ImageFilters.WatershedClustering.ResultingShape{1} = 'clusters';
ImageFilters.WatershedClustering.ResultingShape{2} = {'clusters', 'ridges'};
ImageFilters.WatershedClustering.mibBatchTooltip.ResultingShape = 'Define desired result - clusters or ridges that separate clusters';

% update session settings
obj.mibModel.sessionSettings.ImageFilters = ImageFilters;

end