function updateSamSettings(obj)
% function updateSamSettings(obj)
% Open SAM settings dialog for configuring SAM1 or SAM2 parameters
% the SAM tool is implemented in @MibImageDocument class

% create local copies
SAM = obj.mibModel.preferences.SegmTools.SAM;
SAM1 = obj.mibModel.preferences.SegmTools.SAM1;
SAM2 = obj.mibModel.preferences.SegmTools.SAM2;

% get settings file with links to SAM backbones
if strcmp(SAM.samVersion, 'SAM1')
    linksFile = fullfile(obj.mibModel.mibPath, SAM1.linksFile);
else
    linksFile = fullfile(obj.mibModel.mibPath, SAM2.linksFile);
end

linksJSON = fileread(linksFile);
linksStruct = jsondecode(linksJSON);
% get names of available SAM backbones
sam_names = {linksStruct.name};

if strcmp(SAM.samVersion, 'SAM1')
    prompts = {'Backbone (requires download)'; ...
        'Execution environment(cpu is ~30-60 times slower than cuda)';
        'Show the progress bar in the interactive mode';
        'Location of "sam_links.json" with links to SAM backbones, relative to MIB installation path'
        'PATH to segment-anything installation';
        'Check to select path to segment-anything';
        'Check to reset settings to default values...';
        sprintf('---------------------------- Automatic mode settings ----------------------------\npoints_per_side: the number of points to be sampled along one side of the image [def=32]');
        'points_per_batch: sets the number of points run simultaneously by the model. Higher numbers may be faster but use more GPU memory [def=64]';
        'pred_iou_thresh: filtering threshold in [0,1], using the model''s predicted mask quality [def=0.88]';
        'stability_score_thresh: filtering threshold in [0,1], using the stability of the mask under changes to the cutoff used to binarize the model''s mask predictions [def=0.95]';
        'box_nms_thresh: the box IoU cutoff used by non-maximal suppression to filter duplicate masks [def=0.7]';
        'crop_n_layers: if >0, mask prediction will be run again on crops of the image. Sets the number of layers to run, where each layer has 2^i_layer number of image crops [def=0]';
        'crop_nms_thresh: the box IoU cutoff used by non-maximal suppression to filter duplicate masks between different crops [def=0.7]';
        'crop_overlap_ratio: sets the degree to which crops overlap. In the first crop layer, crops will overlap by this fraction of the image length. Later layers with more crops scale down this overlap [def=0.3413]';
        'crop_n_points_downscale_factor: the number of points-per-side sampled in layer n is scaled down by crop_n_points_downscale_factor^n [def=1]';
        'min_mask_region_area: if >0, postprocessing will be applied to remove disconnected regions and holes in masks with area smaller than min_mask_region_area [def=0]'};

    defAns = {{sam_names{:}, find(ismember(sam_names, SAM1.backbone))};
        {'cuda', 'cpu', find(ismember({'cuda', 'cpu'}, SAM1.environment))};
        SAM1.showProgressBar;
        SAM1.linksFile;
        SAM1.sam_installation_path;
        false;
        false;
        num2str(SAM1.points_per_side);
        num2str(SAM1.points_per_batch);
        num2str(SAM1.pred_iou_thresh);
        num2str(SAM1.stability_score_thresh);
        num2str(SAM1.box_nms_thresh);
        num2str(SAM1.crop_n_layers);
        num2str(SAM1.crop_nms_thresh);
        num2str(SAM1.crop_overlap_ratio);
        num2str(SAM1.crop_n_points_downscale_factor);
        num2str(SAM1.min_mask_region_area)}; %#ok<CCAT>

    dlgTitle = 'Segment-anything settings';
    options.WindowStyle = 'normal';
    %options.PromptLines = [1, 1, 2, 2, 1, 1, 2, 4, 2, 2, 3, 2, 3, 2, 3, 2, 3];
    options.Header = sprintf('Usage of Segment-anything requires Python installation with all necessary modules. Please refer to documentation on how to set it up.\nThe selected backbone will be downloaded to DeepMIB temporary directory that can be updated from Menu->File->Preferences->External Dirs');
    options.HeaderLines = 4;
    options.WindowWidth = 900;
    options.WindowHeight = 700;
    options.Columns = 2;
    options.Focus = 1;
    options.HelpUrl = 'https://mib.helsinki.fi/downloads_systemreq_sam.html';
    options.mibPath = obj.mibModel.mibPath;
    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    if answer{7}
        answer2 = utils.dlgs.inputQuestDlg(obj.mibModel.mibGUI, ...
            sprintf(['!!! Warning !!!\n\nYou are going to reset SAM settings to default values!\n\n' ...
            'Note!\n' ...
            'After that you need to specify location of segment-anything and update other settings if needed']), ...
            'Reset SAM', 'Reset', 'Do not reset, just update', 'Cancel', 'Cancel');
        if strcmp(answer2, 'Cancel')
            return
        elseif strcmp(answer2, 'Reset')
            % restore default values
            if ~strcmp(SAM1.backbone, 'vit_b (0.4Gb)')
                if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
                obj.mibModel.pythonEnv = [];
            end
            SAM1.backbone = 'vit_b (0.4Gb)';
            SAM1.points_per_side = 32;
            SAM1.points_per_batch = 64;
            SAM1.pred_iou_thresh = 0.88;
            SAM1.stability_score_thresh = 0.95;
            SAM1.box_nms_thresh = 0.7;
            SAM1.crop_n_layers = 0;
            SAM1.crop_nms_thresh = 0.7;
            SAM1.crop_overlap_ratio = 0.3413;
            SAM1.crop_n_points_downscale_factor = 1;
            SAM1.min_mask_region_area = 0;
            SAM1.showProgressBar = false;
            
            % update SAM1 settings
            obj.mibModel.preferences.SegmTools.SAM1 = SAM1;
            return
        end
    end

    if answer{6}
        try
            selpath = uigetdir(SAM1.sam_installation_path, 'segment-anything location');
        catch err
            selpath = uigetdir([], 'segment-anything location');
        end
        if selpath == 0; return; end
        SAM1.sam_installation_path = selpath;
    else
        SAM1.sam_installation_path = answer{5};
    end

    if ~strcmp(SAM1.backbone, answer{1})
        if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
        obj.mibModel.pythonEnv = [];
    end
    if ~strcmp(answer{2}, SAM1.environment)
        if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
        obj.mibModel.pythonEnv = [];
    end

    SAM1.backbone = answer{1};
    SAM1.points_per_side = str2double(answer{8});
    SAM1.points_per_batch = str2double(answer{9});
    SAM1.pred_iou_thresh = str2double(answer{10});
    SAM1.stability_score_thresh = str2double(answer{11});
    SAM1.box_nms_thresh = str2double(answer{12});
    SAM1.crop_n_layers = str2double(answer{13});
    SAM1.crop_nms_thresh = str2double(answer{14});
    SAM1.crop_overlap_ratio = str2double(answer{15});
    SAM1.crop_n_points_downscale_factor = str2double(answer{16});
    SAM1.min_mask_region_area = str2double(answer{17});
    SAM1.environment = answer{2};
    SAM1.showProgressBar = logical(answer{3});

    % check for the SAM-links file
    newLinksFile = fullfile(obj.mibModel.mibPath, answer{4});
    if exist(newLinksFile, 'file') == 0
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        dlgOpt.Header = sprintf('The provided file:\n%s\nwith SAM links does not exist!\n\nKeeping the previous version:\n%s', newLinksFile, linksFile);
        dlgOpt.HeaderLines = 5;
        utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, {}, {}, 'Wrong JSON file', dlgOpt);
    else
        SAM1.linksFile = answer{4};
    end
    % update SAM1 settings
    obj.mibModel.preferences.SegmTools.SAM1 = SAM1;

    % validate requirements with the updated settings
    cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
    cImageDoc.segmentationSAM_requirements('SAM1');
