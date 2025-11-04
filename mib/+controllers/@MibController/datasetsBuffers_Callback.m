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
    hData {mustBeButtonEventOrEmpty} = []
end

% get index of the pressed button
buttonId = str2double(hWidget.Text);
% generate identifier of the buffer handle
prevBufferStringId = sprintf('buffer%d', obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet));
newBufferStringId = sprintf('buffer%d', buttonId);

obj.mibModel.Sets.selectedDataset(obj.mibModel.Sets.selectedSet) = buttonId; % update index of the dataset selected in the current set
obj.mibModel.id = buttonId + (obj.mibModel.Sets.selectedSet-1)*obj.mibModel.Sets.datasetsInSet; % update the selected dataset in the global index 

% update the background color for the selected buffer
if ~strcmp(prevBufferStringId, newBufferStringId)
    obj.view.handles.panels.datasets.handles.(prevBufferStringId).BackgroundColor = obj.view.handles.panels.dirContents.handles.updateFileList.BackgroundColor;
end
obj.view.handles.panels.datasets.handles.(newBufferStringId).BackgroundColor = [0 1 0];

obj.plotImage();

fprintf('obj.controller.datasetsBuffers_ButtonPushedFcn -> button %d pressed\n', buttonId);
end

% Local function that performs the validation
function mustBeButtonEventOrEmpty(a)
    % This function allows the input 'a' to be empty OR a specific class
    if ~isempty(a) && ~isa(a, 'matlab.ui.eventdata.ButtonPushedData')
        error('Input must be a ButtonPushedData object or empty');
    end
end