function [imageVolume, labelVolume] = cachedRawDataset(spec)
% CACHEDRAWDATASET - Load raw uint8 image and labels volumes, downloading once if needed.
%
% Checks spec.cacheDir for both files with byte counts matching prod(spec.*Dims).
% If valid cached files exist they are read directly; otherwise the raw bytes are
% downloaded via webread and written to the cache, then reshaped and returned.
%
% Syntax:
%   [imageVolume, labelVolume] = mibtest.helpers.cachedRawDataset(spec)
%
% Output:
%   imageVolume  — uint8 [H W D C] as in spec.imageDims
%   labelVolume  — uint8 [H W D]   as in spec.labelsDims

if ~isfolder(spec.cacheDir)
    mkdir(spec.cacheDir);
end

imageFile  = fullfile(spec.cacheDir, urlBasename(spec.imageUrl));
labelsFile = fullfile(spec.cacheDir, urlBasename(spec.labelsUrl));

imageVolume  = loadOrDownload(imageFile, spec.imageUrl,  spec.imageDims);
labelVolume  = loadOrDownload(labelsFile, spec.labelsUrl, spec.labelsDims);
end

% -------------------------------------------------------------------------

function data = loadOrDownload(localFile, url, dims)
expectedBytes = prod(dims);
if isfile(localFile)
    fileInfo = dir(localFile);
    if fileInfo.bytes == expectedBytes
        fid = fopen(localFile, 'r');
        raw = fread(fid, expectedBytes, '*uint8');
        fclose(fid);
        data = reshape(raw, dims);
        return
    end
end

fprintf('[cachedRawDataset] downloading %s ...\n', url);
raw = webread(url, weboptions('ContentType', 'raw', 'Timeout', 300));
fid = fopen(localFile, 'w');
fwrite(fid, raw, 'uint8');
fclose(fid);
data = reshape(uint8(raw), dims);
fprintf('[cachedRawDataset] saved to %s\n', localFile);
end

function name = urlBasename(url)
parts = strsplit(url, '/');
name  = parts{end};
end
