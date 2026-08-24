classdef FloatConversionLoader < io.loaders.BaseImageLoader
% FLOATCONVERSIONLOADER - Minimal loader exposing the protected float-to-uint16 conversion.
%
% ``io.loaders.BaseImageLoader`` is abstract and its conversion helpers are
% protected, so a concrete subclass is the only way to exercise them without a
% file on disk and a Bio-Formats reader:
%
%   .. code-block:: matlab
%
%      loader = mibtest.helpers.FloatConversionLoader();
%      [img, imginfo] = loader.convert(single(rand(8)), dictionary(), ...
%                                      struct('silentMode', true));
%
% ``loadMetadata`` / ``loadImages`` only exist to satisfy the abstract interface -
% the tests never call them.
%
% See also: io.loaders.BaseImageLoader.convertFloatImage

    methods
        function [imginfo, files] = loadMetadata(~, ~, ~)
            imginfo = dictionary();
            files = struct();
        end

        function [img, imginfo] = loadImages(~, ~, imginfo, ~)
            img = [];
        end

        function [img, imginfo] = convert(obj, img, imginfo, options)
            % CONVERT - call the protected BaseImageLoader.convertFloatImage.
            [img, imginfo] = obj.convertFloatImage(img, imginfo, options);
        end
    end
end
