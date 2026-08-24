function docsPath = getDocsPath()
% GETDOCSPATH - Get the root folder of the built user documentation.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      docsPath = utils.getDocsPath()
%
% The documentation lives in two different places relative to the code, and
% which one is right depends on how MIB was started:
%
% - source checkout - ``docs`` is a sibling of ``mib``, so the pages are in
%   ``<mibPath>/../docs/html``
% - compiled standalone - the deployment scripts ship the pages next to the
%   executable, so they are in ``<mibPath>/docs/html``. There is no way to
%   place them a level higher: the MATLAB installer always puts the folders
%   listed in ``InstallerOptions.AdditionalFiles`` inside ``application``
%
% The deployed layout is tested first because ``mib/docs`` never exists in a
% checkout. When neither folder is present - a checkout with no built
% documentation - the checkout path is returned, which the callers then fail
% to find and open the page on mib.helsinki.fi instead.
%
% Output Arguments:
%   - **docsPath** - [char] full path to the ``docs/html`` folder; the path is not guaranteed to exist
%
% Usage:
%
%   **Example 1** - address of a single help page
%
%   .. code-block:: matlab
%
%      helpFilePath = fullfile(utils.getDocsPath(), ...
%          'user-interface', 'ribbon', 'dataset', 'dataset-alignment.html');
%

mibPath = utils.getInstallationPath('mib3');

docsPath = fullfile(mibPath, 'docs', 'html');
if isfolder(docsPath); return; end

docsPath = fullfile(fileparts(mibPath), 'docs', 'html');
end
