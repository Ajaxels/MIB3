function makeTabFigures(outputFolder)
% MAKETABFIGURES - Screenshots of the four plot tabs for the user page, from the real dialog.
%
% Opens the Sharpness and noise dialog on a headless synthetic model holding slice 3 of
% mib/assets/misc/sharpness_test_gold_on_carbon.tif (astigmatic, 2 nm pixels), analyses the whole
% slice and saves each tab's axes, cropped from a capture of the window. Needs mib/ and tests/ on
% the path.
%
% Example (from the MIB3 folder):
%   addpath('mib', 'tests'); makeTabFigures('docs\docs\user-interface\ribbon\image\images')

testFile = fullfile(fileparts(mfilename('fullpath')), '..', '..', 'mib', 'assets', 'misc', 'sharpness_test_gold_on_carbon.tif');
slice = imread(testFile, 3);
mibModel = mibtest.helpers.buildSyntheticModel('dims', [size(slice) 1]);
mibModel.I{1}.setData2D(slice, 'image', 1);
mibModel.I{1}.image.pixSize.x = 0.002;
mibModel.I{1}.image.pixSize.y = 0.002;
mibModel.I{1}.image.pixSize.units = 'um';
mibModel.I{1}.image.viewPort.min(1) = 0;
mibModel.I{1}.image.viewPort.max(1) = 255;

controller = controllers.ImageSharpness(mibModel);
cleanupWindow = onCleanup(@() controller.closeWindow());
controller.view.gui.Position(3:4) = [1100 760];
controller.results = [];
controller.BatchOpt.RegionSource{1} = 'Whole slice';
controller.calculate();
controller.results(end).datasetName = 'sharpness_test_gold_on_carbon.tif';   % title of the plots

handles = controller.view.handles;
tabs = {handles.ImageTab, handles.spectrumTab, handles.profileTab, handles.directionTab};
axesList = {handles.imageAxes, handles.spectrumAxes, handles.profileAxes, handles.directionAxes};
names = {'Image', 'Spectrum', 'Profile', 'Directions'};
controller.updatePlots(numel(controller.results));
% exportgraphics on these uiaxes dropped the plotted lines (R2026a), so the whole window is captured
% with exportapp and cropped to the axes
temporaryFile = [tempname '.png'];
for tabId = 1:numel(tabs)
    handles.plotTabGroup.SelectedTab = tabs{tabId};
    controller.updatePlots();
    drawnow;
    pause(0.5);     % let the web figure finish rendering before the capture
    exportapp(controller.view.gui, temporaryFile);
    windowImage = imread(temporaryFile);
    scale = size(windowImage, 2) / controller.view.gui.Position(3);
    axesPosition = getpixelposition(axesList{tabId}, true);      % [left bottom width height] in the figure
    columns = max(1, round(axesPosition(1)*scale)):min(size(windowImage, 2), round((axesPosition(1)+axesPosition(3))*scale));
    rows = max(1, round((controller.view.gui.Position(4) - axesPosition(2) - axesPosition(4))*scale)):...
        min(size(windowImage, 1), round((controller.view.gui.Position(4) - axesPosition(2))*scale));
    fileName = fullfile(outputFolder, sprintf('imageSharpnessTab%s.png', names{tabId}));
    imwrite(windowImage(rows, columns, :), fileName);
    fprintf('saved %s\n', fileName);
end
delete(temporaryFile);
end
