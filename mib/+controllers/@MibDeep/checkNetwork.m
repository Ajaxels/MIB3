function checkNetwork(obj, fn)
% CHECKNETWORK - generate and check network using settings in the Train tab.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.checkNetwork(fn)
%
% Input Arguments:
%   - **fn** — optional string with filename (``*.mibDeep``) to preview its
%     configuration
%

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
        FigPos(1) = 1/2*(ScreenSize(3)-800);
        FigPos(2) = 2/3*(ScreenSize(4)-900);
        uiFig.Position = [FigPos(1), FigPos(2), 800, 900];
        uiFig.Name = sprintf('Preview network (%s)', architecture);

        uiFigGridLayout = uigridlayout(uiFig);
        uiFigGridLayout.ColumnWidth = {'1x'};
        uiFigGridLayout.RowHeight = {40, '1x'};

        % Create previewTable
        previewTable = uitable(uiFigGridLayout);
        previewTable.ColumnName = {'Index'; 'Layer name'; 'Layer type'; 'Details'};
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
        tableData = cell([numel(lgraph.Layers), 4]);
        for rowId=1:numel(layerLines)
            if numel(layerLines{rowId}) > 1
                % split line using more than 2 spaces
                rowStr = strsplit(layerLines(rowId), '[ ]{3,}', 'DelimiterType', 'RegularExpression');
                % populate the table data without the first empty entry
                tableData(rowId,:) = rowStr(2:end).cellstr;
            end
        end
        previewTable.Data = tableData;
        previewTable.ColumnWidth = {50, 'fit', 'fit','auto'};

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

