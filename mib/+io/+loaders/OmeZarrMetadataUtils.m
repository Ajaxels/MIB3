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
%
% The one exception is the nested-container search (``findMultiscalesGroups``
% and its helpers): it has to touch the filesystem and therefore takes a
% ``zarrFormat`` argument, but the walk itself is identical for v2 and v3, so a
% single copy shared by both loaders is preferable to two that drift apart.

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
        % values belong at the END of the output vector, i.e.
        % ``scales = [1, 1, 0.03, 0.13, 0.13]``.
        % This is why values are right-aligned, not left-aligned.
        %

        scales = io.loaders.OmeZarrMetadataUtils.extractCTVector(ct, nAxes, 'scale', 1);
    end

    function translations = extractTranslationFromCT(ct, nAxes)
        % EXTRACTTRANSLATIONFROMCT - Extract the physical origin offset from an OME-Zarr coordinateTransformations.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      translations = io.loaders.OmeZarrMetadataUtils.extractTranslationFromCT(ct, nAxes)
        %
        % Mirror of :meth:`extractScaleFromCT` for the ``translation`` transform,
        % with the same axis alignment rule. The default is **zeros**, not ones:
        % a store that declares no translation sits at the origin, which is what
        % every store MIB has read so far does, so this must stay a no-op for
        % them.
        %
        % **Translations are pixel-centre based**, i.e.
        % ``world_centre(i) = translation + i * scale`` for a 0-based index
        % ``i``. That is not an assumption - it is visible inside a pyramid: the
        % OpenOrganelle ``jrc_hela-2`` EM volume declares ``translation``
        % ``[0, 0, 0]`` at ``s0`` and ``[2.62, 2, 2]`` at ``s1``, which is
        % exactly half of ``s1``'s scale, i.e. where the centre of the first
        % coarse voxel falls. It is also the convention
        % ``core.MibImage.updateBoundingBox`` uses, where the extent is
        % ``(dim-1) * pixSize`` - centre of first voxel to centre of last - so
        % the two map onto each other with no half-voxel correction.
        %
        % Input Arguments:
        %   - **ct** - coordinateTransformations value from zarr metadata;
        %     may be a struct array or cell array of transform objects
        %   - **nAxes** - [numeric] number of axes declared in multiscales.axes
        %
        % Output Arguments:
        %   - **translations** - [1 x nAxes numeric] offsets in axisLabels order,
        %     in the axis unit declared by the store; all zeros when absent

        translations = io.loaders.OmeZarrMetadataUtils.extractCTVector(ct, nAxes, 'translation', 0);
    end

    function values = extractCTVector(ct, nAxes, transformType, defaultValue)
        % EXTRACTCTVECTOR - Pull one named transform out of a coordinateTransformations list.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      values = io.loaders.OmeZarrMetadataUtils.extractCTVector(ct, nAxes, transformType, defaultValue)
        %
        % Shared implementation behind :meth:`extractScaleFromCT` and
        % :meth:`extractTranslationFromCT` - the parsing, flattening and
        % right-alignment rules are identical for both and only the transform
        % name and the neutral value differ.
        %
        % Input Arguments:
        %   - **ct** - coordinateTransformations value; struct array or cell array
        %   - **nAxes** - [numeric] number of declared axes
        %   - **transformType** - [char] ``'scale'`` or ``'translation'``
        %   - **defaultValue** - [numeric] neutral value for absent axes
        %     (1 for a scale, 0 for a translation)
        %
        % Output Arguments:
        %   - **values** - [1 x nAxes numeric] in axisLabels order

        values = repmat(defaultValue, 1, nAxes);
        try
            % Normalise ct to a flat row vector
            raw = [];
            if isstruct(ct) && ~isempty(ct)
                for k = 1:numel(ct)
                    if strcmp(ct(k).type, transformType) && isfield(ct, transformType)
                        raw = ct(k).(transformType);
                        break;
                    end
                end
            elseif iscell(ct)
                for k = 1:numel(ct)
                    entry = ct{k};
                    if isfield(entry, 'type') && strcmp(entry.type, transformType) ...
                            && isfield(entry, transformType)
                        raw = entry.(transformType);
                        break;
                    end
                end
            end

            if isempty(raw); return; end

            % Flatten to row vector
            if iscell(raw)
                raw = cell2mat(raw(:)');
            else
                raw = raw(:)';
            end

            nRaw = numel(raw);
            if nRaw == nAxes
                % Exact match: values are already in axisLabels order
                values = raw;
            elseif nRaw < nAxes
                % Fewer CT values than axes - right-align so spatial axes
                % (z, y, x at the end) receive the physical values.
                % Non-spatial leading axes (t, c) keep the neutral value.
                values(end - nRaw + 1 : end) = raw;
            else
                % More CT values than declared axes (non-standard).
                % Take the last nAxes values (spatial axes are at the end).
                values = raw(end - nAxes + 1 : end);
            end
        catch
            % Return the neutral vector on any parsing failure
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

    function factor = unitToMicrometreFactor(unit)
        % UNITTOMICROMETREFACTOR - Multiplier converting a length in ``unit`` to micrometres.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      factor = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(unit)
        %
        % Same table ``core.MibImage.updateBoundingBox`` uses, kept here so a
        % loader can convert a region expressed in micrometres into the unit its
        % store declares without depending on a MibImage instance. An unknown
        % unit gives 1, i.e. "assume it is already micrometres", which is the
        % same fallback MibImage takes.
        %
        % Input Arguments:
        %   - **unit** - [char] unit string as normalised by :meth:`extractAxisUnit`
        %
        % Output Arguments:
        %   - **factor** - [numeric] multiply a value in ``unit`` by this to get um

        switch lower(char(unit))
            case 'm';  factor = 1e6;
            case 'cm'; factor = 1e4;
            case 'mm'; factor = 1e3;
            case 'um'; factor = 1;
            case 'nm'; factor = 1e-3;
            otherwise; factor = 1;
        end
    end

    function boundingBox = worldBoundingBox(multiscale, levelIndex, shape)
        % WORLDBOUNDINGBOX - Physical extent of one pyramid level, from its coordinateTransformations.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      boundingBox = io.loaders.OmeZarrMetadataUtils.worldBoundingBox(multiscale, levelIndex, shape)
        %
        % Returns ``[xmin xmax ymin ymax zmin zmax]`` in the axis unit the store
        % declares - the same unit :meth:`extractAxisUnit` reports and the same
        % one the derived ``pixSize`` is in. **Not** forced to micrometres,
        % deliberately: MIB's own default box is ``(dim-1) * pixSize`` in
        % ``pixSize.units`` (``core.MibImage.initialize``), so returning store
        % units is what keeps a derived box interchangeable with the default one.
        % Convert with :meth:`unitToMicrometreFactor` where absolute units are
        % needed.
        %
        % Pixel-centre convention throughout, matching both OME-NGFF and
        % ``core.MibImage.updateBoundingBox``: the box runs from the centre of
        % the first voxel to the centre of the last, so the extent of ``n``
        % voxels is ``(n-1) * scale`` and **not** ``n * scale``. See
        % :meth:`extractTranslationFromCT` for why that convention is not a guess.
        %
        % A store that declares no translation lands at the origin, which is
        % exactly what every store MIB read before this existed did - so
        % deriving a box is safe for them and changes nothing.
        %
        % A one-voxel axis is given the extent of two voxels, matching the
        % ``max([dim 2])`` tweak in ``core.MibImage.updateBoundingBox``. That
        % keeps a derived box drop-in interchangeable with MIB's default one -
        % without it a single-slice store would report a zero-thickness Z and
        % the next ``updateBoundingBox`` would divide it back into ``pixSize.z = 0``.
        %
        % Input Arguments:
        %   - **multiscale** - [struct] a single entry of the ``multiscales``
        %     array, i.e. ``ms(1)`` where ``ms = extractMultiscales(attrs)``
        %   - **levelIndex** - [numeric] 1-based index into ``multiscale.datasets``
        %   - **shape** - [1xN numeric] the level's zarr ``shape``, C-order, so
        %     its indices line up with ``multiscale.axes``
        %
        % Output Arguments:
        %   - **boundingBox** - [1x6 numeric] ``[xmin xmax ymin ymax zmin zmax]``;
        %     ``[]`` when the metadata is not usable (no datasets, index out of
        %     range), which callers must treat as "leave the box alone"

        boundingBox = [];
        if isempty(multiscale) || ~isfield(multiscale, 'datasets'); return; end
        if levelIndex < 1 || levelIndex > numel(multiscale.datasets); return; end

        axisOrder  = io.loaders.OmeZarrMetadataUtils.extractAxisOrder(multiscale);
        axisLabels = io.loaders.OmeZarrMetadataUtils.axisOrderToLabels(axisOrder);
        nAxes      = numel(axisLabels);

        % The multiscales-level transform applies to the whole pyramid and is
        % composed AFTER the per-dataset one, hence
        % world = globalScale .* (levelScale .* index + levelTranslation) + globalTranslation.
        globalScales       = ones(1, nAxes);
        globalTranslations = zeros(1, nAxes);
        if isfield(multiscale, 'coordinateTransformations')
            globalScales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT( ...
                multiscale.coordinateTransformations, nAxes);
            globalTranslations = io.loaders.OmeZarrMetadataUtils.extractTranslationFromCT( ...
                multiscale.coordinateTransformations, nAxes);
        end

        levelScales       = globalScales;
        levelTranslations = globalTranslations;
        dataset = multiscale.datasets(levelIndex);
        if isfield(dataset, 'coordinateTransformations')
            levelScales = io.loaders.OmeZarrMetadataUtils.extractScaleFromCT( ...
                dataset.coordinateTransformations, nAxes) .* globalScales;
            levelTranslations = io.loaders.OmeZarrMetadataUtils.extractTranslationFromCT( ...
                dataset.coordinateTransformations, nAxes) .* globalScales + globalTranslations;
        end

        boundingBox = zeros(1, 6);
        spatialAxes = {'x', 'y', 'z'};
        for axisIndex = 1:3
            axisPosition = find(strcmp(axisLabels, spatialAxes{axisIndex}), 1);
            nVoxels = io.loaders.OmeZarrMetadataUtils.safeGetDim(shape, axisPosition, 1);
            origin  = io.loaders.OmeZarrMetadataUtils.safeGetScale(levelTranslations, axisPosition, 0);
            step    = io.loaders.OmeZarrMetadataUtils.safeGetScale(levelScales, axisPosition, 1);
            boundingBox(axisIndex*2 - 1) = origin;
            boundingBox(axisIndex*2)     = origin + (max([nVoxels, 2]) - 1) * step;
        end
    end

    function outerBox = outerBoundingBox(centreBox, voxelSizeXYZ)
        % OUTERBOUNDINGBOX - Convert a voxel-centre box into the outer physical extent.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      outerBox = io.loaders.OmeZarrMetadataUtils.outerBoundingBox(centreBox, voxelSizeXYZ)
        %
        % **The half-voxel here is the whole point of this function.** MIB's
        % ``boundingBox`` and OME-NGFF ``translation`` both address voxel
        % *centres*, so a box in that convention is half a voxel short at each
        % end of the volume's true physical extent. Any arithmetic that maps one
        % grid onto another - which is what a region read does - has to happen in
        % *edge* space, or it lands off by a fraction of a voxel and silently
        % shifts the result by one.
        %
        % Concretely, for the OpenOrganelle ``jrc_hela-2`` crop1: its first voxel
        % centre sits at ``x = 25863 nm`` on a 2 nm grid, and ``25863 / 4`` is
        % ``6465.75`` - not an integer, which reads as a misaligned store. Its
        % *edge* is at ``25862 nm``, and the EM 4 nm grid's own first edge is at
        % ``-2 nm``, so ``(25862 + 2) / 4 = 6466`` exactly. The grids do line up;
        % only the centre-space arithmetic hid it.
        %
        % Input Arguments:
        %   - **centreBox** - [1x6 numeric] ``[xmin xmax ymin ymax zmin zmax]``
        %     addressing the centres of the first and last voxel
        %   - **voxelSizeXYZ** - [1x3 numeric] voxel size ``[x y z]``, same units
        %
        % Output Arguments:
        %   - **outerBox** - [1x6 numeric] the same box grown by half a voxel at
        %     each end, i.e. the volume's true physical extent

        halfVoxel = reshape(double(voxelSizeXYZ), 1, 3) / 2;
        outerBox  = reshape(double(centreBox), 1, 6);
        outerBox([1 3 5]) = outerBox([1 3 5]) - halfVoxel;
        outerBox([2 4 6]) = outerBox([2 4 6]) + halfVoxel;
    end

    function [voxelRange, residual] = regionToVoxelRange(outerRegion, levelCentreBox, levelVoxelSizeXYZ, levelShapeXYZ)
        % REGIONTOVOXELRANGE - Which voxels of one pyramid level a world region covers.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [voxelRange, residual] = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange(outerRegion, levelCentreBox, levelVoxelSizeXYZ, levelShapeXYZ)
        %
        % **Rounds outward.** Grid alignment is a property of a particular store,
        % not of OME-NGFF: the 26 ``jrc_hela-2`` crops all land on integer EM
        % voxel bounds, but nothing in the spec promises that, and a store with a
        % half-voxel offset must produce a region one voxel too large rather than
        % labels shifted one voxel against the image. ``residual`` reports how
        % much was added so the caller can say so instead of assuming a clean fit.
        %
        % All arithmetic is in **edge** space - see :meth:`outerBoundingBox` for
        % why that is not interchangeable with centre space.
        %
        % Input Arguments:
        %   - **outerRegion** - [1x6 numeric] requested region
        %     ``[xmin xmax ymin ymax zmin zmax]``, edge-based, in the level's units
        %   - **levelCentreBox** - [1x6 numeric] the level's own world box,
        %     centre-based, from :meth:`worldBoundingBox`
        %   - **levelVoxelSizeXYZ** - [1x3 numeric] the level's voxel size ``[x y z]``
        %   - **levelShapeXYZ** - [1x3 numeric] the level's voxel counts ``[x y z]``
        %
        % Output Arguments:
        %   - **voxelRange** - [3x2 numeric] 1-based inclusive ``[first last]`` per
        %     row ``x``, ``y``, ``z``, clamped to the level; a row reads
        %     ``[1 0]`` when the region misses this level entirely
        %   - **residual** - [3x2 numeric] per axis, how far the selected extent
        %     overshoots the requested one at each end, in the level's units;
        %     zero on an exact fit, negative where clamping cut the region short

        % A voxel index that is a whole number in exact arithmetic can come back
        % as 597.9999999 after a divide, and floor() would then lose a voxel. One
        % part in a million of a voxel is far below any real grid offset and far
        % above the error a few divides introduce.
        gridTolerance = 1e-6;

        voxelSize = reshape(double(levelVoxelSizeXYZ), 1, 3);
        shape     = reshape(double(levelShapeXYZ), 1, 3);
        region    = reshape(double(outerRegion), 1, 6);

        % Edge of voxel 0 on this level's grid.
        gridOrigin = reshape(double(levelCentreBox([1 3 5])), 1, 3) - voxelSize / 2;

        regionLo = region([1 3 5]);
        regionHi = region([2 4 6]);

        firstIndex = floor((regionLo - gridOrigin) ./ voxelSize + gridTolerance);
        lastIndex  = ceil((regionHi - gridOrigin) ./ voxelSize - gridTolerance) - 1;

        clampedFirst = max(firstIndex, 0);
        clampedLast  = min(lastIndex, shape - 1);

        % Selected extent in edge space, for the residual report.
        selectedLo = gridOrigin + clampedFirst .* voxelSize;
        selectedHi = gridOrigin + (clampedLast + 1) .* voxelSize;
        residual   = [(regionLo - selectedLo)', (selectedHi - regionHi)'];

        voxelRange = [clampedFirst', clampedLast'] + 1;   % 1-based inclusive
        missesLevel = clampedLast < clampedFirst;
        voxelRange(missesLevel, :) = repmat([1 0], sum(missesLevel), 1);
        residual(missesLevel, :)   = 0;
    end

    function regionInfo = applyRegionToLevels(outerRegion, levelWorldBoxes, levelVoxelSizes, levelImageSizes)
        % APPLYREGIONTOLEVELS - Crop a whole pyramid to a world region.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      regionInfo = io.loaders.OmeZarrMetadataUtils.applyRegionToLevels(outerRegion, levelWorldBoxes, levelVoxelSizes, levelImageSizes)
        %
        % Each level is intersected with the region **independently**, on its own
        % grid, rather than by scaling level 0's answer. Levels are not obliged
        % to be exact multiples of one another, and dividing a voxel count by a
        % scale factor accumulates exactly the off-by-one this is trying to
        % avoid.
        %
        % Input Arguments:
        %   - **outerRegion** - [1x6 numeric] edge-based world box in the store's units
        %   - **levelWorldBoxes** - [nLevels x 6 numeric] each level's centre-based box
        %   - **levelVoxelSizes** - [nLevels x 3 numeric] voxel size per level, ``[y x z]``
        %   - **levelImageSizes** - [nLevels x 3 numeric] voxel counts per level, ``[y x z]``
        %
        % Output Arguments:
        %   - **regionInfo** - [struct] with fields:
        %
        %     - ``.levelImageSizes`` - [nLevels x 3] cropped voxel counts ``[y x z]``
        %     - ``.levelRegionOrigins`` - [nLevels x 3] 1-based first voxel ``[y x z]``
        %       within each level's own array; all ones means "no crop"
        %     - ``.levelWorldBoxes`` - [nLevels x 6] centre-based box of the crop per level
        %     - ``.residual`` - [3x2] level-0 overshoot per axis, see
        %       :meth:`regionToVoxelRange`
        %     - ``.isExact`` - [logical] true when level 0 fitted the grid with no overshoot

        nLevels            = size(levelImageSizes, 1);
        croppedSizes       = zeros(nLevels, 3);
        levelRegionOrigins = ones(nLevels, 3);
        croppedWorldBoxes  = zeros(nLevels, 6);
        residual           = zeros(3, 2);

        for levelIndex = 1:nLevels
            voxelSizeYXZ = levelVoxelSizes(levelIndex, :);
            shapeYXZ     = levelImageSizes(levelIndex, :);
            % regionToVoxelRange works in x,y,z; the pyramid tables are y,x,z.
            voxelSizeXYZ = voxelSizeYXZ([2 1 3]);
            shapeXYZ     = shapeYXZ([2 1 3]);

            [voxelRange, levelResidual] = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange( ...
                outerRegion, levelWorldBoxes(levelIndex, :), voxelSizeXYZ, shapeXYZ);
            if levelIndex == 1; residual = levelResidual; end

            countXYZ  = max(voxelRange(:, 2) - voxelRange(:, 1) + 1, 0)';
            originXYZ = voxelRange(:, 1)';

            croppedSizes(levelIndex, :)       = countXYZ([2 1 3]);
            levelRegionOrigins(levelIndex, :) = originXYZ([2 1 3]);

            % Centre-based box of the cropped extent: the centre of the first
            % kept voxel, out to the centre of the last.
            gridOrigin = levelWorldBoxes(levelIndex, [1 3 5]);
            firstCentre = gridOrigin + (originXYZ - 1) .* voxelSizeXYZ;
            lastCentre  = firstCentre + max(countXYZ - 1, 0) .* voxelSizeXYZ;
            croppedWorldBoxes(levelIndex, [1 3 5]) = firstCentre;
            croppedWorldBoxes(levelIndex, [2 4 6]) = lastCentre;
        end

        regionInfo = struct();
        regionInfo.levelImageSizes    = croppedSizes;
        regionInfo.levelRegionOrigins = levelRegionOrigins;
        regionInfo.levelWorldBoxes    = croppedWorldBoxes;
        regionInfo.residual           = residual;
        regionInfo.isExact            = all(abs(residual(:)) < 1e-9);
    end

    function requestedRegion = resolveRegionOption(options, loaderOptions)
        % RESOLVEREGIONOPTION - Pick up ``Region`` from the call or the loader's own options.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      requestedRegion = io.loaders.OmeZarrMetadataUtils.resolveRegionOption(options, loaderOptions)
        %
        % Same two-place lookup ``ZarrGroupPath`` already uses: a region can
        % arrive with the ``loadMetadata`` call or be baked into the loader at
        % construction (which is the route ``core.MibDataset.loadModel`` takes),
        % and either has to work.
        %
        % Input Arguments:
        %   - **options** - [struct] options passed to loadMetadata
        %   - **loaderOptions** - [struct] the loader's own ``obj.Options``
        %
        % Output Arguments:
        %   - **requestedRegion** - [1x6 numeric] region in um, or ``[]`` when
        %     neither source supplies a usable one

        requestedRegion = [];
        for candidate = {options, loaderOptions}
            source = candidate{1};
            if isstruct(source) && isfield(source, 'Region') && ~isempty(source.Region)
                value = reshape(double(source.Region), 1, []);
                if numel(value) == 6; requestedRegion = value; return; end
            end
        end
    end

    function requestedLevel = resolveLevelOption(options, loaderOptions, nLevels)
        % RESOLVELEVELOPTION - Pick up an explicit pyramid level, if one was given.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      requestedLevel = io.loaders.OmeZarrMetadataUtils.resolveLevelOption(options, loaderOptions, nLevels)
        %
        % Standard mode normally asks which level to read. ``ZarrLevel`` answers
        % that in advance, and it is not only a batch convenience: when a region
        % was requested to line a dataset up with something else - a ground-truth
        % crop and its labels - the level follows from that pairing, and letting
        % the user pick a different one would silently break the match the
        % caller just asserted.
        %
        % A level outside the pyramid is **ignored rather than clamped**, so a
        % stale batch protocol falls back to asking instead of quietly opening a
        % different resolution than it names.
        %
        % Same two-place lookup as :meth:`resolveRegionOption`.
        %
        % Input Arguments:
        %   - **options** - [struct] options passed to loadImages
        %   - **loaderOptions** - [struct] the loader's own ``obj.Options``
        %   - **nLevels** - [numeric] levels this pyramid actually has
        %
        % Output Arguments:
        %   - **requestedLevel** - [numeric] 1-based level, or ``[]`` for none

        requestedLevel = [];
        for candidate = {options, loaderOptions}
            source = candidate{1};
            if isstruct(source) && isfield(source, 'ZarrLevel') && ~isempty(source.ZarrLevel)
                value = double(source.ZarrLevel);
                if isscalar(value) && value >= 1 && value <= nLevels && value == round(value)
                    requestedLevel = value;
                    return;
                end
            end
        end
    end

    function imginfo = applySelectedLevelGeometry(imginfo, files, selectedLevel)
        % APPLYSELECTEDLEVELGEOMETRY - Put a Standard-mode read on its own level's grid.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      imginfo = io.loaders.OmeZarrMetadataUtils.applySelectedLevelGeometry(imginfo, files, selectedLevel)
        %
        % Standard mode materialises exactly **one** pyramid level, so that
        % level's voxel size and world box are the dataset's - not level 0's.
        % Both setup loaders used to update only ``Height``/``Width``/``Depth``
        % for the chosen level and leave ``pixSize`` and ``BoundingBox`` at level
        % 0, which makes the two disagree: opening ``jrc_ctl-id8-1``'s EM at
        % ``s4`` gave 1157 voxels across a 73996 nm box (64 nm each) while
        % ``pixSize.x`` still said 4 nm. Everything physical reads ``pixSize`` -
        % the scale bar, measurements, the box a model is saved with - so this is
        % a silent 16x error in the recorded voxel size, not a cosmetic one.
        %
        % **Level 1 is deliberately left untouched.** It was already correct, and
        % a store MIB wrote carries its own ``mibBoundingBox``, which
        % ``loadMetadata`` puts into ``imginfo`` and which must keep winning.
        %
        % Input Arguments:
        %   - **imginfo** - [dictionary] the metadata being filled in
        %   - **files** - [struct] the setup loader's files struct, carrying
        %     ``pixSize``, ``levelVoxelSizes`` ``[y x z]`` and ``levelWorldBoxes``
        %   - **selectedLevel** - [numeric] 1-based level actually read
        %
        % Output Arguments:
        %   - **imginfo** - [dictionary] with ``pixSize`` and ``BoundingBox`` of
        %     that level (``dictionary`` is a value type, so this must be assigned
        %     back by the caller)

        if selectedLevel <= 1; return; end
        if ~isfield(files, 'levelVoxelSizes') || ...
                selectedLevel > size(files.levelVoxelSizes, 1)
            return;
        end

        levelPixSize   = files.pixSize;
        levelPixSize.y = files.levelVoxelSizes(selectedLevel, 1);
        levelPixSize.x = files.levelVoxelSizes(selectedLevel, 2);
        levelPixSize.z = files.levelVoxelSizes(selectedLevel, 3);
        imginfo{"pixSize"} = levelPixSize;

        if isfield(files, 'levelWorldBoxes') && selectedLevel <= size(files.levelWorldBoxes, 1)
            imginfo{"BoundingBox"} = files.levelWorldBoxes(selectedLevel, :);
        end
    end

    function [levelImageSizes, levelRegionOrigins, levelWorldBoxes, regionReport] = ...
            applyRequestedRegion(requestedRegion, levelImageSizes, levelVoxelSizes, levelWorldBoxes, storeUnits)
        % APPLYREQUESTEDREGION - Crop the pyramid to a world region, or leave it alone.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [sizes, origins, boxes, report] = io.loaders.OmeZarrMetadataUtils.applyRequestedRegion(requestedRegion, levelImageSizes, levelVoxelSizes, levelWorldBoxes, storeUnits)
        %
        % **An absent or empty region is a literal no-op** - the inputs come back
        % unchanged and ``levelRegionOrigins`` is all ones, which every read path
        % treats as "start at voxel 1". That matters more than it looks: a region
        % touches the read path of every zarr dataset MIB opens, local and remote,
        % v2 and v3, and most of them will never ask for one.
        %
        % ``requestedRegion`` is in **micrometres** and is **edge-based** - the
        % outer physical extent, not voxel centres. Micrometres because a region
        % is compared across pyramids that declare different units and scales, so
        % an absolute unit is the only one that cannot be misread; edge-based
        % because that is the space grid alignment is decided in, see
        % :meth:`outerBoundingBox`. Both differ deliberately from
        % ``MibImage.boundingBox``, which is centre-based in the store's own unit,
        % and mixing the two is exactly the half-voxel error this convention
        % exists to prevent.
        %
        % Input Arguments:
        %   - **requestedRegion** - [1x6 numeric] region in um, or ``[]`` for none
        %   - **levelImageSizes** - [nLevels x 3] voxel counts ``[y x z]``
        %   - **levelVoxelSizes** - [nLevels x 3] voxel sizes ``[y x z]``, store units
        %   - **levelWorldBoxes** - [nLevels x 6] centre-based boxes, store units
        %   - **storeUnits** - [char] the store's length unit, e.g. ``'nm'``
        %
        % Output Arguments:
        %   - **levelImageSizes** - cropped voxel counts (or the input, unchanged)
        %   - **levelRegionOrigins** - [nLevels x 3] 1-based first voxel ``[y x z]``
        %   - **levelWorldBoxes** - boxes of the cropped extent (or the input)
        %   - **regionReport** - [struct] ``.requested``, ``.isExact``,
        %     ``.residual``, ``.message``

        regionReport = struct('requested', false, 'isExact', true, ...
            'residual', zeros(3, 2), 'message', '');
        levelRegionOrigins = ones(size(levelImageSizes, 1), 3);

        if isempty(requestedRegion) || numel(requestedRegion) ~= 6
            return;
        end
        requestedRegion = reshape(double(requestedRegion), 1, 6);

        % Region arrives in micrometres; the level tables are in the store's unit.
        unitFactor = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(storeUnits);
        regionInStoreUnits = requestedRegion / unitFactor;

        regionInfo = io.loaders.OmeZarrMetadataUtils.applyRegionToLevels( ...
            regionInStoreUnits, levelWorldBoxes, levelVoxelSizes, levelImageSizes);

        if any(regionInfo.levelImageSizes(1, :) == 0)
            % Nothing of level 0 lies inside the region. Reported rather than
            % silently returning a zero-sized dataset, which would surface much
            % later as an unexplained empty image.
            regionReport.requested = true;
            regionReport.isExact   = false;
            regionReport.message   = sprintf(['The requested region does not overlap this ' ...
                'image group, so nothing was cropped and the full extent was kept.']);
            return;
        end

        levelImageSizes    = regionInfo.levelImageSizes;
        levelRegionOrigins = regionInfo.levelRegionOrigins;
        levelWorldBoxes    = regionInfo.levelWorldBoxes;

        regionReport.requested = true;
        regionReport.isExact   = regionInfo.isExact;
        regionReport.residual  = regionInfo.residual;
        if regionInfo.isExact
            regionReport.message = '';
        else
            % Round outward, then say by how much - a store whose grid does not
            % divide the region evenly gets a region one voxel too big rather
            % than labels shifted one voxel against the image.
            overshoot = max(abs(regionInfo.residual(:))) * unitFactor;
            regionReport.message = sprintf(['The requested region does not fall exactly on ' ...
                'this pyramid''s voxel grid; it was rounded outward by up to %.4g um.'], overshoot);
        end
    end

    function registration = registerLevelScales(levelVoxelSizesXYZ, levelOuterBox, ...
            referenceVoxelSizesXYZ, referenceOuterBox)
        % REGISTERLEVELSCALES - Express one pyramid's levels in another pyramid's scale space.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales(levelVoxelSizesXYZ, levelOuterBox, referenceVoxelSizesXYZ, referenceOuterBox)
        %
        % A pyramid normally numbers its own levels from its own level 0, which is
        % what ``core.MibBigDataLabelsZarr2.openStore`` does: level 0 becomes scale
        % 1, the next 2, and so on. That is correct only while the two pyramids
        % start at the same resolution. A whole-volume inference segmentation does
        % not: ``jrc_mus-kidney``'s ``nuc`` has 5 levels from 128 nm while the EM it
        % segments has 12 from 8 nm, so ``nuc``'s own level 0 is the EM's ``s4``.
        % Calling it scale 1 is a silent 16x error - the labels land at
        % one-sixteenth of their true size with no warning anywhere.
        %
        % This returns the same ``[nLevels x 3]`` table of scale factors those
        % classes already hold, but measured in the **reference** pyramid's level-0
        % voxels, so ``nuc`` registers as ``[16 32 64 128 256]`` inside the EM's own
        % ``[1 2 4 ... 4096]`` magnification space and every level picker, read
        % window and resize downstream keeps working unchanged.
        %
        % **The extents are checked, not assumed.** Two pyramids can share a voxel
        % size and still describe different volumes, and a scale factor alone cannot
        % tell them apart. Both outer boxes must agree per axis within a tolerance
        % of half a reference voxel or one whole level-0 voxel of the registered
        % pyramid, whichever is larger: a pyramid published as a downsample rounds
        % its shape UP, so its declared extent legitimately overshoots by up to one
        % of its own voxels (``jrc_ctl-id8-1``'s ``nuc`` claims ``1157 * 64 =
        % 74048 nm`` against the EM's ``18500 * 4 = 74000 nm``). This is the same
        % pair of roundings ``controllers.SelectFromUrl.imageBoxContains`` tolerates,
        % and for the same reason.
        %
        % A registration is therefore a pure scale: the two volumes coincide, so
        % voxel 1 of one is voxel 1 of the other. A pyramid covering a **sub-volume**
        % is refused rather than placed, because nothing here carries an origin
        % offset - that case is a crop, and crops are read into memory instead.
        %
        % Input Arguments:
        %   - **levelVoxelSizesXYZ** - [nLevels x 3 numeric] voxel size ``[x y z]``
        %     per level of the pyramid being registered, in micrometres
        %   - **levelOuterBox** - [1x6 numeric] that pyramid's outer extent
        %     ``[xmin xmax ymin ymax zmin zmax]`` in micrometres, edge-based, i.e.
        %     as returned by :meth:`outerBoundingBox`
        %   - **referenceVoxelSizesXYZ** - [nRefLevels x 3 numeric] voxel size
        %     ``[x y z]`` per level of the reference pyramid, in micrometres; row 1
        %     is the full-resolution level that defines scale 1
        %   - **referenceOuterBox** - [1x6 numeric] the reference pyramid's outer
        %     extent, micrometres, edge-based
        %
        % Output Arguments:
        %   - **registration** - [struct] with fields:
        %
        %     - ``.ok`` - [logical] false when the two do not describe the same
        %       volume, or the metadata is unusable
        %     - ``.reason`` - [char] what disagreed, naming both extents; ``''``
        %       when ``ok``
        %     - ``.scaleFactorsYXZ`` - [nLevels x 3] each level as a scale factor in
        %       the reference's level-0 voxels, ``[y x z]`` - the order
        %       ``modelScaleFactors`` and ``levelScaleFactors`` already use
        %     - ``.referenceScaleFactorsYXZ`` - [nRefLevels x 3] the reference's own
        %       levels in that same space, i.e. its magnification axis
        %     - ``.isIntegerScale`` - [logical] every registered level is a whole
        %       number of reference voxels. A fractional scale still reads
        %       correctly, but only an integer one can be served without
        %       resampling a label across a voxel boundary

        registration = struct('ok', false, 'reason', '', 'scaleFactorsYXZ', [], ...
            'referenceScaleFactorsYXZ', [], 'isIntegerScale', false);

        levelVoxelSizesXYZ     = double(levelVoxelSizesXYZ);
        referenceVoxelSizesXYZ = double(referenceVoxelSizesXYZ);
        if isempty(levelVoxelSizesXYZ) || isempty(referenceVoxelSizesXYZ) || ...
                size(levelVoxelSizesXYZ, 2) ~= 3 || size(referenceVoxelSizesXYZ, 2) ~= 3
            registration.reason = 'One of the two pyramids declares no usable levels.';
            return;
        end

        referenceVoxelSize = referenceVoxelSizesXYZ(1, :);
        if any(referenceVoxelSize <= 0) || any(levelVoxelSizesXYZ(:) <= 0)
            registration.reason = 'A pyramid level declares a zero or negative voxel size.';
            return;
        end

        % ---- do the two describe the same volume? --------------------------
        registeredBox = reshape(double(levelOuterBox), 1, 6);
        referenceBox  = reshape(double(referenceOuterBox), 1, 6);
        tolerance = max(referenceVoxelSize / 2, levelVoxelSizesXYZ(1, :));

        lowerGap = abs(registeredBox([1 3 5]) - referenceBox([1 3 5]));
        upperGap = abs(registeredBox([2 4 6]) - referenceBox([2 4 6]));
        if any(lowerGap > tolerance) || any(upperGap > tolerance)
            registeredExtent = registeredBox([2 4 6]) - registeredBox([1 3 5]);
            referenceExtent  = referenceBox([2 4 6]) - referenceBox([1 3 5]);
            registration.reason = sprintf(['These two pyramids do not describe the same ' ...
                'volume: one spans %g x %g x %g um and the other %g x %g x %g um (X x Y x Z). ' ...
                'Levels can only be paired across a volume they both cover in full.'], ...
                registeredExtent(1), registeredExtent(2), registeredExtent(3), ...
                referenceExtent(1), referenceExtent(2), referenceExtent(3));
            return;
        end

        % ---- every level as a scale factor in the reference's level-0 space --
        [registration.scaleFactorsYXZ, isIntegerScale] = ...
            io.loaders.OmeZarrMetadataUtils.scalesAgainstVoxelSize( ...
                levelVoxelSizesXYZ, referenceVoxelSize);
        registration.referenceScaleFactorsYXZ = ...
            io.loaders.OmeZarrMetadataUtils.scalesAgainstVoxelSize( ...
                referenceVoxelSizesXYZ, referenceVoxelSize);
        registration.isIntegerScale = all(isIntegerScale(:));
        registration.ok = true;
    end

    function [scaleFactorsYXZ, isIntegerScale] = scalesAgainstVoxelSize(levelVoxelSizesXYZ, referenceVoxelSize)
        % SCALESAGAINSTVOXELSIZE - Voxel sizes as scale factors, snapped to whole numbers.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      [scaleFactorsYXZ, isIntegerScale] = io.loaders.OmeZarrMetadataUtils.scalesAgainstVoxelSize(levelVoxelSizesXYZ, referenceVoxelSize)
        %
        % Shared by both halves of :meth:`registerLevelScales` - the registered
        % pyramid and the reference's own magnification axis are the same division.
        %
        % **The snap is load-bearing.** A store writes its scales as rounded
        % decimals, so ``5.24 / 2.62`` comes back as ``1.9999999...`` rather than 2,
        % and every ``ceil`` downstream then reads one voxel too far at exactly the
        % level boundaries. Snapping inside one part in a thousand is far more slack
        % than a decimal rounding needs and nowhere near enough to accept a genuinely
        % fractional scale as a whole one.
        %
        % Input Arguments:
        %   - **levelVoxelSizesXYZ** - [nLevels x 3 numeric] voxel size ``[x y z]``
        %     per level, any unit
        %   - **referenceVoxelSize** - [1x3 numeric] the voxel size that means scale
        %     1, same unit
        %
        % Output Arguments:
        %   - **scaleFactorsYXZ** - [nLevels x 3] scale factors reordered to
        %     ``[y x z]``
        %   - **isIntegerScale** - [nLevels x 3 logical] which entries snapped

        scaleTolerance = 1e-3;

        scalesXYZ = double(levelVoxelSizesXYZ) ./ reshape(double(referenceVoxelSize), 1, 3);
        rounded   = round(scalesXYZ);
        isIntegerScale = rounded > 0 & abs(scalesXYZ - rounded) <= scaleTolerance * rounded;
        scalesXYZ(isIntegerScale) = rounded(isIntegerScale);

        scaleFactorsYXZ = scalesXYZ(:, [2 1 3]);
    end

    function screenGrid = screenGridForRange(fullRange, levelScaleFactor, magFactor)
        % SCREENGRIDFORRANGE - Where a displayed slice's pixels land in full-resolution space.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      screenGrid = io.loaders.OmeZarrMetadataUtils.screenGridForRange(fullRange, levelScaleFactor, magFactor)
        %
        % Reproduces, as arithmetic, what ``core.MibVirtualImage.getDataZarr`` does
        % to one axis: round the requested full-resolution range outward onto the
        % level it is reading, then ``imresize`` the result by ``magFactor /
        % levelScaleFactor``. The answer is needed by anything that has to produce a
        % **second** layer over the same view, because the two arrays are composited
        % by ``labeloverlay`` (``models.MibModel.getRGBimage``) and that requires
        % them to be the same size exactly - one row out is an error, not a shift.
        %
        % Two things come out of it, and the second is the one that is easy to miss:
        %
        %   * ``.size`` - how many screen pixels the image layer produced.
        %   * ``.origin`` - the full-resolution coordinate where screen pixel 1
        %     starts. This is **not** ``fullRange(1)``: the image snapped the request
        %     outward onto its own level's grid first, so it starts up to
        %     ``levelScaleFactor`` voxels earlier. For the image itself that is
        %     sub-pixel slop, because it always has a level near the requested
        %     magnification; for a second pyramid that does not, sampling from
        %     ``fullRange(1)`` instead puts every label up to one screen pixel off.
        %
        % **The level range is not clamped** to the level's own dimensions, unlike
        % ``getDataZarr``, which clamps and then finds the clamp never fires: a level
        % holds ``ceil(dim / scale)`` voxels, so a request inside the dataset can
        % never round outward past the end of it.
        %
        % Input Arguments:
        %   - **fullRange** - [1x2 numeric] requested range in full-resolution
        %     voxels, 1-based inclusive
        %   - **levelScaleFactor** - [numeric] full-resolution voxels per voxel of
        %     the level actually read, on this axis
        %   - **magFactor** - [numeric] full-resolution voxels per screen pixel,
        %     i.e. ``dataset.magFactor``. Pass ``levelScaleFactor`` for an axis that
        %     is never magnified, such as z, which gives one screen pixel per level
        %     voxel
        %
        % Output Arguments:
        %   - **screenGrid** - [struct] with fields:
        %
        %     - ``.levelRange`` - [1x2] level voxels the image layer read
        %     - ``.size`` - [numeric] screen pixels produced
        %     - ``.origin`` - [numeric] full-resolution coordinate, 1-based, that
        %       screen pixel 1 starts at
        %     - ``.step`` - [numeric] full-resolution voxels per screen pixel, as
        %       actually delivered. Close to ``magFactor``, but derived from the
        %       rounded ``.size`` rather than assumed, so it stays exact at both
        %       ends of the range

        fullRange        = double(fullRange);
        levelScaleFactor = double(levelScaleFactor);
        magFactor        = double(magFactor);
        if ~(levelScaleFactor > 0); levelScaleFactor = 1; end
        if ~(magFactor > 0);        magFactor = 1; end

        firstLevelVoxel = max(1, ceil(fullRange(1) / levelScaleFactor));
        lastLevelVoxel  = max(firstLevelVoxel, ceil(fullRange(2) / levelScaleFactor));
        levelVoxelCount = lastLevelVoxel - firstLevelVoxel + 1;

        % Same test getDataZarr:215 applies before resizing at all, so a level
        % already at the requested magnification returns its own voxel count.
        resizeFactor = magFactor / levelScaleFactor;
        if abs(resizeFactor - 1) > 1e-3
            screenSize = max(1, round(levelVoxelCount / resizeFactor));
        else
            screenSize = levelVoxelCount;
        end

        screenGrid = struct();
        screenGrid.levelRange = [firstLevelVoxel, lastLevelVoxel];
        screenGrid.size       = screenSize;
        screenGrid.origin     = (firstLevelVoxel - 1) * levelScaleFactor + 1;
        screenGrid.step       = levelVoxelCount * levelScaleFactor / screenSize;
    end

    function window = levelReadWindow(screenGrid, scaleFactor, levelSize)
        % LEVELREADWINDOW - Which voxels of a coarser level each screen pixel comes from.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      window = io.loaders.OmeZarrMetadataUtils.levelReadWindow(screenGrid, scaleFactor, levelSize)
        %
        % The other half of :meth:`screenGridForRange`, and the piece that makes an
        % offset label pyramid land where it belongs. Serving a view from a level
        % much coarser than the one requested is **not a resize**: the coarse block
        % covering the view does not start where the view starts, so scaling it to
        % the viewport gives both the wrong size and a shifted origin. At scale 16, a
        % request for columns 3-34 (32 wide) covers coarse voxels 1-3, and resizing
        % those three returns 48 columns beginning at column 1 - plausible-looking
        % labels, 2 pixels to the left, 50% too large.
        %
        % Rather than resize and then crop back, this returns the **gather** the two
        % steps amount to: one source voxel per screen pixel. That removes the
        % intermediate array (which in full-resolution space is unbounded - at
        % ``magFactor`` 32 the requested window is some 36000 voxels wide), removes
        % the second rounding a resize-then-crop performs, and makes the result exact
        % rather than within a pixel. Applying it is an indexed read:
        %
        %   .. code-block:: matlab
        %
        %      block = obj.readLevel(levelIdx, windowY.levelRange, windowX.levelRange, zRange);
        %      slice = block(windowY.sourceIndex, windowX.sourceIndex, :);
        %
        % Each screen pixel takes the level voxel holding its **centre**, which is
        % also what ``imresize(..., 'nearest')`` does and is why the two agree
        % wherever the naive path was already right. The half-pixel offset that
        % follows from sampling centres keeps the arithmetic clear of exact voxel
        % boundaries, so no tolerance is needed against a ``ceil`` landing on the
        % wrong side of one.
        %
        % Input Arguments:
        %   - **screenGrid** - [struct] from :meth:`screenGridForRange`, describing
        %     the pixels that have to be filled
        %   - **scaleFactor** - [numeric] full-resolution voxels per voxel of the
        %     level being read, on this axis, in the **same** scale space the grid
        %     was built in (see :meth:`registerLevelScales`)
        %   - **levelSize** - [numeric] voxels this level holds on this axis; the
        %     window is clamped to it, so a pyramid whose rounded-up shape overshoots
        %     repeats its last voxel instead of reading past the end
        %
        % Output Arguments:
        %   - **window** - [struct] with fields:
        %
        %     - ``.levelRange`` - [1x2] 1-based inclusive voxels to read, the
        %       smallest range covering the view
        %     - ``.sourceIndex`` - [1 x screenGrid.size] index into that block, one
        %       per screen pixel. Always exactly as long as the image layer is wide,
        %       which is what ``labeloverlay`` requires

        scaleFactor = double(scaleFactor);
        if ~(scaleFactor > 0); scaleFactor = 1; end
        levelSize = max(1, floor(double(levelSize)));

        % Edge space, where voxel j spans (j-1, j] - the centre of screen pixel p
        % is then simply ceil()-ed onto the level's own grid, with no separate
        % full-resolution index in between to round twice.
        pixelCentres = (screenGrid.origin - 1) + ((1:screenGrid.size) - 0.5) * screenGrid.step;
        sourceVoxels = ceil(pixelCentres / scaleFactor);
        sourceVoxels = min(max(sourceVoxels, 1), levelSize);

        window = struct();
        window.levelRange  = [min(sourceVoxels), max(sourceVoxels)];
        window.sourceIndex = sourceVoxels - window.levelRange(1) + 1;
    end

    function bbox = buildZarrBbox(axisOrder, axisRanges)
        % BUILDZARRBBOX - Turn per-axis MIB ranges into a zarr C-order read box.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      bbox = io.loaders.OmeZarrMetadataUtils.buildZarrBbox(axisOrder, axisRanges)
        %
        % The engines take the box in the store's own declared axis order and
        % return an array laid out the same way, so this is the single point
        % where MIB's named ranges become positional ones.
        %
        % Input Arguments:
        %   - **axisOrder** - [char] zarr C-order declaration, e.g. ``'tczyx'``
        %   - **axisRanges** - [struct] fields ``.y .x .z .c .t``, each a
        %     ``[first last]`` 1-based inclusive pair; an axis the store does not
        %     declare is ignored, and an axis with no field becomes a singleton
        %
        % Output Arguments:
        %   - **bbox** - [nDims x 2 numeric] rows in ``axisOrder`` order, each
        %     ``[start_1based, end_exclusive]``

        nDims = numel(axisOrder);
        bbox  = zeros(nDims, 2);
        for dimIndex = 1:nDims
            axisName = axisOrder(dimIndex);
            if isfield(axisRanges, axisName)
                range = axisRanges.(axisName);
                bbox(dimIndex, :) = [range(1), range(2) + 1];
            else
                bbox(dimIndex, :) = [1, 2];   % singleton for an absent axis
            end
        end
    end

    function bbox = levelRegionBbox(axisOrder, regionOrigin, levelSize, nColors, nTimes)
        % LEVELREGIONBBOX - Read box covering a whole cropped level.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      bbox = io.loaders.OmeZarrMetadataUtils.levelRegionBbox(axisOrder, regionOrigin, levelSize, nColors, nTimes)
        %
        % The whole-level equivalent of what ``getDataZarr`` does per slice: turn
        % a crop origin plus a cropped size into the store-space box to read.
        % Used by the Standard and Model load paths, which read a level in one go
        % rather than region by region.
        %
        % Input Arguments:
        %   - **axisOrder** - [char] zarr C-order declaration
        %   - **regionOrigin** - [1x3 numeric] 1-based first voxel ``[y x z]``
        %     within the level's own array; ``[1 1 1]`` for an uncropped store
        %   - **levelSize** - [1x3 numeric] cropped voxel counts ``[y x z]``
        %   - **nColors** - [numeric] colour channel count
        %   - **nTimes** - [numeric] time point count
        %
        % Output Arguments:
        %   - **bbox** - [nDims x 2 numeric] ready for ``io.zarr.Array.read``

        axisRanges.y = [regionOrigin(1), regionOrigin(1) + levelSize(1) - 1];
        axisRanges.x = [regionOrigin(2), regionOrigin(2) + levelSize(2) - 1];
        axisRanges.z = [regionOrigin(3), regionOrigin(3) + levelSize(3) - 1];
        axisRanges.c = [1, nColors];
        axisRanges.t = [1, nTimes];
        bbox = io.loaders.OmeZarrMetadataUtils.buildZarrBbox(axisOrder, axisRanges);
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

    function attrs = readGroupAttributes(groupPath, zarrFormat)
        % READGROUPATTRIBUTES - Read the user attributes of a local zarr group.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      attrs = io.loaders.OmeZarrMetadataUtils.readGroupAttributes(groupPath, zarrFormat)
        %
        % Works for a local folder and for a remote (http/https/s3) group, which
        % is fetched with ``io.RemoteStore.readJson``. A missing or unparsable
        % metadata file is not an error: it simply means "no attributes here",
        % which is exactly how a non-zarr directory should behave.
        %
        % Input Arguments:
        %   - **groupPath** - [char] full path or URL of the group
        %   - **zarrFormat** - [numeric] 2 (``.zattrs``) or 3 (``zarr.json``)
        %
        % Output Arguments:
        %   - **attrs** - [struct] decoded attributes; empty struct when absent

        attrs = struct();

        if zarrFormat == 2; metadataName = '.zattrs'; else; metadataName = 'zarr.json'; end

        try
            if io.RemoteStore.isRemote(groupPath)
                rawMeta = io.RemoteStore.readJson( ...
                    io.RemoteStore.join(groupPath, metadataName));
                if isempty(rawMeta); return; end
            else
                metadataFile = fullfile(groupPath, metadataName);
                if ~isfile(metadataFile); return; end
                rawMeta = jsondecode(fileread(metadataFile));
            end

            if zarrFormat == 2
                attrs = rawMeta;
            elseif isfield(rawMeta, 'attributes') && isstruct(rawMeta.attributes)
                attrs = rawMeta.attributes;
            else
                % non-standard stores put multiscales at the top level
                attrs = rawMeta;
            end
        catch
            attrs = struct();
        end
    end

    function childPaths = listChildGroups(groupPath, zarrFormat)
        % LISTCHILDGROUPS - List sub-directories of a local zarr group that are groups themselves.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      childPaths = io.loaders.OmeZarrMetadataUtils.listChildGroups(groupPath, zarrFormat)
        %
        % Arrays are deliberately excluded. That is what keeps a container walk
        % out of the chunk directory tree: a pyramid level such as ``s0`` is an
        % array, and with ``dimension_separator = "/"`` it holds thousands of
        % nested chunk folders that must never be enumerated.
        %
        % On a remote store the child **names** come from one S3 listing of the
        % parent, but each child is then classified by fetching its marker file
        % rather than by listing it. Listing an array would enumerate its chunk
        % directories - for a store with ``dimension_separator = "/"`` that is
        % hundreds of prefixes per level and would paginate. Two small ranged
        % requests per child are bounded and far cheaper.
        %
        % Input Arguments:
        %   - **groupPath** - [char] full path or URL of the parent group
        %   - **zarrFormat** - [numeric] 2 or 3
        %
        % Output Arguments:
        %   - **childPaths** - [1xN cell] full paths of child groups, sorted by name

        childPaths = {};

        if io.RemoteStore.isRemote(groupPath)
            [childUrls, childNames] = io.RemoteStore.listChildren(groupPath);
            if isempty(childUrls); return; end

            [~, sortOrder] = sort(childNames);   % deterministic, matches the local branch
            childUrls = childUrls(sortOrder);

            for childIndex = 1:numel(childUrls)
                childUrl = childUrls{childIndex};
                if zarrFormat == 2
                    % v2: only groups carry .zgroup, so one probe settles it -
                    % an extra .zarray probe would double the request count of
                    % the walk for no additional information.
                    isGroup = io.RemoteStore.exists(io.RemoteStore.join(childUrl, '.zgroup'));
                else
                    % v3: both node kinds use zarr.json, distinguished by node_type
                    nodeMeta = io.RemoteStore.readJson(io.RemoteStore.join(childUrl, 'zarr.json'));
                    isGroup  = ~isempty(nodeMeta) && isfield(nodeMeta, 'node_type') && ...
                               strcmpi(char(nodeMeta.node_type), 'group');
                end
                if isGroup
                    childPaths{end+1} = childUrl; %#ok<AGROW>
                end
            end
            return;
        end

        try
            items = dir(groupPath);
        catch
            return;
        end
        items = items([items.isdir] & ~ismember({items.name}, {'.', '..'}));
        if isempty(items); return; end

        [~, sortOrder] = sort({items.name});  % deterministic across platforms
        items = items(sortOrder);

        for itemIndex = 1:numel(items)
            childPath = fullfile(groupPath, items(itemIndex).name);
            if zarrFormat == 2
                % v2: groups carry .zgroup, arrays carry .zarray
                isGroup = isfile(fullfile(childPath, '.zgroup')) && ...
                          ~isfile(fullfile(childPath, '.zarray'));
            else
                % v3: both node kinds use zarr.json, distinguished by node_type
                isGroup = false;
                metadataFile = fullfile(childPath, 'zarr.json');
                if isfile(metadataFile)
                    try
                        nodeMeta = jsondecode(fileread(metadataFile));
                        isGroup = isfield(nodeMeta, 'node_type') && ...
                                  strcmpi(nodeMeta.node_type, 'group');
                    catch
                        % unparsable zarr.json -> not a usable group
                    end
                end
            end
            if isGroup
                childPaths{end+1} = childPath; %#ok<AGROW>
            end
        end
    end

    function groupPaths = findMultiscalesGroups(rootPath, zarrFormat, maxDepth, maxVisited)
        % FINDMULTISCALESGROUPS - Search a local zarr container for groups holding multiscales metadata.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      groupPaths = io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups(rootPath, zarrFormat)
        %      groupPaths = io.loaders.OmeZarrMetadataUtils.findMultiscalesGroups(rootPath, zarrFormat, maxDepth, maxVisited)
        %
        % Breadth-first walk over child groups, collecting every group whose
        % attributes contain an OME-NGFF ``multiscales`` entry. Needed because
        % real-world containers nest the image group arbitrarily deep, e.g. the
        % OpenOrganelle / MoBIE layout ``<store>.zarr/recon-1/em/fibsem-uint8``,
        % while OME-Zarr label containers nest it one level down.
        %
        % A group that has multiscales is never descended into - its children
        % are the pyramid level arrays.
        %
        % Breadth-first order means shallower groups are reported first, so a
        % caller that just takes the first hit gets the least nested one.
        %
        % **Remote stores stop at the shallowest level that yields a hit.**
        % Locally each step is a ``dir()`` call and walking the whole tree is
        % free, so the local behaviour is unchanged: every match up to
        % ``maxDepth`` is collected. Remotely each step is a network round trip,
        % and real containers hide very large subtrees below the image group -
        % OpenOrganelle's ``recon-1/labels/groundtruth`` holds 42 crops of about
        % 40 class groups each. Descending past the level that already answered
        % the question would cost hundreds of requests to produce a picker list
        % nobody wants. ``maxVisited`` is also capped harder for remote roots, to
        % bound the case where a store has no multiscales anywhere.
        %
        % Deep interactive navigation of a remote container is the job of the
        % URL browser dialog, which lists exactly one level per user expand.
        %
        % Input Arguments:
        %   - **rootPath** - [char] local path or URL of the container root
        %   - **zarrFormat** - [numeric] 2 or 3
        %   - **maxDepth** - *(optional)* [numeric] deepest level to visit, root is 0 (default: 5)
        %   - **maxVisited** - *(optional)* [numeric] hard cap on visited groups,
        %     a guard against pathological trees (default: 500, capped at 60 for
        %     a remote root)
        %
        % Output Arguments:
        %   - **groupPaths** - [1xN cell] full paths of groups with multiscales;
        %     empty when none found, or when the root is remote on a host that
        %     cannot be listed

        arguments
            rootPath (1,:) char
            zarrFormat (1,1) double
            maxDepth (1,1) double = 5
            maxVisited (1,1) double = 500
        end

        groupPaths = {};

        isRemoteRoot = io.RemoteStore.isRemote(rootPath);
        if isRemoteRoot
            if ~io.RemoteStore.parse(rootPath).listable; return; end
            maxVisited = min(maxVisited, 60);
        elseif ~isfolder(rootPath)
            return;
        end

        currentLevel = {rootPath};
        depth        = 0;
        visited      = 0;

        % Each level is TESTED in full before any of it is EXPANDED. Testing a
        % group costs one metadata read; expanding it costs a listing plus a
        % probe per child. Interleaving the two would expand the siblings of a
        % match before the match is known about - on the OpenOrganelle layout
        % that means listing 'labels/groundtruth' and probing all 42 crops
        % moments before the walk was going to stop anyway, which measured as
        % roughly 60 requests instead of 15.
        while ~isempty(currentLevel) && visited < maxVisited
            % ---- pass 1: test this level ---------------------------------
            isMatch = false(1, numel(currentLevel));
            for levelIndex = 1:numel(currentLevel)
                visited = visited + 1;
                if visited > maxVisited; break; end

                groupPath = currentLevel{levelIndex};
                attrs = io.loaders.OmeZarrMetadataUtils.readGroupAttributes(groupPath, zarrFormat);
                if ~isempty(io.loaders.OmeZarrMetadataUtils.extractMultiscales(attrs))
                    isMatch(levelIndex) = true;
                    groupPaths{end+1} = groupPath; %#ok<AGROW>
                end
            end

            % Shallowest-wins for remote roots (see the note above).
            if isRemoteRoot && ~isempty(groupPaths); break; end
            if depth >= maxDepth; break; end

            % ---- pass 2: expand only the groups that did not match --------
            % A group with multiscales is never descended into: its children are
            % the pyramid level arrays.
            nextLevel = {};
            for levelIndex = 1:numel(currentLevel)
                if isMatch(levelIndex); continue; end
                nextLevel = [nextLevel, ...
                    io.loaders.OmeZarrMetadataUtils.listChildGroups( ...
                        currentLevel{levelIndex}, zarrFormat)]; %#ok<AGROW>
            end

            currentLevel = nextLevel;
            depth        = depth + 1;
        end
    end

    function relativePath = relativeGroupPath(rootPath, groupPath)
        % RELATIVEGROUPPATH - Format a group path relative to the container root, for display.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      relativePath = io.loaders.OmeZarrMetadataUtils.relativeGroupPath(rootPath, groupPath)
        %
        % Returns forward-slash separated text such as ``recon-1/em/fibsem-uint8``.
        % Falls back to the full path when groupPath is not under rootPath.

        relativePath = strrep(groupPath, '\', '/');
        normalisedRoot = strrep(rootPath, '\', '/');
        if endsWith(normalisedRoot, '/'); normalisedRoot = normalisedRoot(1:end-1); end

        if startsWith(relativePath, [normalisedRoot, '/'])
            relativePath = relativePath(numel(normalisedRoot)+2:end);
        elseif strcmp(relativePath, normalisedRoot)
            relativePath = '.';  % the root group itself
        end
    end

    function selectedPath = selectMultiscalesGroup(rootPath, groupPaths, ParentFigure, dlgTitle)
        % SELECTMULTISCALESGROUP - Resolve which nested multiscales group to open.
        %
        % Syntax:
        %   .. code-block:: matlab
        %
        %      selectedPath = io.loaders.OmeZarrMetadataUtils.selectMultiscalesGroup(rootPath, groupPaths, ParentFigure, dlgTitle)
        %
        % Zero candidates returns ``''`` and one candidate is taken silently, so
        % the dialog only appears for genuinely ambiguous containers (an image
        % group plus a labels group, several channels, and so on).
        %
        % Input Arguments:
        %   - **rootPath** - [char] container root, used to shorten the displayed names
        %   - **groupPaths** - [1xN cell] candidates from findMultiscalesGroups
        %   - **ParentFigure** - [handle] parent figure for the dialog
        %   - **dlgTitle** - [char] dialog window title
        %
        % Output Arguments:
        %   - **selectedPath** - [char] chosen group path; ``''`` when nothing to
        %     choose or the user cancelled

        selectedPath = '';
        if isempty(groupPaths); return; end
        if isscalar(groupPaths); selectedPath = groupPaths{1}; return; end

        labels = cell(1, numel(groupPaths));
        for groupIndex = 1:numel(groupPaths)
            labels{groupIndex} = io.loaders.OmeZarrMetadataUtils.relativeGroupPath(...
                rootPath, groupPaths{groupIndex});
        end

        dlgOpts = struct();
        dlgOpts.WindowWidth   = 520;
        dlgOpts.WindowHeight  = 180;
        dlgOpts.LabelPosition = 'top';

        [answer, selectedIndices] = utils.dlgs.inputUniversalDlg(ParentFigure, '', ...
            {'This container holds several image groups; select the one to open:'}, ...
            {[labels, {1}]}, dlgTitle, dlgOpts);
        if isempty(answer); return; end

        selectedPath = groupPaths{selectedIndices(1)};
    end
end
end
