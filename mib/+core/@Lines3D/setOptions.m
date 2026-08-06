function setOptions(obj, options)
% SETOPTIONS - update options of the class.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.setOptions(options)
%
% Input Arguments:
%   - **options** - a structure with options to set
%

if nargin < 2; return; end

fieldNames = fieldnames(options);
for fieldId = 1:numel(fieldNames)
    obj.(fieldNames{fieldId}) = options.(fieldNames{fieldId});
end
obj.nodeStrel = [];     % invalidate the strel cache; rebuilt lazily in addLinesToImage

end
