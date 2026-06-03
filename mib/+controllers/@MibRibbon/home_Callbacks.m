function home_Callbacks(obj, hWidget, hData)
% HOME_CALLBACKS - callback on press of the I/O tools buttons in the Home ribbon.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.home_Callbacks(hWidget, hData)
%
% Input Arguments:
%   - **hWidget** — handle to the pressed widget
%   - **hData** — handle to supporting EventData class
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
    case 'Save as'     % obj.handles.ribbonHome.saveFileAs — save image with dialog
        obj.mibModel.saveImage('image');
    case {'Export', 'Export to MATLAB'}     % obj.handles.ribbonHome.export & obj.handles.ribbonHome.exportToMatlab
        obj.mibModel.exportDataset('image');
    case 'Export to Imaris'     % obj.handles.ribbonHome.exportToImaris
        obj.mibModel.exportDatasetToImaris('image');
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
        utils.fiji.renderVolumeWithFiji(img, obj.mibModel.I{id}.image.pixSize, obj.mibModel.mibGUI);

    % ------ IO Tools section ------
    case sprintf('Batch\nprocessing')   % obj.handles.ribbonHome.batch
        obj.mibController.startController('controllers.BatchProcessing', obj.mibController);  
    case 'Chunk dataset'                % obj.handles.ribbonHome.chunk
        obj.mibController.startController('controllers.ChunkingExport');  
    case 'Stitch dataset'               % obj.handles.ribbonHome.stitch
        obj.mibController.startController('controllers.ChunkingImport');  
    case 'Shuffle images'               % obj.handles.ribbonHome.shuffle
        obj.mibController.startController('controllers.RenameShuffle');  
    case 'Restore order'                % obj.handles.ribbonHome.reshuffle
        obj.mibController.startController('controllers.RenameRestore'); 

        % ------ Preferences section ------
    case {'Load layout', 'Load local default layout'}   % obj.handles.ribbonHome.loadLayout or obj.handles.ribbonHome.loadLayoutLocalDefault
        obj.mibController.loadLayout('localDefault');
    case 'Load custom layout'                           % obj.handles.ribbonHome.loadLayoutCustom
        obj.mibController.loadLayout('custom');
    case 'Load MIB default layout'                      % obj.handles.ribbonHome.loadLayoutMibDefault
        obj.mibController.loadLayout('globalDefault');
    case {'Save layout', 'Save the current layout as default'}  % obj.handles.ribbonHome.saveLayout or obj.handles.ribbonHome.saveLayoutLocalDefault
        obj.mibController.saveLayout('localDefault');
    case 'Save the current layout in a custom file'             % obj.handles.ribbonHome.saveLayoutCustom
        obj.mibController.saveLayout('custom');
    case 'Save the current layout as MIB default'               % obj.handles.ribbonHome.saveLayoutMibDefault
        obj.mibController.saveLayout('globalDefault');
    case 'Preferences'                  % obj.handles.ribbonHome.preferences
        % update obj.mibModel.preferences.Colors from the current dataset
        % otherwise the materials color table won't be properly populated
        id = obj.mibModel.getActiveId;
        obj.mibModel.preferences.Colors.ModelMaterialColors = obj.mibModel.I{id}.labels.materialColors;
        obj.mibController.startController('controllers.Preferences', obj.mibController);  % a new appdesigner version
    case 'Help'                         % obj.handles.ribbonHome.help
    case 'Open MIB help'                % obj.handles.ribbonHome.helpMenu
    case 'Tip of the day'               % obj.handles.ribbonHome.tipOfDay
        obj.mibModel.preferences.Tips.ShowTips = true;
        obj.mibController.startController('controllers.WelcomeTips');
    case 'Support on image.sc'          % obj.handles.ribbonHome.support
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
    case 'Check for update'             % obj.handles.ribbonHome.checkUpdate
    case 'Your personal stats'          % obj.handles.ribbonHome.personalStats
        utils.dlgs.showMilestoneDialog(obj.mibController.view.gui, ...
            obj.mibModel.preferences.Users, ...
            'currentStats', struct('mibPath', obj.mibModel.mibPath, 'WindowStyle', 'normal'));
    case 'Licenses'                     % obj.handles.ribbonHome.licenses
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
