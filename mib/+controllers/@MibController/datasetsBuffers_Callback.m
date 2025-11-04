function datasetsBuffers_Callback(obj, hWidget, hData)
% datasetsBuffers_Callback(obj, hWidget, hData)
% callbacks for press oobj.handles.panels.datasets.handles.buffer1 buttons, selects the dataset
% stored in a buffer defined by the pressed button
%
% Handles the following widgets:
% - obj.handles.panels.datasets.handles.bufferN, where N is number 1 to 10,
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting ButtonPushedData class

arguments (Input)
    obj controllers.MibController
    hWidget matlab.ui.control.Button
    hData matlab.ui.eventdata.ButtonPushedData
end

% get index of the pressed button
buttonId = str2double(hWidget.Text);
fprintf('obj.controller.datasetsBuffers_ButtonPushedFcn -> button %d pressed\n', buttonId);
obj.mibModel.id = buttonId;
obj.plotImage();

end