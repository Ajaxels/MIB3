% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi 
% Date: 25.04.2023

function primaryStruct = concatenateStructures(primaryStruct, secondaryStruct)
% function primaryStruct = concatenateStructures(primaryStruct, secondaryStruct)
% update fields of  primaryStruct using the fields of secondaryStruct
%
% Parameters:
% primaryStruct: primary structure that should be updates
% secondaryStruct: secondary structure that should be concatenated into the primary structure
%
% Return value:
% primaryStruct: updated primary structure

%| 
% @b Examples:
% @code obj.mibModel.preferences = utils.concatenateStructures(obj.mibModel.preferences, mib_pars.preferences); //updates fields of obj.mibModel.preferences with fields from mib_pars.preferences @endcode

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
                    mibConcatenateStructures(primaryStruct.(secFieldsList{fieldId}), secondaryStruct.(secFieldsList{fieldId}));
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