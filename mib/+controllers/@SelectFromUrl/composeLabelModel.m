function [modelData, materialNames, compositionReport] = composeLabelModel(obj, labelGroupUrls, labelPyramids, cropPlan, progressDialog)
% COMPOSELABELMODEL - Blend the selected COSEM label groups into one MIB model.
%
% Syntax:
%   .. code-block:: matlab
%
%      [modelData, materialNames, compositionReport] = obj.composeLabelModel(labelGroupUrls, labelPyramids, cropPlan, progressDialog)
%
% **Three kinds of group, and they encode their values differently.** Getting
% this wrong produces an empty model rather than an error, so the distinction is
% read from the store, never assumed:
%
%   * A **single-class** group carries a ``cellmap.annotation`` block declaring
%     ``semantic_segmentation`` and a ``present`` value. Its data is binary, and
%     it becomes exactly one material.
%   * An **index map** - the merged ``all`` group of a crop - carries **no**
%     ``cellmap`` block at all, and every distinct non-zero value is a different
%     class. It becomes one material per value present.
%   * An **instance segmentation** declares ``instance_segmentation`` and holds
%     an object id per voxel. **By default every object is kept**, one material
%     each: this route builds an ordinary in-memory model, which holds up to
%     65535 materials, so there is no reason to discard them.
%     ``BatchOpt.MergeInstanceObjects`` collapses them all into one material
%     instead - a mask of where the objects are, which is a reasonable thing to
%     want for viewing and is offered by :meth:`chooseInstanceHandling`. Either
%     way the object count is reported, since 864 objects reads very differently
%     from 3.
%
% Assuming the binary form for everything is what an earlier version did, and on
% ``crop266/all`` - whose values are 3, 4, 5, 8, ... 48, with no voxel equal to 1
% - it silently yielded a model with nothing in it.
%
% Groups are applied **in pick order**, so a later pick wins where two overlap.
%
% Three things are counted while blending, because each is invisible in the
% result and misleading if unreported:
%
%   * **Overlap.** COSEM classes are not disjoint - ``er`` is ``er_mem`` plus
%     ``er_lum``, ``er_mem_all`` contains ``er_mem`` - so a pick order silently
%     decides which one a shared voxel ends up as. The overlap is counted
%     exactly, per pair, rather than guessed from class names, which cannot see
%     how a particular crop was annotated.
%   * **``unknown`` is not background.** The value 255 means "not annotated
%     here", and it lands in material 0 alongside genuine background. Anything
%     trained on the result would learn those voxels as negatives, so the count
%     is reported.
%   * **Empty classes.** Many groups exist in a crop but contain nothing.
%     Counting contributions is free here, and it is the same answer a picker
%     could only get by downloading every group speculatively.
%
% Input Arguments:
%   - **labelGroupUrls** - {1xN cell} URLs of the groups, in pick order
%   - **labelPyramids** - {1xN cell} matching readGroupPyramid results
%   - **cropPlan** - [struct] from :meth:`planLabelCrop`
%   - **progressDialog** - [handle] uiprogressdlg to advance, or ``[]``
%
% Output Arguments:
%   - **modelData** - [y x z] index map, ``uint8`` for up to 255 materials
%   - **materialNames** - {1xM cell} one entry per material; M exceeds the number
%     of selected groups when an index map contributes several
%   - **compositionReport** - [struct] ``.lines`` (cell of text for the user),
%     ``.voxelCounts``, ``.unknownCounts``, ``.overlaps``, ``.isHomogeneous``,
%     ``.instanceObjectCounts`` (per group, 0 unless it was an instance group)

shapeYXZ = cropPlan.shapeYXZ;
nGroups  = numel(labelGroupUrls);

% Materials are discovered as groups are read - an index map contributes as many
% as it holds distinct values - so the map starts as uint16 and is narrowed once
% the final count is known.
modelData     = zeros(shapeYXZ, 'uint16');
materialNames = {};
voxelCounts   = [];
unknownCounts = zeros(1, nGroups);
instanceObjectCounts = zeros(1, nGroups);   % instance groups only; 0 for every other kind
sourceGroup   = [];     % which selected group each material came from
overlapPairs  = struct('later', {}, 'earlier', {}, 'voxels', {});

