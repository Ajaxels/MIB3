function importNetwork(obj)
% IMPORTNETWORK - import an externally trained or designed network to be used.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.importNetwork()
%
% with DeepMIB
%
% Example:
% % generate a network:
% net = deeplabv3plusLayers([512 512 3], 5, 'resnet18');
% % save network to a file
% save('myNewNetwork.mat', 'net', '-mat');
% % use Import opetation to load and adapt the network for use with DeepMIB
if obj.mibController.matlabVersion < 9.11 % 'Interpreter' is available only from R2021b
    selection = uiconfirm(obj.view.gui,...
        sprintf('[BETA] The following operation is allowing to import a network designed or trained externally\nResult of the operation is generation of "mibCfg" and "mibDeep" files that can be used with DeepMIB\n\nBefore proceeding please make sure that the most closest architecture is selected in DeepMIB settings and all other relevant parameter (e.g. directories) are specified. Check <a href="http://mib.helsinki.fi/help/main2/ug_gui_menu_tools_deeplearning.html#6">Help</a> for details.\n\nSupported formats:\n-Matlab'),...
        '[BETA] Import network', 'Options', {'Continue', 'Cancel'}, 'Icon', 'info');
else
    selection = uiconfirm(obj.view.gui,...
        sprintf('[BETA] The following operation is allowing to import a network designed or trained externally\nResult of the operation is generation of "mibCfg" and "mibDeep" files that can be used with DeepMIB\n\nBefore proceeding please make sure that the most closest architecture is selected in DeepMIB settings and all other relevant parameter (e.g. directories) are specified. Check <a href="http://mib.helsinki.fi/help/main2/ug_gui_menu_tools_deeplearning.html#6">Help</a> for details.\n\nSupported formats:\n-Matlab'),...
        '[BETA] Import network', 'Options', {'Continue', 'Cancel'}, 'Icon', 'info', 'Interpreter', 'html');
end
if strcmp(selection, 'Cancel'); return; end

fileFilters = {'*.mat;', 'Matlab format (*.mat)';
    '*.*', 'All files (*.*)'};
[filenameIn, pathIn, selectedIndx] = utils.dlgs.mibUiGetFile(fileFilters, 'Select network file', obj.mibModel.currentDirectory);
if isequal(filenameIn, 0); return; end
filenameIn = filenameIn{1};

