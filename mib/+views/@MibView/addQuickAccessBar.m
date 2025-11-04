function addQuickAccessBar(obj)
% function addQAB(obj)
% add quick access buttons to MIB
arguments (Input)
    obj views.MibView
end

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

obj.handles.qab.help = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon.HELP_16);
obj.handles.qab.help.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.help');
obj.handles.qab.help.Text = 'Open MIB documentation';
obj.gui.add(obj.handles.qab.help);

obj.handles.qab.camera = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/snapshot_16.png')));
obj.handles.qab.camera.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.camera');
obj.handles.qab.camera.Text = 'Make a snapshot';
obj.gui.add(obj.handles.qab.camera);

obj.handles.qab.saveModel = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon.SAVE_DIRTY_16);
obj.handles.qab.saveModel.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.saveModel');
obj.handles.qab.saveModel.Text = 'Save model to a file';
obj.gui.add(obj.handles.qab.saveModel);

divider = matlab.ui.internal.toolstrip.qab.QABPushButton();
obj.gui.add(divider);

obj.handles.qab.blockMode = matlab.ui.internal.toolstrip.impl.QABToggleButton();
obj.handles.qab.blockMode.QuickAccessIcon = matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/blockMode_16px.png'));
obj.handles.qab.blockMode.ValueChangedFcn = @(varargin)disp('obj.handles.qab.blockMode');
obj.handles.qab.blockMode.Text = 'Enable the blocked mode to process only visible portion of the dataset';
obj.gui.add(obj.handles.qab.blockMode);

obj.handles.qab.roiMode = matlab.ui.internal.toolstrip.impl.QABToggleButton();
obj.handles.qab.roiMode.QuickAccessIcon = matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/roiMode_16px.png'));
obj.handles.qab.roiMode.ValueChangedFcn = @(varargin)disp('obj.handles.qab.roiMode');
obj.handles.qab.roiMode.Text = 'Enable the ROI mode';
obj.gui.add(obj.handles.qab.roiMode);

obj.handles.qab.target = matlab.ui.internal.toolstrip.impl.QABToggleButton();
obj.handles.qab.target.QuickAccessIcon = matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/target_16px.png'));
obj.handles.qab.target.ValueChangedFcn = @(varargin)disp('obj.handles.qab.target');
obj.handles.qab.target.Text = 'Enable the center marker';
obj.gui.add(obj.handles.qab.target);

obj.handles.qab.measurements = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/measurement_tool_16px.png')));
obj.handles.qab.measurements.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.measurements');
obj.handles.qab.measurements.Text = 'Perform a quick measurement';
obj.gui.add(obj.handles.qab.measurements);

divider = matlab.ui.internal.toolstrip.qab.QABPushButton();
obj.gui.add(divider);

obj.handles.qab.xz_orientation = matlab.ui.internal.toolstrip.impl.QABToggleButton();
obj.handles.qab.xz_orientation.QuickAccessIcon = matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/xz_icon_16px.png'));
obj.handles.qab.xz_orientation.ValueChangedFcn = @(varargin)disp('obj.handles.qab.xz_orientation');
obj.handles.qab.xz_orientation.Text = 'Switch dataset to the XZ orientation';
obj.gui.add(obj.handles.qab.xz_orientation);

obj.handles.qab.yz_orientation = matlab.ui.internal.toolstrip.impl.QABToggleButton();
obj.handles.qab.yz_orientation.QuickAccessIcon = matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/yz_icon_16px.png'));
obj.handles.qab.yz_orientation.ValueChangedFcn = @(varargin)disp('obj.handles.qab.yz_orientation');
obj.handles.qab.yz_orientation.Text = 'Switch dataset to the YZ orientation';
obj.gui.add(obj.handles.qab.yz_orientation);

obj.handles.qab.yx_orientation = matlab.ui.internal.toolstrip.impl.QABToggleButton();
obj.handles.qab.yx_orientation.QuickAccessIcon = matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/yx_icon_16px.png'));
obj.handles.qab.yx_orientation.ValueChangedFcn = @(varargin)disp('obj.handles.qab.yx_orientation');
obj.handles.qab.yx_orientation.Text = 'Switch dataset to the YX orientation';
obj.gui.add(obj.handles.qab.yx_orientation);

divider = matlab.ui.internal.toolstrip.qab.QABPushButton();
obj.gui.add(divider);

obj.handles.qab.fastpan = matlab.ui.internal.toolstrip.impl.QABToggleButton();
%obj.handles.qab.fastpan.QuickAccessIcon = matlab.ui.internal.toolstrip.Icon.PAN_16;
obj.handles.qab.fastpan.QuickAccessIcon = matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/panFast_16px.png'));
obj.handles.qab.fastpan.ValueChangedFcn = @(varargin)disp('obj.handles.qab.fastpan');
obj.handles.qab.fastpan.Text = 'Enable the fast-panning mode for quicker image navigation';
obj.gui.add(obj.handles.qab.fastpan);

obj.handles.qab.zoomOut = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/zoomOut_16px.png')));
obj.handles.qab.zoomOut.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.zoomOut');
obj.handles.qab.zoomOut.Text = 'Zoom out operation';
obj.gui.add(obj.handles.qab.zoomOut);

obj.handles.qab.zoomFit = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/zoomFit_16px.png')));
obj.handles.qab.zoomFit.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.zoomFit');
obj.handles.qab.zoomFit.Text = 'Fit the dataset into the viewing window';
obj.gui.add(obj.handles.qab.zoomFit);

obj.handles.qab.zoom100 = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/zoom100_16px.png')));
obj.handles.qab.zoom100.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.zoom100');
obj.handles.qab.zoom100.Text = 'Scale the image to 100% magnification';
obj.gui.add(obj.handles.qab.zoom100);

obj.handles.qab.zoomIn = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon(fullfile(obj.controller.mibPath, 'assets/icons/zoomIn_16px.png')));
obj.handles.qab.zoomIn.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.zoomIn');
obj.handles.qab.zoomIn.Text = 'Zoom in operation';
obj.gui.add(obj.handles.qab.zoomIn);

divider = matlab.ui.internal.toolstrip.qab.QABPushButton();
obj.gui.add(divider);

obj.handles.qab.redo = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon.REDO_16);
obj.handles.qab.redo.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.redo');
obj.handles.qab.redo.Text = 'Redo the undo operation';
obj.gui.add(obj.handles.qab.redo);

obj.handles.qab.undo = matlab.ui.internal.toolstrip.qab.QABPushButton(matlab.ui.internal.toolstrip.Icon.UNDO_16);
obj.handles.qab.undo.ButtonPushedFcn = @(varargin)disp('obj.handles.qab.undo');
obj.handles.qab.undo.Text = 'Undo the last operation';
obj.gui.add(obj.handles.qab.undo);

end