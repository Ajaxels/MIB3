function balanceClasses(obj)
% BALANCECLASSES - balance classes before training.
%
% Syntax:
%   function balanceClasses(obj)
%
% see example from here:
% https://se.mathworks.com/help/vision/ref/balancepixellabels.html
    if ~isfield(obj.sessionSettings, 'numBalanceObservations'); obj.sessionSettings.numBalanceObservations = 200; end
    if ~isfield(obj.sessionSettings, 'balanceObservationsParallel'); obj.sessionSettings.balanceObservationsParallel = false; end

    % Set block size of the images.
    inputPatchSize = str2num(obj.BatchOpt.T_InputPatchSize);
    blockSize = [inputPatchSize(1) inputPatchSize(2)];

    prompts = {sprintf('Number of patches in the balanced dataset to generate:'); 'Output patch size:'; 'Number of classes (incl. Exterior):'; 'Use parallel processing:'};
    defAns = {struct('Spinner', true, 'Value', obj.sessionSettings.numBalanceObservations, 'Limits', [1 Inf], 'Step', 1, 'Round', true); ...
        num2str(blockSize); ...
        struct('Spinner', true, 'Value', obj.BatchOpt.T_NumberOfClasses{1}, 'Limits', [1 Inf], 'Step', 1, 'Round', true); ...
        obj.sessionSettings.balanceObservationsParallel};
    dlgTitle = 'Settings';
    inputDlgOpt.Header = sprintf(['This is a beta procedure to balance rare classes in the dataset\n' ...
        'The procedure is implemented only for the 2D Semantic workflow and only for images and labels that are ' ...
        'stored in standard image formats (e.g. TIF, PNG, JPG).\n' ...
        'The images and labels needs to be placed in "Images" and "Labels" subfolders under ' ...
        '"Directories with images and labels for training" specified in the "Directories and preprocessing" tab\n' ...
        'The balanced results are generated under the same directory in ' ...
        '"ImagesBalanced" and "LabelsBalanced" subfolders']);
    inputDlgOpt.HeaderLines = 6;
    inputDlgOpt.WindowWidth = 630;
    inputDlgOpt.WindowHeight = 310;
    inputDlgOpt.helpBtnText = 'Info example';
    inputDlgOpt.LabelPosition = 'left';
    inputDlgOpt.HelpUrl = 'https://se.mathworks.com/help/vision/ref/balancepixellabels.html';
    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle, inputDlgOpt);
    if isempty(answer); return; end

    % Speciy number of block locations to sample from the dataset.
    obj.sessionSettings.numBalanceObservations = answer{1};
    blockSize = str2num(answer{2});
    numberOfClasses = answer{3};
    obj.sessionSettings.balanceObservationsParallel = logical(answer{4});

    parforArg = 0;  % no parallel pool
    if obj.sessionSettings.balanceObservationsParallel
        parforArg = obj.view.handles.PreprocessingParForWorkers.Value;    % Maximum number of workers running in parallel
        if isempty(gcp('nocreate')); parpool(parforArg); end % create parpool
    end

    % check for the proper workflow
    if ~strcmp(obj.BatchOpt.Workflow{1}, '2D Semantic')
        mgsOpt.MsgBoxOnly = true;
        header = sprintf('Balancing of labels is implemented only for the 2D Semantic workflow!');
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong workflow', mgsOpt);
        return
    end
    tic;

    % define input directories for images and labels
    try
        imageDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'Images');
        labelDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'Labels');
        imageSet = matlab.io.datastore.FileSet(imageDir, "FileExtensions", {['.' obj.BatchOpt.ImageFilenameExtensionTraining{1}]});
        labelSet = matlab.io.datastore.FileSet(labelDir, "FileExtensions", {['.' obj.BatchOpt.ModelFilenameExtension{1}]});
    catch err
        utils.dlgs.showErrorDialog(obj.view.gui, err, 'Missing files');
        return;
    end
    % check that number of image and label files match
    if imageSet.NumFiles ~= labelSet.NumFiles
        mgsOpt.MsgBoxOnly = true;
        header = sprintf(['Directories with images and labels should have equal number of files!\n\n' ...
                                 'Directory with images:\n%s\n\nDirectory with labels:\n%s\n'], imageDir, labelDir);
        utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Number of files mismatch', mgsOpt);
        return
    end

    pw = core.PoolWaitbar(imageSet.NumFiles, sprintf('Balancing labels\nPlease wait...'), obj.view.gui);

    % Create an array of labeled images from the dataset.
    blockedLabelsList = blockedImage(labelSet);
    blockedImagesList = blockedImage(imageSet);

    % Create a blockedImageDatastore from the image array.
    blockedLabelsDS = blockedImageDatastore(blockedLabelsList, 'BlockSize', blockSize);

    % Count pixel label occurrences of each class. The classes in the pixel label images are not balanced.
    if numberOfClasses == 2
        pixelLabelID = 0:numberOfClasses-1; %  exclude exterior
        classNames = {'Exterior', 'Class01'};
    else
        pixelLabelID = 1:numberOfClasses-1; %  exclude exterior
        classNames = arrayfun(@(x) sprintf('Class%.2d', x), 1:numberOfClasses-1, 'UniformOutput', false);
    end

    % Select block locations from the labeled images to achieve class.
    locationSet = balancePixelLabels(blockedLabelsList, blockSize, obj.sessionSettings.numBalanceObservations,...
        'Classes', classNames, 'PixelLabelIDs', pixelLabelID);

    % Create a blockedImageDatastore using the block locations after balancing.
    blockLabeldsBalanced = blockedImageDatastore(blockedLabelsList, 'BlockLocationSet', locationSet);
    blockImagesBalanced = blockedImageDatastore(blockedImagesList, 'BlockLocationSet', locationSet);

    outImgDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ImagesBalanced');
    outLabelDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'LabelsBalanced');
    if isfolder(outImgDir); rmdir(outImgDir, 's'); end
    if isfolder(outLabelDir); rmdir(outLabelDir, 's'); end
    mkdir(outImgDir);
    mkdir(outLabelDir);

    pw.updateMaxNumberOfIterations(blockImagesBalanced.TotalNumBlocks);
    pw.setIncrement(20);  % set increment step to 20

    fnIndex = 1;
    parfor (fnIndex = 1:blockImagesBalanced.TotalNumBlocks, parforArg)
        [imgIn, imgInfo] = read(blockImagesBalanced);
        [labelIn, labelInfo] = read(blockLabeldsBalanced);
        fn = sprintf('img_%.3d.tif', fnIndex);
        imwrite(imgIn{1}, fullfile(outImgDir, fn));
        imwrite(labelIn{1}, fullfile(outLabelDir, fn));
        if mod(fnIndex, 20) == 1; increment(pw); end
    end

    pw.updateText(sprintf('Counting labels\nPlease wait...'));
    pw.updateMaxNumberOfIterations(3);
    pw.setIncrement(1);  % set increment step to 20
    increment(pw);

    if numberOfClasses == 2
        classNamesCounting = classNames;
        pixelLabelIDCounting = 0:numberOfClasses-1;
    else
        %classNamesCounting = ['Ext', classNames];
        %pixelLabelIDCounting = 0:numberOfClasses-1;
        classNamesCounting = classNames;
        pixelLabelIDCounting = 1:numberOfClasses-1;
    end

    labelCounts = countEachLabel(blockedLabelsDS,...
        'Classes', classNamesCounting, 'PixelLabelIDs', pixelLabelIDCounting);
    increment(pw);

    % Recalculate the pixel label occurrences for the balanced dataset.
    labelCountsBalanced = countEachLabel(blockLabeldsBalanced,...
        'Classes', classNamesCounting, 'PixelLabelIDs', pixelLabelIDCounting);
    increment(pw);

    % Compare the original unbalanced labels and labels after label balancing.
    figure(321);
    h1 = histogram('Categories',labelCounts.Name,...
        'BinCounts',labelCounts.PixelCount);
    title(h1.Parent,'Original dataset labels')

    figure(322);
    h2 = histogram('Categories',labelCountsBalanced.Name,...
        'BinCounts',labelCountsBalanced.PixelCount);
    title(h2.Parent, sprintf('Balanced labels, N=%d', obj.sessionSettings.numBalanceObservations));
    fprintf('Balancing of classes is over!\n');
    toc;
    pw.deletePoolWaitbar();
end

