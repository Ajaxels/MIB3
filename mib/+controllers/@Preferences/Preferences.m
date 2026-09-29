classdef Preferences < handle
% PREFERENCES - Controller for the preferences dialog - displays MIB3 settings.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.startController('Preferences');
    
    properties
        mibController
        % a handle to mibController class
        mibModel
        % handles to mibModel
        view
        % handle to the view / mibPreferencesAppGUI
        listener
        % a cell array with handles to listeners
        shownPanelTag
        % a tag of the shown panel
        oldPreferences
        % stored old preferences
        preferences
        % local copy of MIB preferences
        duplicateEntries  
        % array with duplicate key shortcut entries
        renderedPanels     % indices of panels that are already rendered, for faster change upon press on new tree node
        javaAppliedPath
        % Java folder that MATLAB / MATLAB Runtime is already set to; Apply connects the
        % ExternalDirs.JavaInstallationPath only when it differs from this one
    end
    
    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
    end
    
    methods (Static)
        function viewListner_Callback(obj, src, evnt)
            switch evnt.EventName
                case {'updateGuiWidgets'}
                    obj.updateWidgets();
            end
        end

        function openInSystemBrowser(url)
            % OPENINSYSTEMBROWSER - Open a URL in the browser, ``#section`` intact.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      controllers.Preferences.openInSystemBrowser(url)
            %
            % **Why not simply web(url, '-browser').** A ``file://`` URL carrying
            % a ``#section`` cannot be opened through the Windows file
            % association: the shell resolves the URL to a path, opens the file
            % and throws the fragment away. Measured with a probe page that
            % printed ``location.hash`` - both ``start "url"`` and
            % ``rundll32 url.dll,FileProtocolHandler`` reported no fragment,
            % which is why the Help button always landed at the top of the page.
            %
            % Naming the browser executable and passing the URL as its *argument*
            % keeps the fragment, because the browser parses the URL rather than
            % the shell. Still launched through ``start`` so this returns at once;
            % calling the executable directly would block MATLAB until the browser
            % exits, whenever no instance is already running.
            %
            % Input Arguments:
            %   - **url** - [char] fully formed URL, with its fragment if any

            if ispc
                browserPath = controllers.Preferences.defaultBrowserExecutable();
                if ~isempty(browserPath)
                    command = sprintf('start "" "%s" "%s"', browserPath, url);   % "" is the window title
                else
                    command = sprintf('start "" "%s"', url);    % no fragment, but the page opens
                end
            elseif ismac
                command = sprintf('open "%s"', url);
            else
                command = sprintf('xdg-open "%s"', url);
            end

            failed = system(command);
            if failed
                % Sandboxed shell, or no handler registered. The section jump is
                % likely lost, but the page itself is better than nothing.
                web(url, '-browser');
            end
        end

        function browserPath = defaultBrowserExecutable()
            % DEFAULTBROWSEREXECUTABLE - Path of the default browser, Windows only.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      browserPath = controllers.Preferences.defaultBrowserExecutable()
            %
            % Reads the user's http handler rather than assuming a browser, so
            % this follows whatever they actually set as default.
            %
            % Output Arguments:
            %   - **browserPath** - [char] full path of the executable, or ``''``
            %     when it cannot be determined; callers must cope with ``''``

            browserPath = '';
            if ~ispc; return; end

            [failed, registryOutput] = system(['reg query "HKEY_CURRENT_USER\Software\Microsoft\' ...
                'Windows\Shell\Associations\UrlAssociations\http\UserChoice" /v ProgId']);
            if failed; return; end
            progId = regexp(registryOutput, 'ProgId\s+REG_SZ\s+(\S+)', 'tokens', 'once');
            if isempty(progId); return; end

            [failed, registryOutput] = system(sprintf( ...
                'reg query "HKEY_CLASSES_ROOT\\%s\\shell\\open\\command" /ve', progId{1}));
            if failed; return; end

            % The command reads like: "C:\...\chrome.exe" --single-argument %1
            executable = regexp(registryOutput, '"([^"]+\.exe)"', 'tokens', 'once');
            if isempty(executable) || ~isfile(executable{1}); return; end
            browserPath = executable{1};
        end

        function allocateLabelsLayer(dataset)
            % ALLOCATELABELSLAYER - allocate the 63-material labels layer of a dataset that carries an empty one.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       controllers.Preferences.allocateLabelsLayer(dataset)
            %
            % Called from the Apply and OK handlers when the user switches
            % ``System.EnableSelection`` back on. A dataset opened while the
            % preference was off carries an empty ``labels`` container - see
            % ``core.MibDataset.initialize``, which skips the allocation to keep a
            % browse-only dataset down to the cost of the image alone - so the layer
            % has to be built from the dataset dimensions here.
            %
            % ``initialize`` is used rather than a bare ``dataset.labels.data``
            % assignment because it also sets ``exists`` and the
            % height/width/depth/time/dataClass bookkeeping that
            % ``core.MibLabels63.setData63`` and ``core.MibImage.clearLayer`` clip
            % their coordinates against. Assigning ``data`` alone leaves those at the
            % class defaults, which silently truncates every later write to the layer.
            %
            % Input Arguments:
            %   - **dataset** - [core.MibDataset] dataset whose labels layer to allocate
            %

            labelsDims = [dataset.dim_yxzct(1), dataset.dim_yxzct(2), ...
                          dataset.dim_yxzct(3), 1, dataset.dim_yxzct(5)];
            labelsMeta = core.MibImage.initializeImgInfo( ...
                'Filename',  dataset.labels.filename, ...
                'pixSize',   dataset.image.pixSize, ...
                'Height',    labelsDims(1), ...
                'Width',     labelsDims(2), ...
                'Depth',     labelsDims(3), ...
                'Time',      labelsDims(5), ...
                'Colors',    1, ...
                'SliceSize', dataset.image.sliceSize);
            dataset.labels.initialize(zeros(labelsDims, 'uint8'), labelsMeta);
        end

        function releaseSegmentationLayers(dataset)
            % RELEASESEGMENTATIONLAYERS - drop the model, mask and selection layers of a dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       controllers.Preferences.releaseSegmentationLayers(dataset)
            %
            % Called from the Apply and OK handlers when the user switches
            % ``System.EnableSelection`` off, having confirmed the warning that says
            % the Model and Mask layers will be deleted. The dataset is left in the
            % state ``core.MibDataset.initialize`` produces for a browse-only open, so
            % the re-enable path (``allocateLabelsLayer``) can rebuild from it.
            %
            % The labels handle is **replaced** rather than emptied in place, which is
            % what actually deletes a 255+ material model: emptying the existing
            % ``core.MibLabels`` would leave ``maxMaterials`` at 255, and re-enabling
            % then takes the selection branch, which cannot rebuild a model layer.
            % ``createModel`` and ``convertModel`` swap these handles the same way.
            %
            % Input Arguments:
            %   - **dataset** - [core.MibDataset] dataset whose segmentation layers to drop
            %

            labelsMeta = core.MibImage.initializeImgInfo( ...
                'pixSize', dataset.image.pixSize, ...
                'Height',  dataset.image.height, ...
                'Width',   dataset.image.width,  ...
                'Depth',   dataset.image.depth,  ...
                'Time',    dataset.image.time,   ...
                'Colors',  1);

            dataset.labels    = core.MibLabels63([], labelsMeta);
            dataset.mask      = core.MibLabels([], labelsMeta);
            dataset.selection = core.MibLabels([], labelsMeta);

            % without these the panels keep reporting a model and a mask that no
            % longer hold any data, and the materials list keeps its old entries
            dataset.modelExist = false;
            dataset.maskExist  = false;

            % the materials went with the model, so the indices into them must go too
            dataset.selectedMaterial      = 1;
            dataset.selectedAddToMaterial = 1;
            dataset.lastSegmSelection     = [2 1];
        end

    end
    
    methods
        function obj = Preferences(mibModel, varargin)
            % PREFERENCES - Constructor - create a Preferences controller and open its GUI window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = Preferences(mibModel, mibController)
            %
            % Creates a Preferences controller instance, initializes the AppDesigner view,
            % loads preferences from the model, positions the window in the center of the
            % main MIB window, updates all GUI widgets, and registers a listener for model
            % updates. The preferences dialog allows users to configure MIB3 settings across
            % multiple panels: User Interface, Colors and Styles, Backup and Undo, External
            % Directories, Keyboard Shortcuts, and Segmentation Tools.
            %
            % Input Arguments:
            %   - **mibModel** - handle to the application MibModel instance
            %   - **varargin{1}** - handle to the parent MibController
            %
            % Output Arguments:
            %   - **obj** - handle to the created Preferences controller instance
            %
            % **Example** - open the preferences dialog:
            %
            %   .. code-block:: matlab
            %
            %      obj = Preferences(mibModel, mibController);
            %
            obj.mibModel = mibModel;    % assign model
            obj.mibController = varargin{1};    % get handle to controller
            
            guiName = 'views.PreferencesGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme
            % the color tables paint their value cells with a uistyle, which a theme switch does not remap
            obj.view.gui.ThemeChangedFcn = @(src, evnt) preferencesThemeChanged(obj, src);

            % init the widgets
            obj.shownPanelTag = 'UserInterfacePanel';
            obj.preferences = mibModel.preferences;
            obj.oldPreferences = mibModel.preferences;
            
            % NOTE: EnableSelection is shown as stored in the preferences and is
            % deliberately NOT re-read from the currently shown dataset. The
            % per-dataset enableSelection flag legitimately differs from the
            % global preference: BigData opens browse-only (forced false until a
            % model is created), createModel/loadModel force it true, and the
            % startup placeholder datasets always keep the layer. Copying any of
            % those into obj.preferences made simply opening this dialog and
            % pressing OK overwrite (and save) the user's global setting.
            % The chosen value is still applied to the active dataset on OK.

            % move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'center', 'center');
            
            % resize all elements of the GUI
            % mibRescaleWidgets(obj.view.gui); % this function is not yet
            % compatible with appdesigner
            
            % update font and size
            % you may need to replace "obj.view.handles.text1" with tag of any text field of your own GUI
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.UserInterfacePanel.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.UserInterfacePanel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.duplicateEntries = [];

            % Java row of External directories (MATLAB R2026b and newer come without
            % Java). The field shows the stored folder, or the Java MATLAB actually
            % uses when none is stored; both buttons have no callback in the mlapp
            if ~isfield(obj.preferences.ExternalDirs, 'JavaInstallationPath') || ...
                    isempty(obj.preferences.ExternalDirs.JavaInstallationPath)
                obj.preferences.ExternalDirs.JavaInstallationPath = utils.JavaSetup.configuredHome();
            end
            obj.javaAppliedPath = char(obj.preferences.ExternalDirs.JavaInstallationPath);
            obj.view.handles.JavaFindBtn.ButtonPushedFcn = @(~, ~) obj.JavaFindBtnPushed();
            obj.view.handles.JavaConfigureBtn.ButtonPushedFcn = @(~, ~) obj.JavaConfigureBtnPushed();

            obj.updateWidgets();
           
            % show the gui
            obj.view.gui.Visible = 'on';    % turn on the window 
            
            % add listener to obj.mibModel and call controller function as a callback
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.viewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
        end
        
        function closeWindow(obj)
            % CLOSEWINDOW - closing Preferences window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.closeWindow()
            %
            % **Example** - close the preferences window:
            %
            %   .. code-block:: matlab
            %
            %      obj.closeWindow();
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end
            
            % delete listeners, otherwise they stay after deleting of the
            % controller
            for i=1:numel(obj.listener)
                delete(obj.listener{i});
            end
            
            notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
        end
        
        function updateWidgets(obj, panelId)
            % UPDATEWIDGETS - update widgets of this window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateWidgets()
            %       obj.updateWidgets(panelId)
            %
            % Input Arguments:
            %   - **panelId** *(optional)* - [char] tag of panel to update; when missing, all panels are updated

            panelsList = {'UserInterfacePanel', 'ColorsPanel', 'BackupAndUndoPanel', ...
                'ExternalDirectoriesPanel', 'KeyboardShortcutsPanel', 'SegmentationToolsPanel', ...
                'InputOutputPanel'};

            if nargin < 2
                panelId = 'All';
                obj.renderedPanels = zeros([numel(panelsList) 1]);     % indices of the rendered panels
            end

            handles = obj.view.handles;

            % % ---------  UserInterfacePanel ------------------
            if strcmp(panelId, 'All') || strcmp(panelId, 'UserInterfacePanel')
                if obj.renderedPanels(1) == 1; return; end  % already rendered
                systemPrefs = obj.preferences.System;
                guiScalingPrefs = obj.preferences.System.GUI;

                if strcmp(systemPrefs.MouseWheel, 'zoom')   % zoom or scroll
                    handles.MouseWheelActionDropDown.Value = 'Zoom In/Out';
                else
                    handles.MouseWheelActionDropDown.Value = 'Change slices/frames';
                end
                if strcmp(systemPrefs.LeftMouseButton, 'pan')   % pan or select
                    handles.LeftMouseActionDropDown.Value = 'Pan image';
                else
                    handles.LeftMouseActionDropDown.Value = 'Selection/drawing';
                end
                handles.ImageResizeMethodDropDown.Value = systemPrefs.ImageResizeMethod;

                if systemPrefs.AltWithScrollWheel
                    handles.AltWithScrollWheel.Value = 'Scroll time points';
                else
                    handles.AltWithScrollWheel.Value = 'Return to the slice';
                end

                % show the stored global preference, not activeDataset.enableSelection:
                % the per-dataset flag is forced false for BigData, true for the
                % startup placeholders and by createModel/loadModel, and any of
                % those would be written back to the preferences on OK
                if systemPrefs.EnableSelection
                    handles.EnableSelectionDropDown.Value = 'yes';
                else
                    handles.EnableSelectionDropDown.Value = 'no';
                end

                handles.RecentDirsNumber.Value = systemPrefs.Dirs.RecentDirsNumber;
                handles.RenderingEngine.Value = systemPrefs.RenderingEngine;

                handles.CurrentFontLabel.Text = ...
                    sprintf('Current font: [ %s, %d ]', systemPrefs.Font.FontName, systemPrefs.Font.FontSize);
                handles.FontSizeEditField.Value = systemPrefs.Font.FontSize;
                handles.FontSizeDireContentsEditField.Value = systemPrefs.FontSizeDirView;

                handles.RecheckPeriod.Value = systemPrefs.Update.RecheckPeriod;
                handles.CpuParallelLimit.Limits = [1 obj.mibModel.cpuParallelLimitMax];
                % clamp: systemPrefs is a local copy that may predate the lazy
                % clamp applied inside get.cpuParallelLimitMax
                handles.CpuParallelLimit.Value = min([systemPrefs.cpuParallelLimit, obj.mibModel.cpuParallelLimitMax]);

                handles.SystemScalingEditField.Value = guiScalingPrefs.systemscaling;
                handles.mibScalingFactorEditField.Value = guiScalingPrefs.scaling;
                handles.uibuttongroup.Value = guiScalingPrefs.uibuttongroup;
                handles.uipanel.Value = guiScalingPrefs.uipanel;
                handles.uitab.Value = guiScalingPrefs.uitab;
                handles.uitabgroup.Value = guiScalingPrefs.uitabgroup;
                handles.axes.Value = guiScalingPrefs.axes;
                handles.uitable.Value = guiScalingPrefs.uitable;
                handles.uicontrol.Value = guiScalingPrefs.uicontrol;
                obj.renderedPanels(1) = 1;
            end

            % % ---------  ColorsPanel ------------------
            if strcmp(panelId, 'All') || strcmp(panelId, 'ColorsPanel')
                if obj.renderedPanels(2) == 1; return; end  % already rendered
                colorPrefs = obj.preferences.Colors;
                contourStyles = obj.preferences.Styles.Contour;
                activeDataset = obj.mibModel.I{obj.mibModel.id};

                setColorButton(handles.SelectionColorButton, colorPrefs.SelectionColor);
                setColorButton(handles.MaskColorButton, colorPrefs.MaskColor);
                setColorButton(handles.AnnotationsColorButton, obj.preferences.SegmTools.Annotations.Color);

                % The other widgets of this panel get their callback in App
                % Designer; this one is wired here because the checkbox was added
                % to the .mlapp without one. Assigning it replaces rather than
                % adds, so wiring it in the designer later cannot double-fire.
                handles.cursorMaterialColor.ValueChangedFcn = @(~, event) obj.ColorPanelCallbacks(event);
                % isfield: a preferences file written by the same version before this
                % setting existed has no such field (see MibModel.initializePreferences),
                % fall back to the default of generatePreferences, which is on
                handles.cursorMaterialColor.Value = ~isfield(colorPrefs, 'CursorMaterialColor') || colorPrefs.CursorMaterialColor;
                handles.cursorMaterialColor.Tooltip = sprintf(['Draw the brush cursor in the color of the material ' ...
                    'the stroke is added to.\nWhen unchecked, the cursor is dark green regardless of the material.']);

                % updating options for color palettes
                if activeDataset.labels.maxMaterials < 256
                    materialsNumber = numel(activeDataset.labels.materialNames);
                else
                    materialsNumber = activeDataset.labels.maxMaterials;
                end

                if materialsNumber > 12
                    paletteList = {'Distinct colors, 20 colors', 'Matlab Jet','Matlab Gray','Matlab Bone','Matlab HSV', 'Matlab Cool', 'Matlab Hot','Random Colors'};
                    handles.PaletteGeneratorDropDown.Items = paletteList;
                elseif materialsNumber > 11
                    paletteList = {'Distinct colors, 20 colors', 'Qualitative (Monte Carlo->Half Baked), 3-12 colors','Matlab Jet','Matlab Gray','Matlab Bone','Matlab HSV', 'Matlab Cool', 'Matlab Hot','Random Colors'};
                    handles.PaletteGeneratorDropDown.Items = paletteList;
                elseif materialsNumber > 9
                    paletteList = {'Distinct colors, 20 colors', 'Qualitative (Monte Carlo->Half Baked), 3-12 colors','Diverging (Deep Bronze->Deep Teal), 3-11 colors','Diverging (Ripe Plum->Kaitoke Green), 3-11 colors',...
                        'Diverging (Bordeaux->Green Vogue), 3-11 colors, 3-11 colors', 'Diverging (Carmine->Bay of Many), 3-11 colors',...
                        'Matlab Jet','Matlab Gray','Matlab Bone','Matlab HSV', 'Matlab Cool', 'Matlab Hot','Random Colors'};
                    handles.PaletteGeneratorDropDown.Items = paletteList;
                elseif materialsNumber > 6
                    paletteList = {'Distinct colors, 20 colors', 'Qualitative (Monte Carlo->Half Baked), 3-12 colors','Diverging (Deep Bronze->Deep Teal), 3-11 colors','Diverging (Ripe Plum->Kaitoke Green), 3-11 colors',...
                        'Diverging (Bordeaux->Green Vogue), 3-11 colors, 3-11 colors', 'Diverging (Carmine->Bay of Many), 3-11 colors','Sequential (Kaitoke Green), 3-9 colors',...
                        'Sequential (Catalina Blue), 3-9 colors', 'Sequential (Maroon), 3-9 colors', 'Sequential (Astronaut Blue), 3-9 colors', 'Sequential (Downriver), 3-9 colors',...
                        'Matlab Jet','Matlab Gray','Matlab Bone','Matlab HSV', 'Matlab Cool', 'Matlab Hot','Random Colors'};
                    handles.PaletteGeneratorDropDown.Items = paletteList;
                else
                    paletteList = {'Default, 6 colors', 'Distinct colors, 20 colors', 'Qualitative (Monte Carlo->Half Baked), 3-12 colors','Diverging (Deep Bronze->Deep Teal), 3-11 colors','Diverging (Ripe Plum->Kaitoke Green), 3-11 colors',...
                        'Diverging (Bordeaux->Green Vogue), 3-11 colors', 'Diverging (Carmine->Bay of Many), 3-11 colors','Sequential (Kaitoke Green), 3-9 colors',...
                        'Sequential (Catalina Blue), 3-9 colors', 'Sequential (Maroon), 3-9 colors', 'Sequential (Astronaut Blue), 3-9 colors', 'Sequential (Downriver), 3-9 colors',...
                        'Matlab Jet','Matlab Gray','Matlab Bone','Matlab HSV', 'Matlab Cool', 'Matlab Hot', 'Random Colors'};
                    handles.PaletteGeneratorDropDown.Items = paletteList;
                end
                obj.updateColorsTables('ModelsColorsTable');  % redraw the color table
                obj.updateColorsTables('LUTColorsTable');  % redraw LUT color table

                % Contours and mask styles
                handles.ContourThicknessRendering.Value = contourStyles.ThicknessRendering;
                handles.ContourThicknessModels.Value = contourStyles.ThicknessModels;
                handles.ContourThicknessMasks.Value = contourStyles.ThicknessMasks;
                handles.ContourThicknessMasksMethod.Value = contourStyles.ThicknessMethodMasks;
                handles.LabelsShowAsContours.Value = obj.preferences.Styles.Labels.ShowAsContours;
                handles.MaskShowAsContours.Value = obj.preferences.Styles.Masks.ShowAsContours;
                obj.renderedPanels(2) = 1;
            end

            % % -------------- BackupAndUndoPanel ----------------
            if strcmp(panelId, 'All') || strcmp(panelId, 'BackupAndUndoPanel')
                if obj.renderedPanels(3) == 1; return; end  % already rendered
                undoPrefs = obj.preferences.Undo;

                if undoPrefs.Enable
                    handles.EnableUndo.Value = true;
                    handles.maxUndoHistory.Enable = 'on';
                    handles.max3dUndoHistory.Enable = 'on';
                else
                    handles.EnableUndo.Value = false;
                    handles.maxUndoHistory.Enable = 'off';
                    handles.max3dUndoHistory.Enable = 'off';
                end

                handles.maxUndoHistory.Value = undoPrefs.MaxUndoHistory;
                handles.max3dUndoHistory.Value = undoPrefs.Max3dUndoHistory;
                obj.renderedPanels(3) = 1;
            end

            % % -------------- ExternalDirectoriesPanel ----------------
            if strcmp(panelId, 'All') || strcmp(panelId, 'ExternalDirectoriesPanel')
                if obj.renderedPanels(4) == 1; return; end  % already rendered
                externalDirPrefs = obj.preferences.ExternalDirs;

                handles.FijiInstallationPath.Value = char(externalDirPrefs.FijiInstallationPath);
                handles.OmeroInstallationPath.Value = char(externalDirPrefs.OmeroInstallationPath);
                handles.ImarisInstallationPath.Value  = char(externalDirPrefs.ImarisInstallationPath);
                handles.bm3dInstallationPath.Value = char(externalDirPrefs.bm3dInstallationPath);
                handles.bm4dInstallationPath.Value = char(externalDirPrefs.bm4dInstallationPath);
                handles.BioFormatsMemoizerMemoDir.Value = char(externalDirPrefs.BioFormatsMemoizerMemoDir);
                handles.PythonInstallationPath.Value = char(externalDirPrefs.PythonInstallationPath);
                handles.JavaInstallationPath.Value = char(externalDirPrefs.JavaInstallationPath);
                handles.DeepMIBDir.Value = char(externalDirPrefs.DeepMIBDir);
                % Python execution mode dropdown (guard preferences saved before
                % this field existed); Items are {'OutOfProcess','InProcess'}
                if isfield(externalDirPrefs, 'PythonExecutionMode') && ~isempty(externalDirPrefs.PythonExecutionMode)
                    handles.PythonExecutionMode.Value = char(externalDirPrefs.PythonExecutionMode);
                else
                    handles.PythonExecutionMode.Value = 'OutOfProcess';
                end
                obj.renderedPanels(4) = 1;
            end

            % % -------------- KeyboardShortcutsPanel ----------------
            if strcmp(panelId, 'All') || strcmp(panelId, 'KeyboardShortcutsPanel')
                if obj.renderedPanels(5) == 1; return; end  % already rendered
                % update table with contents of handles.KeyShortcuts
                % Column names and column format
                ColumnName =    {'',    'Action name',  'Key',      'Shift',    'Control',  'Alt'};
                ColumnFormat =  {'char','char',         'char',     'logical',  'logical',  'logical'};
                handles.shortcutsTable.ColumnName = ColumnName;
                handles.shortcutsTable.ColumnFormat = ColumnFormat;

                data(:,2) = obj.preferences.KeyShortcuts.Action;
                data(:,3) = obj.preferences.KeyShortcuts.Key;
                data(:,4) = num2cell(logical(obj.preferences.KeyShortcuts.shift));
                data(:,5) = num2cell(logical(obj.preferences.KeyShortcuts.control));
                data(:,6) = num2cell(logical(obj.preferences.KeyShortcuts.alt));

                handles.shortcutsTable.ColumnWidth = {8, 'auto', 62, 46, 56, 46};

                removeStyle(handles.shortcutsTable);    % remove current styles

                s1 = uistyle;
                s1.BackgroundColor = [0 1 0];
                addStyle(handles.shortcutsTable, s1, 'column', 1);
                drawnow;

                ColumnEditable = [false false true true true true];
                handles.shortcutsTable.ColumnEditable = ColumnEditable;
                handles.shortcutsTable.Data = data;
                obj.renderedPanels(5) = 1;
            end


            % % -------------- SegmentationToolsPanel ----------------
            if strcmp(panelId, 'All') || strcmp(panelId, 'SegmentationToolsPanel')
                if obj.renderedPanels(6) == 1; return; end  % already rendered
                segmToolsPrefs = obj.preferences.SegmTools;

                handles.annotationFontSize.Value = handles.annotationFontSize.Items{segmToolsPrefs.Annotations.FontSize};
                handles.annotationShownExtraDepth.Value = segmToolsPrefs.Annotations.ShownExtraDepth;
                setColorButton(handles.AnnotationsColorButton2, segmToolsPrefs.Annotations.Color);

                handles.InterpolationType.Value = segmToolsPrefs.Interpolation.Type;
                handles.InterpolationNumberOfPoints.Value = segmToolsPrefs.Interpolation.NoPoints;
                handles.InterpolationLineWidth.Value = segmToolsPrefs.Interpolation.LineWidth;

                handles.FavoriteToolA.Value = segmToolsPrefs.FavoriteToolA;
                handles.FavoriteToolB.Value = segmToolsPrefs.FavoriteToolB;

                obj.renderedPanels(6) = 1;
            end

            % % -------------- InputOutputPanel ----------------
            if strcmp(panelId, 'All') || strcmp(panelId, 'InputOutputPanel')
                if obj.renderedPanels(7) == 1; return; end  % already rendered
                handles.ZarrLibrary.Value = obj.preferences.IO.Zarr.Library;
                handles.ZarrLibraryLabel.Text = obj.zarrLibraryDescription(obj.preferences.IO.Zarr.Library);
                handles.ZarrSmoothing.Value = obj.preferences.IO.Zarr.Smoothing;
                % The other widgets of this panel get their callback in App
                % Designer; this one is wired here because the field was added to
                % the .mlapp without one. Assigning it replaces rather than adds,
                % so wiring it in the designer later cannot double-fire.
                handles.ChunkCacheMB.ValueChangedFcn = @(~, event) obj.InputOutputPanelCallbacks(event);
                % 0 is the documented way to switch the cache off, so the field
                % has to accept it - the designer default starts the range at 1.
                handles.ChunkCacheMB.Limits = [0 Inf];
                handles.ChunkCacheMB.Value  = obj.preferences.IO.Zarr.ChunkCacheMB;
                handles.ChunkCacheMB.Tooltip = sprintf(['Memory held for decoded zarr chunks.\n' ...
                    'A chunk is often tens of slices deep, so caching it makes the next ' ...
                    'slice change and small pans instant instead of a re-fetch.\n' ...
                    '0 turns the cache off.']);
                % BioFormats / WSI reader backend dropdown (guarded for older .mlapp).
                % The dropdown shows 'MIB'/'MATLAB'; preferences store the canonical
                % lowercase 'mib'/'matlab' (normalized both ways).
                canon = io.BioFormats.Config.normalizeName(obj.preferences.IO.BioFormats.Library);
                handles.BioFormatsLibrary.Value = obj.bioFormatsLibraryItem(handles.BioFormatsLibrary.Items, canon);
                handles.BioFormatsLabel.Text = obj.bioFormatsLibraryDescription(canon);
                
                obj.renderedPanels(7) = 1;
            end
        end

        function txt = zarrLibraryDescription(~, value)
            % ZARRLIBRARYDESCRIPTION - one-line description of a zarr3 I/O backend.
            switch char(value)
                case 'native'
                    txt = 'Native zarrMex engine: bundled with MIB, no external dependencies (recommended)';
                otherwise   % 'python'
                    txt = 'zarr-python (v2 and v3) via the Python interpreter set in External dirs; requires the zarr and numpy packages';
            end
        end

        function txt = bioFormatsLibraryDescription(~, value)
            % BIOFORMATSLIBRARYDESCRIPTION - one-line description of a BioFormats reader backend.
            switch char(value)
                case 'matlab'
                    txt = 'MATLAB built-in bioformatsread / openslideread (lazy blockedImage; requires the Medical Imaging WSI support package)';
                otherwise   % 'mib'
                    txt = 'MIB bundled OME Bio-Formats Java reader (broadest format coverage, recommended)';
            end
        end

        function item = bioFormatsLibraryItem(~, items, canon)
            % BIOFORMATSLIBRARYITEM - pick the dropdown item matching a canonical
            % backend name ('mib'|'matlab'), case-insensitively (the dropdown shows
            % 'MIB'/'MATLAB'). Falls back to the first item if no match.
            idx = find(strcmpi(items, canon), 1);
            if isempty(idx); idx = find(contains(lower(items), char(canon)), 1); end
            if isempty(idx); idx = 1; end
            item = items{idx};
        end
        
        function helpBtnCallback(obj)
            % HELPBTNCALLBACK - Open the docs at the section for the selected category.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.helpBtnCallback()
            %
            % Jumps to the heading matching the category the user is looking at,
            % rather than dropping them at the top of a long page. Prefers the
            % copy shipped with MIB and falls back to the website when this is a
            % source checkout with no built ``docs/html``.

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.helpBtnCallback: triggered\n');
            end

            % Anchors are generated by Zensical from the headings of
            % docs/docs/user-interface/ribbon/home/home-preferences.md, by
            % lowercasing and replacing spaces with hyphens. Renaming a heading
            % there silently breaks the jump, so PreferencesHelpTest checks these
            % against the built page.
            switch obj.shownPanelTag
                case 'UserInterfacePanel';       anchor = '#user-interface';
                case 'ColorsPanel';              anchor = '#colors-and-styles';
                case 'BackupAndUndoPanel';       anchor = '#backup-and-undo';
                case 'ExternalDirectoriesPanel'; anchor = '#external-directories';
                case 'KeyboardShortcutsPanel';   anchor = '#keyboard-shortcuts';
                case 'SegmentationToolsPanel';   anchor = '#segmentation-tools';
                case 'InputOutputPanel';         anchor = '#input-output';
                otherwise;                       anchor = '';    % top of the page
            end

            helpFilePath = fullfile(utils.getDocsPath(), ...
                'user-interface', 'ribbon', 'home', 'home-preferences.html');
            if isfile(helpFilePath)
                target = ['file:///' strrep(helpFilePath, '\', '/') anchor];
            else
                target = ['http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/' ...
                    'home-preferences.html' anchor];
            end
            obj.openInSystemBrowser(target);
        end

        function status = ApplyButtonPushedCallback(obj)
            % APPLYBUTTONPUSHEDCALLBACK - apply preferences to MIB.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      status = obj.ApplyButtonPushedCallback()
            %
            % Output Arguments:
            %   - **status** - [numeric] 1 if successful, 0 if failed
            %
            % **Example** - apply and validate preferences:
            %
            %   .. code-block:: matlab
            %
            %      status = obj.ApplyButtonPushedCallback();
            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.ApplyButtonPushedCallback: triggered\n');
            end
            status = 0;
            activeDataset = obj.mibModel.I{obj.mibModel.id};
            systemPrefs = obj.preferences.System;
            colorPrefs = obj.preferences.Colors;
            controllerFontSettings = obj.mibController.cActiveDataset.handles.sets;

            % update font size
            if controllerFontSettings.FontSize ~= systemPrefs.Font.FontSize || ...
                    ~strcmp(controllerFontSettings.FontName, systemPrefs.Font.FontName)
                utils.fontSizeUpdate(obj.mibController.view.gui, systemPrefs.Font);
            end
            obj.mibController.cDirContents.handles.fileList.FontSize = systemPrefs.FontSizeDirView;

            % update key shortcuts
            if numel(obj.duplicateEntries) > 1
                uialert(obj.view.gui, ...
                    'Please check for duplicates in key shortcuts!', 'Duplicate shortcuts');
                return;
            end

            data = obj.view.handles.shortcutsTable.Data;
            obj.preferences.KeyShortcuts.Action = data(:, 2)';
            obj.preferences.KeyShortcuts.Key = data(:, 3)';
            obj.preferences.KeyShortcuts.shift = cell2mat(data(:, 4))';
            obj.preferences.KeyShortcuts.control = cell2mat(data(:, 5))';
            obj.preferences.KeyShortcuts.alt = cell2mat(data(:, 6))';

            % deal with change of selection mode
            % Virtual / BigData layers are read-on-demand / disk-backed: obj.data is
            % empty by design, so the in-memory (de)allocation below does not apply and
            % dropping the container would break a live disk-backed model. Just apply
            % the enableSelection flag for those - same rule as OKButtonPushedCallback
            if ~any(activeDataset.datasetType(1) == ['V' 'B'])
                if systemPrefs.EnableSelection   % turn ON the Selection
                    if activeDataset.labels.maxMaterials >= 255 && ~activeDataset.selection.exists
                        obj.mibController.mibModel.clearLayer('selection');
                    elseif activeDataset.labels.maxMaterials == 63 && ~activeDataset.labels.exists
                        obj.allocateLabelsLayer(activeDataset);
                    end
                else         % turn OFF the Selection, Mask, Model
                    obj.releaseSegmentationLayers(activeDataset);
                    obj.mibModel.Backup.clearContents();  % delete backup history
                end
            end
            activeDataset.enableSelection = systemPrefs.EnableSelection;

            % the theme is set from the Home ribbon, not here: keep the current
            % value over the copy, which is stale or reset by the Defaults button
            obj.preferences.Colors.Theme = obj.mibModel.preferences.Colors.Theme;
            obj.mibModel.preferences = obj.preferences;

            % a Java folder typed or selected without pressing "Configure Java..."
            % is connected here, so it cannot be forgotten. Attempted once per
            % change: after a cancel or an error (shown in a dialog) OK does not
            % ask again; the stored path is kept either way
            javaPath = char(obj.preferences.ExternalDirs.JavaInstallationPath);
            if ~isempty(javaPath) && ~strcmpi(javaPath, obj.javaAppliedPath)
                obj.javaAppliedPath = javaPath;
                utils.JavaSetup.apply(obj.view.gui, javaPath, obj.mibModel.mibPath);
            end

            % activate the selected OME-Zarr v3 backend so open/save of zarr3
            % uses it without restarting MIB (io.zarr.Array / io.zarr.Group)
            io.zarr.Config.setLibrary(obj.mibModel.preferences.IO.Zarr.Library);
            io.zarr.Config.setSmoothing(obj.mibModel.preferences.IO.Zarr.Smoothing);
            % Shrinking the budget evicts immediately, so the memory is handed
            % back as soon as Apply is pressed rather than at the next read.
            io.zarr.ChunkCache.setBudgetMB(obj.mibModel.preferences.IO.Zarr.ChunkCacheMB);
            io.zarr.Config.setPythonPath(obj.mibModel.preferences.ExternalDirs.PythonInstallationPath);
            if isfield(obj.mibModel.preferences.ExternalDirs, 'PythonExecutionMode')
                io.zarr.Config.setExecutionMode(obj.mibModel.preferences.ExternalDirs.PythonExecutionMode);
            end

            % activate the selected BioFormats / WSI reader backend (io.BioFormats.Reader)
            if isfield(obj.mibModel.preferences.IO, 'BioFormats')
                io.BioFormats.Config.setLibrary(obj.mibModel.preferences.IO.BioFormats.Library);
            end
            % activate the BioFormats Memoizer (.bfmemo) cache directory without restart
            if isfield(obj.mibModel.preferences.ExternalDirs, 'BioFormatsMemoizerMemoDir') && ...
                    ~isempty(obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir)
                io.BioFormats.Config.setMemoDir(obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir);
            end

            activeDataset.labels.materialColors = colorPrefs.ModelMaterialColors;
            activeDataset.labels.lutColors = colorPrefs.LUTColors;

            obj.mibController.updateInterpolationMode(true);  % update the interpolation button icon
            obj.mibController.updateVisualizationMode('keepcurrent');  % update image visualization mode

            % update imaris path using IMARISPATH environmental variable
            if ~isempty(obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath)
                setenv('IMARISPATH', obj.mibModel.preferences.ExternalDirs.ImarisInstallationPath);
            end

            % refresh the external dirs cached by the lazy Java library
            % gateway, so updated Fiji/OMERO/Imaris paths are picked up
            % without restarting MIB
            utils.ensureJavaLibraries({}, '', obj.mibModel.preferences.ExternalDirs);

            notify(obj.mibModel, 'ShowImage');
            notify(obj.mibModel, 'UpdateGuiWidgets');
            status = 1;
        end
        
        function RescaleGUIButtonPushed(obj)
            % RESCALEGUIBUTTONPUSHED - rescale user interface of MIB.
            %
            % Updates the ``scalingGUI`` global from the System preferences. The
            % widgets of the already open AppDesigner windows are not rescaled
            % live - the new scaling is applied to the windows created after the
            % change; MIB has to be restarted to rescale the main window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.RescaleGUIButtonPushed()
            %
            % **Example** - rescale the MIB GUI:
            %
            %   .. code-block:: matlab
            %
            %      obj.RescaleGUIButtonPushed();
            global scalingGUI;

            scalingGUI = obj.preferences.System.GUI;   % update scalingGUI
            drawnow;
            figure(obj.view.gui);   % set focus to main preference window and move it in front
        end
        
        function OKButtonPushedCallback(obj)
            % OKBUTTONPUSHEDCALLBACK - apply preferences and close the preferences window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.OKButtonPushedCallback()
            %
            % **Example** - confirm and apply preferences:
            %
            %   .. code-block:: matlab
            %
            %      obj.OKButtonPushedCallback();
            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.OKButtonPushedCallback: triggered\n');
            end
            status = obj.ApplyButtonPushedCallback();
            if status == 0; return; end

            activeDataset = obj.mibModel.I{obj.mibModel.id};
            undoPrefs = obj.preferences.Undo;
            backup = obj.mibModel.Backup;

            if undoPrefs.Enable
                backup.enableSwitch = true;
            else
                backup.clearContents();
                backup.enableSwitch = false;
            end

            if undoPrefs.Max3dUndoHistory ~= backup.max3d_steps || undoPrefs.MaxUndoHistory ~= backup.max_steps
                backup.setNumberOfHistorySteps(undoPrefs.MaxUndoHistory, undoPrefs.Max3dUndoHistory);
            end

            % Virtual / BigData layers are read-on-demand / disk-backed: obj.data is
            % empty by design, so the in-memory (de)allocation below does not apply
            % (and indexing data(1) would error / NaN-ing it would break the live
            % disk-backed model). Just apply the enableSelection flag for those.
            if ~any(activeDataset.datasetType(1) == ['V' 'B'])
                if obj.preferences.System.EnableSelection
                    % test 'exists' rather than isnan(data(1)): a dataset opened while
                    % the preference was off has data = [], and data(1) errors on it.
                    % Both spellings of "not allocated" (NaN below, [] from
                    % core.MibDataset.initialize) set exists = false
                    if activeDataset.labels.maxMaterials >= 255 && ~activeDataset.selection.exists
                        obj.mibController.mibModel.clearLayer('selection');
                    elseif activeDataset.labels.maxMaterials == 63 && ~activeDataset.labels.exists
                        obj.allocateLabelsLayer(activeDataset);
                    end
                else         % turn OFF the Selection, Mask, Model
                    obj.releaseSegmentationLayers(activeDataset);
                    backup.clearContents();  % delete backup history
                end
            end
            activeDataset.enableSelection = obj.preferences.System.EnableSelection;

            notify(obj.mibModel, 'ShowImage');
            % modelExist / maskExist and the materials list may have just changed, and
            % only UpdateGuiWidgets refreshes the Segmentation panel that shows them
            notify(obj.mibModel, 'UpdateGuiWidgets');
            obj.closeWindow();
        end
        
        function ColorPanelCallbacks(obj, event)
            % COLORPANELCALLBACKS - callbacks for modification of the Colors panel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.ColorPanelCallbacks(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the GUI element that triggered callback
            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.ColorPanelCallbacks(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'SelectionColorButton'    % update selection color
                    sel_color = obj.preferences.Colors.SelectionColor;
                    c = uisetcolor(sel_color, 'Selection color');
                    if length(c) == 1; return; end
                    obj.preferences.Colors.SelectionColor = c;
                    setColorButton(obj.view.handles.SelectionColorButton, c);
                case 'MaskColorButton'          % update mask color
                    sel_color = obj.preferences.Colors.MaskColor;
                    c = uisetcolor(sel_color, 'Mask color');
                    if length(c) == 1; return; end
                    obj.preferences.Colors.MaskColor = c;
                    setColorButton(obj.view.handles.MaskColorButton, c);
                case 'cursorMaterialColor'      % brush cursor follows the material color
                    obj.preferences.Colors.CursorMaterialColor = obj.view.handles.cursorMaterialColor.Value;
                case {'AnnotationsColorButton', 'AnnotationsColorButton2'}   % update annotations color
                    sel_color = obj.preferences.SegmTools.Annotations.Color;
                    c = uisetcolor(sel_color, 'Annotations color');
                    if length(c) == 1; return; end
                    obj.preferences.SegmTools.Annotations.Color = c;
                    setColorButton(obj.view.handles.AnnotationsColorButton, c);
                    setColorButton(obj.view.handles.AnnotationsColorButton2, c);
                case 'PaletteGeneratorDropDown'     % generate palette
                    materialsNumber = numel(obj.mibModel.I{obj.mibModel.id}.labels.materialNames);
                    
                    switch obj.view.handles.PaletteGeneratorDropDown.Value
                        case 'Default, 6 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = {'6'};
                        case 'Distinct colors, 20 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = {'20'};
                        case 'Qualitative (Monte Carlo->Half Baked), 3-12 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):12);
                        case 'Diverging (Deep Bronze->Deep Teal), 3-11 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):11);
                        case 'Diverging (Ripe Plum->Kaitoke Green), 3-11 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):11);
                        case 'Diverging (Bordeaux->Green Vogue), 3-11 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):11);
                        case 'Diverging (Carmine->Bay of Many), 3-11 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):11);
                        case 'Sequential (Kaitoke Green), 3-9 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):9);
                        case 'Sequential (Catalina Blue), 3-9 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):9);
                        case 'Sequential (Maroon), 3-9 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):9);
                        case 'Sequential (Astronaut Blue), 3-9 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):9);
                        case 'Sequential (Downriver), 3-9 colors'
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', max([3, materialsNumber]):9);
                        case {'Matlab Jet','Matlab Gray','Matlab Bone','Matlab HSV', 'Matlab Cool', 'Matlab Hot', 'Random Colors'}
                            options.Type = 'spinner';
                            defAns = struct('Value', max([1 materialsNumber]), ...
                                'Limits', [1 Inf], 'Step', 1, 'Round', true);
                            options.WindowWidth = 320;
                            options.ParentFigure = obj.view.gui;
                            options.mibPath = obj.mibModel.mibPath;
                            noColors = utils.dlgs.inputSingleDlg(obj.view.gui, ...
                                sprintf('Please enter number of colors\n(max. value is %d)', obj.mibModel.I{obj.mibModel.id}.labels.maxMaterials), ...
                                defAns, ...
                                'Define number of colors', options);
                            if isempty(noColors); return; end

                            if noColors > 255
                                errorOpts.mibPath = obj.mibModel.mibPath;
                                utils.dlgs.showErrorDialog(obj.view.gui, ...
                                    sprintf('Number of colors should be below 256!'), 'Too many colors', 'Error in Preferences.ColorPanelCallbacks', '', errorOpts);
                                figure(obj.view.gui);   % set focus to main preference window and move it in front
                                return;
                            end
                            obj.view.handles.NumberOfColorsDropDown.Items = compose('%d', noColors);
                    end
                    obj.updateColorPalette();
                case 'NumberOfColorsDropDown'
                    obj.updateColorPalette();
                case 'ContourThicknessRendering'
                    obj.preferences.Styles.Contour.ThicknessRendering = obj.view.handles.ContourThicknessRendering.Value;
                case 'ContourThicknessModels'
                    obj.preferences.Styles.Contour.ThicknessModels = obj.view.handles.ContourThicknessModels.Value;
                case 'ContourThicknessMasks'
                    obj.preferences.Styles.Contour.ThicknessMasks = obj.view.handles.ContourThicknessMasks.Value;
                case 'ContourThicknessMasksMethod'
                    obj.preferences.Styles.Contour.ThicknessMethodMasks = obj.view.handles.ContourThicknessMasksMethod.Value;
                case 'LabelsShowAsContours'
                    obj.preferences.Styles.Labels.ShowAsContours = obj.view.handles.LabelsShowAsContours.Value;
                case 'MaskShowAsContours'
                    obj.preferences.Styles.Masks.ShowAsContours = obj.view.handles.MaskShowAsContours.Value;

            end
            figure(obj.view.gui);   % set focus to main preference window and move it in front
        end
        
        function KeyboardShortcutsPanelCallbacks(obj, event)
            % KEYBOARDSHORTCUTSPANELCALLBACKS - callbacks for modification of the Keyboard shortcuts panel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.KeyboardShortcutsPanelCallbacks(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the GUI element that triggered callback
            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.KeyboardShortcutsPanelCallbacks: triggered\n');
            end
            switch event.Source.Tag
                case 'ResetKeyShortcutsButton'
                    selection = uiconfirm(obj.view.gui, ...
                        sprintf('!!! Warning !!!\n\nYou are going to reset all keyboard shortcuts to default values!'), ...
                        'Reset key shortcuts', 'Options', {'Confirm', 'Cancel'}, ...
                        'Icon', 'warning');
                    if strcmp(selection, 'Cancel'); return; end
                    obj.preferences.KeyShortcuts = generateDefaultKeyShortcuts();
                    obj.updateWidgets();
            end
                
        end

        function InputOutputPanelCallbacks(obj, event)
            % INPUTOUTPUTPANELCALLBACKS - callbacks for modification of the input / output panel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.InputOutputPanelCallbacks(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the GUI element that triggered callback
            %
        
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.InputOutputPanelCallbacks(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'ZarrLibrary'
                    obj.preferences.IO.Zarr.Library = obj.view.handles.ZarrLibrary.Value;
                    obj.view.handles.ZarrLibraryLabel.Text = ...
                        obj.zarrLibraryDescription(obj.preferences.IO.Zarr.Library);
                    % Note: this only updates the dialog's working copy of preferences;
                    % the backend is committed in ApplyButtonPushedCallback.
                case 'ZarrSmoothing'
                    % optional widget (boolean) - smooth coarse->fine label propagation
                    obj.preferences.IO.Zarr.Smoothing = logical(obj.view.handles.ZarrSmoothing.Value);
                    % committed in ApplyButtonPushedCallback.
                case 'ChunkCacheMB'
                    % memory held for decoded zarr chunks; 0 disables the cache
                    obj.preferences.IO.Zarr.ChunkCacheMB = obj.view.handles.ChunkCacheMB.Value;
                    % committed in ApplyButtonPushedCallback.
                case 'BioFormatsLibrary'
                    % BioFormats / WSI reader backend; dropdown shows 'MIB'/'MATLAB',
                    % stored canonical lowercase ('mib'|'matlab').
                    if ~isfield(obj.preferences.IO, 'BioFormats'); obj.preferences.IO.BioFormats = struct(); end
                    obj.preferences.IO.BioFormats.Library = ...
                        io.BioFormats.Config.normalizeName(obj.view.handles.BioFormatsLibrary.Value);
                    if isfield(obj.view.handles, 'BioFormatsLabel')
                        obj.view.handles.BioFormatsLabel.Text = ...
                            obj.bioFormatsLibraryDescription(obj.preferences.IO.BioFormats.Library);
                    end
                    % The MATLAB backend needs the "Medical Imaging Toolbox Interface
                    % for Whole Slide Imaging File Reader" support package (provides
                    % bioformatsread/openslideread). Warn now if it is missing - opening
                    % files with this reader would otherwise fail at read time.
                    if strcmp(obj.preferences.IO.BioFormats.Library, 'matlab') && ...
                            exist('bioformatsread', 'file') ~= 2
                        dlgOpt = struct();
                        dlgOpt.MsgBoxOnly  = true;
                        dlgOpt.Icon        = 'puffin_warning';
                        dlgOpt.HeaderLines = 2;
                        dlgOpt.mibPath     = obj.mibModel.mibPath;
                        bodyText = sprintf([ ...
                            'It requires the "Medical Imaging Toolbox Interface for Whole Slide ' ...
                            'Imaging File Reader" support package (provides bioformatsread / ' ...
                            'openslideread).\n\n' ...
                            'Install it from MATLAB: Home tab -> Add-Ons -> Get Add-Ons, then ' ...
                            'search for "Whole Slide Imaging File Reader".\n\n' ...
                            'Until it is installed, opening files with this reader will fail - ' ...
                            'keep the "MIB" library instead.']);
                        utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                            'The MATLAB BioFormats / WSI reader is not installed', ...
                            {''}, {bodyText}, 'Support package not installed', dlgOpt);
                    end
                    % committed in ApplyButtonPushedCallback.
            end

        end

        function ExternalDirectoriesPanelCallbacks(obj, event)
            % EXTERNALDIRECTORIESPANELCALLBACKS - callbacks for the External directories panel widgets.
            %
            % Handles widgets on the External directories panel that are not the
            % path text fields / select buttons (those use ExternalDirPathChange
            % and ExternalDirSelect). Currently the Python execution mode dropdown.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.ExternalDirectoriesPanelCallbacks(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the GUI element that triggered callback
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.ExternalDirectoriesPanelCallbacks: triggered\n');
            end
            switch event.Source.Tag
                case 'PythonExecutionMode'
                    % execution mode for pyenv used by SAM/SAM2 (and other Python
                    % tools). 'OutOfProcess' isolates torch's CUDA context from
                    % MATLAB so DeepMIB's gpuDevice() reset cannot corrupt SAM.
                    % Only updates the dialog's working copy; committed to
                    % obj.mibModel.preferences in ApplyButtonPushedCallback.
                    obj.preferences.ExternalDirs.PythonExecutionMode = obj.view.handles.PythonExecutionMode.Value;
            end
        end

        function SegmentationPanelCallbacks(obj, event)
            % SEGMENTATIONPANELCALLBACKS - callbacks for modification of the Segmentation tools panel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.SegmentationPanelCallbacks(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the GUI element that triggered callback
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.SegmentationPanelCallbacks(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'annotationFontSize'
                    obj.preferences.SegmTools.Annotations.FontSize = find(ismember(obj.view.handles.annotationFontSize.Items, obj.view.handles.annotationFontSize.Value));
                case 'annotationShownExtraDepth'
                    obj.preferences.SegmTools.Annotations.ShownExtraDepth = obj.view.handles.annotationShownExtraDepth.Value;
                case 'InterpolationType'
                    obj.preferences.SegmTools.Interpolation.Type = obj.view.handles.InterpolationType.Value;
                case 'InterpolationNumberOfPoints'
                    obj.preferences.SegmTools.Interpolation.NoPoints = obj.view.handles.InterpolationNumberOfPoints.Value;
                case 'InterpolationLineWidth'
                    obj.preferences.SegmTools.Interpolation.LineWidth = obj.view.handles.InterpolationLineWidth.Value;
                case 'FavoriteToolA'
                    obj.preferences.SegmTools.FavoriteToolA = obj.view.handles.FavoriteToolA.Value;
                case 'FavoriteToolB'
                    obj.preferences.SegmTools.FavoriteToolB = obj.view.handles.FavoriteToolB.Value;
            end
        end
        
        function BackupAndUndoPanelCallbacks(obj, event)
            % BACKUPANDUNDOPANELCALLBACKS - callbacks for modification of the Undo and backup panel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.BackupAndUndoPanelCallbacks(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the GUI element that triggered callback
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.BackupAndUndoPanelCallbacks(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'EnableUndo'
                    obj.preferences.Undo.Enable = obj.view.handles.EnableUndo.Value;
                    obj.updateWidgets('BackupAndUndoPanel');
                case {'maxUndoHistory', 'max3dUndoHistory'}
                    valueMax = obj.view.handles.maxUndoHistory.Value;
                    valueMax3d = obj.view.handles.max3dUndoHistory.Value;
                    
                    if valueMax3d > valueMax
                        uialert(obj.view.gui, ...
                            sprintf('Error!\n\nThe number of 3D history steps should be lower or equal than total number of steps'),...
                            'Error!');
                        obj.view.handles.maxUndoHistory.Value = obj.preferences.Undo.MaxUndoHistory;
                        obj.view.handles.max3dUndoHistory.Value = obj.preferences.Undo.Max3dUndoHistory;
                        return;
                    end
                    obj.preferences.Undo.MaxUndoHistory = valueMax;
                    obj.preferences.Undo.Max3dUndoHistory = valueMax3d;
            end
        end
        
        function UserInterfacePanelCallbacks(obj, event)
            % USERINTERFACEPANELCALLBACKS - callbacks for modification of the User Interface panel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.UserInterfacePanelCallbacks(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the GUI element that triggered callback
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.UserInterfacePanelCallbacks(%s): triggered\n', event.Source.Tag);
            end
            switch event.Source.Tag
                case 'MouseWheelActionDropDown'
                    if strcmp(obj.view.handles.MouseWheelActionDropDown.Value, 'Zoom In/Out')
                        obj.preferences.System.MouseWheel = 'zoom';   % zoom or scroll
                    else
                        obj.preferences.System.MouseWheel = 'scroll';
                    end
                case 'LeftMouseActionDropDown'
                    if strcmp(obj.view.handles.LeftMouseActionDropDown.Value, 'Pan image')
                        obj.preferences.System.LeftMouseButton = 'pan';   % zoom or scroll
                    else    % Selection/drawing
                        obj.preferences.System.LeftMouseButton = 'select';
                    end
                case 'ImageResizeMethodDropDown'
                    obj.preferences.System.ImageResizeMethod = obj.view.handles.ImageResizeMethodDropDown.Value;
                case 'EnableSelectionDropDown'
                    if strcmp(obj.view.handles.EnableSelectionDropDown.Value, 'yes')
                        obj.preferences.System.EnableSelection = 1;   % enable selection
                    else    % no = disable selection
                        selection = uiconfirm(obj.view.gui, ...
                            sprintf('!!! Warning !!!\n\nDisabling of the Selection layer delete the Model and Mask layers!!!\n\nThese changes will affect only the currently shown dataset and the future MIB sessions\n\nAre you sure?'), ...
                            'Turn off selection layer',...
                            'Icon', 'warning');
                        if strcmp(selection, 'Cancel')
                            obj.view.handles.EnableSelectionDropDown.Value = 'yes';
                            return; 
                        end
                        obj.preferences.System.EnableSelection = 0;
                    end
                case 'AltWithScrollWheel'
                    if strcmp(obj.view.handles.AltWithScrollWheel.Value, 'Scroll time points')
                        obj.preferences.System.AltWithScrollWheel = true;
                    else
                        obj.preferences.System.AltWithScrollWheel = false;
                    end
                case 'RecentDirsNumber'
                    obj.preferences.System.Dirs.RecentDirsNumber = obj.view.handles.RecentDirsNumber.Value;
                case 'RenderingEngine'
                    obj.preferences.System.RenderingEngine = obj.view.handles.RenderingEngine.Value;
                case 'FontSizeEditField'
                    obj.preferences.System.Font.FontSize = obj.view.handles.FontSizeEditField.Value;
                    obj.updateWidgets();
                case 'FontSizeDireContentsEditField'
                    obj.preferences.System.FontSizeDirView = obj.view.handles.FontSizeDireContentsEditField.Value;
                case 'SelectFontButton'
                    obj.preferences.System.Font.FontSize = obj.preferences.System.Font.FontSize;
                    selectedFont = uisetfont(obj.preferences.System.Font);
                    if ~isstruct(selectedFont)
                        figure(obj.view.gui); % set focus to main preference window and move it in front
                        return; 
                    end
                    selectedFont.FontSize = selectedFont.FontSize;
                    selectedFont = rmfield(selectedFont, 'FontWeight');
                    selectedFont = rmfield(selectedFont, 'FontAngle');
                    
                    obj.preferences.System.Font = selectedFont;
                    obj.view.handles.FontSizeEditField.Value = obj.preferences.System.Font.FontSize;
                    utils.fontSizeUpdate(obj.view.gui, obj.preferences.System.Font);
                    figure(obj.view.gui);   % set focus to main preference window and move it in front
                case 'RecheckPeriod'
                    obj.preferences.System.Update.RecheckPeriod = obj.view.handles.RecheckPeriod.Value;
                case 'CpuParallelLimit'
                    obj.preferences.System.cpuParallelLimit = obj.view.handles.CpuParallelLimit.Value;
                case 'SystemScalingEditField'
                    obj.preferences.System.GUI.systemscaling = obj.view.handles.SystemScalingEditField.Value;
                case 'mibScalingFactorEditField'
                    obj.preferences.System.GUI.scaling = obj.view.handles.mibScalingFactorEditField.Value;
                case 'uibuttongroup'
                    obj.preferences.System.GUI.uibuttongroup = obj.view.handles.uibuttongroup.Value;
                case 'uipanel'
                    obj.preferences.System.GUI.uipanel = obj.view.handles.uipanel.Value;
                case 'uitab'
                    obj.preferences.System.GUI.uitab = obj.view.handles.uitab.Value;
                case 'uitabgroup'
                    obj.preferences.System.GUI.uitabgroup = obj.view.handles.uitabgroup.Value;
                case 'axes'
                    obj.preferences.System.GUI.axes = obj.view.handles.axes.Value;
                case 'uitable'
                    obj.preferences.System.GUI.uitable = obj.view.handles.uitable.Value;
                case 'uicontrol'
                    obj.preferences.System.GUI.uicontrol = obj.view.handles.uicontrol.Value;
                    
            end
        end
        
        
        function CategoriesTreeSelectionChanged(obj, selectedNodes)
            % CATEGORIESTREESELECTIONCHANGED - callback for change of nodes of CategoriesTree.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.CategoriesTreeSelectionChanged(selectedNodes)
            %
            % Input Arguments:
            %   - **selectedNodes** - [handle] handle to the selected tree node
            
            % hide currently visible (previous) panel
            obj.view.handles.(obj.shownPanelTag).Visible = 'off';
            
            newPanelTag = [selectedNodes.Tag(1:end-4) 'Panel'];
            obj.view.handles.(newPanelTag).Visible = 'on';
            
            obj.shownPanelTag = newPanelTag;    % update currently selected node variable
            obj.updateWidgets(obj.shownPanelTag);
        end
        
        
        function updateColorPalette(obj)
            % UPDATECOLORPALETTE - generate default colors for the selected palette.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateColorPalette()
            %
            % **Example** - update the color palette:
            %
            %   .. code-block:: matlab
            %
            %      obj.updateColorPalette();
            
            % update color palette based on selected parameters in the paletteTypePopup and paletteColorNumberPopup popups
            colorsNo = str2double(obj.view.handles.NumberOfColorsDropDown.Value);
            
            [palette, cancelled] = utils.defaults.generateDefaultPalette(obj.view.handles.PaletteGeneratorDropDown.Value, colorsNo);
            if cancelled; return; end     % the random seed dialog was dismissed, keep the current palette
            obj.preferences.Colors.ModelMaterialColors = palette;
            obj.updateColorsTables('ModelsColorsTable');
        end
        
        function updateColorsTables(obj, ColorTableTag, options)
            % UPDATECOLORSTABLES - update color tables: ModelsColorsTable or LUTColorsTable.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateColorsTables(ColorTableTag, options)
            %
            % Input Arguments:
            %   - **ColorTableTag** - [char] tag of the table: ``'ModelsColorsTable'`` or ``'LUTColorsTable'``
            %   - **options** *(optional)* - [struct] structure with additional parameters:
            %
            %     - ``.updateDataOnly`` - [logical] update data only without redrawing styles (default: ``false``)
            %     - ``.rowId`` - [integer] index of row to update; when empty, update full table (default: ``[]``)
            
            if nargin < 2; error('ColorTableTag  is missing'); end
            if nargin < 3; options = struct(); end
            if ~isfield(options, 'updateDataOnly'); options.updateDataOnly = false; end
            if ~isfield(options, 'rowId'); options.rowId = []; end
            
            switch ColorTableTag
                case 'ModelsColorsTable'
                    prefStruct = 'ModelMaterialColors';     % name of the struture in preferences
                case 'LUTColorsTable'
                    prefStruct = 'LUTColors';
            end
            
            if obj.mibModel.I{obj.mibModel.id}.labels.maxMaterials > 255
                % disable the materials color table for models larger than 255
                obj.view.handles.ModelsColorsTable.Enable = 'off';
                return;
            else
                obj.view.handles.ModelsColorsTable.Enable = 'on';
            end
            
            if ~isempty(options.rowId)
                obj.view.handles.(ColorTableTag).BackgroundColor(options.rowId, :) = obj.preferences.Colors.(prefStruct)(options.rowId,:);
                if obj.view.handles.ScaleToOneCheckBox.Value == 1
                    obj.view.handles.(ColorTableTag).Data(options.rowId, 1:3) = num2cell(obj.preferences.Colors.(prefStruct)(options.rowId,:));
                else
                    obj.view.handles.(ColorTableTag).Data(options.rowId, 1:3) = num2cell(round(obj.preferences.Colors.(prefStruct)(options.rowId,:)*255));
                end
                return;
            end
            
            % add data to table
            if obj.view.handles.ScaleToOneCheckBox.Value == 1
                % scale to 1
                data = obj.preferences.Colors.(prefStruct)(1:min([255, size(obj.preferences.Colors.(prefStruct), 1)]),:);
            else
                % scale to 255
                data = round(obj.preferences.Colors.(prefStruct)(1:min([255, size(obj.preferences.Colors.(prefStruct), 1)]),:) *255);
            end
                
            data = num2cell(data);
            data(:,4) = {''};
            obj.view.handles.(ColorTableTag).Data = data;
            
            if ~options.updateDataOnly
                % define color styles: the row colors are shown in the Preview column,
                % the value columns get the plain cell color of the current theme
                if ~isempty(obj.preferences.Colors.(prefStruct))
                    obj.view.handles.(ColorTableTag).BackgroundColor = obj.preferences.Colors.(prefStruct);
                end

                removeStyle(obj.view.handles.(ColorTableTag));    % remove current styles

                palette = utils.themeColors(obj.view.gui);
                s1 = uistyle;
                s1.BackgroundColor = palette.tableCell;
                s1.FontColor = palette.text;    % explicit: the auto cell text is not reliably the theme text color
                addStyle(obj.view.handles.(ColorTableTag), s1, 'column', 1:3);
            end
            tableWidth = obj.view.handles.(ColorTableTag).Position(3);
            obj.view.handles.(ColorTableTag).ColumnWidth = {tableWidth/4.5, tableWidth/4.5, tableWidth/4.5, 30};
        end
        
        function TableCellSelectionCallback(obj, event)
            % TABLECELLSELECTIONCALLBACK - callback for selection of a cell in ModelsColorsTable.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.TableCellSelectionCallback(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the table cell selection
            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.TableCellSelectionCallback: triggered\n');
            end
            indices = event.Indices;
            if isempty(indices); return; end
            
            sourceTable = event.Source.Tag;     % get tag to the pressed table
            
            obj.view.handles.(sourceTable).UserData = indices;   % store selected position
            if numel(indices) > 2 || indices(2) < 4; return; end
            
            switch sourceTable
                case 'ModelsColorsTable'
                    figTitle = ['Set color for material ' num2str(indices(1))];
                    c = uisetcolor(obj.preferences.Colors.ModelMaterialColors(indices(1),:), figTitle);
                    if sum(ismember(obj.preferences.Colors.ModelMaterialColors(indices(1),:), c)) == 3; return; end
                    obj.preferences.Colors.ModelMaterialColors(indices(1),:) = c;
                    updateColorTableOptions.rowId = indices(1);
                    obj.updateColorsTables('ModelsColorsTable', updateColorTableOptions);
                    
                case 'LUTColorsTable'
                    figTitle = ['Set color for channel ' num2str(indices(1))];
                    c = uisetcolor(obj.preferences.Colors.LUTColors(indices(1),:), figTitle);
                    if sum(ismember(obj.preferences.Colors.LUTColors(indices(1),:), c)) == 3; return; end
                    obj.preferences.Colors.LUTColors(indices(1),:) = c;
                    
                    updateColorTableOptions.rowId = indices(1);
                    obj.updateColorsTables('LUTColorsTable', updateColorTableOptions);
            end
            %obj.view.handles.(sourceTable).BackgroundColor(indices(1),:) = c;
            
        end
        
        function ModelsColorsTableContextMenuCallbacks(obj, event)
            % MODELSCOLORSTABLECONTEXTMENUCALLBACKS - callbacks for the context menu of ModelsColorsTable.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.ModelsColorsTableContextMenuCallbacks(event)
            %
            % Paramters:
            % event:  a handle to the event structure
            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.ModelsColorsTableContextMenuCallbacks: triggered\n');
            end
            position = obj.view.handles.ModelsColorsTable.UserData;   % position = [rowIndex, columnIndex]
            sourceTag = event.Source.Tag;     % get tag to the pressed table
            
            if isempty(position) && ismember(sourceTag, ...
                    {'InsertColorMenu', 'ReplaceWithRandomColorMenu', 'SwapTwoColorsMenu', ...
                    'DeleteColorsMenu'})
                uialert(obj.view.gui, ...
                    sprintf('!!! Error !!!\n\nPlease select a row in the table first'), 'ModelsColorsTableContextMenuCallbacks Error');
                return;
            end
                
            materialsNumber = numel(obj.mibModel.I{obj.mibModel.id}.labels.materialNames);
            rng('shuffle');     % randomize generator
            updateTableOptions.rowId = [];   % update the whole table
            
            switch sourceTag
                case 'ReverseColormapMenu'
                    obj.preferences.Colors.ModelMaterialColors = obj.preferences.Colors.ModelMaterialColors(end:-1:1,:);
                case 'InsertColorMenu'
                    noColors = size(obj.preferences.Colors.ModelMaterialColors, 1);
                    if position(1) == noColors
                        obj.preferences.Colors.ModelMaterialColors = [obj.preferences.Colors.ModelMaterialColors; rand([1,3])];
                    else
                        obj.preferences.Colors.ModelMaterialColors = ...
                            [obj.preferences.Colors.ModelMaterialColors(1:position(1),:); rand([1,3]); obj.preferences.Colors.ModelMaterialColors(position(1)+1:noColors,:)];
                    end
                case 'ReplaceWithRandomColorMenu'
                    obj.preferences.Colors.ModelMaterialColors(position(1),:) = rand([1,3]);
                    updateTableOptions.rowId = position(1); 
                case 'SwapTwoColorsMenu'
                    options.Type = 'spinner';
                    defAns = struct('Value', 1, ...
                        'Limits', [1 size(obj.preferences.Colors.ModelMaterialColors,1)], ...
                        'Step', 1, 'Round', true);
                    options.mibPath = obj.mibModel.mibPath;
                    newIndex = utils.dlgs.inputSingleDlg(obj.view.gui, ...
                        sprintf('Enter a material number to swap with the selected\nSelected: %d', position(1)), ...
                        defAns, ...
                        'Swap material colors', options);
                    if isempty(newIndex); return; end

                    selectedColor = obj.preferences.Colors.ModelMaterialColors(position(1),:);
                    obj.preferences.Colors.ModelMaterialColors(position(1),:) = obj.preferences.Colors.ModelMaterialColors(newIndex,:);
                    obj.preferences.Colors.ModelMaterialColors(newIndex,:) = selectedColor;
                    updateTableOptions.rowId = [position(1), newIndex];
                case 'DeleteColorsMenu'
                    obj.preferences.Colors.ModelMaterialColors(position(:,1),:) = [];
                case 'ImportFromMatlabMenu'
                    % get list of available variables
                    availableVars = evalin('base', 'whos');
                    idx = ismember({availableVars.class}, {'double', 'single'});
                    if sum(idx) == 0
                        errordlg(sprintf('!!! Error !!!\nNothing to import...'), 'Nothing to import');
                        return;
                    end
                    Vars = {availableVars(idx).name}';   
                    % find index of the I variable if it is present
                    idx2 = find(ismember(Vars, 'colormap')==1);
                    if ~isempty(idx2)
                        Vars{end+1} = idx2;
                    end
                    prompts = {sprintf('Input a variable that contains the colormap\n\nIt should be a matrix [colorNumber, [R,G,B]]:')};
                    defAns = {Vars};
                    title = 'Import colormap';
                    dlgOptions.mibPath = obj.mibModel.mibPath;
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, title, dlgOptions);
                    if isempty(answer); return; end
                    
                    try
                        colormap = evalin('base',answer{1});
                    catch exception
                        errordlg(sprintf('The variable was not found in the Matlab base workspace:\n\n%s', exception.message), 'Misssing variable!', 'modal');
                        return;
                    end
                    
                    errorSwitch = 0;
                    if ndims(colormap) ~= 2; errorSwitch = 1;  end %#ok<ISMAT>
                    if size(colormap,2) ~= 3; errorSwitch = 1;  end
                    if max(max(colormap)) > 255 || min(min(colormap)) < 0; errorSwitch = 1;  end
                    
                    if errorSwitch == 1
                        errordlg(sprintf('Wrong format of the colormap!\n\nThe colormap should be a matrix [colorIndex, [R,G,B]],\nwith R,G,B between 0-1 or 0-255'),'Wrong colormap')
                        return;
                    end
                    if max(max(colormap)) > 1   % convert from 0-255 to 0-1
                        colormap = colormap/255;
                    end
                    obj.preferences.Colors.ModelMaterialColors = colormap;
                case 'ExportToMatlabMenu'
                    title = 'Export colormap';
                    prompt = sprintf('Input a destination variable for export\nA matrix containing the current colormap [colorNumber, [R,G,B]] will be assigned to this variable');
                    %answer = inputdlg(prompt,title,[1 30],{'colormap'},'on');
                    answer = utils.dlgs.inputSingleDlg(obj.view.gui, prompt, 'colormap', title);
                    if isempty(answer); return; end

                    assignin('base', answer, obj.preferences.Colors.ModelMaterialColors);
                    fprintf('Colormap export: created variable %s in the Matlab workspace\n', answer);
                case 'LoadFromFileMenu'
                    [fileName, pathName] = utils.dlgs.mibUiGetFile({'*.cmap';'*.mat';'*.*'}, 'Load colormap',...
                        fileparts(obj.mibModel.I{obj.mibModel.id}.meta('Filename')));
                    if isequal(fileName, 0); return; end
                    
                    load(fullfile(pathName, fileName{1}), 'cmap', '-mat');
                    obj.preferences.Colors.ModelMaterialColors = cmap; 
                case 'SaveToFileMenu'
                    [pathName, fileName] = fileparts(obj.mibModel.I{obj.mibModel.id}.meta('Filename'));
                    [fileName, pathName] = uiputfile('*.cmap', 'Save colormap', fullfile(pathName, [fileName '.cmap']));
                    if fileName == 0; return; end
                    
                    cmap = obj.preferences.Colors.ModelMaterialColors; 
                    save(fullfile(pathName, fileName), 'cmap');
                    fprintf('MIB: the colormap was saved to %s\n', fullfile(pathName, fileName));
            end
            
            % generate random colors when number of colors less than number of
            % materials
            if size(obj.preferences.Colors.ModelMaterialColors, 1) < materialsNumber
                missingColors = materialsNumber - size(obj.preferences.Colors.ModelMaterialColors, 1);
                obj.preferences.Colors.ModelMaterialColors = [obj.preferences.Colors.ModelMaterialColors; rand([missingColors,3])];
            end
            
            obj.updateColorsTables('ModelsColorsTable', updateTableOptions);
        end
        
        function TableCellEditCallback(obj, event)
            % TABLECELLEDITCALLBACK - callback for modification of cells in tables.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.TableCellEditCallback(event)
            %
            % Parameters:
            % event:  a handle to the event structure
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.Preferences.TableCellEditCallback: triggered\n');
            end
            indices = event.Indices;
            newData = event.NewData;
            
            if obj.view.handles.ScaleToOneCheckBox.Value    % range between 0 and 1
                if newData < 0 || newData > 1
                    uialert(obj.view.gui, sprintf('!!! Error !!!\nThe colors should be in range 0-1'), 'Wrong value');
                    obj.view.handles.(event.Source.Tag).Data(indices(1),indices(2)) = num2cell(event.PreviousData);
                    return;
                end
            else    % range between 0 and 255
                if newData < 0 || newData > 255
                    uialert(obj.view.gui, sprintf('!!! Error !!!\nThe colors should be in range 0-255'), 'Wrong value');
                    obj.view.handles.(event.Source.Tag).Data(indices(1),indices(2)) = num2cell(event.PreviousData);
                    return;
                end
            end
            
            if obj.view.handles.ScaleToOneCheckBox.Value    % range between 0 and 1
                scalingFactor = 1;  % divide the provided value by this factor
            else
                scalingFactor = 255; % divide the provided value by this factor
            end
            
            sourceTable = event.Source.Tag;     % get tag to the pressed table
            switch sourceTable
                case 'ModelsColorsTable'
                    if obj.mibModel.I{obj.mibModel.id}.labels.maxMaterials > 255; return; end    % do not update for models larger than 255
                    
                    obj.preferences.Colors.ModelMaterialColors(indices(1), indices(2)) = newData/scalingFactor;
                    options.rowId = indices(1);
                    obj.updateColorsTables('ModelsColorsTable', options);
                case 'LUTColorsTable'
                    obj.preferences.Colors.LUTColors(indices(1), indices(2)) = newData/scalingFactor;
                    options.rowId = indices(1);
                    obj.updateColorsTables('LUTColorsTable', options);
            end
            
        end
        
        function ExternalDirSelect(obj, event)
            % EXTERNALDIRSELECT - callback for press of select directory button.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.ExternalDirSelect(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the button press
            %
            % **Example** - handle directory selection:
            %
            %   .. code-block:: matlab
            %
            %      obj.ExternalDirSelect(event);
        
            % Java: the folder is validated and resolved (the "bin" folder or a
            % vendor folder with one Java inside are accepted), see utils.JavaSetup
            if strcmp(event.Source.Tag, 'JavaDirSelectBtn')
                javaInfo = utils.JavaSetup.browseForJava(obj.view.gui, obj.mibModel.mibPath, ...
                    char(obj.preferences.ExternalDirs.JavaInstallationPath));
                drawnow;
                figure(obj.view.gui);
                if isempty(javaInfo); return; end
                obj.preferences.ExternalDirs.JavaInstallationPath = javaInfo.home;
                obj.view.handles.JavaInstallationPath.Value = javaInfo.home;
                return;
            end

            switch event.Source.Tag
                case 'FijiDirSelectBtn'
                    field_name = 'FijiInstallationPath';
                case 'OmeroDirSelectBtn'
                    field_name = 'OmeroInstallationPath';
                case 'ImarisDirSelectBtn'
                    field_name = 'ImarisInstallationPath';
                case 'BM3DDirSelectBtn'
                    field_name = 'bm3dInstallationPath';
                case 'BM4DDirSelectBtn'
                    field_name = 'bm4dInstallationPath';
                case 'MemoizerDirSelectBtn'
                    field_name = 'BioFormatsMemoizerMemoDir';
                case 'DeepMIBDirSelectBtn'
                    field_name = 'DeepMIBDir';
                case 'PythonDirSelectBtn'
                    field_name = 'PythonInstallationPath';
            end
            
            if strcmp(field_name, 'PythonInstallationPath')
                if isempty(obj.preferences.ExternalDirs.(field_name))
                    defaultFilename = 'python.exe';
                else
                    defaultFilename = obj.preferences.ExternalDirs.(field_name);
                end
                [file, path] = utils.dlgs.mibUiGetFile({'*.exe','Executables (*.exe)'; ...
                    '*.*',  'All Files (*.*)'},...
                    'Select python.exe', defaultFilename);
                if isequal(file, 0); return; end
                folder_name = fullfile(path, file{1});
            else
                folder_name = uigetdir(obj.preferences.ExternalDirs.(field_name), 'Select directory');
                if folder_name==0; return; end
            end
            
            % the two following commands are fix of sending the DeepMIB
            % window behind main MIB window
            drawnow;
            figure(obj.view.gui);
            
            if strcmp(field_name, 'bm3dInstallationPath') || strcmp(field_name, 'bm4dInstallationPath')
                answer = uiconfirm(obj.view.gui, ...
                    sprintf('!!! Warning !!!\n\nPlease note that any unauthorized use of BM3D and BM4D filters for industrial or profit-oriented activities is expressively prohibited!'), ...
                    'License warning', 'Options', {'Acknowledge', 'Cancel'}, 'Icon', 'warning', 'DefaultOption', 1);
                if strcmp(answer, 'Cancel')
                    folder_name = '';
                end
            end
            obj.preferences.ExternalDirs.(field_name) = folder_name;
            obj.view.handles.(field_name).Value = folder_name;
        end
        
        function ExternalDirPathChange(obj, event)
            % EXTERNALDIRPATHCHANGE - update of external directories.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.ExternalDirPathChange(event)
            %
            % Input Arguments:
            %   - **event** - [struct] event data from the directory path field
            %
            % **Example** - validate and update directory path:
            %
            %   .. code-block:: matlab
            %
            %      obj.ExternalDirPathChange(event);

            % Java: validate and resolve to the Java folder, see utils.JavaSetup.inspectFolder
            if strcmp(event.Source.Tag, 'JavaInstallationPath')
                typedPath = strtrim(obj.view.handles.JavaInstallationPath.Value);
                if isempty(typedPath)
                    obj.preferences.ExternalDirs.JavaInstallationPath = [];
                    return;
                end
                javaInfo = utils.JavaSetup.inspectFolder(typedPath);
                if isempty(javaInfo)
                    uialert(obj.view.gui, utils.JavaSetup.notJavaMessage(typedPath), 'This is not a Java folder');
                    obj.view.handles.JavaInstallationPath.Value = char(obj.preferences.ExternalDirs.JavaInstallationPath);
                    return;
                end
                obj.preferences.ExternalDirs.JavaInstallationPath = javaInfo.home;
                obj.view.handles.JavaInstallationPath.Value = javaInfo.home;
                return;
            end

            if ~isempty(obj.view.handles.(event.Source.Tag).Value)
                if ~ismember(exist(obj.view.handles.(event.Source.Tag).Value), [2, 7]) %#ok<EXIST> % keep exists function here, for correct work with /Applications/Fiji.app 
                    uialert(obj.view.gui, ...
                        sprintf('!!! Warning !!!\n\nThe directory (filename)\n%s\nis missing', obj.view.handles.(event.Source.Tag).Value),...
                        'Wrong directory/filename');
                    obj.view.handles.(event.Source.Tag).Value = char(obj.preferences.ExternalDirs.(event.Source.Tag));
                else
                    if strcmp(event.Source.Tag, 'bm3dInstallationPath') || strcmp(event.Source.Tag, 'bm4dInstallationPath')
                        answer = uiconfirm(obj.view.gui, ...
                            sprintf('!!! Warning !!!\n\nPlease note that any unauthorized use of BM3D and BM4D filters for industrial or profit-oriented activities is expressively prohibited!'), ...
                            'License warning', 'Options', {'Acknowledge', 'Cancel'}, 'Icon', 'warning', 'DefaultOption', 1);
                        if strcmp(answer, 'Cancel')
                            obj.view.handles.(event.Source.Tag).Value = '';
                        end
                    end
                    obj.preferences.ExternalDirs.(event.Source.Tag) = obj.view.handles.(event.Source.Tag).Value;
                end
            else
                obj.preferences.ExternalDirs.(event.Source.Tag) = [];
            end
        end

        function JavaFindBtnPushed(obj)
            % JAVAFINDBTNPUSHED - search for installed Java and put the chosen folder into the Java field.
            %
            % Opens ``utils.JavaSetup.selectJava`` (list of the Java installations
            % found in the usual folders, **Download Java**, manual selection).
            % Nothing is written to MATLAB here: that happens with
            % **Configure Java...** or, for a changed path, on Apply/OK.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.JavaFindBtnPushed()
            %
            javaInfo = utils.JavaSetup.selectJava(obj.view.gui, obj.mibModel.mibPath);
            drawnow;
            figure(obj.view.gui);
            if isempty(javaInfo); return; end
            obj.preferences.ExternalDirs.JavaInstallationPath = javaInfo.home;
            obj.view.handles.JavaInstallationPath.Value = javaInfo.home;
        end

        function JavaConfigureBtnPushed(obj)
            % JAVACONFIGUREBTNPUSHED - connect MATLAB / MATLAB Runtime to the Java in the Java field.
            %
            % With an empty field the search dialog (``JavaFindBtnPushed``) is shown
            % first. The folder is written with ``utils.JavaSetup.apply`` (``jenv`` in
            % MATLAB, ``matlab_jenv`` of MATLAB Runtime in the standalone) and, on
            % success, also stored in the MIB preferences right away, so it is kept
            % even when the Preferences dialog is then closed with Cancel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.JavaConfigureBtnPushed()
            %
            if isempty(obj.preferences.ExternalDirs.JavaInstallationPath)
                obj.JavaFindBtnPushed();
                if isempty(obj.preferences.ExternalDirs.JavaInstallationPath); return; end
            end
            javaPath = char(obj.preferences.ExternalDirs.JavaInstallationPath);
            status = utils.JavaSetup.apply(obj.view.gui, javaPath, obj.mibModel.mibPath);
            drawnow;
            figure(obj.view.gui);
            if ~status; return; end
            obj.javaAppliedPath = javaPath;
            obj.mibModel.preferences.ExternalDirs.JavaInstallationPath = javaPath;
        end

        function updateKeyShortcut(obj, eventdata)
            % UPDATEKEYSHORTCUT - callback for change of key shortcuts in the table.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateKeyShortcut(eventdata)
            %
            % Input Arguments:
            %   - **eventdata** - [struct] event data from the shortcuts table cell edit
            %
            % **Example** - update a keyboard shortcut:
            %
            %   .. code-block:: matlab
            %
            %      obj.updateKeyShortcut(eventdata);
            
            index = eventdata.Indices(1);
            data = obj.view.handles.shortcutsTable.Data;    % have to take the whole table as looking for duplicates
            
            % make it impossible to change Shift action for some actions
            if ismember(data(index, 2), obj.preferences.KeyShortcuts.Action(6:16))
                data(index, 4) = num2cell(false);
                obj.view.handles.shortcutsTable.Data = data;
            end
            if ~isempty(data{index, 3})
                % check for duplicates
                KeyShortcutsLocal.Key = data(:, 3)';
                KeyShortcutsLocal.shift = cell2mat(data(:, 4))';
                KeyShortcutsLocal.control = cell2mat(data(:, 5))';
                KeyShortcutsLocal.alt = cell2mat(data(:, 6))';
                
                shiftSw = data{index, 4};
                controlSw = data{index, 5};
                altSw = data{index, 6};
                
                ActionId = ismember(KeyShortcutsLocal.Key, data(index, 3)) & ismember(KeyShortcutsLocal.control, controlSw) & ...
                    ismember(KeyShortcutsLocal.shift, shiftSw) & ismember(KeyShortcutsLocal.alt, altSw);
                ActionId = find(ActionId > 0);    % action id is the index of the action, handles.preferences.KeyShortcuts.Action(ActionId)
                if numel(ActionId) > 1
                    actionId = ActionId(ActionId ~= index);
                    
                    button = uiconfirm(obj.view.gui, ...
                        sprintf('!!! Warning !!!\n\nA duplicate entry was found in the list of shortcuts!\nThe keystroke "%s" is already assigned to action number "%d"\n"%s"\n\nContinue anyway?', data{index, 3}, actionId(1), data{actionId(1), 2}),...
                        'Duplicate found!',...
                        'Options', {'Continue','Cancel'},'DefaultOption', 2, ...
                        'Icon','warning');
                    
                    if strcmp(button, 'Cancel')
                        data(index, eventdata.Indices(2)) = {eventdata.PreviousData};
                    else
                        obj.duplicateEntries = [obj.duplicateEntries ActionId];     % add index of a duplicate entry
                        obj.duplicateEntries = unique(obj.duplicateEntries);     % add index of a duplicate entry
                        
                        s = uistyle('BackgroundColor','red');
                        addStyle(obj.view.handles.shortcutsTable, s, 'cell', [ActionId', ones([numel(ActionId) 1])]);
                    end
                else
                    obj.duplicateEntries(obj.duplicateEntries==ActionId) = [];  % remove possible diplicate
                    s = uistyle('BackgroundColor', 'green');
                    if numel(obj.duplicateEntries) < 2
                        obj.duplicateEntries =[];
                        removeStyle(obj.view.handles.shortcutsTable);
                        addStyle(obj.view.handles.shortcutsTable, s, 'column', 1);
                    else
                        addStyle(obj.view.handles.shortcutsTable, s, 'cell', [index, 1]);
                    end
                end
            else
                obj.duplicateEntries(obj.duplicateEntries == index) = [];  % remove possible diplicate
                s = uistyle('BackgroundColor', 'green');
                if numel(obj.duplicateEntries) < 2
                    obj.duplicateEntries =[];
                    removeStyle(obj.view.handles.shortcutsTable);
                    addStyle(obj.view.handles.shortcutsTable, s, 'column', 1);
                else
                    addStyle(obj.view.handles.shortcutsTable, s, 'cell', [index, 1]);
                end
            end
            obj.view.handles.shortcutsTable.Data = data;
        end
        
        % ------------------------------------------------------------------
        % % Additional functions and callbacks
        function Calculate(obj)
            % CALCULATE - start main calculation of the plugin.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.Calculate()
            %
            % **Example** - trigger calculation:
            %
            %   .. code-block:: matlab
            %
            %      obj.Calculate();
            
            % redraw the image if needed
            notify(obj.mibModel, 'plotImage');
            
        end
        
        
    end
end

% =====================================================================
function setColorButton(buttonHandle, color)
% SETCOLORBUTTON - paint a color-picker button with the chosen color and a
% readable text on it: black on light colors, white on dark ones, independent of
% the light/dark theme (the auto font is near-white in the dark theme and
% unreadable on the usual bright layer colors). The threshold 0.179 is the
% relative luminance at which black and white text have equal WCAG contrast.
buttonHandle.BackgroundColor = color;
linearColor = color;
isLowValue = linearColor <= 0.03928;
linearColor(isLowValue) = linearColor(isLowValue) / 12.92;
linearColor(~isLowValue) = ((linearColor(~isLowValue) + 0.055) / 1.055) .^ 2.4;
if sum([0.2126 0.7152 0.0722] .* linearColor) > 0.179
    buttonHandle.FontColor = [0 0 0];
else
    buttonHandle.FontColor = [1 1 1];
end
end

% =====================================================================
function preferencesThemeChanged(obj, hFig)
% PREFERENCESTHEMECHANGED - ThemeChangedFcn of the Preferences window: remap the
% standard dialog colors and redraw the color tables, whose value cells are painted
% with a uistyle in the color of the current theme (utils.themeColors tableCell).
utils.applyThemeColors(hFig);
obj.updateColorsTables('ModelsColorsTable');
obj.updateColorsTables('LUTColorsTable');
end
