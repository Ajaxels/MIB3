function closeVirtualDataset(obj)
% CLOSEVIRTUALDATASET - Close open virtual readers and loader objects to release file handles.
%
% Syntax:
%   function closeVirtualDataset(obj)
%
% Closes any BioFormatsVirtualLoader readers held in obj.loaders, then
% clears the loaders cache.  Also handles the legacy case where BioFormats
% Memoizer handles were stored directly in obj.data{}.
%
% Input Arguments:
%
% Output Arguments:
%   % Updates
%

% --- close cached loader objects ------------------------------------------
for i = 1:numel(obj.loaders)
    if ~isempty(obj.loaders{i}) && isa(obj.loaders{i}, 'io.loaders.BioFormatsVirtualLoader')
        obj.loaders{i}.close();
    end
end
obj.loaders = {};

% --- legacy: readers stored directly in obj.data (old approach) -----------
if iscell(obj.data) && ~isempty(obj.data) && isa(obj.data{1}, 'loci.formats.Memoizer')
    for imgId = 1:numel(obj.data)
        try
            obj.data{imgId}.close();
        catch
            % reader may already be closed; ignore
        end
    end
end
end
