function loadOptions = buildLoadImagesBatchOpt(obj)
% BUILDLOADIMAGESBATCHOPT - Map the dialog state onto MibModel.loadImages options.
%
% Syntax:
%   .. code-block:: matlab
%
%      loadOptions = obj.buildLoadImagesBatchOpt()
%
% Kept pure - no network, no widgets, no side effects - so the mapping can be
% asserted in a unit test without opening anything.
%
% Two details are load-bearing:
%
%   * ``Filenames`` **must** be present. ``MibModel.loadImages`` only skips its
%     ``fullfile`` path joins when the incoming BatchOpt carries that field, and
%     ``fullfile`` would rewrite ``https://host/group`` as ``https://host\group``
%     on Windows.
%   * ``DirectoryName`` gets the current MIB directory, never the URL, so the
%     recent-directories list stays usable.
%
% Output Arguments:
%   - **loadOptions** - [struct] BatchOpt for ``MibModel.loadImages``

loadOptions = struct();
loadOptions.Mode          = {'Combine datasets'};
loadOptions.Filenames     = {obj.rootUrl};
loadOptions.DirectoryName = {obj.mibModel.currentDirectory};
loadOptions.Reader        = {'Default'};
loadOptions.ZarrGroupPath = obj.BatchOpt.GroupPath;
loadOptions.showWaitbar   = obj.BatchOpt.showWaitbar;
loadOptions.id            = obj.BatchOpt.id;
end
