classdef InMemorySliceProvider < io.savers.SliceProvider
% INMEMORYSLICEPROVIDER - SliceProvider backed by a resident 5-D array.
%
% Wraps an in-memory ``[Height, Width, Depth, Colors, Time]`` array so that a
% streaming saver (``io.savers.BaseSaver.saveStream``) can pull it slice-by-slice.
% Used by the default ``BaseSaver.save`` wrapper so that callers passing a full
% array keep working, and as a test double for ``saveStream`` without a live
% out-of-core dataset.
%
% See also: io.savers.SliceProvider, io.savers.BaseSaver
%
% **Example** - wrap a resident volume and stream it through a saver:
%
%   .. code-block:: matlab
%
%      data     = uint8(rand(256, 256, 40, 1, 1) * 255);   % [H W D C T]
%      provider = io.savers.InMemorySliceProvider(data);
%      provider.NumSlices                                  % == 40
%      slice = provider.getSlice(10, 1);                   % [256 256 1]
%      meta  = struct('colorType','grayscale','dataClass','uint8','imageDescription','');
%      saver = io.SaverFactory.create('TIF format uncompressed (*.tif)');
%      saver.saveStream(provider, meta, 'C:\out\stack.tif', struct('silent',true));

    properties (Access = private)
        Data    % [H W D C T] resident array
    end

    methods
        function obj = InMemorySliceProvider(data)
            % INMEMORYSLICEPROVIDER - Wrap a resident [H W D C T] array.
            %
            % Input Arguments:
            %   - **data** - numeric array, MIB3 native order ``[H, W, D, C, T]``
            %     (trailing singleton dimensions are allowed and assumed = 1).
            sz = ones(1, 5);
            d  = size(data);
            sz(1:numel(d)) = d;
            obj.Data        = data;
            obj.OutputSize  = sz;
            obj.DataClass   = class(data);
            obj.SliceSize   = sz(1:2);
            obj.NumSlices   = sz(3);
            obj.NumChannels = sz(4);
            obj.NumFrames   = sz(5);
        end

        function slice = getSlice(obj, z, t)
            % GETSLICE - Return slice [H W C] at depth z, frame t.
            if nargin < 3; t = 1; end
            slice = reshape(obj.Data(:, :, z, :, t), ...
                obj.SliceSize(1), obj.SliceSize(2), obj.NumChannels);
        end
    end
end
