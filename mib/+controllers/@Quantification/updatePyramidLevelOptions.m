function updatePyramidLevelOptions(obj)
% UPDATEPYRAMIDLEVELOPTIONS - Refresh BatchOpt.BigData_PyramidLevel from the pyramid of the active dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.updatePyramidLevelOptions()
%
% Sets ``obj.BatchOpt.BigData_PyramidLevel`` to ``{selected, items}`` with one
% item per pyramid level of the active BigData dataset: ``'s0'`` (full
% resolution) to ``'sN'`` (coarsest). The items are plain level names without
% sizes, the format of ``controllers.BigDataOptions``, so a protocol recorded on
% one dataset matches the items of another. The selected level is kept when the
% dataset still has it, otherwise it falls back to ``'s0'``. A dataset that is
% not BigData gets ``{'s0', {'s0'}}``; the field is ignored for it.
%
% Called by the constructor (before the view exists, so batch mode also has
% the items) and by ``updateWidgets``.

% Updates
%

id = obj.mibModel.getActiveId();
dataset = obj.mibModel.I{id};

levelItems = {'s0'};
if strcmp(dataset.datasetType, 'BigData')
    levelItems = arrayfun(@(level) sprintf('s%d', level), ...
        0:size(dataset.image.pyramid.levelImageSizes, 1) - 1, 'UniformOutput', false);
end

selectedItem = 's0';
if isfield(obj.BatchOpt, 'BigData_PyramidLevel') && ~isempty(obj.BatchOpt.BigData_PyramidLevel) && ...
        ismember(obj.BatchOpt.BigData_PyramidLevel{1}, levelItems)
    selectedItem = obj.BatchOpt.BigData_PyramidLevel{1};
end
obj.BatchOpt.BigData_PyramidLevel = {selectedItem, levelItems};
end
