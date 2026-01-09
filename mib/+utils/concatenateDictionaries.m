function primaryDict = concatenateDictionaries(primaryDict, secondaryDict)
    % function primaryDict = concatenateDictionaries(primaryDict, secondaryDict)
    % update keys of primaryDict using the keys of secondaryDict
    %
    % Parameters:
    % primaryDict: primary dictionary that should be updated
    % secondaryDict: secondary dictionary that should be concatenated into the primary dictionary
    %
    % Return value:
    % primaryDict: updated primary dictionary
    %|
    % @b Examples:
    % @code obj.mibModel.preferences = utils.concatenateDictionaries(obj.mibModel.preferences, mib_pars.preferences); //updates keys of obj.mibModel.preferences with keys from mib_pars.preferences @endcode
    
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
