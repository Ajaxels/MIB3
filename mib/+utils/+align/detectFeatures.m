function points = detectFeatures(image, detector, options)
% DETECTFEATURES - Dispatch a single image to one of MATLAB's feature detectors.
%
% Syntax:
%   .. code-block:: matlab
%
%      points = utils.align.detectFeatures(image, detector, options)
%
% Thin dispatcher used by the automatic feature-based alignment algorithms in
% :class:`controllers.Alignment`. Each branch forwards to the corresponding
% MATLAB ``detect*Features`` function in the Computer Vision Toolbox, picking
% its parameters from the matching field of ``options``.
%
% Input Arguments:
%   - **image** - [numeric] grayscale image to analyse.
%   - **detector** - [char] detector type. Supported values:
%
%     - ``'Blobs: Speeded-Up Robust Features (SURF) algorithm'`` → ``detectSURFFeatures``
%     - ``'Blobs: Detect scale invariant feature transform (SIFT)'`` → ``detectSIFTFeatures``
%     - ``'Regions: Maximally Stable Extremal Regions (MSER) algorithm'`` → ``detectMSERFeatures``
%     - ``'Corners: Harris-Stephens algorithm'`` → ``detectHarrisFeatures``
%     - ``'Corners: Binary Robust Invariant Scalable Keypoints (BRISK)'`` → ``detectBRISKFeatures``
%     - ``'Corners: Features from Accelerated Segment Test (FAST)'`` → ``detectFASTFeatures``
%     - ``'Corners: Minimum Eigenvalue algorithm'`` → ``detectMinEigenFeatures``
%     - ``'Oriented FAST and rotated BRIEF (ORB)'`` → ``detectORBFeatures``
%
%   - **options** - struct with one field per detector carrying the
%     parameters forwarded to the corresponding ``detect*Features`` call:
%
%     - ``.detectSURFFeatures``    - ``.MetricThreshold``, ``.NumOctaves``, ``.NumScaleLevels``
%     - ``.detectSIFTFeatures``    - ``.ContrastThreshold``, ``.EdgeThreshold``, ``.NumLayersInOctave``, ``.Sigma``
%     - ``.detectMSERFeatures``    - ``.ThresholdDelta``, ``.RegionAreaRange``, ``.MaxAreaVariation``
%     - ``.detectHarrisFeatures``  - ``.MinQuality``, ``.FilterSize``
%     - ``.detectBRISKFeatures``   - ``.MinContrast``, ``.MinQuality``, ``.NumOctaves``
%     - ``.detectFASTFeatures``    - ``.MinQuality``, ``.MinContrast``
%     - ``.detectMinEigenFeatures``- ``.MinQuality``, ``.FilterSize``
%     - ``.detectORBFeatures``     - ``.ScaleFactor``, ``.NumLevels``
%
% Output Arguments:
%   - **points** - feature-points object returned by the chosen ``detect*Features``
%     function (e.g. :class:`SURFPoints`, :class:`SIFTPoints`, …). Empty if
%     ``detector`` did not match any supported case.
%
% **Example** - detect SURF features:
%
% .. code-block:: matlab
%
%    opts.detectSURFFeatures = struct('MetricThreshold', 1000, ...
%                                     'NumOctaves', 3, 'NumScaleLevels', 4);
%    pts = utils.align.detectFeatures(image, ...
%        'Blobs: Speeded-Up Robust Features (SURF) algorithm', opts);

% Updates
%

points = [];

switch detector
    case 'Blobs: Speeded-Up Robust Features (SURF) algorithm'
        detectOpt = options.detectSURFFeatures;
        points = detectSURFFeatures(image, ...
            'MetricThreshold', detectOpt.MetricThreshold, ...
            'NumOctaves',      detectOpt.NumOctaves, ...
            'NumScaleLevels',  detectOpt.NumScaleLevels);
    case 'Blobs: Detect scale invariant feature transform (SIFT)'
        detectOpt = options.detectSIFTFeatures;
        points = detectSIFTFeatures(image, ...
            'ContrastThreshold', detectOpt.ContrastThreshold, ...
            'EdgeThreshold',     detectOpt.EdgeThreshold, ...
            'NumLayersInOctave', detectOpt.NumLayersInOctave, ...
            'Sigma',             detectOpt.Sigma);
    case 'Regions: Maximally Stable Extremal Regions (MSER) algorithm'
        detectOpt = options.detectMSERFeatures;
        points = detectMSERFeatures(image, ...
            'ThresholdDelta',   detectOpt.ThresholdDelta, ...
            'RegionAreaRange',  detectOpt.RegionAreaRange, ...
            'MaxAreaVariation', detectOpt.MaxAreaVariation);
    case 'Corners: Harris-Stephens algorithm'
        detectOpt = options.detectHarrisFeatures;
        points = detectHarrisFeatures(image, ...
            'MinQuality', detectOpt.MinQuality, ...
            'FilterSize', detectOpt.FilterSize);
    case 'Corners: Binary Robust Invariant Scalable Keypoints (BRISK)'
        detectOpt = options.detectBRISKFeatures;
        points = detectBRISKFeatures(image, ...
            'MinContrast', detectOpt.MinContrast, ...
            'MinQuality',  detectOpt.MinQuality, ...
            'NumOctaves',  detectOpt.NumOctaves);
    case 'Corners: Features from Accelerated Segment Test (FAST)'
        detectOpt = options.detectFASTFeatures;
        points = detectFASTFeatures(image, ...
            'MinQuality',  detectOpt.MinQuality, ...
            'MinContrast', detectOpt.MinContrast);
    case 'Corners: Minimum Eigenvalue algorithm'
        detectOpt = options.detectMinEigenFeatures;
        points = detectMinEigenFeatures(image, ...
            'MinQuality', detectOpt.MinQuality, ...
            'FilterSize', detectOpt.FilterSize);
    case 'Oriented FAST and rotated BRIEF (ORB)'
        detectOpt = options.detectORBFeatures;
        points = detectORBFeatures(image, ...
            'ScaleFactor', detectOpt.ScaleFactor, ...
            'NumLevels',   detectOpt.NumLevels);
end

end
