function startPreprocessing(obj)
    % function startPreprocessing(obj)
    % preprocess imaging for training and prediction

    if strcmp(obj.BatchOpt.Workflow{1},  '2D Patch-wise')  % '2D Patch-wise Resnet18' or '2D Patch-wise Resnet50'
        if ismember(obj.BatchOpt.PreprocessingMode{1}, {'Training and Prediction', 'Training', 'Prediction'})
            mgsOpt.MsgBoxOnly = true;
            header = sprintf('Preprocessing of images is not required for patch-wise workflows');
            utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Ops!', mgsOpt);
            return;
        end
    end

    switch obj.BatchOpt.PreprocessingMode{1}
        case 'Training and Prediction'
            t1 = tic;   % init the timer
            obj.processImages('training');     % process images for training
            res1 = toc(t1);
            t2 = tic;   % init the timer
            obj.processImages('prediction');     % process images for training
            res2 = toc(t2);
            fprintf('Training images preprocessing time: %f seconds\n', res1);
            fprintf('Prediction images preprocessing time: %f seconds\n', res2);
        case 'Training'
            t1 = tic;   % init the timer
            obj.processImages('training');     % process images for training
            res1 = toc(t1);
            fprintf('Training images preprocessing time: %f seconds\n', res1);
        case 'Prediction'
            t2 = tic;   % init the timer
            obj.processImages('prediction');     % process images for training
            res2 = toc(t2);
            fprintf('Prediction images preprocessing time: %f seconds\n', res2);
        case 'Split files for training/validation'
            if strcmp(obj.BatchOpt.Workflow{1}, '2D Instance')
                sourceLabelDir = 'LabelsInstances';
                labelsFilenameExt = '*.mat';
                labelsSourceDir = 'LabelsInstances';
                splitForInstanceSegmentation = true;
            else
                sourceLabelDir = 'Labels';
                labelsFilenameExt = lower(['*.' obj.BatchOpt.ModelFilenameExtension{1}]);
                labelsSourceDir = 'Labels';
                splitForInstanceSegmentation = false;
            end
            msg = sprintf('!!! Attention !!!\nThe following operation will split files in\n"%s"\n\n- Images\n- %s\n\nto\n- TrainImages, TrainLabels\n- ValidationImages, ValidationLabels', obj.BatchOpt.OriginalTrainingImagesDir, sourceLabelDir);

            selection = uiconfirm(obj.view.gui, ...
                msg, 'Split files',...
                'Options',{'Split and copy', 'Split and move', 'Cancel'},...
                'DefaultOption', 3, 'CancelOption', 3,...
                'Icon', 'warning');
            if strcmp(selection, 'Cancel'); return; end

            if obj.BatchOpt.RandomGeneratorSeed{1} == 0
                rng('shuffle');
            else
                rng(obj.BatchOpt.RandomGeneratorSeed{1}, 'twister');
            end

            if strcmp(obj.BatchOpt.Workflow{1},  '2D Patch-wise')  % '2D Patch-wise Resnet18' or '2D Patch-wise Resnet50'
                imds = imageDatastore(fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'Images'),...
                    'LabelSource', 'foldernames', 'IncludeSubfolders', true, ...
                    'FileExtensions', lower(['.' obj.BatchOpt.ImageFilenameExtensionTraining{1}]));
                [imds_val, imds_train] = splitEachLabel(imds, obj.BatchOpt.ValidationFraction{1}, 'randomized');

                % define output directories
                outputTrainImagesDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainImages');
                outputValidationImagesDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationImages');

                try
                    if isfolder(outputTrainImagesDir)
                        msg = sprintf('!!! Warning !!!\nThe following subfolders\n- TrainImages\n- ValidationImages\nunder\n"%s"\n\nwill be removed!\nAre you sure?', obj.BatchOpt.OriginalTrainingImagesDir);
                        selection2 = uiconfirm(obj.view.gui, ...
                            msg, 'Split files',...
                            'Options',{'Delete folders', 'Cancel'},...
                            'DefaultOption', 2, 'CancelOption', 2,...
                            'Icon', 'warning');
                        if strcmp(selection2, 'Cancel'); return; end

                        rmdir(outputTrainImagesDir, 's');
                    end
                    if isfolder(outputValidationImagesDir)
                        rmdir(outputValidationImagesDir, 's');
                    end

                    mkdir(outputTrainImagesDir);
                    mkdir(outputValidationImagesDir);

                    classNames = unique(imds.Labels);
                    for classId = 1:numel(classNames)
                        mkdir(fullfile(outputTrainImagesDir, char(classNames(classId))));
                        mkdir(fullfile(outputValidationImagesDir, char(classNames(classId))));
                    end
                catch err
                    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Split images problem');
                    if obj.BatchOpt.showWaitbar; delete(obj.wb); end
                    return;
                end

                wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Splitting and copying files\nPlease wait...'), ...
                    'Title', 'Split files', 'Cancelable','on');

                noFiles = numel(imds_train.Files) + numel(imds_val.Files);
                for fileId = 1:numel(imds_train.Files)
                    [path1, fn1, ext1] = fileparts(imds_train.Files{fileId});
                    [~, classFolderName] = fileparts(path1);
                    copyfile(imds_train.Files{fileId}, fullfile(outputTrainImagesDir, classFolderName, [fn1, ext1]));
                    if mod(fileId, 10) == 1; wb.Value = fileId/noFiles; end
                    if wb.CancelRequested; delete(wb); return; end
                end
                for fileId = 1:numel(imds_val.Files)
                    [path1, fn1, ext1] = fileparts(imds_val.Files{fileId});
                    [~, classFolderName] = fileparts(path1);
                    copyfile(imds_val.Files{fileId}, fullfile(outputValidationImagesDir, classFolderName, [fn1, ext1]));
                    if mod(fileId, 10) == 1; wb.Value = fileId/noFiles; end
                    if wb.CancelRequested; delete(wb); return; end
                end
                if strcmp(selection, 'Split and move')
                    % remove the empty dirs
                    rmdir(fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'Images'), 's');
                end
            else            % split images for semantic segmentation
                imageFiles = dir(fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'Images', lower(['*.' obj.BatchOpt.ImageFilenameExtensionTraining{1}])));
                labelsFiles = dir(fullfile(obj.BatchOpt.OriginalTrainingImagesDir, labelsSourceDir, labelsFilenameExt));

                if numel(imageFiles) ~= numel(labelsFiles) || numel(imageFiles) == 0
                    mgsOpt.MsgBoxOnly = true;
                    header = sprintf('There are no files or number of files mismatch in\n\n%s\n\n- Images\n- Labels', obj.BatchOpt.OriginalTrainingImagesDir);
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Wrong files', mgsOpt);
                    return;
                end
                noFiles = numel(imageFiles);
                randIndices = randperm(noFiles);   % Random permutation of integers
                validationIndices = randIndices(1:ceil(obj.BatchOpt.ValidationFraction{1}*noFiles));   % get indices of images to be used for validation

                % define output directories
                outputTrainImagesDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainImages');
                outputTrainLabelsDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'TrainLabels');
                outputValidationImagesDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationImages');
                outputValidationLabelsDir = fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'ValidationLabels');

                try
                    if isfolder(outputTrainImagesDir)
                        msg = sprintf('!!! Warning !!!\nThe following subfolders\n- TrainImages\n- TrainLabels\n- ValidationImages\n- ValidationLabels\n under\n"%s"\n\nwill be removed!\nAre you sure?', obj.BatchOpt.OriginalTrainingImagesDir);
                        selection2 = uiconfirm(obj.view.gui, ...
                            msg, 'Split files',...
                            'Options',{'Delete folders', 'Cancel'},...
                            'DefaultOption', 2, 'CancelOption', 2,...
                            'Icon', 'warning');
                        if strcmp(selection2, 'Cancel'); return; end

                        rmdir(outputTrainImagesDir, 's');
                    end
                    if isfolder(outputTrainLabelsDir)
                        rmdir(outputTrainLabelsDir, 's');
                    end
                    if isfolder(outputValidationImagesDir)
                        rmdir(outputValidationImagesDir, 's');
                    end
                    if isfolder(outputValidationLabelsDir)
                        rmdir(outputValidationLabelsDir, 's');
                    end

                    mkdir(outputTrainImagesDir);
                    mkdir(outputTrainLabelsDir);
                    if ~isempty(validationIndices)
                        mkdir(outputValidationImagesDir);
                        mkdir(outputValidationLabelsDir);
                    end
                catch err
                    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Split images problem');
                    if obj.BatchOpt.showWaitbar; delete(obj.wb); end
                    return;
                end

                trainLogicalList = true([numel(imageFiles), 1]);   % indices of files for training
                trainLogicalList(validationIndices) = false;   % indices of files for validation

                if strcmp(selection, 'Split and copy')
                    wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Splitting and copying files\nPlease wait...'), ...
                        'Title', 'Split and copy files', 'Cancelable','on');

                    for fileId = 1:noFiles
                        if trainLogicalList(fileId)     % for training
                            copyfile(fullfile(imageFiles(fileId).folder, imageFiles(fileId).name), fullfile(outputTrainImagesDir, imageFiles(fileId).name));
                            copyfile(fullfile(labelsFiles(fileId).folder, labelsFiles(fileId).name), fullfile(outputTrainLabelsDir, labelsFiles(fileId).name));
                        else    % for validation
                            copyfile(fullfile(imageFiles(fileId).folder, imageFiles(fileId).name), fullfile(outputValidationImagesDir, imageFiles(fileId).name));
                            copyfile(fullfile(labelsFiles(fileId).folder, labelsFiles(fileId).name), fullfile(outputValidationLabelsDir, labelsFiles(fileId).name));
                        end
                        if wb.CancelRequested; delete(wb); return; end
                        if mod(fileId, 10) == 1; wb.Value = fileId/noFiles; end
                    end
                elseif strcmp(selection, 'Split and move')
                    wb = uiprogressdlg(obj.view.gui, 'Message', sprintf('Splitting and copying files\nPlease wait...'), ...
                        'Title', 'Split and move files', 'Cancelable','on');
                    for fileId = 1:noFiles
                        if trainLogicalList(fileId)     % for training
                            movefile(fullfile(imageFiles(fileId).folder, imageFiles(fileId).name), fullfile(outputTrainImagesDir, imageFiles(fileId).name));
                            movefile(fullfile(labelsFiles(fileId).folder, labelsFiles(fileId).name), fullfile(outputTrainLabelsDir, labelsFiles(fileId).name));
                        else    % for validation
                            movefile(fullfile(imageFiles(fileId).folder, imageFiles(fileId).name), fullfile(outputValidationImagesDir, imageFiles(fileId).name));
                            movefile(fullfile(labelsFiles(fileId).folder, labelsFiles(fileId).name), fullfile(outputValidationLabelsDir, labelsFiles(fileId).name));
                        end
                        if wb.CancelRequested; delete(wb); return; end
                        if mod(fileId, 10) == 1;  wb.Value = fileId/noFiles; end
                    end
                    % remove the empty dirs
                    rmdir(fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'Images'), 's');
                    rmdir(fullfile(obj.BatchOpt.OriginalTrainingImagesDir, 'Labels'), 's');
                end
            end

            obj.view.handles.PreprocessingMode.Value = 'Preprocessing is not required';
            obj.BatchOpt.PreprocessingMode{1} = 'Preprocessing is not required';

            delete(wb);
    end
    % Preprocessing for training, AM files 256x256x3x512
    % C:\MATLAB\Data\CNN_FileRead_Test /notebook
    %             R2019b
    %             DeepMIB ver1, no compression = [17.548520 17.203554 17.444283], average=17.3988 (100%)
    %             DeepMIB ver1, model compression = [17.202636 17.368104 16.817339], average=17.1294 (98%)
    %             DeepMIB ver1, image+model compression = [20.123545 20.309843 19.809388], average 20.0809 (115%)
    %             DeepMIB direct AM-read, model compression = [10.975879 10.601845 10.738362]; average=10.772 (62%)
    %             DeepMIB no-meta AM-read, model compression = [8.410581 8.541582 8.414153]; average = 8.4554 (49%)
    %             DeepMIB no-meta AM-read, model comp, waitbar x10 = [7.555503 7.618259 7.555017], average = 7.5763 (43%)
    %             DeepMIB with parfor [7.108081 8.261853 6.799513], average = 7.3898 (42%, 2workers, 17% 8workers)
    %
    %             R2020b
    %             DeepMIB ver1, no compression = [16.799966 16.688955 15.628009], average=16.3723 (100%) vs 2019b 94%
    %             DeepMIB ver1, model compression = [15.955620 15.851953 16.127321], average=15.9783 (98%)
    %             DeepMIB ver1, image+model compression = [19.077072 18.302455 18.434443], average 18.6047 (114%)
end

