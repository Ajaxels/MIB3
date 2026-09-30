function home_Callbacks(obj, hWidget, hData)
% HOME_CALLBACKS - callback on press of the I/O tools buttons in the Home ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.home_Callbacks(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** - handle to the pressed widget
%   - **hData** - handle to supporting EventData class
%

arguments (Input)
    obj controllers.MibRibbon
    hWidget matlab.ui.internal.toolstrip.base.Action
    hData matlab.ui.internal.toolstrip.base.ToolstripEventData
end

mode = hWidget.Text;
if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibRibbon.home_Callbacks: pressed -> %s\n', mode);
end

switch mode
    % ------ Export section ------
    case 'Save as'     % obj.handles.ribbonHome.saveFileAs - save image with dialog
        obj.mibModel.saveImage('image');
    case {'Export', 'Export to MATLAB'}     % obj.handles.ribbonHome.export & obj.handles.ribbonHome.exportToMatlab
        obj.mibModel.exportDataset('image');
    case 'Export to Imaris'     % obj.handles.ribbonHome.exportToImaris
        obj.mibModel.exportDatasetToImaris('image');
    case 'Export to Zarr3'      % obj.handles.ribbonHome.exportToZarr3
        % write the current image as an OME-Zarr v3 pyramid (openable as BigData)
        parentFig = obj.mibModel.getProgressBarParent();
        id = obj.mibModel.getActiveId();
        ds = obj.mibModel.I{id};
        if strcmp(ds.image.filename, 'none.tif') || ~ds.image.exists
            utils.dlgs.showErrorDialog(parentFig, 'No image is open to export.', 'Export to Zarr3');
            return;
        end
        [imgPath, imgStem] = fileparts(ds.image.filename);
        if isempty(imgPath); imgPath = obj.mibModel.currentDirectory; end
        if isempty(imgStem); imgStem = 'dataset'; end
        % the chosen extension selects the zarr format - see
        % io.savers.Zarr3Saver.resolveZarrFormat
        [zFile, zDir] = uiputfile({'*.zarr3', 'OME-Zarr v3 (*.zarr3)'; ...
            '*.zarr2', 'OME-Zarr v2 (*.zarr2)'}, ...
            'Export image to OME-Zarr', fullfile(imgPath, [imgStem '.zarr3']));
        if isequal(zFile, 0); return; end
        outPath = fullfile(zDir, zFile);
        datasetInfo = struct('Y', ds.image.height, 'X', ds.image.width, 'Z', ds.image.depth, ...
            'pixSize', ds.image.pixSize);
        zOpt = io.savers.Zarr3Saver.optionsDialog(parentFig, obj.mibModel.mibPath, false, datasetInfo);
        if isempty(zOpt); return; end   % cancelled the settings dialog
        wb = uiprogressdlg(parentFig, 'Title', 'Export to Zarr3', ...
            'Message', 'Writing OME-Zarr v3 pyramid, please wait...', 'Indeterminate', 'on');
        try
            io.savers.Zarr3Saver.exportDataset(obj.mibModel, id, outPath, zOpt);
            delete(wb);
            uialert(parentFig, sprintf('Image exported to:\n%s', outPath), ...
                'Export to Zarr3', 'Icon', 'success');
        catch ME
            if isvalid(wb); delete(wb); end
            utils.dlgs.showErrorDialog(parentFig, ME.message, 'Export to Zarr3 failed');
        end
    case 'Snapshot'     % obj.handles.ribbonHome.snapshot
        obj.mibController.startController('controllers.Snapshot');
    case 'Movie'     % obj.handles.ribbonHome.movie
        obj.mibController.startController('controllers.MakeMovie');
    case {'Render', 'MIB Rendering'}     % obj.handles.ribbonHome.render &  obj.handles.ribbonHome.renderMIB
        obj.mibController.startController('controllers.VolRenApp');
    case 'MATLAB Volume Viewer'     % obj.handles.ribbonHome.renderMatlab
        if isdeployed
            dlgOpts.MsgBoxOnly = true; 
            dlgOpts.Icon = 'puffin_error';
            header = sprintf('MATLAB Volume Viewer is only available in MIB for MATLAB!\nPlese use MIB Rendering instead.');
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'ObtainDirectoryForAction error', dlgOpts);
            return;
        end
        id = obj.mibModel.getActiveId();
        dataset = obj.mibModel.I{id};
        img = cell2mat(obj.mibModel.getData3D('image', [], 3));
        if size(img, 4) > 1
            utils.dlgs.showErrorDialog(obj.view.gui, sprintf('Volume viewer is not compatible with multicolor images;\nplease keep only a single color channel displayed and try again!'), 'Not implemented');
            return;
        end

        answer = 'Only volume';
        if dataset.modelExist
            answer = utils.dlgs.inputQuestDlg(obj.view.gui, sprintf('Would you like to have the model exported together with the volume?'), ...
                'Include model', 'Volume+labels', 'Only volume', 'Cancel', 'Only volume');
            if strcmp(answer, 'Cancel'); return; end
        end
        pixSize = dataset.image.pixSize;
        if strcmp(answer, 'Only volume')
            %#exclude volumeViewer
            volumeViewer(squeeze(img), 'VolumeType', 'Volume', 'ScaleFactors', [pixSize.x pixSize.y pixSize.z]);
        else
            labels = cell2mat(obj.mibModel.getData3D('labels'));
            %#exclude volumeViewer
            volumeViewer(squeeze(img), labels, 'ScaleFactors', [pixSize.x pixSize.y pixSize.z]);
        end

    case '3D viewer in Fiji'     % obj.handles.ribbonHome.renderFiji
        img = cell2mat(obj.mibModel.getData3D('image', [], 3));
        id = obj.mibModel.getActiveId();
        utils.fiji.renderVolumeWithFiji(img, obj.mibModel.I{id}.image.pixSize, obj.mibModel.getProgressBarParent());

    % ------ IO Tools section ------
    case sprintf('Batch\nprocessing')   % obj.handles.ribbonHome.batch
        obj.mibController.startController('controllers.BatchProcessing', obj.mibController);  
    case 'Chunk dataset'                % obj.handles.ribbonHome.chunk
        obj.mibController.startController('controllers.ChunkingExport');  
    case {'Stitch dataset', 'Fuse into dataset'}    % obj.handles.ribbonHome.stitch & obj.handles.ribbonHome.fuse
        if strcmp(mode, 'Stitch dataset')
            combineMode = 'New Stack';
        else
            combineMode = 'Fuse to Existing';
        end
        % when the dialog is already open, startController only brings it to
        % the front and refreshes it from BatchOpt, so switch its mode here
        childId = obj.mibController.findChildId('controllers.ChunkingImport');
        if ~isempty(childId) && childId <= numel(obj.mibController.childControllers)
            obj.mibController.childControllers{childId}.BatchOpt.Mode{1} = combineMode;
        end
        obj.mibController.startController('controllers.ChunkingImport', combineMode);
    case 'Shuffle images'               % obj.handles.ribbonHome.shuffle
        obj.mibController.startController('controllers.RenameShuffle');  
    case 'Restore order'                % obj.handles.ribbonHome.reshuffle
        obj.mibController.startController('controllers.RenameRestore'); 

        % ------ Preferences section ------
    case {'Load layout', 'Load local default layout'}   % obj.handles.ribbonHome.loadLayout or obj.handles.ribbonHome.loadLayoutLocalDefault
        status = obj.mibController.loadLayout('localDefault');
        if ~status
            dlgOpt = struct('MsgBoxOnly', true, 'Icon', 'puffin_error', 'HeaderLines', 1, 'WindowType', 'modal');
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                'The local default layout could not be restored!', ...
                {}, {'The saved layout was created with a different panel configuration'}, 'Load Layout', dlgOpt);
        end
        
    case 'Load custom layout'                           % obj.handles.ribbonHome.loadLayoutCustom
        status = obj.mibController.loadLayout('custom');
        if ~status
            dlgOpt = struct('MsgBoxOnly', true, 'Icon', 'puffin_error', 'HeaderLines', 1, 'WindowType', 'modal');
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                'The custom layout could not be restored!', ...
                {}, {'The saved layout was created with a different panel configuration'}, 'Load Layout', dlgOpt);
        end

    case 'Load MIB default layout'                      % obj.handles.ribbonHome.loadLayoutMibDefault
        status = obj.mibController.loadLayout('globalDefault');
        if ~status
            dlgOpt = struct('MsgBoxOnly', true, 'Icon', 'puffin_error', 'HeaderLines', 1, 'WindowType', 'modal');
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                'The MIB global default layout could not be restored!', ...
                {}, {'The saved layout was created with a different panel configuration'}, 'Load Layout', dlgOpt);
        end

    case {'Save layout', 'Save the current layout as default'}  % obj.handles.ribbonHome.saveLayout or obj.handles.ribbonHome.saveLayoutLocalDefault
        obj.mibController.saveLayout('localDefault');
    case 'Save the current layout in a custom file'             % obj.handles.ribbonHome.saveLayoutCustom
        obj.mibController.saveLayout('custom');
    case 'Save the current layout as MIB default'               % obj.handles.ribbonHome.saveLayoutMibDefault
        obj.mibController.saveLayout('globalDefault');

    case {'Follow the system theme', 'Light theme', 'Dark theme'}  % obj.handles.ribbonHome.systemTheme, lightTheme, darkTheme
        themeNames = dictionary(["Follow the system theme", "Light theme", "Dark theme"], ["System", "Light", "Dark"]);
        themeName = char(themeNames(string(mode)));
        if ~utils.setMibTheme(themeName)
            dlgOpt = struct('MsgBoxOnly', true, 'Icon', 'puffin_error', 'HeaderLines', 1, 'WindowType', 'modal');
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                'The theme could not be changed!', ...
                {}, {'Selection of the theme requires MATLAB R2025a or newer'}, 'Theme', dlgOpt);
            return;
        end
        obj.mibModel.preferences.Colors.Theme = themeName;

    case {'Preferences', 'Open MIB preferences'}    % obj.handles.ribbonHome.preferences & obj.handles.ribbonHome.preferencesMenu
        % update obj.mibModel.preferences.Colors from the current dataset
        % otherwise the materials color table won't be properly populated
        id = obj.mibModel.getActiveId;
        obj.mibModel.preferences.Colors.ModelMaterialColors = obj.mibModel.I{id}.labels.materialColors;
        obj.mibController.startController('controllers.Preferences', obj.mibController);  % a new appdesigner version

    case 'Make override default settings file'     % obj.handles.ribbonHome.prefOverrideMenu
        % the settings of this session that differ from the MIB defaults become the
        % starting preferences of every new user, see MibModel.saveOverridePreferences
        computerName = utils.identifyComputerName();
        thisComputerButton = sprintf('Only %s', computerName);
        answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
            sprintf(['Save the settings that differ from the MIB defaults as the starting settings of new users.\n\n' ...
            'Users who already have their own preferences file (mib3.mat) are not affected.\n\n' ...
            'Which computers should use the file?']), ...
            'Preferences override file', 'All computers', thisComputerButton, 'Cancel', 'All computers');
        switch answer
            case 'All computers'
                overrideFilename = 'mib3_prefs_override.json';
            case thisComputerButton
                overrideFilename = sprintf('mib3_prefs_override_%s.json', computerName);
            otherwise
                return;
        end
        [overrideFilename, overridePath] = uiputfile({'*.json', 'JSON files (*.json)'}, ...
            'Save preferences override file', fullfile(obj.mibModel.mibPath, overrideFilename));
        if isequal(overrideFilename, 0); return; end
        overrideFilename = fullfile(overridePath, overrideFilename);

        try
            numberOfSettings = obj.mibModel.saveOverridePreferences(overrideFilename);
        catch err
            utils.dlgs.showErrorDialog(obj.view.gui, sprintf(['%s\n\nIf the MIB folder is write-protected, ' ...
                'save the file elsewhere and copy it into\n%s'], err.message, obj.mibModel.mibPath), ...
                'Preferences override file');
            return;
        end

        dlgOpt = struct('MsgBoxOnly', true, 'Icon', 'puffin_info', 'HeaderLines', 1);
        if numberOfSettings == 0
            infoText = {'The current settings match the MIB defaults, the file lists no settings'};
        else
            infoText = {sprintf('%d settings that differ from the MIB defaults were saved to:\n%s', numberOfSettings, overrideFilename)};
        end
        if ~strcmpi(strip(overridePath, 'right', filesep), strip(obj.mibModel.mibPath, 'right', filesep))
            infoText{1} = sprintf('%s\n\nMIB reads the file only from\n%s', infoText{1}, obj.mibModel.mibPath);
        end
        utils.dlgs.inputUniversalDlg(obj.view.gui, 'Preferences override file saved', ...
            {}, infoText, 'Preferences override file', dlgOpt);
    case 'Help'                         % obj.handles.ribbonHome.help
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'index.html');
        utils.openHelpPage(helpFilPath, 'http://mib.helsinki.fi/help/main3/index.html');

    case 'Open MIB help'                % obj.handles.ribbonHome.helpMenu
        helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'index.html');
        utils.openHelpPage(helpFilPath, 'http://mib.helsinki.fi/help/main3/index.html');

    case 'Tip of the day'               % obj.handles.ribbonHome.tipOfDay
        obj.mibModel.preferences.Tips.ShowTips = true;
        obj.mibController.startController('controllers.WelcomeTips');
    case 'Support on image.sc'          % obj.handles.ribbonHome.support
        web('https://forum.image.sc/tag/mib', '-browser');
    case 'Personal support session'     % obj.handles.ribbonHome.call4help
        link = 'http://mib.helsinki.fi/web-update/call4help.json';
        try
            urlText = urlread(link, 'Timeout', 4);
            call4help = jsondecode(urlText);

            fieldNames = fieldnames(call4help);
            infoText = '<html><body>';
            for i=1:numel(fieldNames)
                infoText = sprintf('%s<h3 style="margin-bottom: 3px;">%s</h3>%s', infoText, fieldNames{i}, call4help.(fieldNames{i}));
            end
            infoText = [infoText '</body></html>'];
        catch err
            infoText = sprintf('<html>If you need help please join a personal zoom support sessions<br><br>Reservation calendar is available on the main page of <a href="https://mib.helsinki.fi">mib.helsinki.fi</a><br>Under the Call4Help section on the right-hand side</html>');
            call4help.Link = 'http:\\mib.helsinki.fi';
        end

        options = struct();
        dlgTitle = 'MIB Call4Help';
        options.WindowWidth = 700;
        options.WindowHeight = 380;
        options.MsgBoxOnly = true;
        options.Icon = 'call4help';
        options.OkBtnText = 'Copy';
        options.HelpBtnText = 'Calendar';
        options.HelpUrl = 'https://outlook.office365.com/owa/calendar/MIBcall4help@HelsinkiFI.onmicrosoft.com/bookings/s/olBBIX11aEqP-UndmR2Emg2';
        options.mibPath = obj.mibModel.mibPath;
        utils.dlgs.inputUniversalDlg(obj.view.gui, '', {infoText}, {infoText}, dlgTitle, options);
        clipboard('copy', call4help.Link);


    case 'API class reference'          % obj.handles.ribbonHome.classReference
        web('https://mib.helsinki.fi/help/api3/index.html', '-browser');

    case 'Check for update'             % obj.handles.ribbonHome.checkUpdate
        obj.mibController.startController('controllers.UpdateCheck', obj.mibController);

    case 'Your stats'          % obj.handles.ribbonHome.personalStats
        newStatsFolder = utils.dlgs.showMilestoneDialog( ...
            obj.mibController.view.gui, ...
            obj.mibModel.preferences.Users, ...
            'currentStats', struct( ...
                'mibPath',        obj.mibModel.mibPath, ...
                'WindowStyle',    'normal', ...
                'userStatsPath',  obj.mibModel.preferences.System.UserStatsProfile));
        if ~isempty(newStatsFolder) && ...
                ~strcmp(newStatsFolder, fileparts(obj.mibModel.preferences.System.UserStatsProfile))
            % carries this machine's points over and sums in the statistics
            % other workstations already left in the chosen folder
            obj.mibModel.relocateUserStats(newStatsFolder);
        end

    case 'Licenses'                     % obj.handles.ribbonHome.licenses
        web('https://mib.helsinki.fi/license.html', '-browser');

    case 'About MIB'                    % obj.handles.ribbonHome.about
        obj.mibController.startController('controllers.About');  % a new appdesigner version

        % ------ Development section ------
    case 'Developer mode' 
        statusText = 'DISABLED';
        if hData.EventData.NewValue
            statusText = 'ENABLED';
        end
        % update DeveloperMode switch
        obj.mibModel.preferences.System.DeveloperMode = hData.EventData.NewValue;

        options.MsgBoxOnly = true;
        options.Icon       = 'puffin_info';
        options.HeaderLines = 1;
        infoText = 'Restart MIB to update tooltips!';
        utils.dlgs.inputUniversalDlg(obj.view.gui, sprintf('The developer mode was %s!', statusText), {infoText}, {infoText}, 'Info', options);

end
end
