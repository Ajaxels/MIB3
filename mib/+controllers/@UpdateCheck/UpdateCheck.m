classdef UpdateCheck < handle
% UPDATECHECK - Controller for the Check for Update dialog.

    properties
        mibModel
        % handle to the model
        view
        % handle to the view
        mibController
        % handle to MibController; optional, required only to restart MIB after an in-place update
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
        %   - **mibController** - *(optional)* handle to MibController; without it the
        %     Update button installs the new version but cannot restart MIB
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
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme

            % before updateWidgets, which enlarges the font of informationText
            % when a new version is available
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.informationText.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.informationText.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.updateWidgets();
            obj.addCallbacks();

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
        %
        % When a newer version is available, ``informationText`` is emphasized: bold,
        % 4 points larger than the MIB font, word-wrapped, centered next to the
        % image and painted ``panelGreen`` of ``utils.themeColors``, which
        % ``utils.applyThemeColors`` (the ``ThemeChangedFcn`` of the dialog) remaps on
        % a light/dark theme switch. Must run after ``utils.fontSizeUpdate``, which
        % would reset the font size.

            if isdeployed
                obj.view.handles.updateBtn.Enable = 'off';
                if ismac
                    link = 'http://mib.helsinki.fi/web-update3/mib3_mac.txt';
                elseif isunix
                    link = 'http://mib.helsinki.fi/web-update3/mib3_linux.txt';
                else
                    link = 'http://mib.helsinki.fi/web-update3/mib3_win.txt';
                end
            else
                link = 'http://mib.helsinki.fi/web-update3/mib3_matlab.txt';
            end

            try
                urlText = urlread(link, 'Timeout', 4);  %#ok<URLRD>
            catch
                urlText = sprintf('<html>\n<div style="font-family:arial;">\n<b>The update file has not been detected...</b>\n</div>\n</html>\n---Info---\n<html></html>');
            end

            htmlStartPositions = strfind(urlText, '<html>');
            infoSeparatorPosition = strfind(urlText, '---Info---');
            if ~isempty(htmlStartPositions) && ~isempty(infoSeparatorPosition)
                availableVersionText = strtrim(urlText(1:htmlStartPositions(1)-1));
                releaseComments = urlText(htmlStartPositions(1):infoSeparatorPosition(1)-2);
                infoText = urlText(htmlStartPositions(2):end);
            else
                availableVersionText = strtrim(urlText);
                releaseComments = '';
                infoText = '';
            end
            % keep the text for display: str2double('2026.10') is 2026.1
            availableVersion = str2double(availableVersionText);

            obj.view.handles.recheckPeriodSpinner.Value = obj.mibModel.preferences.System.Update.RecheckPeriod;

            if availableVersion - obj.mibVersion > 0
                informationText = obj.view.handles.informationText;
                informationText.Text = ...
                    sprintf('Microscopy Image Browser\nnew version (%s) is available!', availableVersionText);
                informationText.FontWeight = 'bold';
                informationText.FontSize = obj.mibModel.preferences.System.Font.FontSize + 4;
                informationText.WordWrap = 'on';
                informationText.VerticalAlignment = 'center';
                informationText.HorizontalAlignment = 'center';
                informationText.BackgroundColor = utils.themeColors(obj.view.gui).panelGreen;
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
        % Prompts for the installation directory, downloads ``MIB3_Matlab.zip`` to
        % a temporary file and unzips it into the destination.
        %
        % The zip contains the whole distribution with ``mib\`` at its top level,
        % so the suggested destination is the parent of ``mibModel.mibPath``;
        % unzipping into ``mibPath`` itself would create ``mib\mib\`` and leave
        % the running installation untouched.
        %
        % Cancel is honoured after the download, before the unzip, which is the
        % only irreversible step; the download and the unzip themselves cannot be
        % interrupted, so the dialog stops being cancelable once the unzip starts.
        %
        % Files held open by MATLAB cannot be replaced; ``unzip`` skips them with
        % the ``MATLAB:io:archive:extractArchive:OverwriteOpenFile`` warning and
        % leaves them out of its returned list. This always hits the window icons
        % (``mib_icon_16px.png`` of the dialogs, ``mib_icon_32px.png`` of the main
        % window): a uifigure keeps its ``Icon`` file locked for the rest of the
        % MATLAB session, even after it is deleted, so an update run at startup is
        % affected as well. The warning ID is language independent; when it is the
        % last warning of the unzip, the zip is extracted once more to a temporary
        % folder to get its full file list, and the skipped files are named in the
        % final message. Skipped icons are reported as harmless; anything else as
        % a possible malfunction, with the advice to restart MATLAB and update
        % again. A lock scan of the installation instead would take about 70 s.
        %
        % MIB is restarted only when the destination is the running installation
        % and ``mibController`` was supplied; otherwise the running MIB stays open
        % and the user is told where the new copy is. The restart closes the main
        % window with ``AppContainer.close()``, which runs
        % ``MibController.exitProgram`` through ``CanCloseFcn`` exactly as the
        % window close button does: preferences and user stats are saved and all
        % child windows, this one included, are closed. ``exitProgram`` must not be
        % called directly - it is only the close request handler and leaves the
        % main window open. ``close()`` is synchronous, so the new MIB is started
        % afterwards from a single-shot timer: it is constructed once this callback
        % has returned and released its handles to the old instance, not inside
        % the callback of a window that no longer exists.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.UpdateCheck.updateBtn_Callback: triggered\n');
            end
            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                {'MIB installation directory (the folder that contains "mib")'}, ...
                {fileparts(obj.mibModel.mibPath)}, 'Update MIB');
            if isempty(answer); return; end
            destination = answer{1};
            if ~isfolder(destination)
                uialert(obj.view.gui, sprintf('The folder does not exist:\n%s\n\nNothing was changed.', destination), ...
                    'Update MIB');
                return;
            end

            progressDialog = uiprogressdlg(obj.view.gui, 'Title', 'Update MIB', ...
                'Message', sprintf('Downloading Microscopy Image Browser...\nMay take a few minutes.'), ...
                'Indeterminate', 'on', 'Cancelable', 'on');
            zipFilename = [tempname '.zip'];
            try
                websave(zipFilename, 'http://mib.helsinki.fi/web-update3/MIB3_Matlab.zip', weboptions('Timeout', 60));
            catch err
                delete(progressDialog);
                if isfile(zipFilename); delete(zipFilename); end
                utils.dlgs.showErrorDialog(obj.view.gui, err, 'Update MIB', ...
                    'The update could not be downloaded. Nothing was changed.');
                return;
            end
            if progressDialog.CancelRequested
                delete(progressDialog);
                delete(zipFilename);
                uialert(obj.view.gui, 'The update was canceled. Nothing was changed.', 'Update MIB', 'Icon', 'info');
                return;
            end

            progressDialog.Message = sprintf('Installing to\n%s\n\nPlease wait...', destination);
            progressDialog.Cancelable = 'off';
            lastwarn('');
            try
                extractedFiles = unzip(zipFilename, destination);
            catch err
                delete(progressDialog);
                delete(zipFilename);
                utils.dlgs.showErrorDialog(obj.view.gui, err, 'Update MIB', ...
                    sprintf('The update was not fully installed to\n%s\nSome files may already be replaced.', destination));
                return;
            end

            % unzip skips a file that is held open with only a warning, and leaves it
            % out of the returned list. The window icons are always held open: MATLAB
            % keeps the Icon file of a uifigure locked for the rest of the session.
            % The list of skipped files needs the full content of the zip, so only
            % in that case it is unzipped once more, into a temporary folder
            skippedFiles = {};
            [~, warningId] = lastwarn;
            if strcmp(warningId, 'MATLAB:io:archive:extractArchive:OverwriteOpenFile')
                progressDialog.Message = 'Checking which files were not replaced...';
                stagingFolder = tempname;
                allFiles = unzip(zipFilename, stagingFolder);
                skippedFiles = setdiff(extractAfter(allFiles, fullfile(stagingFolder, filesep)), ...
                    extractAfter(extractedFiles, fullfile(destination, filesep)));
                rmdir(stagingFolder, 's');
            end
            delete(zipFilename);
            delete(progressDialog);

            skippedNote = '';
            if ~isempty(skippedFiles)
                if all(startsWith(skippedFiles, fullfile('mib', 'assets', 'icons')) & endsWith(skippedFiles, '.png'))
                    skippedNote = sprintf(['\n\nThese files are in use by MATLAB and were not replaced:\n%s\n\n' ...
                        'They are only window icons, so MIB works normally. To replace them as well, ' ...
                        'restart MATLAB and update again.'], strjoin(skippedFiles, newline));
                else
                    skippedNote = sprintf(['\n\nThese files are in use by MATLAB and were not replaced:\n%s\n\n' ...
                        'MIB may not work correctly until they are. Restart MATLAB and update again.'], ...
                        strjoin(skippedFiles, newline));
                end
            end

            newMibPath = fullfile(destination, 'mib');
            if ~strcmpi(newMibPath, fullfile(obj.mibModel.mibPath))
                uialert(obj.view.gui, sprintf(['MIB was installed to\n%s\n\nThe running MIB was not changed. ' ...
                    'To start the new copy:\ncd(''%s''); mib3%s'], destination, newMibPath, skippedNote), ...
                    'Update MIB', 'Icon', 'success');
                return;
            end
            if isempty(obj.mibController)
                uialert(obj.view.gui, ['MIB was updated. Restart MIB to use the new version.' skippedNote], ...
                    'Update MIB', 'Icon', 'success');
                return;
            end
            if ~isempty(skippedNote)
                % must block, as the main window and this dialog with it close right after;
                % uiconfirm waits for the answer only when its output is assigned
                restartAnswer = uiconfirm(obj.view.gui, ['MIB was updated and will now restart.' skippedNote], ...
                    'Update MIB', 'Options', {'Restart MIB'}, 'Icon', 'info'); %#ok<NASGU>
            end

            mainWindow = obj.mibController.view.gui;
            mainWindow.close();     % runs exitProgram and closes this dialog as well
            if isvalid(mainWindow) && mainWindow.State ~= matlab.ui.container.internal.appcontainer.AppState.TERMINATED
                warning('MIB was updated but could not be closed; restart it to use the new version.');
                return;
            end
            restartTimer = timer('StartDelay', 1, 'ExecutionMode', 'singleShot', ...
                'TimerFcn', @(~, ~) evalin('base', 'rehash; mib3;'), ...
                'StopFcn', @(timerObj, ~) delete(timerObj));
            start(restartTimer);
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
