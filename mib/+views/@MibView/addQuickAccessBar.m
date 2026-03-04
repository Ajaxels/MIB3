function qab = addQuickAccessBar(obj)
% function qab = addQAB(obj)
% add quick access buttons to MIB
% 
% Parameters:
%
% Return values:
% qab: structure with the generated handles

arguments (Input)
    obj views.MibView
end

import matlab.ui.internal.toolstrip.qab.QABPushButton
import matlab.ui.internal.toolstrip.impl.QABToggleButton
import matlab.ui.internal.toolstrip.Icon

iconPath = fullfile(obj.controller.mibPath, 'assets', 'icons');

%% Populate Quick Access Bar
% Add Common Controls to the QAB from right-to-left
% Possible options
% matlab.ui.internal.toolstrip.qab.QABHelpButton
% matlab.ui.internal.toolstrip.qab.QABPushButton
% matlab.ui.internal.toolstrip.qab.QABRedoButton
% matlab.ui.internal.toolstrip.qab.QABUndoButton
% matlab.ui.internal.toolstrip.impl.QABDropDownButton
% matlab.ui.internal.toolstrip.impl.QABPushButton
% matlab.ui.internal.toolstrip.impl.QABSplitButton
% matlab.ui.internal.toolstrip.impl.QABToggleButton
% matlab.ui.internal.toolstrip.impl.QABToggleSplitButton

qab.help = QABPushButton(Icon.HELP_16);

qab.help.ButtonPushedFcn = @(varargin)disp('qab.help');
qab.help.Text = 'Open MIB documentation';
qab.help.Description = 'Open MIB documentation';
obj.gui.add(qab.help);

qab.camera = QABPushButton(Icon(fullfile(iconPath, 'snapshot_16px.png')));
qab.camera.Text = 'Make a snapshot';
qab.camera.Description = 'Make a snapshot';
obj.gui.add(qab.camera);

qab.saveModel = QABPushButton(Icon.SAVE_DIRTY_16);
qab.saveModel.Text = 'Save model to a file';
qab.saveModel.Description = 'Save model to a file';
obj.gui.add(qab.saveModel);

divider = QABPushButton();
obj.gui.add(divider);

qab.blockMode = QABToggleButton();
qab.blockMode.QuickAccessIcon = Icon(fullfile(iconPath, 'blockMode_16px.png'));
qab.blockMode.Text = 'Enable the blocked mode to process only visible portion of the dataset';
qab.blockMode.Description = 'Enable the blocked mode to process only visible portion of the dataset';
obj.gui.add(qab.blockMode);

qab.roiMode = QABToggleButton();
qab.roiMode.QuickAccessIcon = Icon(fullfile(iconPath, 'roiMode_16px.png'));
qab.roiMode.Text = 'Enable the ROI mode';
qab.roiMode.Description = 'Enable the ROI mode';
obj.gui.add(qab.roiMode);

qab.target = QABToggleButton();
qab.target.QuickAccessIcon = Icon(fullfile(iconPath, 'target_16px.png'));
qab.target.Text = 'Enable the center marker';
qab.target.Description = 'Enable the center marker';
obj.gui.add(qab.target);

qab.measurements = QABPushButton(Icon(fullfile(iconPath, 'measurement_tool_16px.png')));
%qab.measurements = QABToggleButton();
%qab.measurements.QuickAccessIcon = Icon(fullfile(iconPath, 'measurement_tool_16px.png'));
qab.measurements.Text = 'Perform a quick measurement';
qab.measurements.Description = 'Perform a quick measurement';
obj.gui.add(qab.measurements);

divider = QABPushButton();
obj.gui.add(divider);

qab.xz_orientation = QABToggleButton();
qab.xz_orientation.QuickAccessIcon = Icon(fullfile(iconPath, 'xz_icon_16px.png'));
qab.xz_orientation.Text = 'Switch dataset to the XZ orientation';
qab.xz_orientation.Description = 'Switch dataset to the XZ orientation';
obj.gui.add(qab.xz_orientation);

qab.yz_orientation = QABToggleButton();
qab.yz_orientation.QuickAccessIcon = Icon(fullfile(iconPath, 'yz_icon_16px.png'));
qab.yz_orientation.Text = 'Switch dataset to the YZ orientation';
qab.yz_orientation.Description = 'Switch dataset to the YZ orientation';
obj.gui.add(qab.yz_orientation);

qab.yx_orientation = QABToggleButton();
qab.yx_orientation.QuickAccessIcon = Icon(fullfile(iconPath, 'yx_icon_16px.png'));
qab.yx_orientation.Text = 'Switch dataset to the YX orientation';
qab.yx_orientation.Description = 'Switch dataset to the YX orientation';
qab.yx_orientation.Value = true; % press the button
obj.gui.add(qab.yx_orientation);

divider = QABPushButton();
obj.gui.add(divider);

qab.fastpan = QABToggleButton();
qab.fastpan.QuickAccessIcon = Icon(fullfile(iconPath, 'panFast_16px.png'));
qab.fastpan.Text = 'Enable the fast-panning mode for quicker image navigation';
qab.fastpan.Description = 'Enable the fast-panning mode for quicker image navigation';
obj.gui.add(qab.fastpan);

qab.zoomOut = QABPushButton(Icon(fullfile(iconPath, 'zoomOut_16px.png')));
qab.zoomOut.Text = 'Zoom out';
qab.zoomOut.Description = 'Zoom out';
obj.gui.add(qab.zoomOut);

qab.zoomFit = QABPushButton(Icon(fullfile(iconPath, 'zoomFit_16px.png')));
qab.zoomFit.Text = 'Fit the dataset into the viewing window';
qab.zoomFit.Description = 'Fit the dataset into the viewing window';
obj.gui.add(qab.zoomFit);

qab.zoom100 = QABPushButton(Icon(fullfile(iconPath, 'zoom100_16px.png')));
qab.zoom100.Text = 'Scale the image to 100% magnification';
qab.zoom100.Description = 'Scale the image to 100% magnification';
obj.gui.add(qab.zoom100);

qab.zoomIn = QABPushButton(Icon(fullfile(iconPath, 'zoomIn_16px.png')));
qab.zoomIn.Text = 'Zoom in';
qab.zoomIn.Description = 'Zoom in';
obj.gui.add(qab.zoomIn);

divider = QABPushButton();
obj.gui.add(divider);

qab.redo = QABPushButton(Icon.REDO_16);
qab.redo.Text = 'Redo the undo operation';
qab.redo.Description = 'Redo the undo operation';
obj.gui.add(qab.redo);

qab.undo = QABPushButton(Icon.UNDO_16);
qab.undo.Text = 'Undo the last operation';
qab.undo.Description = 'Undo the last operation';
obj.gui.add(qab.undo);

obj.handles.qab = qab;

% add handle tags to the status bar
if obj.mibModel.preferences.System.DeveloperMode
    utils.overrideDescriptions(qab, true, 'obj.cQuickAccessBar.view.handles');
end

end