classdef MibImageSliceProvider < io.savers.SliceProvider
% MIBIMAGESLICEPROVIDER - SliceProvider that streams from a MibImage at a pyramid level.
%
% Reads one Z-slice at a time, on demand, from **any** ``core.MibImage`` subclass
% — a pixel image (``core.MibImage`` / ``core.MibVirtualImage`` /
% ``core.MibBigDataImage``) **or** a label object (``core.MibLabels63`` /
% ``core.MibBigDataLabels``) — by calling the polymorphic
% ``src.getData(layerType, 3, colChannel, options)`` with
% ``options.pyramidLevel`` and ``options.z = [z z]``. This is the **backend-neutral**
% read path: it never names zarr, so a future BioFormats / OpenSlide BigData backend
% works unchanged as long as it satisfies the read contract (honor ``pyramidLevel``
% + ``z`` in ``getData``).
%
% Slices are always read in native YX orientation (``orient = 3``) so export walks
% the dataset Z-slice by Z-slice. Depth and time are constant across pyramid levels
% (the pyramid downsamples XY only), so the caller passes ``numSlices`` / ``numFrames``
% while the per-slice height/width/channels/class are discovered by a single probe
% read of slice 1 in the constructor.
%
% See also: io.savers.SliceProvider, io.savers.BaseSaver,
% core.MibImage.getData, core.MibVirtualImage.getDataZarr,
% core.MibBigDataLabels.getData63
%
% **Example 1** — stream pyramid level 2 of a BigData image to disk:
%
%   .. code-block:: matlab
%
%      img       = mibModel.I{mibModel.getActiveId()}.image;   % MibBigDataImage
%      level     = 2;
%      numSlices = img.pyramid.levelImageSizes(level, 3);       % Z extent at this level
%      zScale    = img.pyramid.levelScaleFactors(level, 3);     % full-res z per level slice
%      provider  = io.savers.MibImageSliceProvider(img, 'image', level, [], numSlices, img.time, zScale);
%      slice     = provider.getSlice(1, 1);                     % first slice of level 2
%
% **Example 2** — stream a disk-backed BigData model (labels) at a level:
%
%   .. code-block:: matlab
%
%      labels    = mibModel.I{mibModel.getActiveId()}.labels;   % MibBigDataLabels
%      level     = 1;
%      numSlices = labels.modelLevelSizes(level, 3);
%      zScale    = labels.modelScaleFactors(level, 3);
%      provider  = io.savers.MibImageSliceProvider(labels, 'labels', level, [], numSlices, 1, zScale);

    properties (Access = private)
        Source       % core.MibImage subclass (image or label object)
        LayerType    (1,:) char = 'image'
        Level        (1,1) double = 1
        ColChannel   = []
        ZScale       (1,1) double = 1
        % [double] full-resolution Z spacing per slice at this level (= level's Z
        % scale factor). ``getData`` expects ``options.z`` in FULL-resolution
        % coordinates and divides by the level Z-scale, so level-slice ``k`` is
        % read by requesting full-res ``z = (k-1)*ZScale + 1``. This matters
        % because coarse pyramid levels may downsample Z as well as XY.
    end

    methods
        function obj = MibImageSliceProvider(src, layerType, level, colChannel, numSlices, numFrames, zScale)
            % MIBIMAGESLICEPROVIDER - Build a per-slice reader for a pyramid level.
            %
            % Input Arguments:
            %   - **src** — a ``core.MibImage`` subclass (image or label object)
            %   - **layerType** — [char] ``'image'`` | ``'labels'`` | ``'mask'`` | ``'selection'``
            %   - **level** — [double] 1-based pyramid level to export (1 = full res)
            %   - **colChannel** — colour-channel indices, ``[]`` = all (ignored for labels)
            %   - **numSlices** — [double] number of Z-slices at this level
            %   - **numFrames** — [double] number of time frames
            %   - **zScale** — [double] full-res Z spacing per level slice (level Z scale
            %     factor); default 1. Needed because ``getData``'s ``options.z`` is in
            %     full-resolution coordinates.
            if nargin < 4; colChannel = []; end
            if nargin < 5 || isempty(numSlices); numSlices = 1; end
            if nargin < 6 || isempty(numFrames); numFrames = 1; end
            if nargin < 7 || isempty(zScale);    zScale = 1;    end

            obj.Source     = src;
            obj.LayerType  = layerType;
            obj.Level      = level;
            obj.ColChannel = colChannel;
            obj.NumSlices  = numSlices;
            obj.NumFrames  = numFrames;
            obj.ZScale     = zScale;

            % Probe slice 1 to discover height/width/channels/class at this level.
            probe = obj.readRaw(1, 1);
            H = size(probe, 1);
            W = size(probe, 2);
            C = max(1, round(numel(probe) / max(1, H * W)));

            obj.SliceSize   = [H W];
            obj.NumChannels = C;
            obj.DataClass   = class(probe);
            obj.OutputSize  = [H, W, numSlices, C, numFrames];
        end

        function slice = getSlice(obj, z, t)
            % GETSLICE - Return slice [H W C] at depth z, frame t (read from disk).
            if nargin < 3; t = 1; end
            raw   = obj.readRaw(z, t);
            slice = reshape(raw, obj.SliceSize(1), obj.SliceSize(2), obj.NumChannels);
        end
    end

    methods (Access = private)
        function raw = readRaw(obj, z, t)
            % READRAW - One getData call for a single level-slice z, frame t.
            % Map the level-slice index to a full-resolution z coordinate, since
            % getData interprets options.z in full-resolution coordinates.
            zFull = (z - 1) * obj.ZScale + 1;
            opt.pyramidLevel = obj.Level;
            opt.z = [zFull zFull];
            if obj.NumFrames > 1; opt.t = [t t]; end
            raw = obj.Source.getData(obj.LayerType, 3, obj.ColChannel, opt);
        end
    end
end
