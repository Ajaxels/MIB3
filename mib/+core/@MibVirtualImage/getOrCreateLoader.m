function loader = getOrCreateLoader(obj, fileIdx)
% function loader = getOrCreateLoader(obj, fileIdx)
% Return the virtual loader for the given file index, creating it if needed.
%
% Loaders are created lazily on first access and cached in obj.loaders{fileIdx}.
% The loader type is determined by obj.Virtual.objectType{fileIdx}:
%   'matlab.hdf5' / 'hdf5_image'  ->  io.loaders.HDF5VirtualLoader
%   'bioformats'                   ->  io.loaders.BioFormatsVirtualLoader
%
% Parameters:
% fileIdx : [numeric] 1-based index into obj.data{} / obj.Virtual arrays
%
% Return values:
% loader  : loader object (HDF5VirtualLoader or BioFormatsVirtualLoader)

%% Updates
%

if fileIdx <= numel(obj.loaders) && ~isempty(obj.loaders{fileIdx})
    loader = obj.loaders{fileIdx};
    return;
end

objectType = obj.Virtual.objectType{fileIdx};
filename   = obj.data{fileIdx};

switch objectType
    case {'matlab.hdf5', 'hdf5_image'}
        loader = io.loaders.HDF5VirtualLoader(filename, obj.Virtual.seriesName{fileIdx});

    case 'bioformats'
        % seriesName stores a 1-based series number for BioFormats;
        % BioFormatsVirtualLoader expects 0-based
        loader = io.loaders.BioFormatsVirtualLoader( ...
            filename, ...
            obj.Virtual.seriesName{fileIdx} - 1, ...
            obj.bioFormatsMemoizerMemoDir);

    otherwise
        error('core:MibVirtualImage:unknownObjectType', ...
            'getOrCreateLoader: unknown objectType "%s" for file "%s"', ...
            objectType, filename);
end

obj.loaders{fileIdx} = loader;
end
