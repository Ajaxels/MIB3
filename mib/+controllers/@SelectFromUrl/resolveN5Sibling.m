function [resolvedUrl, swapped] = resolveN5Sibling(~, url)
% RESOLVEN5SIBLING - Swap an N5 container URL for the OME-Zarr copy beside it.
%
% Syntax:
%   .. code-block:: matlab
%
%      [resolvedUrl, swapped] = obj.resolveN5Sibling(url)
%
% OpenOrganelle publishes each volume twice, as an N5 container and as an
% OME-Zarr one, under the same stem::
%
%   jrc_hela-2/jrc_hela-2.n5/     <- what the dataset page hands out
%   jrc_hela-2/jrc_hela-2.zarr/   <- the same volume, readable here
%
% Both the "Fiji" link and the "Copy data url" button on a dataset page give
% the **N5** form, and MIB has no N5 reader at all, so a user following the
% website lands on a URL that can never work. Rather than reporting that, look
% for the OME-Zarr copy and use it. Verified present for every dataset checked
% in the ``janelia-cosem-datasets`` bucket.
%
% The swap is confirmed against the store, never assumed: a URL is only
% rewritten once ``probeRemoteZarr`` finds real zarr metadata at the candidate.
% A deep path inside the container is carried across intact, so
% ``.../jrc_hela-2.n5/recon-1/em/fibsem-uint8`` resolves to the matching group
% of the zarr copy rather than to its root.
%
% Input Arguments:
%   - **url** - [char] URL as typed, already normalised by
%     ``io.RemoteStore.normalise``
%
% Output Arguments:
%   - **resolvedUrl** - [char] the OME-Zarr URL when one was found, otherwise
%     ``url`` unchanged
%   - **swapped** - [logical] true when the URL was rewritten; the caller says
%     so in the status line rather than changing the address silently

resolvedUrl = url;
swapped     = false;

% Match '.n5' only where a path component ends, so a bucket or dataset whose
% name merely contains those characters is left alone. 'once' keeps the
% container name the only thing rewritten.
candidateUrl = regexprep(url, '\.n5(?=/|$)', '.zarr', 'once', 'ignorecase');
if strcmp(candidateUrl, url); return; end

% No zarr metadata at the candidate means there is no copy to switch to - and
% probeRemoteZarr caches, so the caller's own probe of the result is free.
if isempty(io.ExtensionRegistryLoad.probeRemoteZarr(candidateUrl)); return; end

resolvedUrl = candidateUrl;
swapped     = true;
end
