function saveTrainingPlot(src, evnt, trainingProgressStruct, outputFilename)
% SAVETRAININGPLOT - Save the custom training progress plot to an image file.
%
% Syntax:
%   .. code-block:: matlab
%
%      saveTrainingPlot(src, evnt, trainingProgressStruct, outputFilename)
%
% Input Arguments:
%   - **src** - source object that triggered the callback (e.g. menu item)
%   - **evnt** - event data (unused; pass ``[]`` when calling manually)
%   - **trainingProgressStruct** - ``mibDeepTrainingProgressStruct`` with fields:
%
%     - ``.UIFigure`` - handle to the training progress ``uifigure``
%     - ``.NetworkFilename`` - [char] path to the network file (used to suggest a save name)
%
%   - **outputFilename** *(optional)* - [char] full output path; when empty or
%     omitted a file-save dialog is presented
%

if nargin < 4; outputFilename = []; end

% grab the figure as a screenshot
screenSize = get(0, 'ScreenSize');
robot = java.awt.Robot();
pos = trainingProgressStruct.UIFigure.Position; % [left top width height]
rect = java.awt.Rectangle(pos(1), screenSize(4) - (pos(2)+pos(4)), pos(3), pos(4));
cap = robot.createScreenCapture(rect);

% Convert to an RGB image
rgb = typecast(cap.getRGB(0,0,cap.getWidth, cap.getHeight, [] ,0, cap.getWidth),'uint8');
imgData = zeros(cap.getHeight, cap.getWidth, 3, 'uint8');
imgData(:,:,1) = reshape(rgb(3:4:end), cap.getWidth, [])';
imgData(:,:,2) = reshape(rgb(2:4:end), cap.getWidth, [])';
imgData(:,:,3) = reshape(rgb(1:4:end), cap.getWidth, [])';
%imtool(imgData);

if isempty(outputFilename)
    formatsList = {'*.png', 'Portable Network Graphics (*.png)';
        '*.jpg', 'Joint Photographic Experts Group (*.jpg)';
        '*.tif', 'Tagged Image File Format (*.tif)'};
    
    [pathOut, fnOut] = fileparts(trainingProgressStruct.NetworkFilename);
    [fnOut, pathOut, indx] = uiputfile(formatsList, 'Select format and destination', ...
        fullfile(pathOut, ['Training_' fnOut]));
    if fnOut == 0; return; end
    outputFilename = fullfile(pathOut, fnOut);
end

imwrite(imgData, outputFilename);
fprintf('DeepMIB training snapshot has been exported to:\n%s\n', outputFilename);
end
