function setOptions(obj, options)
% function setOptions(obj, options)
% update options of the class
%
% Parameters:
% options: a structure with options to set

if nargin < 2; return; end

fieldNames = fieldnames(options);
for fieldId = 1:numel(fieldNames)
    obj.(fieldNames{fieldId}) = options.(fieldNames{fieldId});
end
obj.updateNodeStrel(obj.nodeRadius);     % update strel element

end
