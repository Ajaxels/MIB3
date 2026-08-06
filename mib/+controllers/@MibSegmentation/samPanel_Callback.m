function samPanel_Callback(obj, hWidget, hData)
% SAMPANEL_CALLBACK - Callback for Segment Anything Model (SAM) tool widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.samPanel_Callback(hWidget, hData)
%
% Handles callbacks for Segment Anything Model segmentation tool widgets in the Segmentation panel.
% Supports SAM version selection, segmentation method, prompt management, and result layer configuration.
%
% Input Arguments:
%   - **hWidget** - [matlab.ui.control.Button | matlab.ui.control.CheckBox | matlab.ui.control.DropDown] pressed widget; operation identified via ``hWidget.Tag``:
%
%     - ``'samMethod'`` - select SAM usage method (interactive, automatic, landmark)
%     - ``'samVersion'`` - select SAM version (SAM 1 or SAM 2)
%     - ``'samDataset'`` - select dataset type to apply segmentation
%     - ``'samDestination'`` - select destination layer for segmentation results
%     - ``'samMode'`` - set segmentation mode (replace, add, or subtract)
%     - ``'samSettings'`` - open SAM configuration dialog
%     - ``'samList'`` - show list of annotation points for landmark mode
%     - ``'samClear'`` - clear all annotation points/prompts
%     - ``'samSegment'`` - execute SAM segmentation
%
%   - **hData** - [matlab.ui.eventdata.ButtonPushedData | matlab.ui.eventdata.ValueChangedData] event data from widget
%
% Output Arguments:
%   None
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
    case 'samVersion' % update SAM version to use 
        % Note: preferences.SegmTools.SAM.samVersion -> string with the version
        % the parameters for each specific version are in  preferences.SegmTools.SAM(N)., e.g. preferences.SegmTools.SAM2
        obj.mibModel.preferences.SegmTools.SAM.samVersion = hWidget.Value;
        % force to reset python during next usage, to minimize GPU memory consumption
        if ~isempty(obj.mibModel.pythonEnv); utils.terminatePythonEnv(); end
        obj.mibModel.pythonEnv = [];
    case 'samDataset' % select type of dataset to apply SAM
        % no action needed
    case 'samDestination' % destination layer for SAM results
        % no action needed
    case 'samMode' % SAM mode, add/replace/subtract
        % no action needed
    case 'samSettings' % open SAM settings dialog
        % update SAM settings
        obj.updateSamSettings();
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
            header = sprintf('To use segment-anything in the automatic mode the model should be able to keep 65535 or more materials!\n\nCreate a new model or change the type of the current model from\nMenu->Models->Convert type');
            dlgOpt.HeaderLines = 4;
            utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), header, {}, {}, 'Wrong model type', dlgOpt);
            return;
        end

        switch obj.mibModel.preferences.SegmTools.SAM.samVersion
            case 'SAM1'
                cImageDoc.segmentationSAM();
            case 'SAM2'
                cImageDoc.segmentationSAM2();
        end
end

end
