function loader = getOrCreateLoader(obj, fileIdx)
% GETORCREATELOADER - Return the virtual loader for the given file index, creating it if needed.
%
% Syntax:
%   .. code-block:: matlab
%
%       loader = obj.getOrCreateLoader(fileIdx)
%
% Loaders are created lazily on first access and cached in obj.loaders{fileIdx}.
% The loader type is determined by obj.Virtual.objectType{fileIdx}:
% 'matlab.hdf5' / 'hdf5_image' io.loaders.HDF5VirtualLoader
% 'bioformats' io.loaders.BioFormatsVirtualLoader
% 'zarr3' io.loaders.Zarr3VirtualLoader
%
% Input Arguments:
%   - **fileIdx** — [numeric] 1-based index into obj.filePaths{} / obj.Virtual arrays
%
% Output Arguments:
%   - **loader** — loader object (HDF5VirtualLoader or BioFormatsVirtualLoader)
%

%% Updates
%

if fileIdx <= numel(obj.loaders) && ~isempty(obj.loaders{fileIdx})
    loader = obj.loaders{fileIdx};
    return;
end

objectType = obj.Virtual.objectType{fileIdx};
filename   = obj.filePaths{fileIdx};

switch objectType
    case {'matlab.hdf5', 'hdf5_image'}
        % Pass transMatrix so resolveAxisOrder uses the correct native axis
        % order (set by the user in the SelectHDFSeries dialog) instead of
        % guessing from JSON attributes or falling back to 'yxzct'.
        tm = [];
        if isfield(obj.Virtual, 'transMatrix') && fileIdx <= numel(obj.Virtual.transMatrix)
            tm = obj.Virtual.transMatrix{fileIdx};
        end
        loader = io.loaders.HDF5VirtualLoader(filename, obj.Virtual.seriesName{fileIdx}, tm);

    case 'bioformats'
        % seriesName stores a 1-based series number for BioFormats;
        % BioFormatsVirtualLoader expects 0-based
        loader = io.loaders.BioFormatsVirtualLoader( ...
            filename, ...
            obj.Virtual.seriesName{fileIdx} - 1, ...
            obj.bioFormatsMemoizerMemoDir);

    case 'zarr3'
        % Zarr v3 OME-Zarr — root path is in obj.filePaths{1}, axis order from pyramid
        axOrder = 'tczyx';
        if isfield(obj.pyramid, 'axisOrder') && ~isempty(obj.pyramid.axisOrder)
            axOrder = obj.pyramid.axisOrder;
        end
        loader = io.loaders.Zarr3VirtualLoader(obj.filePaths{1}, axOrder);

    otherwise
        error('core:MibVirtualImage:unknownObjectType', ...
            'getOrCreateLoader: unknown objectType "%s" for file "%s"', ...
            objectType, filename);
end

obj.loaders{fileIdx} = loader;
end
