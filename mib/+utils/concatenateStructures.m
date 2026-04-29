function primaryStruct = concatenateStructures(primaryStruct, secondaryStruct)
% CONCATENATESTRUCTURES - Update fields of primaryStruct using the fields of secondaryStruct.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      primaryStruct = concatenateStructures(primaryStruct, secondaryStruct)
%
% Input Arguments:
%   - **primaryStruct** — primary structure that should be updated
%   - **secondaryStruct** — secondary structure that should be concatenated into the primary structure
%
% Output Arguments:
%   - **primaryStruct** — updated primary structure
%
% Usage:
%
%   **Example 1** — update preferences structure from a saved session
%
%   .. code-block:: matlab
%
%      obj.mibModel.preferences = utils.concatenateStructures(obj.mibModel.preferences, mib_pars.preferences);
%

% Updates
% 

secFieldsList = fieldnames(secondaryStruct);

for fieldId = 1:length(secFieldsList)
    % try
    if isstruct(secondaryStruct.(secFieldsList{fieldId})) || ...
            ( isfield(primaryStruct, secFieldsList{fieldId}) && isstruct(primaryStruct.(secFieldsList{fieldId})) )
        if isempty(secondaryStruct.(secFieldsList{fieldId}))
            continue;
        elseif isfield(primaryStruct, secFieldsList{fieldId})
            if isstruct(secondaryStruct.(secFieldsList{fieldId}))
                primaryStruct.(secFieldsList{fieldId}) = ...
                    utils.concatenateStructures(primaryStruct.(secFieldsList{fieldId}), secondaryStruct.(secFieldsList{fieldId}));
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
