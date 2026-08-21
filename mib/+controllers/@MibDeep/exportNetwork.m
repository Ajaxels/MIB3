function exportNetwork(obj)
% EXPORTNETWORK - convert and export network to ONNX or TensorFlow formats.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.exportNetwork()
%
    
    if exist(obj.BatchOpt.NetworkFilename, 'file') ~= 2
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.Header = sprintf('The network file:\n%s\ncan not be found!', obj.BatchOpt.NetworkFilename);
        mgsOpt.Icon = 'puffin_error';
        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Missing file', mgsOpt);
        return;
    end

    prompts = {'Output format'; 'Alter the final segmentation layer as'; 'Version of ONNX operator set [6-20]'};
    defAns = {{'ONNX', 'TensorFlow', 1}; ...
              {'Keep as it is', 'Remove the layer', 'pixelClassificationLayer', 'dicePixelClassificationLayer', 1}; ...
              struct('Spinner', true, 'Value', 14, 'Limits', [6 20], 'Step',1, 'Round',true) };

    dlgTitle = 'Export network';
    header = sprintf('Convert and export the network to ONNX or TensorFlow format');
    options.HeaderLines = 1;
    options.WindowWidth = 540;
    options.WindowHeight = 220;
    options.HelpUrl = 'https://se.mathworks.com/help/deeplearning/ref/exportonnxnetwork.html';

    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    exportFormat = answer{1};
    finalSegmentationLayer = answer{2};
    opsetVersion = answer{3};

    [currDir, fn] = fileparts(obj.BatchOpt.NetworkFilename);

    switch exportFormat
        case 'ONNX'
            outputFilename = fullfile(currDir, [fn '.onnx']);
            [filename, pathname] = uiputfile( ...
                {'*.onnx','ONNX-files (*.onnx)';...
                '*.*',  'All Files (*.*)'}, ...
                'Set output file', outputFilename);
            if filename == 0; return; end
            outputFilename = fullfile(pathname, filename);
        case 'TensorFlow'
            outputFilename = uigetdir(currDir, 'TensorFlow: define model package name');
            if outputFilename == 0; return; end
    end

    wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Exporting to %s\nPlease wait...', exportFormat), 'Title', 'Export network');
    % load the model
    Model = load(obj.BatchOpt.NetworkFilename, '-mat');
    wb.Value = 0.4;

    % correct for dlnetwork that final layer (softmax) should be
    % kept as it is
    if isa(Model.net, 'dlnetwork')
        finalSegmentationLayer = 'Keep as it is';
    end

    if ~strcmp(finalSegmentationLayer, 'Keep as it is')
        lgraph = layerGraph(Model.net);

        % find index of the output layer
        outPutLayerName = lgraph.OutputNames;
        notFound = 1;
        layerId = numel(lgraph.Layers) + 1;
        while notFound
            layerId = layerId - 1;
            if strcmp(lgraph.Layers(layerId).Name, outPutLayerName) || layerId == 0
                notFound = 0;
            end
        end
        outLayer = lgraph.Layers(layerId);
        switch answer{2}
            case 'pixelClassificationLayer'
                outLayer = pixelClassificationLayer('Name', 'Segmentation-Layer', 'Classes', outLayer.Classes);
                lgraph = replaceLayer(lgraph, outPutLayerName{1}, outLayer);
            case 'dicePixelClassificationLayer'
                outLayer = dicePixelClassificationLayer('Name', 'Segmentation-Layer', 'Classes', outLayer.Classes);
                lgraph = replaceLayer(lgraph, outPutLayerName{1}, outLayer);
            case 'Remove the layer'
                lgraph = removeLayers(lgraph, outPutLayerName{1});
        end
    else
        lgraph = Model.net;
    end

    switch exportFormat
        case 'ONNX'
            try
                exportONNXNetwork(lgraph, outputFilename, 'OpsetVersion', opsetVersion);
            catch err
                delete(wb);
                reply = uiconfirm(obj.view.gui, ...
                    sprintf('!!! Error !!!\n\n%s\n\n%s\n\nThe error message was copied to clipboard', err.identifier, err.message), ...
                    'ONNX export', ...
                    'Options',{'Copy error message to clipboard and close', 'Close'}, 'Icon', 'error');
                if strcmp(reply, 'Copy error message to clipboard and close'); clipboard('copy', err.message); end
                return;
            end
        case 'TensorFlow'
            try
                exportNetworkToTensorFlow(lgraph, outputFilename);
            catch err
                utils.dlgs.showErrorDialog(obj.view.gui, err, 'Export to TensorFlow');
                delete(wb); return;
            end
    end
    wb.Value = 1;
    delete(wb);
    
    mgsOpt.MsgBoxOnly = true;
    header = sprintf('Export finished!\n%s', outputFilename);
    mgsOpt.Icon = 'puffin_info';
    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Network export: done!', mgsOpt);
end

