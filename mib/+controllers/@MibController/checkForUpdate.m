function checkForUpdate(obj)
% CHECKFORUPDATE - Check the MIB website for availability of a newer version.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.checkForUpdate()
%
% Fetches the latest released version number from mib.helsinki.fi and offers
% to start the update procedure when a newer version is available. The check
% is only performed when more days than
% ``preferences.System.Update.RecheckPeriod`` have passed since the last check.
%
% Executed from the single-shot ``obj.updateCheckTimer`` started at the end of
% ``MibController.initialize``, so the network request (up to 4 s timeout)
% never blocks the GUI during startup.
%
% Output Arguments:
%   (none)
%

arguments (Input)
    obj controllers.MibController
end

% MIB may have been closed between timer creation and firing
if isempty(obj.view) || ~isvalid(obj.view.gui); return; end

currentDate = floor(now);  %#ok<TNOW1>
if currentDate - obj.mibModel.preferences.System.Update.SinceLastCheck <= ...
        obj.mibModel.preferences.System.Update.RecheckPeriod
    return;
end
obj.mibModel.preferences.System.Update.SinceLastCheck = currentDate;

if isdeployed
    if ismac
        link = 'http://mib.helsinki.fi/web-update/mib3_mac.txt';
    elseif isunix
        link = 'http://mib.helsinki.fi/web-update/mib3_linux.txt';
    else
        link = 'http://mib.helsinki.fi/web-update/mib3_win.txt';
    end
else
    link = 'http://mib.helsinki.fi/web-update/mib3_matlab.txt';
end
try
    urlText = webread(link, weboptions('Timeout', 4, 'ContentType', 'text'));
catch
    urlText = '0';
end
linefeedPositions = strfind(urlText, sprintf('\n'));
if ~isempty(linefeedPositions)
    availableVersion = str2double(urlText(1:linefeedPositions(1)));
else
    availableVersion = str2double(urlText);
end
mibVersionNumeric = utils.getMibVersionNumberic(obj.mibModel.mibVersion);
if availableVersion - mibVersionNumeric > 0
    answer = utils.dlgs.inputQuestDlg(obj.mibModel.getProgressBarParent(), ...
        sprintf('A new version %g of MIB is available!\nWould you like to download/install it?\n\nYou can always do that later via Help \x2192 Check for Update.', availableVersion), ...
        'New version available', 'Update now', 'Later', 'Update now');
    if strcmp(answer, 'Update now')
        obj.startController('controllers.UpdateCheck', obj);
    end
end

end
