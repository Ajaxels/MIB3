function closeVirtualDataset(obj)
% function closeVirtualDataset(obj)
% Close opened virtual dataset readers to release file locks.
%
% Currently handles BioFormats Memoizer readers stored in obj.data{}.
% Call this before re-initialising or destroying the virtual image.
%
% Parameters:
%
% Return values:
%% Updates
%
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
