function mibVersion = getMibVersion()
% GETMIBVERSION - The version string of this MIB installation.
%
% Syntax:
%   .. code-block:: matlab
%
%      mibVersion = getMibVersion()
%
% This is the single place where the version is written down. ``mib3.m`` passes
% the returned string to :class:`models.MibModel` and
% :class:`controllers.MibController`, and it is also the default value of the
% ``mibVersion`` argument of the ``MibModel`` constructor, so a model built
% outside the application (tests, scripts) reports the same version as the
% application itself.
%
% .. warning::
%
%    Keeping a second copy of the string anywhere is a bug. The numeric form
%    (:func:`utils.getMibVersionNumberic`) is compared against the version
%    recorded in ``mib3.mat`` to decide how the saved preferences are restored:
%    when the saved version is **newer** than the running one, neither branch of
%    that comparison applies and the saved preferences are silently dropped in
%    favour of the defaults. A stale duplicate of this string therefore makes
%    MIB ignore the user's own preferences, see
%    :func:`models.MibModel.initializePreferences`.
%
% ATTENTION! it is important to have the version number between "ver." and "/"
%
% - Release syntax example: ``ver. 2025.11 / 04.11.2025``
% - Beta syntax example: ``ver. 2025.11 (beta 4) / 04.11.2025``
%
% Output Arguments:
%   - **mibVersion** - [char] version of MIB, for example
%     ``'ver. 2026.09 / 20.08.2026 (preview)'``
%
% Usage:
%   **Example 1** - the numeric version used for the preferences comparison
%
%   .. code-block:: matlab
%
%      versionNumeric = utils.getMibVersionNumberic(utils.getMibVersion());
%
% See also: utils.getMibVersionNumberic, models.MibModel,
% models.MibModel.initializePreferences

arguments (Output)
    mibVersion (1,:) char
end

% ATTENTION! it is important to have the version number between "ver." and "/"
% Release syntax example: "ver. 2025.11 / 04.11.2025"
% Beta syntax example: "ver. 2025.11 (beta 4) / 04.11.2025"
% This is the ONLY place where the version string may be edited: mib3.m and the
% default value of the mibVersion argument of models.MibModel both read it from
% here, and a second copy that falls behind makes MIB discard the preferences
% saved by the newer version (see models.MibModel.initializePreferences)

mibVersion = 'ver. 2026.10 / 04.10.2026';

end