switch fileFilters{selectedIndx, 2}
    case 'Matlab format (*.mat)'
        import = load(fullfile(pathIn, filenameIn), '-mat');
        % generate list of available variables and allow selection
        fieldNames = fieldnames(import);
        if numel(fieldNames) > 1
            fieldNamesList = [];
            for i=1:numel(fieldNames)
                fieldNamesList = [fieldNamesList {sprintf('%s (%s)', fieldNames{i}, class(import.(fieldNames{i})))}];
            end

            prompts = {'Select the variable containing the network:'};
            defAns = {fieldNamesList, 1};
            dlgTitle = 'Import network';
            [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle);
            if isempty(answer); return; end

            wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Importing the network\nPlease wait...'), 'Title', 'Import network');

            net = import.(fieldNames{selIndex});
        else
            wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Importing the network\nPlease wait...'), 'Title', 'Import network');
            net = import.(fieldNames{1});
        end

        %                     wb = uiprogressdlg(obj.view.gui,...
        %                         'Message', sprintf('Importing the network\nPlease wait...'), ...
        %                         'Title', 'Importing network', ...
        %                         'Cancelable', 'on', ...
        %                         'Value',0);
        %                     if wb.CancelRequested; delete(wb); return; end

        % generate new filenames
        [~, outputNetworkName] = fileparts(filenameIn);
        networkFileName = fullfile(pathIn, [outputNetworkName '.mibDeep']);
        configFileName = fullfile(pathIn, [outputNetworkName '.mibCfg']);
        if isfile(networkFileName)
            selection = uiconfirm(obj.view.gui,...
                sprintf('!!! Warning !!!\n\n%s\n\nalready exist!\nDo you want to overwrite it?', networkFileName),...
                'Owerwrite existing network', 'Options', {'Overwrite', 'Cancel'} );
            if strcmp(selection, 'Cancel'); return; end
        end

        obj.view.handles.NetworkFilename.Value = networkFileName;

        inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize);     % as [height, width, depth, colors]
        % generate names for the classes
        classNames = cell([1, obj.BatchOpt.T_NumberOfClasses{1}]);
        classNames{1} = 'Exterior';
        for classId = 2:obj.BatchOpt.T_NumberOfClasses{1}
            classNames{classId} = sprintf('Class%.2d', classId-1);
        end
        wb.Value = 0.4;

        outputPatchSize = [inputPatchSize([1 2 3]) numel(classNames)];
        prompts = {sprintf('Confirm output patch size\n(height width depth number_of_classes):')};
        defAns = {num2str(outputPatchSize)};
        dlgTitle = 'Import network';
        answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle);
        if isempty(answer); delete(wb); return; end
        outputPatchSize = str2num(answer{1});

        % generate colormaps
        obj.colormap6 = [166 67 33; 71 178 126; 79 107 171; 150 169 213; 26 51 111; 255 204 102 ]/255;
        obj.colormap20 = [230 25 75; 255 225 25; 0 130 200; 245 130 48; 145 30 180; 70 240 240; 240 50 230; 210 245 60; 250 190 190; 0 128 128; 230 190 255; 170 110 40; 255 250 200; 128 0 0; 170 255 195; 128 128 0; 255 215 180; 0 0 128; 128 128 128; 60 180 75]/255;
        obj.colormap255 = rand([255,3]);
        if numel(classNames) < 7
            classColors = obj.colormap6;
        elseif numel(classNames) < 21
            classColors = obj.colormap20;
        else
            classColors = obj.colormap255;
        end
        wb.Value = 0.5;

        % update batch opt to take into account new parameters
        obj.BatchOpt.NetworkFilename = networkFileName;

        % save config file
        obj.saveConfig(configFileName)
        wb.Value = 0.6;

        % define path to the parameters file with settings
        importedParameters = load(configFileName, '-mat');

        % update fields and generate fields for mibDeep file
        TrainingOptStruct = importedParameters.TrainingOptStruct;
        AugOpt2DStruct = importedParameters.AugOpt2DStruct;
        AugOpt3DStruct = importedParameters.AugOpt3DStruct;
        InputLayerOpt = importedParameters.InputLayerOpt;
        BatchOpt = importedParameters.BatchOpt;
        ActivationLayerOpt = importedParameters.ActivationLayerOpt;
        SegmentationLayerOpt = importedParameters.SegmentationLayerOpt;
        if isfield(importedParameters, 'DynamicMaskOpt')
            DynamicMaskOpt = importedParameters.DynamicMaskOpt;
        else
            DynamicMaskOpt = obj.DynamicMaskOpt;
        end
        if isfield(importedParameters, 'ScoreExportOpt')
            ScoreExportOpt = importedParameters.ScoreExportOpt;
        else
            ScoreExportOpt = obj.ScoreExportOpt;
        end

        wb.Value = 0.7;

        % save network
        save(networkFileName, 'net', 'TrainingOptStruct', 'AugOpt2DStruct', 'AugOpt3DStruct', 'InputLayerOpt', ...
            'ActivationLayerOpt', 'SegmentationLayerOpt', 'DynamicMaskOpt', 'ScoreExportOpt', ...
            'classNames', 'classColors', 'inputPatchSize', 'outputPatchSize', 'BatchOpt', '-mat', '-v7.3');
        wb.Value = 1;
        delete(wb);
    case 'All files (*.*)'
        mgsOpt.MsgBoxOnly = true;
        header = sprintf('Please select correct file format for the network to import!');
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong format', mgsOpt);
        return;
end
end

