function appliedFields = applyProjectSettings(obj, settings, skipFields)
% APPLYPROJECTSETTINGS - Restore tool parameters from a project sidecar into BatchOpt.
%
% Syntax:
%   .. code-block:: matlab
%
%      appliedFields = obj.applyProjectSettings(settings)
%      appliedFields = obj.applyProjectSettings(settings, skipFields)
%
% Reverses the flattening done by :meth:`controllers.Stitching.collectProjectSettings`:
% each saved value is written back into the ``{1}`` slot of a dropdown / numeric
% ``BatchOpt`` cell, or straight into a logical / char field, guided by the SHAPE
% of the current default. Unknown fields, dropdown items no longer offered, and
% type mismatches are ignored rather than raising - a project saved by an older
% MIB must still load into a newer dialog.
%
% The method only touches ``obj.BatchOpt`` and ``obj.automaticOptions``: it never
% rebuilds the layout or touches measurements, so the caller decides what the new
% settings mean for the current tiles (see
% :meth:`controllers.Stitching.loadProjectBtn_Callback`).
%
% Input Arguments:
%   - **settings** - struct as returned by :func:`utils.stitch.loadProject`
%     (8th output); an empty struct applies nothing
%   - **skipFields** *(optional)* - [cell] field names to leave untouched.
%     Pass ``{'InputPath', 'OutputPath'}`` for the "settings only" load, where
%     the parameters are reused on a DIFFERENT set of tiles.
%
% Output Arguments:
%   - **appliedFields** - [cell] names of the fields actually written
%
% **Example** - reuse a project's parameters on the tiles selected right now:
%
%   .. code-block:: matlab
%
%      [~, ~, ~, ~, ~, ~, ~, settings] = utils.stitch.loadProject(projectPath);
%      obj.applyProjectSettings(settings, {'InputPath', 'OutputPath'});
%      obj.buildLayoutFromBatchOpt();
%

arguments
    obj
    settings struct
    skipFields cell = {}
end

appliedFields = {};
if isempty(fieldnames(settings)); return; end

% A project saved before a field was renamed still has to load (AtlasImport ->
% LayoutImport). Same mapping the batch entry point applies, so the two agree.
settings = controllers.Stitching.renameLegacyFields(settings);

% ---- Feature-detector tuning (nested struct, merged field by field) ----
if isfield(settings, 'FeatureOptions') && isstruct(settings.FeatureOptions) && ...
        ~ismember('FeatureOptions', skipFields)
    % jsondecode returns arrays as COLUMNS; the detectors take row vectors
    % (e.g. detectMSERFeatures 'RegionAreaRange'), so restore the orientation.
    obj.automaticOptions = utils.concatenateStructures(obj.automaticOptions, ...
        numericFieldsToRows(settings.FeatureOptions));
    appliedFields{end+1} = 'FeatureOptions';
end

% ---- Flat BatchOpt fields ----
persistedFields = controllers.Stitching.projectSettingFields();
for fieldIdx = 1:numel(persistedFields)
    fieldName = persistedFields{fieldIdx};
    if ~isfield(settings, fieldName) || ~isfield(obj.BatchOpt, fieldName); continue; end
    if ismember(fieldName, skipFields); continue; end

    savedValue   = settings.(fieldName);
    currentValue = obj.BatchOpt.(fieldName);

    if iscell(currentValue)
        if numel(currentValue) > 1 && iscell(currentValue{2})
            % Dropdown {'selected', {items}} - accept only items this MIB offers,
            % so a renamed/removed choice falls back to the current default.
            savedValue = char(savedValue);
            if ~ismember(savedValue, currentValue{2}); continue; end
            obj.BatchOpt.(fieldName){1} = savedValue;
        else
            % Numeric spinner {value, [minLim maxLim], 'on'|'off'} - clamp to the
            % limits in force now (they may be dataset-derived).
            if ~isnumeric(savedValue) || ~isscalar(savedValue); continue; end
            savedValue = double(savedValue);
            if numel(currentValue) > 1 && numel(currentValue{2}) == 2
                savedValue = min(max(savedValue, currentValue{2}(1)), currentValue{2}(2));
            end
            obj.BatchOpt.(fieldName){1} = savedValue;
        end
    elseif islogical(currentValue)
        if ~(isnumeric(savedValue) || islogical(savedValue)) || ~isscalar(savedValue); continue; end
        obj.BatchOpt.(fieldName) = logical(savedValue);
    elseif ischar(currentValue)
        if ~(ischar(savedValue) || isstring(savedValue)); continue; end
        obj.BatchOpt.(fieldName) = char(savedValue);
    else
        obj.BatchOpt.(fieldName) = savedValue;
    end
    appliedFields{end+1} = fieldName; %#ok<AGROW>
end

end

% =========================================================================
function structIn = numericFieldsToRows(structIn)
% NUMERICFIELDSTOROWS - Reshape every numeric vector in a (possibly nested)
% struct to a row, undoing jsondecode's column orientation.

fieldList = fieldnames(structIn);
for fieldIdx = 1:numel(fieldList)
    value = structIn.(fieldList{fieldIdx});
    if isstruct(value)
        structIn.(fieldList{fieldIdx}) = numericFieldsToRows(value);
    elseif isnumeric(value) && isvector(value) && ~isscalar(value)
        structIn.(fieldList{fieldIdx}) = reshape(value, 1, []);
    end
end

end
