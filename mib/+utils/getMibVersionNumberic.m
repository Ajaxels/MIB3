function mibVersionNumeric = getMibVersionNumberic(mibVersionString)
% GETMIBVERSIONNUMBERIC - Get MIB version as a numeric value from a version string.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      mibVersionNumeric = getMibVersionNumberic(mibVersionString)
%
% Two string formats are supported:
%
% - Release:  ``'ver. 2.909 / 06.08.2024'`` - ``mibVersionNumeric`` is extracted
%   from the text between ``'ver.'`` and ``'/'``.
% - Beta:     ``'ver. 2.909 (beta 07) / 06.08.2024'`` - ``mibVersionNumeric`` is
%   computed as version minus beta offset: ``2.909 - (1000 - 7) / 1000000``.
%
% Input Arguments:
%   - **mibVersionString** - [char] MIB version string as defined in ``mib3.m``
%
% Output Arguments:
%   - **mibVersionNumeric** - [double] numeric representation of the MIB version
%
% Usage:
%
%   **Example 1** - parse a release version string
%
%   .. code-block:: matlab
%
%      ver = utils.getMibVersionNumberic('ver. 2025.12 / 05.12.2025');
%
%   **Example 2** - parse a beta version string
%
%   .. code-block:: matlab
%
%      ver = utils.getMibVersionNumberic('ver. 2025.11 (beta 4) / 04.11.2025');
%

arguments (Input)
    mibVersionString (1,:) char
end

arguments (Output)
    mibVersionNumeric (1,1) double
end

index1 = strfind(mibVersionString, 'ver.');
index2 = strfind(mibVersionString, '/');

% look for beta keyword
% expected syntax "ver. 2.909 (beta 04) / 06.08.2024"
%                 'ver. 2025.11 (beta 4) / 04.11.2025'
index3 = strfind(mibVersionString, 'beta');

if isempty(index3) % release, no beta
    mibVersionNumeric = str2double(mibVersionString(index1+4:index2-1));
else % for beta version mibVersionNumeric is calculated as the version - beta/10000
    index4 = strfind(mibVersionString, ')');
    
    % % print the beta version as string:
    % sprintf('%s', str2double(mibVersionString(index1+4:index3-2)) - ...
    %    (.01 - str2double(mibVersionString(index3+4:index4-1))/10000))

    mibVersionNumeric = ...
        str2double(mibVersionString(index1+4:index3-2)) - ...
        (.01 - str2double(mibVersionString(index3+4:index4-1))/10000);
        
end

end
