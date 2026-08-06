classdef (Abstract) SliceProvider < handle
% SLICEPROVIDER - Abstract per-slice source for streaming savers.
%
% A ``SliceProvider`` lets a saver write a dataset **one Z-slice at a time** so
% that the full volume is never held in memory. It is the input to
% ``io.savers.BaseSaver.saveStream`` and is the single abstraction that keeps the
% save layer **backend-neutral**: the saver only ever asks for shape metadata and
% individual slices and never knows whether the pixels come from a resident array,
% an OME-Zarr pyramid, or a future BioFormats / OpenSlide reader.
%
% **Shape convention.** All sizes follow MIB3 native order
% ``[Height, Width, Depth, Colors, Time]``. ``getSlice(z, t)`` returns a single
% slice as ``[Height, Width, Colors]`` (a grayscale slice is ``[Height, Width, 1]``).
%
% Concrete implementations:
%   - ``io.savers.InMemorySliceProvider`` - slices a resident 5-D array.
%   - ``io.savers.MibImageSliceProvider`` - reads slices on demand from any
%     ``core.MibImage`` subclass (image or label object) at a chosen pyramid level
%     via the polymorphic ``getData`` (``options.pyramidLevel`` + ``options.z``).
%
% See also: io.savers.BaseSaver, io.savers.InMemorySliceProvider,
% io.savers.MibImageSliceProvider
%
% **Example** - a saver consuming a provider slice-by-slice (memory ≈ one slice):
%
%   .. code-block:: matlab
%
%      % provider is any io.savers.SliceProvider subclass
%      sz = provider.OutputSize;          % [H W D C T]
%      for t = 1:provider.NumFrames
%          for z = 1:provider.NumSlices
%              slice = provider.getSlice(z, t);   % [H W C]
%              % ... write slice to the output file/stream ...
%          end
%      end

    properties
        OutputSize  (1,5) double = [0 0 0 0 0]
        % [1x5] full output dimensions ``[Height, Width, Depth, Colors, Time]``.
        DataClass   (1,:) char   = 'uint8'
        % [char] numeric class of the returned slices (e.g. ``'uint8'``, ``'uint16'``).
        NumSlices   (1,1) double = 0
        % [double] number of Z-slices (Depth).
        NumChannels (1,1) double = 1
        % [double] number of colour channels.
        NumFrames   (1,1) double = 1
        % [double] number of time frames.
        SliceSize   (1,2) double = [0 0]
        % [1x2] single-slice dimensions ``[Height, Width]``.
    end

    methods (Abstract)
        slice = getSlice(obj, z, t)
        % GETSLICE - Return one Z-slice ``[Height, Width, Colors]`` at depth ``z``, frame ``t``.
    end
end
