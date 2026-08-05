classdef StitchSliceProvider < io.savers.SliceProvider
% STITCHSLICEPROVIDER - SliceProvider that fuses stitched tiles per output slice.
%
% Lets the streaming zarr writer (:meth:`io.savers.Zarr3Saver.saveStream`) build a
% stitched mosaic slice-by-slice without ever holding the whole volume: each
% :meth:`getSlice` composites all tiles intersecting the requested global Z-slice
% via :func:`utils.stitch.fuseSliceComposite`, using the same blend math as
% :func:`utils.stitch.fuseInMemory`. Transient blending accumulators are bounded
% to one slice, so a mosaic whose single XY slice fits in RAM can be written to a
% full OME-Zarr v3 pyramid for free.
%
% See also: io.savers.SliceProvider, utils.stitch.fuseSliceComposite,
% utils.stitch.fuseInMemory
%
% **Example** — stream a stitched mosaic into a zarr3 pyramid:
%
%   .. code-block:: matlab
%
%      provider = io.savers.StitchSliceProvider(layout, canvas, ...
%          struct('blendMode', 'Feather', 'background', 0));
%      meta  = struct('pixSize', canvas.pixSize);
%      io.savers.Zarr3Saver(struct()).saveStream(provider, meta, outputPath, ...
%          struct('showWaitbar', false));

    properties (Access = private)
        Layout      % [struct array] tile layout
        Canvas      % [struct] planCanvas output
        FuseOptions % [struct] blendMode / background / marginPx
        ReaderFcn   % [function_handle] cached tile reader
    end

    methods
        function obj = StitchSliceProvider(layout, canvas, options)
            % STITCHSLICEPROVIDER - Wrap a solved layout/canvas as a slice provider.
            %
            % Input Arguments:
            %   - **layout** — [struct array] tile layout.
            %   - **canvas** — [struct] from :func:`utils.stitch.planCanvas`.
            %   - **options** *(optional)* — struct with fields ``.blendMode``,
            %     ``.background``, ``.marginPx``, ``.cacheSizeBytes``, ``.readerFcn``.
            if nargin < 3; options = struct(); end
            if ~isfield(options, 'blendMode');      options.blendMode = 'Feather'; end
            if ~isfield(options, 'background');     options.background = 0; end
            if ~isfield(options, 'cacheSizeBytes'); options.cacheSizeBytes = 2 * 1024^3; end
if ~isfield(options, 'correction');      options.correction = []; end

            obj.Layout      = layout;
            obj.Canvas      = canvas;
            obj.FuseOptions = options;

            if isfield(options, 'readerFcn') && ~isempty(options.readerFcn)
                obj.ReaderFcn = options.readerFcn;
            else
                obj.ReaderFcn = utils.stitch.makeTileReader(layout, ...
                    struct('cacheSizeBytes', options.cacheSizeBytes, 'correction', options.correction));
            end

            % Populate the SliceProvider shape contract from the canvas.
            sz = canvas.size;                 % [H W Z C T]
            obj.OutputSize  = sz;
            obj.DataClass   = canvas.dataClass;
            obj.SliceSize   = sz(1:2);
            obj.NumSlices   = sz(3);
            obj.NumChannels = sz(4);
            obj.NumFrames   = sz(5);
        end

        function slice = getSlice(obj, z, t)
            % GETSLICE - Return the fused output slice ``[H W C]`` at depth z, frame t.
            if nargin < 3; t = 1; end
            slice = utils.stitch.fuseSliceComposite(obj.Layout, obj.Canvas, ...
                z, t, obj.ReaderFcn, obj.FuseOptions);
        end
    end
end
