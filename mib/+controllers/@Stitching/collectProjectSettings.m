function settings = collectProjectSettings(obj)
% COLLECTPROJECTSETTINGS - Flatten the tool's own parameters for the project sidecar.
%
% Syntax:
%   .. code-block:: matlab
%
%      settings = obj.collectProjectSettings()
%
% Produces the ``settings`` block written by :func:`utils.stitch.saveProject`
% (schema v3): one plain value per persisted ``BatchOpt`` field — dropdown and
% numeric-limit cells are reduced to their ``{1}`` entry, since the item lists
% and spinner limits belong to the controller, not to the saved project — plus
% the nested ``FeatureOptions`` (the feature-detector tuning behind the
% *Settings…* dialog). :meth:`controllers.Stitching.applyProjectSettings`
% reverses the flattening on load.
%
% Deliberately NOT persisted: ``showWaitbar`` and the ``mibBatch*`` fields
% (batch plumbing, not user settings) and ``id`` (the active dataset).
%
% Output Arguments:
%   - **settings** — struct with one field per persisted setting
%
% **Example** — save the current dialog state with the project:
%
%   .. code-block:: matlab
%
%      utils.stitch.saveProject(projectPath, obj.layout, obj.edges, obj.positions, ...
%          struct(), outputInfo, obj.tforms, obj.zSliceFixes, obj.collectProjectSettings());
%

settings = struct();
persistedFields = controllers.Stitching.projectSettingFields();

for fieldIdx = 1:numel(persistedFields)
    fieldName = persistedFields{fieldIdx};
    if ~isfield(obj.BatchOpt, fieldName); continue; end
    value = obj.BatchOpt.(fieldName);
    % Dropdowns {'value', {items}} and numeric spinners {value, [lims], 'on'}
    % both keep only their first element — the rest is controller-side metadata.
    if iscell(value); value = value{1}; end
    settings.(fieldName) = value;
end

% Feature-detector tuning (per-detector params, RANSAC, downsampling); a nested
% struct, so jsonencode keeps it readable and applyProjectSettings can merge it.
settings.FeatureOptions = obj.automaticOptions;

end
