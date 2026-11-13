classdef PredictionSliceProvider < io.savers.SliceProvider
% PREDICTIONSLICEPROVIDER - slices of a prediction computed slab by slab, for a streaming saver.
%
% Lets ``io.savers.Zarr3Saver.saveStreamResumable`` (or ``saveStream``) write the
% score maps of a zarr image while it is being predicted
% (``MibDeep.predictZarrStore``), so that neither the image nor the scores are
% ever held whole. The saver pulls the slices in increasing order; when ``z`` is
% past the slab held, the provider calls ``nextSlabFcn(z)``, which predicts a
% slab (and writes its other outputs, such as the model store) and returns its
% scores and its first slice. Only one slab is held.
%
% The slabs need not follow each other: a resumed saver starts at its first
% missing slice, and ``nextSlabFcn`` may skip the slabs before it that every
% other output already holds. It may also return a slab that ends before ``z``
% (one an other output still needs); the provider then asks again. An error
% raised inside ``nextSlabFcn`` (a cancel included) propagates out of the saver.
%
% Properties:
%   - inherited ``OutputSize``, ``DataClass``, ``NumSlices``, ``NumChannels``,
%     ``NumFrames``, ``SliceSize`` (see ``io.savers.SliceProvider``)
%
% **Example** - stream the slabs of a function into a zarr store:
%
%   .. code-block:: matlab
%
%      % nextSlab(z) returns a [y x c d] uint8 block and its first slice, covering z
%      provider = deepmib.PredictionSliceProvider([512 512 100 3 1], 'uint8', @nextSlab);
%      io.savers.Zarr3Saver().saveStream(provider, struct(), 'C:\out\scores.zarr3', struct('silent', true));

    properties (Access = private)
        nextSlabFcn         % function handle, [slab, slabFirst] = nextSlabFcn(z), slab [y x c d]
        slab = []           % [y x c d] the slab held
        slabFirst = 1       % first slice of the slab held
        slabLast = 0        % last slice of the slab held
    end

    methods
        function obj = PredictionSliceProvider(outputSize, dataClass, nextSlabFcn)
            % PREDICTIONSLICEPROVIDER - create the provider.
            %
            % Input Arguments:
            %   - **outputSize** - [1x5 numeric] ``[height, width, depth, channels, 1]``
            %   - **dataClass** - [char] class of the slices, e.g. ``'uint8'``
            %   - **nextSlabFcn** - [function handle] ``[slab, slabFirst] = nextSlabFcn(z)``:
            %     a ``[height, width, channels, slabDepth]`` block after the one held,
            %     and its first slice; called until a block covers slice ``z``
            obj.OutputSize = outputSize;
            obj.DataClass = dataClass;
            obj.NumSlices = outputSize(3);
            obj.NumChannels = outputSize(4);
            obj.NumFrames = outputSize(5);
            obj.SliceSize = outputSize(1:2);
            obj.nextSlabFcn = nextSlabFcn;
        end

        function slice = getSlice(obj, z, ~)
            % GETSLICE - return slice ``z`` as ``[height, width, channels]``.
            %
            % Slices are served in increasing order; asking for a slice before the
            % slab held is an error, since earlier slabs are not kept.
            if z < obj.slabFirst
                error('deepmib:PredictionSliceProvider:order', ...
                    'Slice %d was requested after slice %d: the slices must be read in order', z, obj.slabLast);
            end
            while z > obj.slabLast
                [obj.slab, obj.slabFirst] = obj.nextSlabFcn(z);
                obj.slabLast = obj.slabFirst + size(obj.slab, 4) - 1;
            end
            slice = obj.slab(:, :, :, z - obj.slabFirst + 1);
        end
    end
end
