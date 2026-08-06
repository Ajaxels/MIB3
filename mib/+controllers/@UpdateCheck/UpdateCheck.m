classdef UpdateCheck < handle
% UPDATECHECK - Controller for the Check for Update dialog.

    properties
        mibModel
        % handle to the model
        view
        % handle to the view
        mibController
        % handle to MibController; optional, required only for in-place update restart
        mibVersion
        % numeric version of the currently running MIB (double)
    end

    events
        CloseEvent
        % fires when the window is closed
    end

    methods

        function obj = UpdateCheck(mibModel, varargin)
        % UPDATECHECK - Constructor for the Check for Update dialog controller.
        %
        % Syntax:
        %
        %   .. code-block:: matlab
        %
        %      controller = controllers.UpdateCheck(mibModel)
        %      controller = controllers.UpdateCheck(mibModel, mibController)
        %
        % Input Arguments:
        %   - **mibModel** - handle to the MibModel instance
        %   - **mibController** - *(optional)* handle to MibController; pass when the
        %     in-place MATLAB update button needs to call ``exitProgram()``
        %
        % Output Arguments:
        %   - **controller** - handle to the constructed ``UpdateCheck`` controller

            obj.mibModel = mibModel;
            if nargin > 1 && ~isempty(varargin{1})
                obj.mibController = varargin{1};
            else
                obj.mibController = [];
            end
            obj.mibVersion = utils.getMibVersionNumberic(obj.mibModel.mibVersion);

            obj.view = core.ChildView(obj, 'views.UpdateCheckGUI');

            obj.updateWidgets();
            obj.addCallbacks();

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.informationText.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.informationText.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'center', 'center');
            %obj.view.gui.WindowStyle = 'modal';
            obj.view.gui.Visible = true;
        end

        function addCallbacks(obj)
        % ADDCALLBACKS - Wire all widget callbacks and tooltips for the Update Check dialog.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            handles = obj.view.handles;

            handles.closeButton.ButtonPushedFcn      = @(~,~) obj.closeWindow();
            handles.websiteBtn.ButtonPushedFcn       = @(~,~) web('http://mib.helsinki.fi', '-browser');
            handles.listofchangesBtn.ButtonPushedFcn = @(~,~) web('http://mib.helsinki.fi/downloads.html', '-browser');
            handles.downloadBtn.ButtonPushedFcn      = @(~,~) obj.downloadBtn_Callback();
            handles.updateBtn.ButtonPushedFcn        = @(~,~) obj.updateBtn_Callback();

            handles.recheckPeriodSpinner.ValueChangedFcn = @(src,~) obj.recheckPeriodSpinner_Callback(src);

            handles.closeButton.Tooltip           = 'Close this dialog';
            handles.websiteBtn.Tooltip            = 'Open the MIB website (mib.helsinki.fi) in a browser';
            handles.listofchangesBtn.Tooltip      = 'Open the MIB downloads and changelog page in a browser';
            handles.downloadBtn.Tooltip           = 'Download the latest MIB installer for your platform';
            handles.updateBtn.Tooltip             = 'Download and install the latest MIB update in-place (MATLAB mode only)';
            handles.informationText.Tooltip       = 'Comparison of the running version against the latest available version';
            handles.informationEdit.Tooltip       = 'Release notes or general information from the MIB server';
            handles.recheckPeriodSpinner.Tooltip  = 'Number of days between automatic update checks at startup';
        end

        function updateWidgets(obj)
        % UPDATEWIDGETS - Fetch the version file from the MIB server and populate the dialog.
        %
        % Selects the appropriate URL by platform, fetches the text file, parses the
        % version number and HTML sections, then updates ``informationText`` and the
        % ``informationEdit`` HTML pane.

            if isdeployed
                obj.view.handles.updateBtn.Enable = 'off';
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
                urlText = urlread(link, 'Timeout', 4);  %#ok<URLRD>
            catch
                urlText = sprintf('<html>\n<div style="font-family:arial;">\n<b>The update file has not been detected...</b>\n</div>\n</html>\n---Info---\n<html></html>');
            end

            htmlStartPositions = strfind(urlText, '<html>');
            infoSeparatorPosition = strfind(urlText, '---Info---');
            if ~isempty(htmlStartPositions) && ~isempty(infoSeparatorPosition)
                availableVersion = str2double(urlText(1:htmlStartPositions(1)-1));
                releaseComments = urlText(htmlStartPositions(1):infoSeparatorPosition(1)-2);
                infoText = urlText(htmlStartPositions(2):end);
            else
                availableVersion = str2double(urlText);
                releaseComments = '';
                infoText = '';
            end

            obj.view.handles.recheckPeriodSpinner.Value = obj.mibModel.preferences.System.Update.RecheckPeriod;

            if availableVersion - obj.mibVersion > 0
                obj.view.handles.informationText.Text = ...
                    sprintf('New version (%g) of Microscopy Image Browser is available!', availableVersion);
                obj.view.handles.informationEdit.HTMLSource = releaseComments;
            else
                obj.view.handles.informationText.Text = ...
                    'You are running the latest version of Microscopy Image Browser!';
                obj.view.handles.informationEdit.HTMLSource = infoText;
            end
        end

        function downloadBtn_Callback(obj)
        % DOWNLOADBTN_CALLBACK - Open the platform-specific MIB download page in a browser.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.UpdateCheck.downloadBtn_Callback: triggered\n');
            end
            if isdeployed
                if ismac
                    web('http://mib.helsinki.fi/web-update3/MIB3_Mac.zip', '-browser');
                elseif isunix
                    web('http://mib.helsinki.fi/web-update3/MIB3_Linux.zip', '-browser');
                else
                    web('http://mib.helsinki.fi/web-update3/MIB3_Win.zip', '-browser');
                end
            else
                web('http://mib.helsinki.fi/web-update3/MIB3_Matlab.zip', '-browser');
            end
        end

        function updateBtn_Callback(obj)
        % UPDATEBTN_CALLBACK - Download and install a MIB update in-place (MATLAB mode only).
        %
        % Prompts for the installation directory, downloads ``MIB3_Matlab.zip``,
        % unzips it to the destination, then exits and restarts MIB3.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.UpdateCheck.updateBtn_Callback: triggered\n');
            end
            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                {'MIB installation directory'}, {obj.mibModel.mibPath}, 'Update MIB', []);
            if isempty(answer); return; end
            destination = answer{1};

            progressDialog = uiprogressdlg(obj.view.gui, 'Title', 'Updating...', ...
                'Message', sprintf('Updating Microscopy Image Browser...\nMay take a few minutes.\n\nPlease wait...'), ...
                'Value', 0.05);
            unzip('http://mib.helsinki.fi/web-update/MIB3_Matlab.zip', destination);
            progressDialog.Value = 0.9;
            if ~isempty(obj.mibController)
                obj.mibController.exitProgram();
            end
            drawnow;
            progressDialog.Value = 0.95;
            rehash;
            progressDialog.Value = 1;
            delete(progressDialog);
            mib3;
        end

        function recheckPeriodSpinner_Callback(obj, hObject)
        % RECHECKPERIODSPINNER_CALLBACK - Save the recheck period preference.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.UpdateCheck.recheckPeriodSpinner_Callback: triggered\n');
            end
            obj.mibModel.preferences.System.Update.RecheckPeriod = hObject.Value;
        end

        function closeWindow(obj)
        % CLOSEWINDOW - Close the Update Check dialog and fire CloseEvent.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.UpdateCheck.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            notify(obj, 'CloseEvent');
        end

    end
end
