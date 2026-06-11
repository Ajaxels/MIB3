function result = hasTestData(spec)
% HASTESTDATA - Return true if test data is cached locally or the server is reachable.
%
% First checks whether both raw files exist in spec.cacheDir with the expected
% byte counts (uint8 => bytes == elements). If cached and valid, returns true
% without any network activity.
%
% If not cached, probes mib.helsinki.fi reachability via a Java DNS lookup
% (fast, no HTTP traffic). Returns false on any network error so that tests
% can self-skip offline rather than failing.
%
% Syntax:
%   tf = mibtest.helpers.hasTestData(mibtest.helpers.datasetSpec('Trypanosoma'))

imageFile  = fullfile(spec.cacheDir, urlBasename(spec.imageUrl));
labelsFile = fullfile(spec.cacheDir, urlBasename(spec.labelsUrl));
imageBytes  = prod(spec.imageDims);
labelsBytes = prod(spec.labelsDims);

if isfile(imageFile) && isfile(labelsFile)
    imageInfo  = dir(imageFile);
    labelsInfo = dir(labelsFile);
    if imageInfo.bytes == imageBytes && labelsInfo.bytes == labelsBytes
        result = true;
        return
    end
end

result = false;
try
    java.net.InetAddress.getByName('mib.helsinki.fi');
    result = true;
catch
end
end

function name = urlBasename(url)
parts = strsplit(url, '/');
name  = parts{end};
end
