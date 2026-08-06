classdef GuiTutorial < handle
% GuiTutorial < handle
% Tutorial plugin controller demonstrating the MIB3 plugin architecture.
%
% This plugin shows how to build a GUI plugin for MIB3, covering:
%   - Controller class structure and constructor pattern
%   - Connecting to the AppDesigner view via core.ChildView
%   - Reading widget values (Spinners, DropDowns, RadioButtons)
%   - Using getData4D / setData4D for image access
%   - Showing error dialogs, warnings, and progress dialogs
%   - Firing MibModel events to update the main MIB window
%
% The plugin provides four operations on the current dataset:
%   Crop    - crop to a specified XY rectangle
%   Resize  - resize to new XY dimensions
%   Convert - convert image class between uint8 and uint16
%   Invert  - invert a selected colour channel
%
% @b Usage:
% @code
%   controller = plugins.Tutorials.GuiTutorial.GuiTutorial(mibModel);
% @endcode
%
% @b See @b also: core.ChildView, instruction.md in this folder

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% URL: https://mib.helsinki.fi
% Date: 01.07.2025

    properties
        mibModel            % handle to MibModel - the central application state
        view                % handle to the AppDesigner view (core.ChildView wrapper)
        listener            % cell array of event listeners - kept so they can be deleted on close
        childControllers    = {}    % handles to open child controllers (e.g. ResampleDataset)
        childControllersIds = {}    % class names matching childControllers{} - used by utils.startController
    end

    events
        % CloseEvent is fired by closeWindow() after the GUI is destroyed.
        % utils.startController wires a listener to this event so the parent
        % controller can remove this plugin from its childControllers list.
        CloseEvent
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
        % ViewListner_Callback2  React to MibModel events.
        %
        % This static method is used as an addlistener callback.  It is
        % static so that the listener can hold a weak reference to obj
        % without preventing garbage collection.
        %
        % The switch dispatches to the appropriate update method.  Add
        % more cases here if the plugin needs to react to other events
        % (e.g. 'SliceChanged', 'SegmentationLayerChanged').
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    % A new dataset was loaded or MIB performed an operation
                    % that may have changed the image dimensions or class.
                    % Re-read the dataset state and refresh the GUI.
                    obj.updateWidgets();
            end
        end
    end

    methods

        % =====================================================================
        function obj = GuiTutorial(mibModel, varargin)
        % GuiTutorial Constructor - initialises the plugin controller and GUI.
        %
        % Called by utils.startController as:  GuiTutorial(parentObj.mibModel)
        % The second argument (varargin) is unused here but must be accepted
        % so the constructor is compatible with batch-mode callers that pass
        % a BatchOpt struct as the second argument.
        %
        % Parameters:
        % mibModel: handle to the MibModel instance
        % varargin: [@em optional] unused; reserved for future batch options

            obj.mibModel = mibModel;

            % core.ChildView instantiates the AppDesigner app GuiTutorialGUI(obj),
            % calls its startupFcn(app, obj) to store the controller reference,
            % then collects all named UI component properties into obj.view.handles
            % so the controller can address them as obj.view.handles.<propertyName>.
            obj.view = core.ChildView(obj, 'GuiTutorialGUI');

            % Place the plugin window to the left of the main MIB app window
            % so it does not overlap the image canvas.
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            % Set the window title-bar icon.  Use a plugin-specific 16 px icon
            % when present, otherwise fall back to the shared MIB application icon.
            pluginDir   = fileparts(mfilename('fullpath'));
            localIcon   = fullfile(pluginDir, 'icon_16px.png');
            fallbackIcon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
            if isfile(localIcon)
                obj.view.gui.Icon = localIcon;
            elseif isfile(fallbackIcon)
                obj.view.gui.Icon = fallbackIcon;
            end

            % Match the application font to the global MIB font preference.
            % Only update if the font actually differs to avoid unnecessary redraws.
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.infoText1.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.infoText1.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % Wire the window X-close button to our closeWindow() method.
            % Without this, closing the window via the OS title bar would
            % destroy the figure but leave the controller alive (and the
            % listener wired by utils.startController would never fire).
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            % Populate the Convert dropdown with the two supported output classes.
            % This is done once in the constructor; updateWidgets never changes it.
            obj.view.handles.convertDropdown.Items = {'uint8', 'uint16'};

            % Default to Crop mode so widgets are in a well-defined state
            % before updateWidgets() runs.
            obj.view.handles.cropRadio.Value = true;

            % Fill all data-dependent widgets from the current dataset.
            obj.updateWidgets();

            % Subscribe to MibModel events so the plugin stays in sync when
            % the user loads a new file or another tool changes the dataset.
            % Store the listener handles so closeWindow() can delete them,
            % preventing callbacks from firing after the window is gone.
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % =====================================================================
        function closeWindow(obj)
        % closeWindow  Close the plugin window and release all resources.
        %
        % Call order matters:
        %  1. Close child controllers first - they may reference this window.
        %  2. Clear CloseRequestFcn before deleting the figure to prevent
        %     a recursive call (deleting the figure would re-trigger the fcn).
        %  3. Delete event listeners so they cannot fire after deletion.
        %  4. Fire CloseEvent last - utils.purgeChildController is wired to
        %     this and removes this controller from the parent's list.

            % Reverse iteration avoids index-shift bugs when a child's own
            % CloseEvent modifies obj.childControllers during teardown.
            for i = numel(obj.childControllers):-1:1
                child = obj.childControllers{i};
                if isa(child, 'handle') && isvalid(child)
                    child.closeWindow();
                end
            end
            obj.childControllers    = {};
            obj.childControllersIds = {};

            if isvalid(obj.view.gui)
                obj.view.gui.CloseRequestFcn = '';  % prevent recursive close
                delete(obj.view.gui);
            end

            % Delete all MibModel listeners to prevent memory leaks and
            % stale callbacks running after the window is gone.
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end

            % Signal to utils.startController's lifecycle wiring that this
            % controller has finished closing.
            notify(obj, 'CloseEvent');
        end

        % =====================================================================
        function updateWidgets(obj)
        % updateWidgets  Refresh all GUI widgets from the current dataset state.
        %
        % Called from the constructor and from ViewListner_Callback2 whenever
        % MibModel fires UpdateGuiWidgets or NewDataset.

            id = obj.mibModel.getActiveId();

            % blockModeSwitch = 0 → return full dataset dimensions, ignoring
            % any active viewport crop.  orient 3 = native XY orientation.
            options.blockModeSwitch = 0;
            [height, width, depth, colors, time] = ...
                obj.mibModel.I{id}.getDatasetDimensions('image', 3, options);

            % Show the current dataset dimensions as a read-only info label
            % (Height × Width × Depth × Colors × Time).
            obj.view.handles.infoText2.Text = ...
                sprintf('%d x %d x %d x %d x %d', height, width, depth, colors, time);

            % Reset the crop/resize spinners to the full dataset extents so
            % the user sees sensible defaults whenever a new dataset is loaded.
            obj.view.handles.xMinEdit.Value    = 1;
            obj.view.handles.yMinEdit.Value    = 1;
            obj.view.handles.widthEdit.Value   = width;
            obj.view.handles.heightEdit.Value  = height;

            % Build the colour channel dropdown items dynamically from the
            % actual number of channels in the loaded dataset.
            colorsList = arrayfun(@(i) sprintf('Channel %d', i), 1:colors, 'UniformOutput', false);
            obj.view.handles.colorDropdown.Items = colorsList;
            if colors >= 1
                obj.view.handles.colorDropdown.Value = colorsList{1};
            end

            % Sync enable/disable state of all widgets for the currently
            % selected operation radio button.
            obj.buttonGroup_Callback();
        end

        % =====================================================================
        function helpBtn_Callback(obj)
        % helpBtn_Callback  Open the MIB tutorials page in the browser.
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'plugins', 'tutorials', 'gui-tutorial.html');
            if isfile(helpFilPath)
                web(helpFilPath, '-browser');
            else
                web('http://mib.helsinki.fi/help/main3/user-interface/plugins/tutorials/gui-tutorial.html', '-browser');
            end
        end

        % =====================================================================
        function buttonGroup_Callback(obj)
        % buttonGroup_Callback  Enable/disable widgets based on the selected mode.
        %
        % Called both from the mlapp SelectionChangedFcn callback and directly
        % from updateWidgets(), so it requires no event argument.
        %
        % Each operation only needs a subset of the available widgets:
        %   Crop    - XY position (xMin, yMin) and size (width, height)
        %   Resize  - target size (width, height)
        %   Convert - target class (convertDropdown)
        %   Invert  - colour channel (colorDropdown)

            % Start from all widgets enabled, then selectively disable those
            % that are irrelevant for the active operation.
            obj.view.handles.xMinEdit.Enable      = 'on';
            obj.view.handles.yMinEdit.Enable      = 'on';
            obj.view.handles.widthEdit.Enable     = 'on';
            obj.view.handles.heightEdit.Enable    = 'on';
            obj.view.handles.convertDropdown.Enable  = 'on';
            obj.view.handles.colorDropdown.Enable    = 'on';

            if obj.view.handles.cropRadio.Value
                % Crop needs x/y origin and width/height; class and channel
                % are irrelevant - disable them to guide the user.
                obj.view.handles.convertDropdown.Enable  = 'off';
                obj.view.handles.colorDropdown.Enable    = 'off';
            elseif obj.view.handles.resizeRadio.Value
                % Resize needs the target width/height only; the XY origin
                % and class/channel are not used.
                obj.view.handles.xMinEdit.Enable      = 'off';
                obj.view.handles.yMinEdit.Enable      = 'off';
                obj.view.handles.convertDropdown.Enable  = 'off';
                obj.view.handles.colorDropdown.Enable    = 'off';
            elseif obj.view.handles.convertRadio.Value
                % Convert needs only the target class; spatial dimensions
                % and channel selection are irrelevant.
                obj.view.handles.xMinEdit.Enable      = 'off';
                obj.view.handles.yMinEdit.Enable      = 'off';
                obj.view.handles.widthEdit.Enable     = 'off';
                obj.view.handles.heightEdit.Enable    = 'off';
                obj.view.handles.colorDropdown.Enable    = 'off';
            elseif obj.view.handles.invertRadio.Value
                % Invert needs only the channel to invert; spatial and
                % class controls are irrelevant.
                obj.view.handles.xMinEdit.Enable      = 'off';
                obj.view.handles.yMinEdit.Enable      = 'off';
                obj.view.handles.widthEdit.Enable     = 'off';
                obj.view.handles.heightEdit.Enable    = 'off';
                obj.view.handles.convertDropdown.Enable  = 'off';
            end
        end

        % =====================================================================
        function continueBtn_Callback(obj)
        % continueBtn_Callback  Dispatch to the active operation.
        %
        % Reads the radio button group to determine which operation is
        % selected, then calls the corresponding private method.
            if obj.view.handles.cropRadio.Value
                obj.cropDataset();
            elseif obj.view.handles.resizeRadio.Value
                obj.resizeDataset();
            elseif obj.view.handles.convertRadio.Value
                obj.convertDataset();
            elseif obj.view.handles.invertRadio.Value
                obj.invertDataset();
            end
        end

        % =====================================================================
        function cropDataset(obj)
        % cropDataset  Crop the current dataset to the specified XY rectangle.
        %
        % Reads the four spinner values (xMin, yMin, width, height), validates
        % them against the actual dataset dimensions, then delegates to
        % MibDataset.cropDataset() which handles all layers (image, labels,
        % mask, selection) and updates the bounding box in one call.

            id      = obj.mibModel.getActiveId();
            x1      = obj.view.handles.xMinEdit.Value;
            y1      = obj.view.handles.yMinEdit.Value;
            width1  = obj.view.handles.widthEdit.Value;
            height1 = obj.view.handles.heightEdit.Value;

            % Get the full dataset extent to validate the requested rectangle.
            % blockModeSwitch=0 ensures we see the complete image, not just
            % the currently visible viewport.
            options.blockModeSwitch = 0;
            [height, width, depth, ~, time] = ...
                obj.mibModel.I{id}.getDatasetDimensions('image', 3, options);

            % Reject requests that fall outside the image boundaries.
            if x1 < 1 || y1 < 1 || x1+width1-1 > width || y1+height1-1 > height
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'Please check dimensions for cropping!', 'Wrong dimensions');
                return;
            end

            % cropF format: [x1, y1, dx, dy, z1, dz, t1, dt]
            % Crop the full Z and T extents (z1=1, dz=depth, t1=1, dt=time).
            cropF = [x1, y1, width1, height1, 1, depth, 1, time];
            cropOpts.showWaitbar = true;
            cropOpts.UIFigure    = obj.view.gui;  % progress dialog parent
            result = obj.mibModel.I{id}.cropDataset(cropF, cropOpts);

            if result
                % Notify MIB that the dataset dimensions have changed so the
                % main image canvas and toolbar are fully refreshed.
                notify(obj.mibModel, 'NewDataset');
                notify(obj.mibModel, 'ShowImage');
            end
        end

        % =====================================================================
        function resizeDataset(obj)
        % resizeDataset  Resize the current dataset to new XY dimensions.
        %
        % setData4D cannot resize a dataset because it assigns into a fixed-
        % size pre-allocated array.  Instead, we open controllers.ResampleDataset
        % in batch mode via utils.startController.  ResampleDataset handles
        % all layers (image, labels, mask, selection) and fires NewDataset +
        % ShowImage on completion.
        %
        % The BatchOpt struct below matches the fields that ResampleDataset
        % reads when running in batch (non-interactive) mode.

            width1  = obj.view.handles.widthEdit.Value;
            height1 = obj.view.handles.heightEdit.Value;

            if width1 < 1 || height1 < 1
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    'Please check dimensions for resizing!', 'Wrong dimensions');
                return;
            end

            % Build the batch options struct for ResampleDataset.
            % 'Dimensions' mode sets an absolute pixel target size.
            % DimensionX/Y are strings because ResampleDataset parses them
            % from a text field in its own GUI.
            BatchOpt.ResamplingMode = {'Dimensions'};
            BatchOpt.DimensionX     = num2str(width1);
            BatchOpt.DimensionY     = num2str(height1);

            % utils.startController checks whether ResampleDataset is already
            % open (re-focuses it) or creates it fresh.  Passing BatchOpt as
            % the third argument triggers silent batch execution instead of
            % showing the ResampleDataset GUI.
            utils.startController(obj, 'controllers.ResampleDataset', [], BatchOpt);
        end

        % =====================================================================
        function convertDataset(obj)
        % convertDataset  Convert the image data class (uint8 <-> uint16).
        %
        % Pixel values are scaled linearly so that the full dynamic range
        % of the source class maps to the full dynamic range of the target
        % class (e.g. 0-255 → 0-65535).
        %
        % Important: setData4D cannot be used for a type conversion because
        % MibImage.setData writes into the existing typed container via
        % indexed assignment (obj.data(...) = dataset), which silently
        % casts the incoming array back to the container's original type.
        % We therefore write directly to MibImage.data and update the
        % associated metadata properties (dataClass, maxInt, viewPort).

            id        = obj.mibModel.getActiveId();
            convertTo = obj.view.handles.convertDropdown.Value;  % DropDown returns a string

            % Fetch the full 4-D volume.  col_channel=[] means all channels.
            % blockModeSwitch=0 ignores any active viewport crop.
            options.blockModeSwitch = 0;
            img       = obj.mibModel.getData4D('image', [], [], options);
            classFrom = class(img{1});

            if strcmp(classFrom, convertTo)
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon       = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                    sprintf('The current dataset is already %s class!', convertTo), ...
                    {}, {}, 'No conversion needed', dlgOpt);
                return;
            end

            waitbarHandle = uiprogressdlg(obj.view.gui, ...
                'Message', 'Converting dataset...', 'Title', 'Convert', 'Value', 0);

            % Scale pixel values to fill the target type's full dynamic range.
            % coef = intmax(target) / intmax(source) preserves relative brightness.
            if strcmp(convertTo, 'uint16')
                coef   = double(intmax('uint16')) / double(intmax(class(img{1})));
                img{1} = uint16(double(img{1}) * coef);
            else
                coef   = double(intmax('uint8')) / double(intmax(class(img{1})));
                img{1} = uint8(double(img{1}) * coef);
            end
            waitbarHandle.Value = 0.5;

            % Directly replace the data container.  setData casts to the
            % existing type via indexed assignment, so we bypass it entirely
            % and write the new typed array straight into MibImage.data.
            % After replacing the data we must update three interdependent
            % metadata properties on MibImage:
            %   dataClass  - the MATLAB class string ('uint8', 'uint16', …)
            %   maxInt     - the maximum displayable integer for this class
            %   viewPort   - per-channel display range [min, max, gamma]
            imageObj           = obj.mibModel.I{id}.image;
            imageObj.data   = img{1};
            imageObj.dataClass = class(img{1});
            imageObj.maxInt    = double(intmax(class(img{1})));
            imageObj.getDefaultViewPort();  % resets viewPort.max to new maxInt
            imageObj.updateActionLog(sprintf('Converted from %s to %s', classFrom, class(img{1})));

            waitbarHandle.Value = 1;
            % UpdateGuiWidgets refreshes the MIB toolbar (e.g. class label).
            % ShowImage redraws the image canvas with the new display range.
            notify(obj.mibModel, 'UpdateGuiWidgets');
            notify(obj.mibModel, 'ShowImage');
            close(waitbarHandle);
        end

        % =====================================================================
        function invertDataset(obj)
        % invertDataset  Invert a single colour channel of the dataset.
        %
        % Processes one 2-D slice at a time (getData2D/setData2D) rather than
        % loading the whole 4-D volume, which minimises peak memory usage for
        % large datasets.
        %
        % The inversion formula is:  result = intmax(class) - pixel_value
        % which maps 0→max, max→0 while preserving the data type.

            id       = obj.mibModel.getActiveId();
            colChStr = obj.view.handles.colorDropdown.Value;  % DropDown: returns the string
            % Convert the selected item string to a channel index so we can
            % pass it as col_channel to getData2D/setData2D.
            colCh    = find(strcmp(obj.view.handles.colorDropdown.Items, colChStr), 1);

            % Empty options struct - no ROI, no viewport crop.
            % Passing roiId in options as [] would activate "currently selected ROI"
            % mode, which fails when no ROI exists.  Omitting roiId disables
            % ROI mode and processes the full image.
            options = struct();
            [~, ~, depth, ~, time] = obj.mibModel.I{id}.getDatasetDimensions('image');

            % Back up the full 3-D volume before modifying it so the user
            % can undo via Edit → Undo.  Skip backup for time-series datasets
            % to avoid storing an excessively large undo snapshot.
            if time == 1
                obj.mibModel.backup('image', 1, struct());
            end

            waitbarHandle = uiprogressdlg(obj.view.gui, ...
                'Message', 'Inverting dataset...', 'Title', 'Invert', 'Value', 0);

            frameIdx    = 1;
            totalFrames = depth * time;
            for t = 1:time
                for z = 1:depth
                    % getData2D returns a cell array.  When ROI mode is active
                    % the cell contains one entry per ROI region; here it always
                    % has one entry (the full slice for the selected channel).
                    img    = obj.mibModel.getData2D('image', z, [], colCh, options);
                    maxInt = intmax(class(img{1}));
                    for roiIdx = 1:numel(img)
                        img{roiIdx} = maxInt - img{roiIdx};
                    end
                    % setData2D argument order: (dataset, type, slice_no, orient, col_channel, options)
                    % orient=[] means "use current orientation".
                    obj.mibModel.setData2D(img, 'image', z, [], colCh, options);
                    waitbarHandle.Value = frameIdx / totalFrames;
                    frameIdx = frameIdx + 1;
                end
            end

            % updateActionLog lives on MibImage (I{id}.image), not MibDataset (I{id}).
            obj.mibModel.I{id}.image.updateActionLog('Invert image');
            notify(obj.mibModel, 'ShowImage');
            close(waitbarHandle);
        end

    end  % methods
end  %