classdef OmeZarrMetadataUtils
% OMEZARRMETADATAUTILS - Version-agnostic OME-NGFF metadata helpers shared by zarr v2/v3 loaders.
%
% Static utility methods factored out of ``Zarr3VirtualSetupLoader`` /
% ``Zarr3VirtualLoader`` so ``Zarr2VirtualSetupLoader`` / ``Zarr2VirtualLoader``
% can reuse the same OME-NGFF multiscales/axes/coordinateTransformations parsing
% and the zarr-C-order -> MIB3 ``[y,x,z,c,t]`` permutation logic, without a second
% copy of this logic. Everything here operates on already-parsed JSON (structs) or
% plain numeric/char values, so it has no dependency on which zarr format version
% (v2 ``.zattrs``/``.zarray`` or v3 ``zarr.json``) produced the metadata.
%
% Things that genuinely differ per zarr version (root-metadata file detection,
% per-level array metadata file format/location, dtype-string convention) are
% NOT here - they stay local to each version-specific loader.

methods (Static)
    function ms = extractMultiscales(attrs)
        % EXTRACTMULTISCALES - Extract the multiscales array from zarr attributes.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      ms = io.loaders.OmeZarrMetadataUtils.extractMultiscales(attrs)
        %
        % Handles two OME-NGFF versions:
        % v0.4: attrs.multiscales (top-level)
        % v0.5: attrs.ome.multiscales (nested under "ome" namespace)
        %
        % Returns the multiscales struct array, or ``[]`` if not found.

        ms = [];
        if isfield(attrs, 'multiscales') && ~isempty(attrs.multiscales)
            ms = attrs.multiscales;
        elseif isfield(attrs, 'ome') && isstruct(attrs.ome) && ...
                isfield(attrs.ome, 'multiscales') && ~isempty(attrs.ome.multiscales)
            ms = attrs.ome.multiscales;
        end
    end

    function axisOrder = extractAxisOrder(ms)
        % EXTRACTAXISORDER - Extract axis order string (e.g. ``'tczyx'``) from multiscales entry.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      axisOrder = io.loaders.OmeZarrMetadataUtils.extractAxisOrder(ms)
        %

        axisOrder = 'tczyx'; % OME-Zarr default if not specified
        if ~isfield(ms, 'axes') || isempty(ms.axes)
            return;
        end
        try
            axes = ms.axes;
            if isstruct(axes)
                names = {axes.name};
            elseif iscell(axes)
                names = cellfun(@(a) a.name, axes, 'UniformOutput', false);
            else
                return;
            end
            axisOrder = lower(strjoin(names, ''));
        catch
            % leave default
        end
    end

    function labels = axisOrderToLabels(axisOrder)
        % AXISORDERTOLABELS - Convert axis order string to cell array of single-char labels.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      labels = io.loaders.OmeZarrMetadataUtils.axisOrderToLabels(axisOrder)
        %

        labels = num2cell(lower(char(axisOrder)));
    end

    function scales = extractScaleFromCT(ct, nAxes)
        % EXTRACTSCALEFROMCT - Extract physical scale vector from an OME-Zarr coordinateTransformations.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      scales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT(ct, nAxes)
        %
        % The returned vector has length nAxes and is aligned to the axis
        % order declared in multiscales.axes (C-order, e.g. [t,c,z,y,x]).
        % Missing leading axes (t, c) default to 1.0.
        %
        % Input Arguments:
        %   - **ct** - coordinateTransformations value from zarr metadata;
        %     may be a struct array or cell array of transform objects
        %   - **nAxes** - [numeric] number of axes declared in multiscales.axes
        %     (equals the length of the desired output vector)
        %
        % Output Arguments:
        %   - **scales** - [1 x nAxes numeric] vector in axisLabels order;
        %     for ``'tczyx'`` (nAxes=5): index 1=t, 2=c, 3=z, 4=y, 5=x
        %
        % Alignment rule when CT provides fewer values than nAxes:
        % In OME-Zarr, non-spatial axes (t, c) come BEFORE spatial axes
        % (z, y, x) and typically have scale=1. So a 3-element CT scale
        % [0.03, 0.13, 0.13] for a 'tczyx' dataset means [z, y, x] - the
        % values belong at the END of the output vector:
        %   scales = [1, 1, 0.03, 0.13, 0.13]
        % This is why values are right-aligned, not left-aligned.
        %

        scales = ones(1, nAxes);
        try
            % Normalise ct to a flat row vector sc
            sc = [];
            if isstruct(ct) && ~isempty(ct)
                for k = 1:numel(ct)
                    if strcmp(ct(k).type, 'scale')
                        sc = ct(k).scale;
                        break;
                    end
                end
            elseif iscell(ct)
                for k = 1:numel(ct)
                    entry = ct{k};
                    if isfield(entry, 'type') && strcmp(entry.type, 'scale')
                        sc = entry.scale;
                        break;
                    end
                end
            end

            if isempty(sc); return; end

            % Flatten to row vector
            if iscell(sc)
                sc = cell2mat(sc(:)');
            else
                sc = sc(:)';
            end

            nSc = numel(sc);
            if nSc == nAxes
                % Exact match: values are already in axisLabels order
                scales = sc;
            elseif nSc < nAxes
                % Fewer CT values than axes - right-align so spatial axes
                % (z, y, x at the end) receive the physical scale values.
                % Non-spatial leading axes (t, c) remain 1.0.
                scales(end - nSc + 1 : end) = sc;
            else
                % More CT values than declared axes (non-standard).
                % Take the last nAxes values (spatial axes are at the end).
                scales = sc(end - nAxes + 1 : end);
            end
        catch
            % Return default ones on any parsing failure
        end
    end

    function unit = extractAxisUnit(ms, yIdx)
        % EXTRACTAXISUNIT - Extract physical unit string from the Y axis definition.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      unit = io.loaders.OmeZarrMetadataUtils.extractAxisUnit(ms, yIdx)
        %

        unit = 'um'; % default
        if ~isfield(ms, 'axes') || isempty(ms.axes) || isempty(yIdx)
            return;
        end
        try
            axes = ms.axes;
            if isstruct(axes)
                ax = axes(yIdx);
            elseif iscell(axes)
                ax = axes{yIdx};
            else
                return;
            end
            if isfield(ax, 'unit') && ~isempty(ax.unit)
                rawUnit = lower(ax.unit);
                % normalise common spellings to MIB3 conventions
                switch rawUnit
                    case {'micrometer', 'micron', 'um', 'µm'}
                        unit = 'um';
                    case {'nanometer', 'nm'}
                        unit = 'nm';
                    case {'millimeter', 'mm'}
                        unit = 'mm';
                    otherwise
                        unit = rawUnit;
                end
            end
        catch
            % leave default
        end
    end

    function v = safeGetDim(shape, idx, default)
        % SAFEGETDIM - Return shape(idx) or default if idx is empty or out of range.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      v = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, idx, default)
        %

        if isempty(idx) || idx > numel(shape)
            v = default;
        else
            v = shape(idx);
        end
    end

    function v = safeGetScale(scales, idx, default)
        % SAFEGETSCALE - Return scales(idx) or default if idx is empty or out of range.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      v = io.loaders.OmeZarrMetadataUtils.safeGetScale(scales, idx, default)
        %

        if isempty(idx) || isempty(scales) || idx > numel(scales)
            v = default;
        else
            v = scales(idx);
        end
    end

    function r = safeRatio(levelScales, idx, level0Scales)
        % SAFERATIO - Compute levelScales(idx) / level0Scales(idx), returning 1 on failure.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      r = io.loaders.OmeZarrMetadataUtils.safeRatio(levelScales, idx, level0Scales)
        %

        if isempty(idx) || isempty(level0Scales) || idx > numel(level0Scales) ...
                || level0Scales(idx) == 0
            r = 1;
        else
            r = levelScales(idx) / level0Scales(idx);
        end
    end

    function mx = classMaxInt(imgClass)
        % CLASSMAXINT - Maximum intensity value for the given MATLAB class.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      mx = io.loaders.OmeZarrMetadataUtils.classMaxInt(imgClass)
        %

        switch imgClass
            case {'uint8','uint16','uint32','uint64','int8','int16','int32','int64'}
                mx = double(intmax(imgClass));
            case {'single','double'}
                mx = 1;
            otherwise
                mx = 255;
        end
    end

    function ct = colorType(nColors)
        % COLORTYPE - 'grayscale' for a single colour channel, else 'multichannel'.
        if nColors == 1
            ct = 'grayscale';
        else
            ct = 'multichannel';
        end
    end

    function vp = buildViewPort(nColors, maxInt)
        % BUILDVIEWPORT - Default per-channel display viewport (min/max/gamma).
        vp.min   = zeros(1, nColors);
        vp.max   = repmat(maxInt, 1, nColors);
        vp.gamma = ones(1, nColors);
    end

    function [names, colors] = resolveMaterialMetadata(attrs)
        % RESOLVEMATERIALMETADATA - Resolve model material names/colors from an
        % already-parsed zarr attributes struct (version-agnostic - the caller
        % is responsible for reading/merging the actual root+level attrs, since
        % that differs between v2 (``.zattrs`` file per group/array) and v3
        % (``zarr.json``'s nested ``attributes`` key)).
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [names, colors] = io.loaders.OmeZarrMetadataUtils.resolveMaterialMetadata(attrs)
        %
        % Checks two conventions, in order:
        %
        %   1. MIB's own ``mibMaterials`` attribute (the same shape
        %      ``Zarr3Saver.exportModel`` / ``MibBigDataLabels.writeMaterialMetadata``
        %      write): ``{materialNames, materialColors}``.
        %   2. OME-NGFF ``image-label`` convention: ``colors`` (label-value/rgba
        %      pairs) and ``properties`` (label-value/name pairs). MATLAB's
        %      ``jsondecode`` sanitises hyphenated JSON keys into underscores
        %      (``image-label`` -> ``image_label``, ``label-value`` ->
        %      ``label_value``) - both spellings are checked defensively.
        %
        % Input Arguments:
        %   - **attrs** - [struct] parsed zarr attributes (root group and/or
        %     array level, already merged by the caller if both apply).
        %
        % Output Arguments:
        %   - **names** - {1 x N cell} material name strings, or ``{}`` if neither
        %     convention is present (callers then fall back to auto-generated names).
        %   - **colors** - [N x 3 numeric] RGB colors in ``[0,1]``, or ``[]``.

        names  = {};
        colors = [];

        % 1. MIB's own convention
        if isfield(attrs, 'mibMaterials')
            mm = attrs.mibMaterials;
            if isfield(mm, 'materialNames') && ~isempty(mm.materialNames)
                n = mm.materialNames;
                if ischar(n); n = {n}; end
                if iscell(n); names = n(:)'; end
            end
            if isfield(mm, 'materialColors') && ~isempty(mm.materialColors) && isnumeric(mm.materialColors)
                colors = double(mm.materialColors);
                if size(colors, 2) ~= 3 && size(colors, 1) == 3; colors = colors.'; end
            end
            if ~isempty(names) || ~isempty(colors); return; end
        end

        % 2. OME-NGFF image-label convention
        ilKey = '';
        if isfield(attrs, 'image_label'); ilKey = 'image_label';
        elseif isfield(attrs, 'image-label'); ilKey = 'image-label'; end
        if isempty(ilKey); return; end
        il = attrs.(ilKey);

        lvKey = 'label_value';

        labelValues = [];
        if isfield(il, 'colors') && ~isempty(il.colors) && isstruct(il.colors)
            colorEntries = il.colors;
            nEntries     = numel(colorEntries);
            labelValues  = zeros(1, nEntries);
            colors       = zeros(nEntries, 3);
            for k = 1:nEntries
                entry = colorEntries(k);
                if isfield(entry, lvKey)
                    labelValues(k) = entry.(lvKey);
                elseif isfield(entry, 'label-value')
                    labelValues(k) = entry.('label-value');
                end
                if isfield(entry, 'rgba') && numel(entry.rgba) >= 3
                    colors(k, :) = double(entry.rgba(1:3)) / 255;
                end
            end
        end

        if isfield(il, 'properties') && ~isempty(il.properties) && isstruct(il.properties) && ~isempty(labelValues)
            propEntries = il.properties;
            names = cell(1, numel(labelValues));
            for k = 1:numel(labelValues)
                names{k} = num2str(labelValues(k)); % fallback if no matching name property
                for p = 1:numel(propEntries)
                    pv = propEntries(p);
                    if isfield(pv, lvKey)
                        pvVal = pv.(lvKey);
                    elseif isfield(pv, 'label-value')
                        pvVal = pv.('label-value');
                    else
                        continue;
                    end
                    if pvVal == labelValues(k) && isfield(pv, 'name')
                        names{k} = char(pv.name);
                        break;
                    end
                end
            end
        end
    end

    function perm = computePermutation(axisOrder)
        % COMPUTEPERMUTATION - Compute the permutation from zarr C-order output to MIB3 [y,x,z,c,t].
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      perm = io.loaders.OmeZarrMetadataUtils.computePermutation(axisOrder)
        %
        % A zarr array read via the native (zarrMex) or python backend is returned
        % in zarr's declared C-order axis layout. For OME-Zarr with axisOrder
        % ``'czyx'`` (shape [nC,nZ,nY,nX]), the returned MATLAB array has size
        % [nC, nZ, nY, nX] where dim 1 = C, dim 2 = Z, dim 3 = Y, dim 4 = X.
        % This function computes the permutation that maps that to MIB3's
        % required [y, x, z, c, t] order.
        %
        % Input Arguments:
        %   - **axisOrder** - [char] zarr C-order axis declaration,
        %     e.g. ``'czyx'`` or ``'tczyx'``
        %
        % Output Arguments:
        %   - **perm** - [1x5 numeric] permutation for ``permute(raw, perm)`` → [y,x,z,c,t]
        %
        % **Example** - permutation for common axis orders:
        %
        %   .. code-block:: matlab
        %
        %      perm = io.loaders.OmeZarrMetadataUtils.computePermutation('czyx');   % [3,4,2,1,5]
        %      perm = io.loaders.OmeZarrMetadataUtils.computePermutation('tczyx');  % [4,5,3,2,1]
        %      perm = io.loaders.OmeZarrMetadataUtils.computePermutation('zyx');    % [2,3,1,4,5]
        %

        mib3Axes      = 'yxzct';     % MIB3 dimension order (dims 1-5)
        nDims         = numel(axisOrder);
        perm          = zeros(1, 5);
        nextSingleton = nDims + 1;

        for k = 1:5
            ax  = mib3Axes(k);
            pos = strfind(axisOrder, ax);   % find in C-order declaration
            if ~isempty(pos)
                perm(k) = pos(1);
            else
                % axis absent in this dataset -> trailing singleton slot
                perm(k)       = nextSingleton;
                nextSingleton = nextSingleton + 1;
            end
        end
    end
end
end
