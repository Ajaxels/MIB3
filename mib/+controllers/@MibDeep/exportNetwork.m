function exportNetwork(obj)
    % function exportNetwork(obj)
    % convert and export network to ONNX or TensorFlow formats
    
    if exist(obj.BatchOpt.NetworkFilename, 'file') ~= 2
        mgsOpt.MsgBoxOnly = true;
        mgsOpt.Header = sprintf('The network file:\n%s\ncan not be found!', obj.BatchOpt.NetworkFilename);
        mgsOpt.Icon = 'puffin_error';
        utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Missing file', mgsOpt);
        return;
    end

    prompts = {'Output format'; 'Alter the final segmentation layer as'; 'Version of ONNX operator set'};
    defAns = {{'ONNX', 'TensorFlow', 1};{'Keep as it is', 'Remove the layer', 'pixelClassificationLayer', 'dicePixelClassificationLayer', 1};  {'6', '7', '8', '9','10','11','12','13', 4}; };
    dlgTitle = 'Export network';
    options.PromptLines = [1, 1, 1];
    options.Title = sprintf('Convert and export the network to ONNX or TensorFlow format');
    options.TitleLines = 1;
    options.WindowWidth = 1.2;
    options.HelpUrl = 'https://se.mathworks.com/help/deeplearning/ref/exportonnxnetwork.html';

    [answer, selIndex] = mibInputMultiDlg({mibPath}, prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    exportFormat = answer{1};
    finalSegmentationLayer = answer{2};
    opsetVersion = str2double(answer{3});

    [currDir, fn] = fileparts(obj.BatchOpt.NetworkFilename);

    switch exportFormat
        case 'ONNX'
            outoutFilename = fullfile(currDir, [fn '.onnx']);
            [filename, pathname] = uiputfile( ...
                {'*.onnx','ONNX-files (*.onnx)';...
                '*.*',  'All Files (*.*)'}, ...
                'Set output file', outoutFilename);
            if filename == 0; return; end
            outoutFilename = fullfile(pathname, filename);
        case 'TensorFlow'
            outoutFilename = uigetdir(currDir, 'TensorFlow: define model package name');
            if outoutFilename == 0; return; end
    end

    wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Exporting to %s\nPlease wait...', exportFormat), ...
        'Title', 'Export network');
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
                exportONNXNetwork(lgraph, outoutFilename, 'OpsetVersion', opsetVersion);
            catch err
                % when addSpkgBinPath is not patched a second attempt to export is needed
                % line 6: should be "if isempty(pathSet) && ~isdeployed"
                try
                    exportONNXNetwork(lgraph, outoutFilename, 'OpsetVersion', opsetVersion);
                catch err2
                    delete(wb);
                    reply = uiconfirm(obj.view.gui, ...
                        sprintf('!!! Error !!!\n\n%s\n\n%s\n\nThe error message was copied to clipboard', err2.identifier, err2.message), ...
                        'ONNX export', ...
                        'Options',{'Copy error message to clipboard and close', 'Close'}, 'Icon', 'error');
                    if strcmp(reply, 'Copy error message to clipboard and close'); clipboard('copy', err2.message); end
                    return;
                end
            end
        case 'TensorFlow'
            try
                exportNetworkToTensorFlow(lgraph, outoutFilename);
            catch err
                utils.dlgs.showErrorDialog(obj.view.gui, err, 'Export to TensorFlow');
                delete(wb); return;
            end
    end
    wb.Value = 1;
    delete(wb);
    mgsOpt.MsgBoxOnly = true;
    mgsOpt.Header = sprintf('Export finished!\n%s', outoutFilename);
    mgsOpt.Icon = 'puffin_info';
    utils.dlgs.inputUniversalDlg(obj.view.gui, {}, {}, 'Network export: done!', mgsOpt);
end