for groupIndex = 1:nGroups
    pyramidInfo = labelPyramids{groupIndex};
    groupName   = obj.labelGroupName(labelGroupUrls{groupIndex}, pyramidInfo);

    if ~isempty(progressDialog) && isvalid(progressDialog)
        % The group count is the first thing in this import that can be counted,
        % so this is where the bar stops being Indeterminate.
        progressDialog.Indeterminate = 'off';
        progressDialog.Value   = (groupIndex - 1) / nGroups;
        progressDialog.Message = sprintf('Reading %s (%d of %d)...', groupName, groupIndex, nGroups);
        drawnow limitrate;
    end

    levelUrl = io.RemoteStore.join(labelGroupUrls{groupIndex}, ...
        pyramidInfo.levelNames{cropPlan.labelLevel});
    raw = io.zarr.Array(levelUrl).read();

    % zarr C-order -> MIB3 [y x z c t], then drop the singleton c/t
    permutation = io.loaders.OmeZarrMetadataUtils.computePermutation(pyramidInfo.axisOrder);
    block = permute(raw, permutation);
    block = reshape(block, size(block, 1), size(block, 2), size(block, 3));

    if ~isequal(size(block), shapeYXZ)
        error('controllers:SelectFromUrl:labelShapeMismatch', ...
            ['Label group "%s" is %s but the crop was planned as %s. ' ...
             'The groups of this crop do not share one extent.'], ...
            groupName, mat2str(size(block)), mat2str(shapeYXZ));
    end

    [presentValue, unknownValue, isSemantic] = obj.labelEncodingValues(pyramidInfo);
    unknownCounts(groupIndex) = nnz(block == unknownValue);

    isInstanceGroup = strcmp(pyramidInfo.annotationType, 'instance_segmentation');
    if isInstanceGroup
        instanceObjectCounts(groupIndex) = numel(unique(block(block ~= 0 & block ~= unknownValue)));
    end

    if isInstanceGroup && obj.BatchOpt.MergeInstanceObjects
        % Asked for deliberately: every object id becomes the same material, a
        % mask of where the objects are. This is a Standard buffer, so keeping
        % them is perfectly possible - merging is only ever a choice about what
        % the user wants to look at, never a limit of the model.
        objectIds = unique(block(block ~= 0 & block ~= unknownValue));
        block(ismember(block, objectIds)) = cast(presentValue, 'like', block);
        classValues = presentValue;
        classLabels = {groupName};
    elseif isSemantic
        classValues = presentValue;
        classLabels = {groupName};
    else
        % An index map: every distinct value that is neither background nor
        % "not annotated" is its own class. Named by the store's own id - the
        % ids are a canonical COSEM table that is NOT the crop's class_names
        % order, so indexing a name list by them would mislabel every material.
        classValues = unique(block(block ~= 0 & block ~= unknownValue))';
        classLabels = arrayfun(@(value) sprintf('%s_%d', groupName, value), ...
            classValues, 'UniformOutput', false);
    end

    % modelData accumulates in uint16, so this is the ceiling on distinct
    % materials. An instance group is the only realistic way to approach it, and
    % merging is exactly the answer, so the error says so rather than leaving the
    % user with an overflowed model.
    if numel(materialNames) + numel(classValues) > 65535
        error('controllers:SelectFromUrl:tooManyMaterials', ...
            ['"%s" would bring the model past 65535 materials. Load it with ' ...
             'MergeInstanceObjects (or answer "Merge into one material") to take it as a ' ...
             'single mask instead.'], groupName);
    end

    % ---- store value -> material index, in ONE pass over the block ------
    % A mask per class (``block == classValues(k)``, once per k) is the obvious
    % way and is O(classes x volume): jrc_mus-kidney's nuc has 864 objects over
    % 530 Mvoxels, which measured **375 s** against 12 s for the image read it
    % sits behind. A lookup table costs one pass whatever the class count.
    %
    % Values are distinct within a group, so a later class can only ever
    % overwrite a material from an EARLIER group - which is what bounds the
    % overlap bookkeeping below to [1, baseMaterialCount].
    baseMaterialCount = numel(materialNames);
    nClasses          = numel(classValues);
    % Grown once per group, not per class - a handful of times in all.
    materialNames(baseMaterialCount + (1:nClasses)) = classLabels;    %#ok<AGROW>
    sourceGroup(baseMaterialCount + (1:nClasses))   = groupIndex;     %#ok<AGROW>
    voxelCounts(baseMaterialCount + (1:nClasses))   = 0;              %#ok<AGROW>

    maxClassValue = double(max(classValues));
    valueToMaterial = zeros(maxClassValue + 1, 1, 'uint16');
    valueToMaterial(double(classValues) + 1) = uint16(baseMaterialCount + (1:nClasses));

    % Slice at a time so the temporaries stay a slice wide: a whole-volume
    % double copy of the block would be four times the block itself.
    overlapCounts = sparse(baseMaterialCount + nClasses, max(baseMaterialCount, 1));
    for sliceIndex = 1:size(block, 3)
        sliceValues = double(block(:, :, sliceIndex));
        sliceValues(sliceValues > maxClassValue) = 0;   % not a class of this group
        assignedSlice = valueToMaterial(sliceValues + 1);
        assignedHere  = assignedSlice ~= 0;
        if ~any(assignedHere(:)); continue; end

        currentSlice = modelData(:, :, sliceIndex);
        overlapHere  = assignedHere & currentSlice ~= 0;
        if baseMaterialCount > 0 && any(overlapHere(:))
            overlapCounts = overlapCounts + sparse(double(assignedSlice(overlapHere)), ...
                double(currentSlice(overlapHere)), 1, ...
                baseMaterialCount + nClasses, baseMaterialCount);
        end

        currentSlice(assignedHere)       = assignedSlice(assignedHere);
        modelData(:, :, sliceIndex)      = currentSlice;
        voxelCounts(baseMaterialCount + (1:nClasses)) = ...
            voxelCounts(baseMaterialCount + (1:nClasses)) + ...
            accumarray(double(assignedSlice(assignedHere)) - baseMaterialCount, 1, [nClasses, 1])';
    end

    [laterMaterials, earlierMaterials, overlapVoxels] = find(overlapCounts);
    for pairIndex = 1:numel(overlapVoxels)
        overlapPairs(end+1) = struct('later', laterMaterials(pairIndex), ...
            'earlier', earlierMaterials(pairIndex), ...
            'voxels', overlapVoxels(pairIndex)); %#ok<AGROW>
    end
