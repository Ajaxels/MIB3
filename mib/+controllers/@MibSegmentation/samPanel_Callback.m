function samPanel_Callback(obj, hWidget, hData)
% samPanel_Callback(obj, hWidget, hData)
% Callbacks for widgets in the Segmentation panel->SAM tool
%
% Parameters:
% hWidget: handle to the pressed widget
% hWidget.Tag - identifier the widget, used when the same operation is called from menu
% 'samMethod' -> method of SAM usage
% 'samVersion' -> select version of SAM to use 'SAM 1', 'SAM 2'
% 'samDataset' -> select type of dataset to apply SAM
% 'samDestination' -> destination layer for SAM results
% 'samMode' -> SAM mode, add/replace/subtract
% 'samSettings' -> open SAM settings dialog
% 'samList' -> show the list of points (annotations) for the landmark mode
% 'samClear' -> clear the annotation points
% 'samSegment' -> do SAM segmentation
%
% hData: handle to supporting data class
%

arguments (Input)
    obj controllers.MibSegmentation
    hWidget {mustBeA(hWidget, {'matlab.ui.control.Button', 'matlab.ui.control.CheckBox', 'matlab.ui.control.DropDown'})}
    hData {mustBeA(hData, {'matlab.ui.eventdata.ButtonPushedData', 'matlab.ui.eventdata.ValueChangedData'})}
end

mode = hWidget.Tag;

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibSegmentation.samPanel_Callback: "obj.view.handles.panels.segmentation.handles.%s" -> changed/pressed\n', mode);
end

switch mode
    case 'samMethod' % method of SAM usage
        switch hWidget.Value
            case {'Automatic everything', 'Landmarks'}
                obj.view.handles.panels.segmentation.handles.samSegment.Enable = 'on';
            case {'Interactive', 'Interactive 3D'}
                obj.view.handles.panels.segmentation.handles.samSegment.Enable = 'off';
        end
    case 'samVersion' % use SAM2 instead of SAM1
        obj.mibModel.preferences.SegmTools.SAM.samVersion = hWidget.ValueIndex;
        % force to reset python during next usage, to minimize GPU memory consumption
        if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
        obj.mibModel.pythonEnv = [];
    case 'samDataset' % select type of dataset to apply SAM
        % no action needed
    case 'samDestination' % destination layer for SAM results
        % no action needed
    case 'samMode' % SAM mode, add/replace/subtract
        % no action needed
    case 'samSettings' % open SAM settings dialog
        samSettingsDialog(obj);
    case 'samList' % show the list of points (annotations) for the landmark mode
        obj.mibController.startController('controllers.Annotations');
    case 'samClear' % clear the annotation points
        dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
        dataset.annotations.removeAnnotations();
        notify(obj.mibModel, 'ShowImage');
    case 'samSegment' % do SAM segmentation
        cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
        dataset = obj.mibModel.I{obj.mibModel.getActiveId()};

        % check model type for automatic mode
        if strcmp(obj.handles.samMethod.Value, 'Automatic everything') && ...
                dataset.labels.maxMaterials < 65535
            dlgOpt.MsgBoxOnly = true;
            dlgOpt.Icon = 'puffin_error';
            dlgOpt.Header = sprintf('To use segment-anything in the automatic mode the model should be able to keep 65535 or more materials!\n\nCreate a new model or change the type of the current model from\nMenu->Models->Convert type');
            dlgOpt.HeaderLines = 4;
            utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, {}, {}, 'Wrong model type', dlgOpt);
            return;
        end

        switch obj.mibModel.preferences.SegmTools.SAM.samVersion
            case 1
                cImageDoc.segmentationSAM();
            case 2
                cImageDoc.segmentationSAM2();
        end
end

end

function samSettingsDialog(obj)
% Open SAM settings dialog for configuring SAM1 or SAM2 parameters

% get settings file with links to SAM backbones
if obj.mibModel.preferences.SegmTools.SAM.samVersion == 1
    linksFile = fullfile(obj.mibModel.mibPath, obj.mibModel.preferences.SegmTools.SAM.linksFile);
