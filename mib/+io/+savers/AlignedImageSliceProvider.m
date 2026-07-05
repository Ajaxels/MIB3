classdef AlignedImageSliceProvider < io.savers.SliceProvider
% ALIGNEDIMAGESLICEPROVIDER - Streams warped level-0 image slices for BigData alignment.
%
% Reads each full-resolution (level-0) slice from a source ``core.MibBigDataImage``
% via ``getData('image', 3, colCh, struct('pyramidLevel', 1, 'z', [z z]))``, applies
% the per-slice level-0 geometric transform into the (possibly extended) output
% canvas with ``imwarp``, and returns the placed slice. One code path serves both
% drift (translation expressed as an affine) and feature/landmark (affine) modes —
% the caller supplies the per-slice transforms and the interpolation method.
% Consumed by ``io.savers.Zarr3Saver.saveStream`` so the full-resolution stack is
% never resident in memory.
%
% See also: io.savers.SliceProvider, io.savers.Zarr3Saver,
% controllers.Alignment.applyAlignmentBigData

    properties (Access = private)
        Source        % source core.MibBigDataImage (or any MibImage subclass) handle
        Tforms        % {NumSlices x 1} cell of level-0 transforms (affinetform2d), one per slice
        OutputView    % imref2d for the output canvas [newH0 newW0]
        Background    % scalar fill value for out-of-canvas pixels
        ColChannels   % colour-channel indices to read; [] = all channels
        Interp        % imwarp interpolation method ('nearest' for integer translation, 'cubic' for affine)
    end

    methods
        function obj = AlignedImageSliceProvider(source, tforms, outputView, background, colChannels, interp, numSlices, numFrames)
            % ALIGNEDIMAGESLICEPROVIDER - Build the streaming warped-image provider.
            %
            % Input Arguments:
            %   - **source** — source ``core.MibBigDataImage`` (read-only).
            %   - **tforms** — ``{numSlices x 1}`` cell of level-0 geometric
            %     transforms (``affinetform2d`` / ``affine2d`` / ``projective2d``).
            %   - **outputView** — output canvas as an ``imref2d`` (may carry world
            %     limits for an offset canvas) or a ``[newH0 newW0]`` size vector.
            %   - **background** — scalar background fill for out-of-canvas pixels.
            %   - **colChannels** — colour-channel indices; ``[]`` = all channels.
            %   - **interp** — imwarp interpolation ('nearest' | 'linear' | 'cubic').
            %   - **numSlices** — number of Z-slices (level-0 depth).
            %   - **numFrames** — number of time frames (default 1).
            if nargin < 5; colChannels = []; end
            if nargin < 6 || isempty(interp); interp = 'cubic'; end
            if nargin < 7 || isempty(numSlices); numSlices = 1; end
            if nargin < 8 || isempty(numFrames); numFrames = 1; end

            if isa(outputView, 'imref2d')
                obj.OutputView = outputView;
            else
                obj.OutputView = imref2d(outputView);
            end
            sz = obj.OutputView.ImageSize;

            obj.Source      = source;
            obj.Tforms      = tforms;
            obj.Background  = background;
            obj.ColChannels = colChannels;
            obj.Interp      = interp;
            obj.NumSlices   = numSlices;
            obj.NumFrames   = numFrames;

            % Probe a raw source slice to discover channel count and class.
            probe = obj.readRaw(1, 1);
            C = size(probe, 3);

            obj.NumChannels = C;
            obj.DataClass   = class(probe);
            obj.SliceSize   = sz(1:2);
            obj.OutputSize  = [sz(1), sz(2), numSlices, C, numFrames];
        end

        function slice = getSlice(obj, z, t)
            % GETSLICE - Return the warped level-0 slice [newH0, newW0, Colors].
            if nargin < 3; t = 1; end
            raw = obj.readRaw(z, t);            % [H0 W0 C]
            C   = size(raw, 3);
            slice = zeros([obj.OutputSize(1), obj.OutputSize(2), C], obj.DataClass);
            for c = 1:C
                slice(:, :, c) = imwarp(raw(:, :, c), obj.Tforms{z}, obj.Interp, ...
                    'OutputView', obj.OutputView, 'FillValues', obj.Background);
            end
        end
    end

    methods (Access = private)
        function raw = readRaw(obj, z, t)
            % READRAW - One level-0 getData for slice z, frame t; returns [H0 W0 C].
            opt.pyramidLevel = 1;
            opt.z = [z z];
            if obj.NumFrames > 1; opt.t = [t t]; end
            raw = obj.Source.getData('image', 3, obj.ColChannels, opt);
            % Normalise to [H0 W0 C] (getData squeezes singleton z/colour dims).
            raw = reshape(raw, size(raw, 1), size(raw, 2), []);
        end
    end
end