else
    % SAM 2
    prompts = {'Backbone (requires download)'; ...
        'Execution environment(cpu is ~30-60 times slower than cuda)';
        'Show the progress bar in the interactive mode';
        'Location of "sam2_links.json" with links to SAM backbones, relative to MIB installation path'
        'PATH to segment-anything-2 installation';
        'Check to select path to segment-anything-2';
        'Check to reset settings to default values...';
        sprintf('---------------------------- Automatic mode settings ----------------------------\npoints_per_side: the number of points to be sampled along one side of the image. The total number of points is points_per_side**2 [def=32]');
        'points_per_batch: sets the number of points run simultaneously by the model. Higher numbers may be faster but use more GPU memory [def=64]';
        'pred_iou_thresh: a filtering threshold in [0, 1], using the model predicted mask quality [def=0.8]';
        'stability_score_thresh: a filtering threshold in [0, 1], using the stability of the mask under changes to the cutoff used to binarize the models mask predictions (def=0.95)';
        'stability_score_offset: the amount to shift the cutoff when calculated the stability score [def=1.0]';
        'crop_n_layers: if >0, mask prediction will be run again on crops of the image. Sets the number of layers to run, where each layer has 2**i_layer number of image crops [def=0]';
        'box_nms_thresh: the box IoU cutoff used by non-maximal suppression to filter duplicate mask [def=0.7]';
        'crop_n_points_downscale_factor: The number of points-per-side sampled in layer n is scaled down by crop_n_points_downscale_factor**n [def=1]';
        'min_mask_region_area: if >0, postprocessing will be applied to remove disconnected regions and holes in masks with area smaller than min_mask_region_area [def=0]';
        'use_m2m: add refinement using previous mask [def=false]'};
    defAns = {{sam_names{:}, find(ismember(sam_names, SAM2.backbone))};
        {'cuda', 'cpu', find(ismember({'cuda', 'cpu'}, SAM2.environment))};
        SAM2.showProgressBar;
        SAM2.linksFile;
        SAM2.sam_installation_path;
        false;
        false;
        num2str(SAM2.points_per_side);
        num2str(SAM2.points_per_batch);
        num2str(SAM2.pred_iou_thresh);
        num2str(SAM2.stability_score_thresh);
        num2str(SAM2.stability_score_offset);
        num2str(SAM2.crop_n_layers);
        num2str(SAM2.box_nms_thresh);
        num2str(SAM2.crop_n_points_downscale_factor);
        num2str(SAM2.min_mask_region_area);
        SAM2.use_m2m};

    dlgTitle = 'Segment-anything-2 settings';
    options.WindowStyle = 'normal';
    %options.PromptLines = [1, 1, 1, 2, 1, 1, 1, 4, 2, 2, 3, 2, 3, 2, 2, 3, 1];
    options.Header = sprintf('Usage of Segment-anything requires Python installation with all necessary modules. Please refer to documentation on how to set it up.\nThe selected backbone will be downloaded to DeepMIB temporary directory that can be updated from\nRibbon->Home->Preferences->External Dirs');
    options.HeaderLines = 3;
    options.WindowWidth = 900;
    options.WindowHeight = 650;
    options.Columns = 2;
    options.Focus = 1;
    options.HelpUrl = 'https://mib.helsinki.fi/downloads_systemreq_sam2.html';
    options.mibPath = obj.mibModel.mibPath;

    [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, prompts, defAns, dlgTitle, options);
    if isempty(answer); return; end

    if answer{7}
        questOpt.WindowHeight = 240;
        answer2 = utils.dlgs.inputQuestDlg(obj.mibModel.mibGUI, ...
            sprintf(['You are going to reset SAM2 settings to default values!\n\n' ...
            'Note!\n' ...
            'After that you need to specify location of segment-anything-2 and update other settings if needed']), ...
            'Reset SAM', 'Reset', 'Do not reset, just update', 'Cancel', 'Cancel', questOpt);
        if strcmp(answer2, 'Cancel')
            return
        elseif strcmp(answer2, 'Reset')
            if ~strcmp(obj.mibModel.preferences.SegmTools.SAM2.backbone, 'sam2_hiera_t (0.15Gb)')
                if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
                obj.mibModel.pythonEnv = [];
            end
            SAM2.backbone = 'sam2_hiera_t (0.15Gb)';
            SAM2.showProgressBar = false;
            SAM2.points_per_side = 32;
            SAM2.points_per_batch = 64;
            SAM2.pred_iou_thresh = 0.8;
            SAM2.stability_score_thresh = 0.95;
            SAM2.stability_score_offset = 1.0;
            SAM2.crop_n_layers = 0;
            SAM2.box_nms_thresh = 0.7;
            SAM2.crop_n_points_downscale_factor = 1;
            SAM2.min_mask_region_area = 0;
            SAM2.use_m2m = false;

            % update SAM2 settings
            obj.mibModel.preferences.SegmTools.SAM2 = SAM2;
            return
        end
    end

    if answer{6}
        try
            selpath = uigetdir(SAM2.sam_installation_path, 'segment-anything-2 location');
        catch err
            selpath = uigetdir([], 'segment-anything-2 location');
        end
        if selpath == 0; return; end
        SAM2.sam_installation_path = selpath;
    else
        SAM2.sam_installation_path = answer{5};
    end

    if ~strcmp(SAM2.backbone, answer{1})
        if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
        obj.mibModel.pythonEnv = [];
    end
    if ~strcmp(answer{2}, SAM2.environment)
        if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
        obj.mibModel.pythonEnv = [];
    end

    SAM2.backbone = answer{1};
    SAM2.environment = answer{2};
    SAM2.showProgressBar = logical(answer{3});

    SAM2.points_per_side = round(str2double(answer{8}));
    SAM2.points_per_batch = round(str2double(answer{9}));
    SAM2.pred_iou_thresh = str2double(answer{10});
    SAM2.stability_score_thresh = str2double(answer{11});
    SAM2.stability_score_offset = str2double(answer{12});
    SAM2.crop_n_layers = round(str2double(answer{13}));
    SAM2.box_nms_thresh = str2double(answer{14});
    SAM2.crop_n_points_downscale_factor = round(str2double(answer{15}));
    SAM2.min_mask_region_area = round(str2double(answer{16}));
    SAM2.use_m2m = logical(answer{17});

    % check for the SAM-links file
    newLinksFile = fullfile(obj.mibModel.mibPath, answer{4});
    if exist(newLinksFile, 'file') == 0
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        dlgOpt.Header = sprintf('The provided file:\n%s\nwith SAM links does not exist!\n\nKeeping the previous version:\n%s', newLinksFile, linksFile);
        dlgOpt.HeaderLines = 5;
        utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, {}, {}, 'Wrong JSON file', dlgOpt);
    else
        SAM2.linksFile = answer{4};
    end

    % update SAM2 settings
    obj.mibModel.preferences.SegmTools.SAM2 = SAM2;

    % validate requirements with the updated settings
    cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
    cImageDoc.segmentationSAM_requirements('SAM2');
end
end