end

if ~isempty(progressDialog) && isvalid(progressDialog)
    progressDialog.Value = 1;
end

if numel(materialNames) <= 255
    modelData = uint8(modelData);
end

% ---- report -------------------------------------------------------------
reportLines = {};
distinctValues = unique(modelData(:));
isHomogeneous  = isscalar(distinctValues);
if isHomogeneous
    % Some crops really are one class throughout - entirely extracellular
    % space, entirely nucleus. Saying so beats letting the user find a
    % solid-colour model and assume MIB lost the data.
    if distinctValues == 0
        reportLines{end+1} = ['Warning: the composed model is empty - no selected class has ' ...
            'any voxel in this crop.'];
    else
        reportLines{end+1} = sprintf(['Note: the composed model is a single material (%s) ' ...
            'everywhere. This crop is genuinely homogeneous.'], materialNames{distinctValues});
    end
end

% The object count is only knowable once the pixels are read, so neither the
% info panel nor the question before Open could name it - and 864 objects reads
% very differently from 3, whichever way they were taken.
for groupIndex = find(instanceObjectCounts > 0)
    groupName = obj.labelGroupName(labelGroupUrls{groupIndex}, labelPyramids{groupIndex});
    if obj.BatchOpt.MergeInstanceObjects
        reportLines{end+1} = sprintf(['%s is an instance segmentation: its %d object(s) were ' ...
            'merged into the single material "%s". Which voxel belonged to which object is ' ...
            'not kept.'], groupName, instanceObjectCounts(groupIndex), ...
            materialNames{find(sourceGroup == groupIndex, 1)}); %#ok<AGROW>
    elseif numel(materialNames) > 255
        % core.MibDataset.createModel ignores material names above type 255 and
        % numbers them instead, so promising names here would be a lie - and the
        % numbering is MIB's own, not the store's ids, since the ids need not be
        % contiguous. Say both.
        reportLines{end+1} = sprintf(['%s is an instance segmentation: its %d object(s) were ' ...
            'kept, one material each. Materials are numbered 1..%d in the store''s id order; ' ...
            'a model this large carries no material names.'], ...
            groupName, instanceObjectCounts(groupIndex), numel(materialNames)); %#ok<AGROW>
    else
        reportLines{end+1} = sprintf(['%s is an instance segmentation: its %d object(s) were ' ...
            'kept as one material each, named by the object id the store uses.'], ...
            groupName, instanceObjectCounts(groupIndex)); %#ok<AGROW>
    end
end

% Instance groups are split too, but for a different reason and with different
% naming, so they are reported above and excluded here.
splitGroupCount = nnz(arrayfun(@(groupIndex) ...
    nnz(sourceGroup == groupIndex) > 1 && instanceObjectCounts(groupIndex) == 0, 1:nGroups));
if splitGroupCount > 0
    reportLines{end+1} = sprintf(['%d group(s) hold several classes in one array and were split ' ...
        'into separate materials, named by the class id the store uses (the ids are the ' ...
        'publisher''s own table, not the crop''s class_names order).'], splitGroupCount);
end

emptyMaterials = find(voxelCounts == 0);
if ~isempty(emptyMaterials)
    reportLines{end+1} = sprintf('Empty in this crop (kept as materials with no voxels): %s', ...
        strjoin(materialNames(emptyMaterials), ', '));
end

for pairIndex = 1:numel(overlapPairs)
    pair = overlapPairs(pairIndex);
    reportLines{end+1} = sprintf('Overlap: %s took %d voxel(s) from %s (later pick wins).', ...
        materialNames{pair.later}, pair.voxels, materialNames{pair.earlier}); %#ok<AGROW>
end

totalUnknown = sum(unknownCounts);
if totalUnknown > 0
    reportLines{end+1} = sprintf(['%d voxel(s) are marked "unknown" (not annotated) and are ' ...
        'material 0, the same as background - do not treat them as negatives.'], totalUnknown);
end

compositionReport = struct();
compositionReport.lines         = reportLines;
compositionReport.voxelCounts   = voxelCounts;
compositionReport.unknownCounts = unknownCounts;
compositionReport.overlaps      = overlapPairs;
compositionReport.isHomogeneous = isHomogeneous;
compositionReport.instanceObjectCounts = instanceObjectCounts;
end
