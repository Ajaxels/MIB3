function initialize(obj)
% function initialize(obj)
% Initialize the main MibController class

arguments (Input)
    obj controllers.MibController
end

% tweaks
showSplashScreen = false;

% ---- show splash screen
if showSplashScreen
    [hSplashScreen, hSplashAxes, hLabel] = obj.showSplashScreen(sprintf('MIB %s', obj.mibVersion), sprintf('Staring MIB\n%s\nPlease wait...', obj.mibVersion));
    %hLabel.String = 'adding something else';
end

% generate the resource file for icons and images
assetsDir = fullfile(obj.mibPath, 'assets');
resourceFile  = fullfile(obj.mibPath, 'assets', 'mib_icons.res');
if ~isfile(resourceFile)
    core.MibIconCache.buildResourceFile(assetsDir, resourceFile);
    % usage example:
    % imgBrush = core.MibIconCache.get('about_16px');         % loads from the resource class on first call
    % h.brushButton.Icon = imgBrush;
end

% Initialize all external libraries and Java paths
obj.initializeLibraries();   

% get the current version of Matlab
obj.matlabVersion = obj.mibModel.matlabVersion;

%% ----------------- INIT THE MAIN VIEW -----------------
obj.view = views.MibView(obj);
obj.mibModel.mibGUI = obj.view.gui;
% --- create controller for panels and add view into them
obj.addGuiControllers();

% ---- add callbacks ----
% add callback for selection of the
obj.view.handles.ribbon.global.SelectedTabChangedFcn = @(~, ~)obj.globalTabGroup_SelectionCallback;


if obj.mibModel.preferences.System.EnableSelection
    obj.view.brushCursorShow =  true;
else
    obj.view.brushCursorShow =  false;
end

% --------- update listeners
% callback for change of properties in obj.view.handles.imageViewDocGroup, used to track selection of panels in the image view panel
obj.listeners{1} = addlistener(obj.view.handles.imageViewDocGroup, 'PropertyChanged', @obj.listener_appStateChanged);
obj.listeners{end+1} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) obj.listener_newDataset(src, evnt)); % update toolbar buttons
obj.listeners{end+1} = addlistener(obj.mibModel, 'ShowErrorDialog', @(src, evnt) obj.listener_showErrorDialog(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'ShowImage', @(src, evnt) obj.listener_showImage(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateDatasetAxes', @(src, evnt) obj.listener_updateDatasetAxes(src, evnt));
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateToolbar', @(src, evnt) obj.listener_updateToolbar(src, evnt)); % update toolbar buttons
obj.listeners{end+1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.listener_updateGuiWidgets(src, evnt)); % update GUI widgets

%obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @(src, evnt) obj.listner_ModelEvent_Callback(src, evnt));
%obj.listeners{end+1} = addlistener(obj.model, 'modelNotify', @obj.listner_ModelEvent_Callback);
%obj.listeners{end+1} = addlistener(obj.model, 'keyPressEvent', @obj.listner2_Callback);
%obj.listeners{end+1} = addlistener(obj.model, 'newFileCreated', @obj.listner2_Callback);

% Make the GUI visible
obj.view.gui.Visible = true;
drawnow;

if showSplashScreen; hSplashScreen.focus; end  % focus on the splash screen
%pause(2);

% do GUI post-initialization tasks that require GUI to be visible
obj.view.doPostInitializationTasks();

% show image
obj.showImage();

if showSplashScreen
    %hLabel.String = 'finishing'; drawnow nocallbacks;
    % close the splash screen
    delete(hSplashScreen);
end

if obj.mibModel.preferences.Tips.ShowTips == 1
    try     % on MacOs this gives an error
        obj.startController('controllers.WelcomeTips');
    catch err
        obj.mibModel.preferences.Tips.ShowTips = false;
    end
end

% % check for update
% currentDate = floor(now);
% if currentDate - obj.mibModel.preferences.System.Update.SinceLastCheck > obj.mibModel.preferences.System.Update.RecheckPeriod
%     % check for update
%     obj.mibModel.preferences.System.Update.SinceLastCheck = currentDate;
%     if isdeployed
%         if ismac
%             link = 'http://mib.helsinki.fi/web-update/mib2_mac.txt';
%         elseif isunix
%             link = 'http://mib.helsinki.fi/web-update/mib2_linux.txt';
%         else
%             link = 'http://mib.helsinki.fi/web-update/mib2_win.txt';
%         end
%     else
%         link = 'http://mib.helsinki.fi/web-update/mib2_matlab.txt';
%     end
%     try
%         urlText = urlread(link, 'Timeout', 4);
%     catch err
%         urlText = sprintf('0.305\n<html>\ntest\n</html>\n---Info---\n<html>\n<div style="font-family: arial;">\n<b>The update file has not been detected...</b>\n</html>');
%     end
% 
%     linefeedPos = strfind(urlText, sprintf('\n'));
%     availableVersion = str2double(urlText(1:linefeedPos(1)));
%     if availableVersion - obj.mibVersionNumeric > 0
%         anwser = questdlg(sprintf('A new version %f of MIB is available!\nWould you like to download/install it?\n\nYou can always do that later from Menu->Help->Check for Update', availableVersion),'New version', 'Update now', 'Later', 'Update now');
%         if strcmp(anwser, 'Update now')
%             obj.startController('mibUpdateCheckController', obj);
%         end
%     end
% end

end
