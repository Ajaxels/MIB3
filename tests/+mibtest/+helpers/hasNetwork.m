function result = hasNetwork(hostName)
% HASNETWORK - Return true if a host is resolvable, so network tests can self-skip.
%
% Probes reachability with a Java DNS lookup, which is fast and generates no
% HTTP traffic. Any failure returns false rather than throwing, so a test can
% call it from assumeTrue and be filtered out offline instead of failing.
%
% The result is cached per host for the MATLAB session: a suite with several
% network tests would otherwise repeat the same lookup, and the answer does not
% change mid-run in practice.
%
% Syntax:
%   tf = mibtest.helpers.hasNetwork()
%   tf = mibtest.helpers.hasNetwork('janelia-cosem-datasets.s3.amazonaws.com')
%
% Input Arguments:
%   - hostName - (optional) [char] host to resolve (default: 'mib.helsinki.fi')
%
% Output Arguments:
%   - result - [logical] true when the host resolved

if nargin < 1 || isempty(hostName); hostName = 'mib.helsinki.fi'; end
hostName = char(hostName);

persistent probedHosts
if isempty(probedHosts)
    probedHosts = configureDictionary("string", "logical");
end

if isKey(probedHosts, string(hostName))
    result = probedHosts(string(hostName));
    return
end

result = false;
try
    java.net.InetAddress.getByName(hostName);
    result = true;
catch
end

probedHosts(string(hostName)) = result;
end
