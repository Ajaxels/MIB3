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
            % MIBBIGDATAIMAGE - Construct a BigData image reader from a metadata dictionary.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = core.MibBigDataImage(data, meta)
            %      obj = core.MibBigDataImage([], meta)
            %
            % Delegates to ``core.MibVirtualImage``, which opens the zarr store,
            % populates ``obj.pyramid`` (``levelNames``, ``levelImageSizes``,
            % ``levelScaleFactors``, ``chunkSizes``, ``axisOrder``) from the OME-NGFF
            % ``multiscales`` metadata, and sets up the reader handle.  This constructor
            % then overrides ``obj.type`` to ``'bigdata'`` so ``MibDataset`` routes label
            % and export paths correctly.
            %
            % Input Arguments:
            %   - **data** *(optional)* — [cell | empty] cell array of file path string(s)
            %     to the zarr3 dataset, or ``[]`` for a placeholder object with no open store.
            %   - **meta** *(optional)* — [dictionary] metadata dictionary produced by a
            %     setup loader (e.g. ``io.loaders.BioFormatsVirtualSetupLoader`` or
            %     ``io.loaders.Zarr3VirtualSetupLoader``).  Default: empty ``MibImage`` info.
            %
            % **Example** — open a previously converted OME-Zarr pyramid as BigData:
            %
            %   .. code-block:: matlab
            %
            %      opts = struct('datasetMode', 'BigData', 'silentMode', true, ...
            %                    'mibPath', 'C:\MIB3\mib', 'ParentFigure', []);
            %      loader = io.loaders.Zarr3VirtualSetupLoader(opts);
            %      [meta, filelist] = loader.loadMetadata({'C:\data\slide.zarr3'}, opts);
            %      [imgInfo, meta]  = loader.loadImages(filelist, meta, opts);
            %      obj = core.MibBigDataImage(imgInfo, meta);
            %      % obj.type == 'bigdata';  obj.pyramid.levelNames has N level paths

            if nargin < 2; meta = core.MibImage.initializeImgInfo(); end
            if nargin < 1; data = []; end

            obj = obj@core.MibVirtualImage(data, meta);

            % mark type (parent set it to 'virtual')
            obj.type = 'bigdata';
        end
    end
end
