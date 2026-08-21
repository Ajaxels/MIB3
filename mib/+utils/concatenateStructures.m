function primaryStruct = concatenateStructures(primaryStruct, secondaryStruct, knownFieldsOnly)
% CONCATENATESTRUCTURES - Update fields of primaryStruct using the fields of secondaryStruct.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      primaryStruct = concatenateStructures(primaryStruct, secondaryStruct)
%      primaryStruct = concatenateStructures(primaryStruct, secondaryStruct, knownFieldsOnly)
%
% Input Arguments:
%   - **primaryStruct** - primary structure that should be updated
%   - **secondaryStruct** - secondary structure that should be concatenated into the primary structure
%   - **knownFieldsOnly** - [optional, default false] logical; when ``false`` a field of
%     ``secondaryStruct`` that ``primaryStruct`` does not have is added to the result. When
%     ``true`` such a field is dropped instead, at every nesting level, so the result keeps
%     exactly the shape of ``primaryStruct`` and only its values are updated. Used when
%     restoring preferences saved by a **newer** MIB into an older one: the older version
%     must not inherit settings whose meaning it does not implement, see
%     :func:`models.MibModel.initializePreferences`
%
% Output Arguments:
%   - **primaryStruct** - updated primary structure
%
% Usage:
%
%   **Example 1** - update preferences structure from a saved session
%
%   .. code-block:: matlab
%
%      obj.mibModel.preferences = utils.concatenateStructures(obj.mibModel.preferences, mib_pars.preferences);
%
%   **Example 2** - take only the settings this version knows about
%
%   .. code-block:: matlab
%
%      obj.preferences = utils.concatenateStructures(obj.preferences, mib_pars.preferences, true);
%

% Updates
%

if nargin < 3; knownFieldsOnly = false; end

secFieldsList = fieldnames(secondaryStruct);

for fieldId = 1:length(secFieldsList)
    % a field the primary structure does not have is unknown to this version of
    % MIB; with knownFieldsOnly it is skipped rather than added
    if knownFieldsOnly && ~isfield(primaryStruct, secFieldsList{fieldId}); continue; end

    % try
    if isstruct(secondaryStruct.(secFieldsList{fieldId})) || ...
            ( isfield(primaryStruct, secFieldsList{fieldId}) && isstruct(primaryStruct.(secFieldsList{fieldId})) )
        if isempty(secondaryStruct.(secFieldsList{fieldId}))
            continue;
        elseif isfield(primaryStruct, secFieldsList{fieldId})
            if isstruct(secondaryStruct.(secFieldsList{fieldId}))
                primaryStruct.(secFieldsList{fieldId}) = ...
                    utils.concatenateStructures(primaryStruct.(secFieldsList{fieldId}), secondaryStruct.(secFieldsList{fieldId}), knownFieldsOnly);
            end
        else
            primaryStruct.(secFieldsList{fieldId}) = secondaryStruct.(secFieldsList{fieldId});
        end
    else
        primaryStruct.(secFieldsList{fieldId}) = secondaryStruct.(secFieldsList{fieldId});
    end
    % catch err
    %     err
    % end
end
end
