function unFocus(hObject)
% function unFocus(hObject)
% move focus to the main window

% Example:
% utils.unFocus(obj.view.handles.panels.segmentation.handles.addMaterial);
% Updates
% 

hObject.Enable = 'off';
drawnow;
hObject.Enable = 'on';
end
