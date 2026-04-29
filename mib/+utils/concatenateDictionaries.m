function primaryDict = concatenateDictionaries(primaryDict, secondaryDict)
% CONCATENATEDICTIONARIES - Update keys of primaryDict using the keys of secondaryDict.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      primaryDict = concatenateDictionaries(primaryDict, secondaryDict)
%
% Input Arguments:
%   - **primaryDict** — primary dictionary that should be updated
%   - **secondaryDict** — secondary dictionary that should be concatenated into the primary dictionary
%
% Output Arguments:
%   - **primaryDict** — updated primary dictionary
%
% Usage:
%
%   **Example 1** — update preferences dictionary from a saved session
%
%   .. code-block:: matlab
%
%      obj.mibModel.preferences = utils.concatenateDictionaries(obj.mibModel.preferences, mib_pars.preferences);
%
    
    % Updates
    %
    
    % Handle empty dictionaries
    if isempty(secondaryDict) || numEntries(secondaryDict) == 0
        return;
    end
    
    secKeysList = keys(secondaryDict);
    for keyId = 1:length(secKeysList)
        % try
        if isa(secondaryDict(secKeysList{keyId}), 'dictionary') || ...
                (isKey(primaryDict, secKeysList{keyId}) && isa(primaryDict(secKeysList{keyId}), 'dictionary'))
            if isempty(secondaryDict(secKeysList{keyId}))
                continue;
            elseif isKey(primaryDict, secKeysList{keyId})
                if isa(secondaryDict(secKeysList{keyId}), 'dictionary')
                    primaryDict(secKeysList{keyId}) = ...
                        utils.concatenateDictionaries(primaryDict(secKeysList{keyId}), secondaryDict(secKeysList{keyId}));
                end
            else
                primaryDict(secKeysList{keyId}) = secondaryDict(secKeysList{keyId});
            end
        else
            primaryDict(secKeysList{keyId}) = secondaryDict(secKeysList{keyId});
        end
        % catch err
        %     err
        % end
    end
end
