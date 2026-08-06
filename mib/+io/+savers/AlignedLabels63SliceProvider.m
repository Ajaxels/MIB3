classdef AlignedLabels63SliceProvider < io.savers.SliceProvider
% ALIGNEDLABELS63SLICEPROVIDER - Streams warped packed-63 label slices for BigData alignment.
%
% Reads each full-resolution (level-0) packed ``'everything'`` slice from a
% source ``core.MibBigDataLabels`` store, warps it with nearest-neighbour
% interpolation (``FillValues = 0``) into the aligned output canvas, and returns
% the placed slice. Nearest-neighbour copies whole bytes, so the material bits
% (1-6), mask bit (7), and selection bit (8) transport together with no
% averaging.
%
% .. note::
%    Labels are NOT written through ``saveStream`` in the Phase 1 design - the
%    packed pyramid must go through the ``MibBigDataLabels`` materialize /
%    level-map path so bit semantics and coarse levels stay correct. This
%    provider exists for symmetry / potential reuse; the apply pipeline may
%    warp packed labels inline instead. Decided during Phase 1 implementation.
%
% See also: io.savers.SliceProvider, core.MibBigDataLabels,
% controllers.Alignment.applyAlignmentBigData

    properties
        sourceLabels    % source core.MibBigDataLabels handle
        tforms          % {depth x 1} cell of level-0 affine transforms (one per slice)
        outputView      % imref2d for the output canvas [newH0 newW0]
    end

    methods
        function obj = AlignedLabels63SliceProvider(varargin)
            % ALIGNEDLABELS63SLICEPROVIDER - Construct the provider.
            %
            % STUB - Phase 0. Fully implemented in Phase 1
            % (see development/bigdata/alignment_plan.md).
        end

        function slice = getSlice(obj, z, t) %#ok<INUSD,STOUT>
            % GETSLICE - Return the warped packed-63 slice [Height, Width, 1].
            %
            % STUB - Phase 0. Implemented in Phase 1.
            error('io:savers:AlignedLabels63SliceProvider:notImplemented', ...
                'AlignedLabels63SliceProvider.getSlice is not implemented yet (Phase 1).');
        end
    end
end
