classdef MibBigDataImage < core.MibVirtualImage
% MIBBIGDATAIMAGE - BigData image class for MIB3 — on-demand reader for pyramidal, chunked datasets.
%
% Subclass of ``core.MibVirtualImage``. It inherits the full on-demand
% read machinery (``getData`` → ``getDataZarr`` / ``getDataVirt``,
% ``getOrCreateLoader``, ``closeVirtualDataset``) and adds the BigData
% identity used by ``core.MibDataset`` (``datasetType = 'BigData'``).
%
% **Why a subclass of MibVirtualImage?**
%   For browsing, BigData reads are identical to the Virtual zarr path —
%   both stream sub-regions from a multi-resolution OME-Zarr v3 pyramid.
%   What BigData adds on top (a disk-backed, writable, pyramidal
%   segmentation model via ``io.adapters.ZarrBlockedAdapter``, copy-or-
%   modify image edits, and a Zarr3 saver) lives in ``core.MibDataset`` /
%   ``core.MibBigDataLabels`` rather than in the image reader. Keeping the
%   image reader as a thin subclass means ``isa(obj, 'core.MibVirtualImage')``
%   stays true, so reader-cleanup paths (e.g. ``closeVirtualDataset``)
%   work unchanged.
%
% **Type marker:** ``obj.type = 'bigdata'`` (the parent sets ``'virtual'``).

    methods
        function obj = MibBigDataImage(data, meta)
            % MIBBIGDATAIMAGE - obj = MibBigDataImage(data, meta).
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = MibBigDataImage(data, meta)
            %
            % Constructor — delegates to MibVirtualImage (which performs the
            % virtual initialise and populates pyramid / Virtual structs from
            % meta) then marks the image as a BigData reader.
            %
            % Input Arguments:
            %   - **data** — ignored for pixel storage; pass [] for a blank
            %     placeholder, or a cell array of path string(s) to a dataset
            %   - **meta** — metadata dictionary, passed to the parent constructor

            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; data = []; end

            obj = obj@core.MibVirtualImage(data, meta);

            % mark type (parent set it to 'virtual')
            obj.type = 'bigdata';
        end
    end
end