else
    linksFile = fullfile(obj.mibModel.mibPath, obj.mibModel.preferences.SegmTools.SAM2.linksFile);
end

linksJSON = fileread(linksFile);
linksStruct = jsondecode(linksJSON);
% get names of available SAM backbones
sam_names = {linksStruct.name};

if obj.mibModel.preferences.SegmTools.SAM.samVersion == 1
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

    defAns = {{sam_names{:}, find(ismember(sam_names, obj.mibModel.preferences.SegmTools.SAM.backbone))};
        {'cuda', 'cpu', find(ismember({'cuda', 'cpu'}, obj.mibModel.preferences.SegmTools.SAM.environment))};
        obj.mibModel.preferences.SegmTools.SAM.showProgressBar;
        obj.mibModel.preferences.SegmTools.SAM.linksFile;
        obj.mibModel.preferences.SegmTools.SAM.sam_installation_path;
        false;
        false;
        num2str(obj.mibModel.preferences.SegmTools.SAM.points_per_side);
        num2str(obj.mibModel.preferences.SegmTools.SAM.points_per_batch);
        num2str(obj.mibModel.preferences.SegmTools.SAM.pred_iou_thresh);
        num2str(obj.mibModel.preferences.SegmTools.SAM.stability_score_thresh);
        num2str(obj.mibModel.preferences.SegmTools.SAM.box_nms_thresh);
        num2str(obj.mibModel.preferences.SegmTools.SAM.crop_n_layers);
        num2str(obj.mibModel.preferences.SegmTools.SAM.crop_nms_thresh);
        num2str(obj.mibModel.preferences.SegmTools.SAM.crop_overlap_ratio);
        num2str(obj.mibModel.preferences.SegmTools.SAM.crop_n_points_downscale_factor);
        num2str(obj.mibModel.preferences.SegmTools.SAM.min_mask_region_area)}; %#ok<CCAT>

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
            if ~strcmp(obj.mibModel.preferences.SegmTools.SAM.backbone, 'vit_b (0.4Gb)')
                if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
                obj.mibModel.pythonEnv = [];
            end
            obj.mibModel.preferences.SegmTools.SAM.backbone = 'vit_b (0.4Gb)';
            obj.mibModel.preferences.SegmTools.SAM.points_per_side = 32;
            obj.mibModel.preferences.SegmTools.SAM.points_per_batch = 64;
            obj.mibModel.preferences.SegmTools.SAM.pred_iou_thresh = 0.88;
            obj.mibModel.preferences.SegmTools.SAM.stability_score_thresh = 0.95;
            obj.mibModel.preferences.SegmTools.SAM.box_nms_thresh = 0.7;
            obj.mibModel.preferences.SegmTools.SAM.crop_n_layers = 0;
            obj.mibModel.preferences.SegmTools.SAM.crop_nms_thresh = 0.7;
            obj.mibModel.preferences.SegmTools.SAM.crop_overlap_ratio = 0.3413;
            obj.mibModel.preferences.SegmTools.SAM.crop_n_points_downscale_factor = 1;
            obj.mibModel.preferences.SegmTools.SAM.min_mask_region_area = 0;
            obj.mibModel.preferences.SegmTools.SAM.showProgressBar = false;
            return
        end
    end

    if answer{6}
        try
            selpath = uigetdir(obj.mibModel.preferences.SegmTools.SAM.sam_installation_path, 'segment-anything location');
        catch err
            selpath = uigetdir([], 'segment-anything location');
        end
        if selpath == 0; return; end
        obj.mibModel.preferences.SegmTools.SAM.sam_installation_path = selpath;
    else
        obj.mibModel.preferences.SegmTools.SAM.sam_installation_path = answer{5};
    end

    if ~strcmp(obj.mibModel.preferences.SegmTools.SAM.backbone, answer{1})
        if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
        obj.mibModel.pythonEnv = [];
    end
    if ~strcmp(answer{2}, obj.mibModel.preferences.SegmTools.SAM.environment)
        if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
        obj.mibModel.pythonEnv = [];
    end

    obj.mibModel.preferences.SegmTools.SAM.backbone = answer{1};
    obj.mibModel.preferences.SegmTools.SAM.points_per_side = str2double(answer{8});
    obj.mibModel.preferences.SegmTools.SAM.points_per_batch = str2double(answer{9});
    obj.mibModel.preferences.SegmTools.SAM.pred_iou_thresh = str2double(answer{10});
    obj.mibModel.preferences.SegmTools.SAM.stability_score_thresh = str2double(answer{11});
    obj.mibModel.preferences.SegmTools.SAM.box_nms_thresh = str2double(answer{12});
    obj.mibModel.preferences.SegmTools.SAM.crop_n_layers = str2double(answer{13});
    obj.mibModel.preferences.SegmTools.SAM.crop_nms_thresh = str2double(answer{14});
    obj.mibModel.preferences.SegmTools.SAM.crop_overlap_ratio = str2double(answer{15});
    obj.mibModel.preferences.SegmTools.SAM.crop_n_points_downscale_factor = str2double(answer{16});
    obj.mibModel.preferences.SegmTools.SAM.min_mask_region_area = str2double(answer{17});
    obj.mibModel.preferences.SegmTools.SAM.environment = answer{2};
    obj.mibModel.preferences.SegmTools.SAM.showProgressBar = logical(answer{3});

    % check for the SAM-links file
    newLinksFile = fullfile(obj.mibModel.mibPath, answer{4});
    if exist(newLinksFile, 'file') == 0
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        dlgOpt.Header = sprintf('The provided file:\n%s\nwith SAM links does not exist!\n\nKeeping the previous version:\n%s', newLinksFile, linksFile);
        dlgOpt.HeaderLines = 5;
        utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, {}, {}, 'Wrong JSON file', dlgOpt);
    else
        obj.mibModel.preferences.SegmTools.SAM.linksFile = answer{4};
    end
    % validate requirements with the updated settings
    cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
    cImageDoc.segmentationSAM_requirements(1);
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
    defAns = {{sam_names{:}, find(ismember(sam_names, obj.mibModel.preferences.SegmTools.SAM2.backbone))};
        {'cuda', 'cpu', find(ismember({'cuda', 'cpu'}, obj.mibModel.preferences.SegmTools.SAM2.environment))};
        obj.mibModel.preferences.SegmTools.SAM2.showProgressBar;
        obj.mibModel.preferences.SegmTools.SAM2.linksFile;
        obj.mibModel.preferences.SegmTools.SAM2.sam_installation_path;
        false;
        false;
        num2str(obj.mibModel.preferences.SegmTools.SAM2.points_per_side);
        num2str(obj.mibModel.preferences.SegmTools.SAM2.points_per_batch);
        num2str(obj.mibModel.preferences.SegmTools.SAM2.pred_iou_thresh);
        num2str(obj.mibModel.preferences.SegmTools.SAM2.stability_score_thresh);
        num2str(obj.mibModel.preferences.SegmTools.SAM2.stability_score_offset);
        num2str(obj.mibModel.preferences.SegmTools.SAM2.crop_n_layers);
        num2str(obj.mibModel.preferences.SegmTools.SAM2.box_nms_thresh);
        num2str(obj.mibModel.preferences.SegmTools.SAM2.crop_n_points_downscale_factor);
        num2str(obj.mibModel.preferences.SegmTools.SAM2.min_mask_region_area);
        obj.mibModel.preferences.SegmTools.SAM2.use_m2m};

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
            obj.mibModel.preferences.SegmTools.SAM2.backbone = 'sam2_hiera_t (0.15Gb)';
            obj.mibModel.preferences.SegmTools.SAM2.showProgressBar = false;
            obj.mibModel.preferences.SegmTools.SAM2.points_per_side = 32;
            obj.mibModel.preferences.SegmTools.SAM2.points_per_batch = 64;
            obj.mibModel.preferences.SegmTools.SAM2.pred_iou_thresh = 0.8;
            obj.mibModel.preferences.SegmTools.SAM2.stability_score_thresh = 0.95;
            obj.mibModel.preferences.SegmTools.SAM2.stability_score_offset = 1.0;
            obj.mibModel.preferences.SegmTools.SAM2.crop_n_layers = 0;
            obj.mibModel.preferences.SegmTools.SAM2.box_nms_thresh = 0.7;
            obj.mibModel.preferences.SegmTools.SAM2.crop_n_points_downscale_factor = 1;
            obj.mibModel.preferences.SegmTools.SAM2.min_mask_region_area = 0;
            obj.mibModel.preferences.SegmTools.SAM2.use_m2m = false;
            return
        end
    end

    if answer{6}
        try
            selpath = uigetdir(obj.mibModel.preferences.SegmTools.SAM2.sam_installation_path, 'segment-anything-2 location');
        catch err
            selpath = uigetdir([], 'segment-anything-2 location');
        end
        if selpath == 0; return; end
        obj.mibModel.preferences.SegmTools.SAM2.sam_installation_path = selpath;
    else
        obj.mibModel.preferences.SegmTools.SAM2.sam_installation_path = answer{5};
    end

    if ~strcmp(obj.mibModel.preferences.SegmTools.SAM2.backbone, answer{1})
        if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
        obj.mibModel.pythonEnv = [];
    end
    if ~strcmp(answer{2}, obj.mibModel.preferences.SegmTools.SAM2.environment)
        if ~isempty(obj.mibModel.pythonEnv); terminate(pyenv); end
        obj.mibModel.pythonEnv = [];
    end

    obj.mibModel.preferences.SegmTools.SAM2.backbone = answer{1};
    obj.mibModel.preferences.SegmTools.SAM2.environment = answer{2};
    obj.mibModel.preferences.SegmTools.SAM2.showProgressBar = logical(answer{3});

    obj.mibModel.preferences.SegmTools.SAM2.points_per_side = round(str2double(answer{8}));
    obj.mibModel.preferences.SegmTools.SAM2.points_per_batch = round(str2double(answer{9}));
    obj.mibModel.preferences.SegmTools.SAM2.pred_iou_thresh = str2double(answer{10});
    obj.mibModel.preferences.SegmTools.SAM2.stability_score_thresh = str2double(answer{11});
    obj.mibModel.preferences.SegmTools.SAM2.stability_score_offset = str2double(answer{12});
    obj.mibModel.preferences.SegmTools.SAM2.crop_n_layers = round(str2double(answer{13}));
    obj.mibModel.preferences.SegmTools.SAM2.box_nms_thresh = str2double(answer{14});
    obj.mibModel.preferences.SegmTools.SAM2.crop_n_points_downscale_factor = round(str2double(answer{15}));
    obj.mibModel.preferences.SegmTools.SAM2.min_mask_region_area = round(str2double(answer{16}));
    obj.mibModel.preferences.SegmTools.SAM2.use_m2m = logical(answer{17});

    % check for the SAM-links file
    newLinksFile = fullfile(obj.mibModel.mibPath, answer{4});
    if exist(newLinksFile, 'file') == 0
        dlgOpt.MsgBoxOnly = true;
        dlgOpt.Icon = 'puffin_error';
        dlgOpt.Header = sprintf('The provided file:\n%s\nwith SAM links does not exist!\n\nKeeping the previous version:\n%s', newLinksFile, linksFile);
        dlgOpt.HeaderLines = 5;
        utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, {}, {}, 'Wrong JSON file', dlgOpt);
    else
        obj.mibModel.preferences.SegmTools.SAM2.linksFile = answer{4};
    end
    % validate requirements with the updated settings
    cImageDoc = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet};
    cImageDoc.segmentationSAM_requirements(obj.mibModel.preferences.SegmTools.SAM.samVersion);
end
end
