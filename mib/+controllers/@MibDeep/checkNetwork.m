function checkNetwork(obj, fn)
% CHECKNETWORK - generate and check network using settings in the Train tab.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.checkNetwork(fn)
%
% Input Arguments:
%   - **fn** - optional string with filename (``*.mibDeep``) to preview its
%     configuration
%
% In MATLAB the network is opened in ``analyzeNetwork``. The deployed version
% has no ``analyzeNetwork``, so the layers are listed in a table (index, name,
% type, patch size, details) and the layer graph is plotted in a separate
% figure. The patch size is the size of the activations a layer outputs,
% height x width (x depth) x channels. It comes from ``deep.internal.sdk.forwardDataAttributes``,
% which propagates the size of the input layer through the network without
% computing any activations, so it is fast and needs no memory for the data. It
% accepts a layerGraph, DAGNetwork or dlnetwork. The batch dimension is not shown,
% and for a layer with several outputs only its first output is listed. Custom
% layers without an ``OutputNames`` property (e.g. ``dicePixelCustomClassificationLayer``)
% are addressed by their name. Being an
% internal function it may change between MATLAB releases; if it fails the column
% shows ``-`` and, in DeveloperMode, the error is printed to the command window.
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDeep.checkNetwork: triggered\n');
end

    if nargin < 2; fn = []; end
    if ~isempty(fn) && exist(fn, 'file') == 0
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.WindowHeight = 200;
        mgsOpt.WindowWidth = 550;
        mgsOpt.headerLines = 1;
        msgText = sprintf('Please check filename:\n%s', fn);
        utils.dlgs.inputUniversalDlg(obj.view.gui, 'The selected network file is empty!', {}, {msgText}, 'Network file is missing!', mgsOpt);
        return;
    end

    if isempty(fn)
        obj.wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Generating network\nPlease wait...'), ...
            'Title', 'Generating network', 'Cancelable','on');
    else
        obj.wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('%s\nPlease wait...', fn), ...
            'Title', 'Loading network', 'Cancelable','on');
    end
    if isempty(fn) && strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
        % SOLOv2 networks are built directly (not via createNetwork); preview them here
        inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize); %#ok<ST2NM>
        inputPatchSize = [inputPatchSize([1 2]) 3];
        switch obj.BatchOpt.T_EncoderNetwork{1}
            case 'Resnet50'
                detectorName = 'resnet50-coco';
            otherwise
                detectorName = 'light-resnet18-coco';
        end
        % constructing the detector also validates that the SOLOv2 support package is installed
        try
            solov2Net = solov2(detectorName, {'object'}, "InputSize", inputPatchSize);
        catch err
            utils.dlgs.showErrorDialog(obj.view.gui, err, 'Network initialization problem');
            delete(obj.wb);
            return;
        end
        obj.wb.Value = 0.9;
        % analyzeNetwork / layer-graph preview is not available for the solov2 detector
        % object (it exposes no underlying dlnetwork), so show a configuration summary
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.Icon = 'puffin_info';
        mgsOpt.HeaderLines = 6;
        header = sprintf(['SOLOv2 instance segmentation network\n\n' ...
            'Backbone: %s\nInput size: %d x %d x %d\nClass: %s\n\n' ...
            'A detailed layer-graph preview is not available for the solov2 detector object.'], ...
            detectorName, inputPatchSize(1), inputPatchSize(2), inputPatchSize(3), ...
            strjoin(string(solov2Net.ClassNames), ', '));
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Instance network', mgsOpt);
        obj.wb.Value = 1;
        delete(obj.wb);
        return;
    end

    if isempty(fn)
        previewSwitch = 1;  % indicate that the network is only for preview, the weights of classes won't be calculated
        [lgraph, outputPatchSize] = obj.createNetwork(previewSwitch);
        if isempty(lgraph); if ~isempty(obj.wb); delete(obj.wb); end; return; end
        if obj.wb.CancelRequested; delete(obj.wb); return; end

        architecture = obj.BatchOpt.Architecture{1};
        inputPatchSize = obj.BatchOpt.T_InputPatchSize;
        outputPatchSize = num2str(outputPatchSize);
    else
        try
            loadedNet = load(fn, '-mat');   % load 'net'-variables
            lgraph = loadedNet.net;
            architecture = loadedNet.BatchOpt.Architecture{1};
            inputPatchSize = loadedNet.BatchOpt.T_InputPatchSize;
            outputPatchSize = num2str(loadedNet.outputPatchSize);
        catch err
            utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing net-variable');
            delete(obj.wb);
            return;
        end
    end

    obj.wb.Value = 0.6;
    if ~isdeployed
        %#exclude analyzeNetwork
        analyzeNetwork(lgraph);
    else
        uiFig = uifigure('Visible', 'off');
        ScreenSize = get(0, 'ScreenSize');
        FigPos(1) = 1/2*(ScreenSize(3)-950);
        FigPos(2) = 2/3*(ScreenSize(4)-900);
        uiFig.Position = [FigPos(1), FigPos(2), 950, 900];
        uiFig.Name = sprintf('Preview network (%s)', architecture);

        uiFigGridLayout = uigridlayout(uiFig);
        uiFigGridLayout.ColumnWidth = {'1x'};
        uiFigGridLayout.RowHeight = {40, '1x'};

        % Create previewTable
        previewTable = uitable(uiFigGridLayout);
        previewTable.ColumnName = {'Index'; 'Layer name'; 'Layer type'; 'Patch size'; 'Details'};
        previewTable.RowName = {};
        previewTable.Layout.Row = 2;
        previewTable.Layout.Column = 1;

        % text area
        textArea = uitextarea(uiFigGridLayout);
        textArea.Layout.Row = 1;
        textArea.Layout.Column = 1;

        % format lgraph into string
        layersStr = formattedDisplayText(lgraph.Layers);
        % split lines
        layerLines = splitlines(layersStr);
        % clip the header
        layerLines = layerLines(3:end);
        % allocate space for the table
        tableData = cell([numel(lgraph.Layers), 5]);
        for rowId=1:numel(layerLines)
            if numel(layerLines{rowId}) > 1
                % split line using more than 2 spaces
                rowStr = strsplit(layerLines(rowId), '[ ]{3,}', 'DelimiterType', 'RegularExpression');
                % populate the table data without the first empty entry,
                % column 4 is filled with the patch sizes below
                tableData(rowId, [1 2 3 5]) = rowStr(2:end).cellstr;
            end
        end

        % patch sizes (layer activation sizes), propagated from the size of the input layer
        % without running the network; for layers with several outputs
        % (e.g. max pooling with unpooling outputs in SegNet) only the first
        % output is shown. forwardDataAttributes is an internal
        % Deep Learning Toolbox function, so any failure only blanks the column
        try
            layerOutputNames = cell([numel(lgraph.Layers), 1]);
            for layerId = 1:numel(lgraph.Layers)
                layerOutputNames{layerId} = lgraph.Layers(layerId).Name;
                % custom layers, e.g. dicePixelCustomClassificationLayer, may have no OutputNames
                if isprop(lgraph.Layers(layerId), 'OutputNames') && numel(lgraph.Layers(layerId).OutputNames) > 1
                    layerOutputNames{layerId} = [lgraph.Layers(layerId).Name '/' lgraph.Layers(layerId).OutputNames{1}];
                end
            end
            [activationSizes, activationFormats] = deep.internal.sdk.forwardDataAttributes(lgraph, 'Outputs', layerOutputNames);
            for layerId = 1:numel(activationSizes)
                % drop the batch dimension and the absent (NaN) dimensions
                activationSize = activationSizes{layerId}(char(activationFormats{layerId}) ~= 'B');
                activationSize = activationSize(~isnan(activationSize));
                tableData{layerId, 4} = char(strjoin(string(activationSize), char(215)));  % char(215) is the multiplication sign, as in the Details column
            end
        catch err
            tableData(:, 4) = {'-'};
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.MibDeep.checkNetwork: activation sizes are not available: %s\n', err.message);
            end
        end

        previewTable.Data = tableData;
        previewTable.ColumnWidth = {50, 'fit', 'fit', 'fit', 'auto'};

        % add header
        textArea.Value = [  {sprintf('Architecture: %s', architecture)}; ...
            {sprintf('Input patch size: %s   Output patch size: %s', inputPatchSize, outputPatchSize)} ];
        textArea.Editable = false;
        uiFig.Visible = 'on';

        % plot layer-graph, this function can not be included in uiFig
        figure;
        plot(lgraph);
        title(architecture);
    end
    obj.wb.Value = 1;
    delete(obj.wb);
end

