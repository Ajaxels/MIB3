function transferLearning(obj)
% TRANSFERLEARNING - perform fine-tuning of the loaded network to a different.
%
% Syntax:
%   function transferLearning(obj)
%
% number of classes

    obj.BatchOpt.Mode{1} = 'Predict';   % change the mode, so that selectNetwork function loads the network
    net = obj.selectNetwork();
    if isempty(net); return; end
    dlnetwork_flag = false; % type of the loaded model
    if isa(net, 'dlnetwork'); dlnetwork_flag = true; end
    obj.BatchOpt.Mode{1} =  'Train';    % restore the mode

    [outPath, outNetworkName, outExt] = fileparts(obj.BatchOpt.NetworkFilename);
    outNetworkName = [outNetworkName '_TrLrn'];

    header = sprintf('You are going to modify number of output classes!\nThis operation should be followed with retraining of the network!');
    prompts = { 'Define new number of classes (including Exterior):';...
        'Segmentation layer:';...
        'New network name:'};
    defAns = {struct('Spinner', true, 'Value', obj.BatchOpt.T_NumberOfClasses{1}, 'Limits', [1 Inf], 'Step', 1, 'Round', true)
        [obj.view.Figure.T_SegmentationLayer.Items find(ismember(obj.view.Figure.T_SegmentationLayer.Items, obj.BatchOpt.T_SegmentationLayer{1}))];...
        outNetworkName
        };
    dlgTitle = 'Transfer learning';
    options.HeaderLines = 2;
    options.Icon = 'puffin_warning';
    options.WindowWidth = 400;
    options.WindowHeight = 250;
    %options.HelpUrl = 'https://se.mathworks.com/help/deeplearning/ref/imagedataaugmenter.html'; % [optional], an url for the Help button

    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    obj.wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Performing transfer learning\nPlease wait...'), ...
        'Title', 'Transfer learning');

    newNoClasses = answer{1};
    newSegLayer = answer{2};
    outNetworkName = answer{3};
    outConfigName = fullfile(outPath, [outNetworkName '.mibCfg']);
    outNetworkName = fullfile(outPath, [outNetworkName, outExt]);

    % generate a new network to obtain the ending part
    obj.BatchOpt.T_NumberOfClasses{1} = newNoClasses;  % redefine number of classes
    obj.BatchOpt.T_SegmentationLayer{1} = newSegLayer;  % update segmentation layer

    [lgraph, outputPatchSize] = obj.createNetwork();
    if isempty(lgraph)
        if ~isempty(obj.wb); delete(obj.wb); end
        return;
    end
    obj.wb.Value = 0.3;

    % find layer after which all layers should be replaced
    switch obj.BatchOpt.Architecture{1}
        case 'SegNet'
            layerName = 'decoder1_conv1';   % 2D segnet
        case {'DeepLab v3+', 'Z2C + DLv3'}
            layerName = 'scorer';   % 2D DeepLabV3
        case {'U-net +Encoder', 'Z2C + U-net +Encoder'}
            layerName = 'encoderDecoderFinalConvLayer'; % 2D Unet with encoders
        otherwise
            layerName = 'Final-ConvolutionLayer';
    end

    segmLayerId = numel(net.Layers);
    notOk = 1;
    while notOk
        if ~strcmp(net.Layers(segmLayerId).Name, layerName)
            segmLayerId = segmLayerId - 1;
        else
            notOk = 0;
        end

        if segmLayerId == 0
            mgsOpt.MsgBoxOnly = true;
            header = sprintf('The original network does not have %s layer', layerName);
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Transfer learning', mgsOpt);
            delete(obj.wb);
            return;
        end
    end
    obj.wb.Value = 0.5;

    % convert DAG object to LayerGraph object to allow
    % modification of layers
    net = layerGraph(net);
    for layerId=segmLayerId:numel(net.Layers)
        net = replaceLayer(net, net.Layers(layerId).Name, lgraph.Layers(layerId));
    end
    obj.wb.Value = 0.6;

    obj.BatchOpt.NetworkFilename = outNetworkName;
    if dlnetwork_flag; net = dlnetwork(net); end
    save(outNetworkName, 'net', '-mat', '-v7.3');
    obj.saveConfig(outConfigName);
    obj.wb.Value = 0.9;

    % update elements of GUI
    obj.view.Figure.NetworkFilename.Value = obj.BatchOpt.NetworkFilename;
    obj.view.Figure.T_NumberOfClasses.Value = obj.BatchOpt.T_NumberOfClasses{1};
    obj.view.Figure.NumberOfClassesPreprocessing.Value = obj.BatchOpt.T_NumberOfClasses{1};
    obj.view.Figure.T_SegmentationLayer.Value = obj.BatchOpt.T_SegmentationLayer{1};

    obj.wb.Value = 1;
    fprintf('The transfer learning finished:\n%s\n', outNetworkName);
    delete(obj.wb);
end

