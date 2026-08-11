function [modelData, materialNames, compositionReport] = composeLabelModel(obj, labelGroupUrls, labelPyramids, cropPlan, progressDialog)
% COMPOSELABELMODEL - Blend the selected COSEM label groups into one MIB model.
%
% Syntax:
%   .. code-block:: matlab
%
%      [modelData, materialNames, compositionReport] = obj.composeLabelModel(labelGroupUrls, labelPyramids, cropPlan, progressDialog)
%
% **Two kinds of group, and they encode their values differently.** Getting this
% wrong produces an empty model rather than an error, so the distinction is read
% from the store, never assumed:
%
%   * A **single-class** group carries a ``cellmap.annotation`` block declaring
%     ``semantic_segmentation`` and a ``present`` value. Its data is binary, and
%     it becomes exactly one material.
%   * An **index map** - the merged ``all`` group of a crop - carries **no**
%     ``cellmap`` block at all, and every distinct non-zero value is a different
%     class. It becomes one material per value present.
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
%     ``.voxelCounts``, ``.unknownCounts``, ``.overlaps``, ``.isHomogeneous``

shapeYXZ = cropPlan.shapeYXZ;
nGroups  = numel(labelGroupUrls);

% Materials are discovered as groups are read - an index map contributes as many
% as it holds distinct values - so the map starts as uint16 and is narrowed once
% the final count is known.
modelData     = zeros(shapeYXZ, 'uint16');
materialNames = {};
voxelCounts   = [];
unknownCounts = zeros(1, nGroups);
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

    if isSemantic
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

    for classIndex = 1:numel(classValues)
        materialIndex = numel(materialNames) + 1;
        materialNames{materialIndex} = classLabels{classIndex}; %#ok<AGROW>
        sourceGroup(materialIndex)   = groupIndex;              %#ok<AGROW>

        presentMask = (block == classValues(classIndex));

        alreadyLabelled = presentMask & (modelData ~= 0);
        if any(alreadyLabelled(:))
            overwritten = modelData(alreadyLabelled);
            for earlierIndex = unique(overwritten)'
                overlapPairs(end+1) = struct('later', materialIndex, ...
                    'earlier', double(earlierIndex), ...
                    'voxels', nnz(overwritten == earlierIndex)); %#ok<AGROW>
            end
        end

        modelData(presentMask)     = materialIndex;
        voxelCounts(materialIndex) = nnz(presentMask); %#ok<AGROW>
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

splitGroupCount = nnz(arrayfun(@(groupIndex) nnz(sourceGroup == groupIndex) > 1, 1:nGroups));
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
end
