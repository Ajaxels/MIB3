classdef GuiTutorialBatch < handle
% GuiTutorialBatch < handle
% Tutorial plugin extending GuiTutorial with full batch-processing support.
%
% This plugin builds on GuiTutorial (which teaches basic GUI plugin structure)
% by adding the BatchOpt infrastructure needed for:
%   - Macro recording and replay (Edit → Batch Processing)
%   - Headless / scriptable execution without a GUI
%   - Parameter discovery for the Batch Processing GUI
%
% It is recommended to read GuiTutorial.m and DemoPlugin.m before this file:
%   GuiTutorial   - teaches the four image operations (Crop/Resize/Convert/Invert)
%   DemoPlugin    - teaches the BatchOpt system, three calling modes, and macro recording
%   This file     - combines both: all four operations plus full BatchOpt support
%
% KEY DIFFERENCES FROM GuiTutorial
% ─────────────────────────────────
%   1. A BatchOpt property stores every tunable parameter.  Field names match
%      widget Tags so the two shared sync utilities can auto-populate the GUI
%      and harvest changed values without per-widget code.
%   2. The constructor accepts a BatchOpt struct as its 3rd argument for
%      headless/batch execution (no GUI needed).
%   3. Every operation method reads its inputs from BatchOpt (not from
%      widget handles), making operations reusable from all three call modes.
%   4. Each operation returns a boolean success flag so Calculate() can
%      decide whether to register the run in the macro recorder.
%
% THREE CALLING MODES
% ────────────────────
%   Interactive (normal)  - called from the Plugins ribbon; GUI is shown
%   Headless/batch        - 3rd constructor arg is a BatchOpt struct
%   Query                 - 3rd constructor arg is NaN; returns defaults
%
% @b Usage:
% @code
%   % Interactive (from the ribbon):
%   utils.startController(parentObj, 'plugins.Tutorials.GuiTutorialBatch.GuiTutorialBatch');
%
%   % Headless batch:
%   BatchOpt.OperationButtonGroup = {'cropRadio'};
%   BatchOpt.xMinEdit   = {10, [1 50000], 'on'};
%   BatchOpt.widthEdit  = {200, [1 50000], 'on'};
%   BatchOpt.yMinEdit   = {10, [1 50000], 'on'};
%   BatchOpt.heightEdit = {200, [1 50000], 'on'};
%   GuiTutorialBatch(mibModel, parentObj, BatchOpt);
%
%   % Query mode (get default BatchOpt without running):
%   GuiTutorialBatch(mibModel, parentObj, NaN);
% @endcode
%
% @b See @b also:
%   GuiTutorial.m, DemoPlugin/README.md, instruction.md, README.md

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% URL: https://mib.helsinki.fi
% Date: 01.07.2025

    properties
        mibModel
        % Handle to the central MibModel instance.
        view
        % core.ChildView wrapper for the AppDesigner GUI, or [] in batch mode.
        %   obj.view.gui           - uifigure handle
        %   obj.view.handles.<Tag> - individual widget handles
        listener
        % Cell array of event listener handles; deleted in closeWindow().
        BatchOpt
        % Parameter struct compatible with the MIB batch-processing system.
        %
        % IMPORTANT: every field name must EXACTLY match the Tag of the
        % corresponding AppDesigner widget (case-sensitive).  The two shared
        % utilities find widgets by Tag so a mismatch silently skips the widget.
        %
        % Supported widget types and their BatchOpt encoding:
        %
        %  Widget type     Field format
        %  --------------- -----------------------------------------------
        %  uicheckbox      logical (true / false)
        %  uidropdown      {selectedString, {'opt1','opt2',...}}
        %                    element 2 is optional; omit to keep existing items
        %  uibuttongroup   {selectedRadioTag, {'Tag1','Tag2',...}}
        %                    element 2 is documentation only; not pushed to GUI
        %  uispinner       {value, [min max], 'on'/'off'}
        %                    'on' = integer-only, 'off' = allow fractional values
        %
        childControllers    = {}
        % Handles to child controllers opened by this plugin (e.g. ResampleDataset).
        % Required by utils.startController / utils.purgeChildController.
        childControllersIds = {}
        % Class-name strings matching childControllers{}, used by utils.startController.
    end

    events
        % CloseEvent - fired by closeWindow() after the GUI is destroyed.
        % utils.startController wires a listener so the parent controller
        % automatically removes this plugin from its childControllers list.
        CloseEvent
    end

    % =========================================================================
    methods (Static)

        function ViewListner_Callback2(obj, ~, evnt)
        % ViewListner_Callback2  Dispatch MibModel events to update methods.
        %
        % Static scope prevents a strong reference cycle.  The isempty guard
        % makes this a no-op in headless / batch mode where obj.view is [].
            if isempty(obj.view); return; end   % no GUI in batch mode
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    % A new dataset was loaded or another tool changed the image.
                    % Re-read dataset state and refresh the widgets.
                    obj.updateWidgets();
            end
        end

    end

    % =========================================================================
    methods

        % ─────────────────────────────────────────────────────────────────────
        function obj = GuiTutorialBatch(mibModel, varargin)
        % GuiTutorialBatch  Constructor - initialise the controller.
        %
        % Parameters:
        % mibModel: handle to MibModel
        % varargin{1}: parent controller (passed by utils.startController; unused here)
        % varargin{2}: [@em optional]
        %   • struct - BatchOpt for headless / batch mode
        %   • NaN    - query mode: send default BatchOpt via SyncBatch
        %   • (absent) - interactive GUI mode

            obj.mibModel = mibModel;
            obj.view     = [];  % stays [] in batch / headless mode; assigned below in GUI mode

            % -----------------------------------------------------------------
            % STEP 1 - Define BatchOpt defaults.
            %
            % These values are used as:
            %   a) The initial widget state when the GUI is opened.
            %   b) Fallback defaults when batch mode is called with a partial
            %      BatchOpt (missing fields keep these values via
            %      updateBatchOptCombineFields_Shared).
            %
            % Spinner note: upper limits are set to a large fixed value
            % (50 000) rather than the current dataset size so that Resize can
            % upscale the image beyond its current dimensions.  Validation for
            % the Crop operation is done inside cropDataset() at run time.
            % -----------------------------------------------------------------

            % Radio button group (uibuttongroup, Tag = 'OperationButtonGroup')
            % Cell element 1 : Tag of the initially-selected radio button
            % Cell element 2 : all radio button Tags (documentation only)
            obj.BatchOpt.OperationButtonGroup{1} = 'cropRadio';
            obj.BatchOpt.OperationButtonGroup{2} = {'cropRadio', 'resizeRadio', 'convertRadio', 'invertRadio'};

            % Spinners - shared between Crop and Resize operations.
            % Cell element 1 : current value
            % Cell element 2 : [min  max] spinner limits  (upper = 50 000)
            % Cell element 3 : 'on'  = integer-only rounding
            obj.BatchOpt.xMinEdit{1} = 1;
            obj.BatchOpt.xMinEdit{2} = [1, 50000];
            obj.BatchOpt.xMinEdit{3} = 'on';

            obj.BatchOpt.yMinEdit{1} = 1;
            obj.BatchOpt.yMinEdit{2} = [1, 50000];
            obj.BatchOpt.yMinEdit{3} = 'on';

            obj.BatchOpt.widthEdit{1} = 512;
            obj.BatchOpt.widthEdit{2} = [1, 50000];
            obj.BatchOpt.widthEdit{3} = 'on';

            obj.BatchOpt.heightEdit{1} = 512;
            obj.BatchOpt.heightEdit{2} = [1, 50000];
            obj.BatchOpt.heightEdit{3} = 'on';

            % Dropdown for the Convert operation (uidropdown, Tag = 'convertDropdown')
            % Cell element 1 : selected item; element 2 : all items
            obj.BatchOpt.convertDropdown{1} = 'uint8';
            obj.BatchOpt.convertDropdown{2} = {'uint8', 'uint16'};

            % Dropdown for the Invert operation (uidropdown, Tag = 'colorDropdown')
            % Items are dynamically rebuilt in updateWidgets() from the dataset.
            % We initialise element 2 here as a placeholder; the actual channel
            % count is filled in when updateWidgets() runs for the first time.
            obj.BatchOpt.colorDropdown{1} = 'Channel 1';
            obj.BatchOpt.colorDropdown{2} = {'Channel 1'};

            % Show or suppress the progress dialog
            obj.BatchOpt.showWaitbar = true;

            % Active-dataset index - NOT a widget field.
            % Refreshed in updateWidgets() and at the top of Calculate().
            % Stripped before macro recording (returnBatchOpt) because the
            % index is session-specific and meaningless when replaying later.
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            % -----------------------------------------------------------------
            % STEP 2 - Batch registration metadata.
            %
            % mibBatchSectionName : category in the Batch Processing menu
            % mibBatchActionName  : label for this specific action
            % mibBatchTooltip     : per-field help shown in the batch GUI
            %
            % To register this plugin in BatchProcessing, add to
            % controllers.BatchProcessing.initialize:
            %   obj.Sections(secIndex).Actions(actionId).Name = 'GuiTutorial Batch';
            %   obj.Sections(secIndex).Actions(actionId).Command = ...
            %     'obj.mibController.startController(''plugins.Tutorials.GuiTutorialBatch.GuiTutorialBatch'', [], Batch);';
            %   actionId = actionId + 1;
            % -----------------------------------------------------------------
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Plugins';
            obj.BatchOpt.mibBatchActionName  = 'GuiTutorial Batch';

            obj.BatchOpt.mibBatchTooltip.OperationButtonGroup = ...
                'Operation to run: cropRadio | resizeRadio | convertRadio | invertRadio';
            obj.BatchOpt.mibBatchTooltip.xMinEdit      = 'Crop: left edge X coordinate (1-based, pixels)';
            obj.BatchOpt.mibBatchTooltip.yMinEdit      = 'Crop: top edge Y coordinate (1-based, pixels)';
            obj.BatchOpt.mibBatchTooltip.widthEdit     = 'Crop/Resize: target width in pixels';
            obj.BatchOpt.mibBatchTooltip.heightEdit    = 'Crop/Resize: target height in pixels';
            obj.BatchOpt.mibBatchTooltip.convertDropdown = 'Convert: target image class (uint8 or uint16)';
            obj.BatchOpt.mibBatchTooltip.colorDropdown   = 'Invert: colour channel to invert (e.g. "Channel 1")';
            obj.BatchOpt.mibBatchTooltip.showWaitbar     = 'Show or suppress the progress dialog';

            % -----------------------------------------------------------------
            % STEP 3 - Batch / headless execution branch.
            %
            % utils.startController calls the constructor as:
            %   GuiTutorialBatch(mibModel)                         interactive
            %   GuiTutorialBatch(mibModel, parentObj, BatchOptIn)  batch
            %
            % varargin{1} = parentObj (the calling controller)
            % varargin{2} = BatchOptIn (struct / NaN / other)
            % -----------------------------------------------------------------
            if nargin == 3
                BatchOptIn = varargin{2};
                if ~isstruct(BatchOptIn)
                    if isscalar(BatchOptIn) && isnan(BatchOptIn)
                        % Query mode - advertise parameters without running.
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], ...
                            'A BatchOpt structure is required as the 3rd argument.', ...
                            'BatchOpt Error');
                        notify(obj.mibModel, 'StopProtocol');
                    end
                    notify(obj, 'CloseEvent');
                    return
                end

                % Merge supplied fields onto defaults: fields present in
                % BatchOptIn override the defaults above; absent fields keep
                % their default values.
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared( ...
                    obj.BatchOpt, BatchOptIn);

                % Validate and normalise dynamic fields that depend on the
                % current dataset (channel list, operation enum).
                obj.normalizeBatchOptForCurrentDataset();
                if isempty(obj.BatchOpt)
                    % normalizeBatchOptForCurrentDataset signals failure by
                    % returning an empty BatchOpt; notify and exit.
                    notify(obj.mibModel, 'StopProtocol');
                    notify(obj, 'CloseEvent');
                    return;
                end

                obj.Calculate();
                notify(obj, 'CloseEvent');
                return;
            end

            % -----------------------------------------------------------------
            % STEP 4 - Interactive GUI mode.
            % -----------------------------------------------------------------

            % core.ChildView(controller, appClassName) instantiates the
            % AppDesigner app GuiTutorialBatchGUI(obj), calls its
            % startupFcn(app, obj) to store the controller reference, and
            % collects all named component properties into obj.view.handles.
            obj.view = core.ChildView(obj, 'GuiTutorialBatchGUI');

            % Window title-bar icon - use a plugin-specific 16 px icon when
            % present next to this file; otherwise fall back to the shared MIB
            % application icon.
            pluginDir    = fileparts(mfilename('fullpath'));
            localIcon    = fullfile(pluginDir, 'icon_16px.png');
            fallbackIcon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
            if isfile(localIcon)
                obj.view.gui.Icon = localIcon;
            elseif isfile(fallbackIcon)
                obj.view.gui.Icon = fallbackIcon;
            end

            % Place the plugin window to the left of the main MIB window.
            obj.view.gui = utils.moveWindowOutside( ...
                obj.view.gui, obj.mibModel.mibGUI, 'left');

            % Match the application font to the global MIB font preference.
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.infoText1.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.infoText1.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % Wire the OS window-close button (×) to our closeWindow method.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            % Populate all widgets from BatchOpt and refresh dataset info.
            obj.updateWidgets();

            % Subscribe to MibModel events so the plugin tracks dataset changes.
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % ─────────────────────────────────────────────────────────────────────
        function closeWindow(obj)
        % closeWindow  Tear down the plugin window and release all resources.
        %
        % Teardown order:
        %   1. Close child controllers in reverse order.
        %   2. Delete the AppDesigner uifigure (interactive mode only).
        %   3. Delete event listeners.
        %   4. Fire CloseEvent so utils.startController removes this plugin
        %      from the parent's childControllers list.

            % 1. Close child controllers in reverse order to avoid index-shift
            %    bugs if a child's own CloseEvent modifies childControllers{}.
            for i = numel(obj.childControllers):-1:1
                child = obj.childControllers{i};
                if isa(child, 'handle') && isvalid(child)
                    child.closeWindow();
                end
            end
            obj.childControllers    = {};
            obj.childControllersIds = {};

            % 2. Delete the figure (guard: only in interactive mode).
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                % Clear CloseRequestFcn first to prevent a recursive call
                % when deleting the figure triggers another close event.
                obj.view.gui.CloseRequestFcn = '';
                delete(obj.view.gui);
            end

            % 3. Delete listeners to prevent stale callbacks after deletion.
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end

            % 4. Notify the parent so it can clean up its childControllers list.
            notify(obj, 'CloseEvent');
        end

        % ─────────────────────────────────────────────────────────────────────
        function updateWidgets(obj)
        % updateWidgets  Synchronise BatchOpt with the current dataset, then
        % push all values into their matching GUI widgets.
        %
        % Called from the constructor (after the view is built) and by
        % ViewListner_Callback2 when UpdateGuiWidgets or NewDataset fires.
        %
        % Compared with GuiTutorial.updateWidgets(), this version does NOT
        % write directly to widget properties.  Instead it:
        %   1. Updates the data-dependent fields in BatchOpt (spinner defaults,
        %      channel list).
        %   2. Calls utils.updateGUIFromBatchOpt_Shared to push all BatchOpt
        %      values into their widgets in one pass (field name → Tag → widget).
        %   3. Calls buttonGroup_Callback to re-apply enable/disable rules.

            if isempty(obj.view); return; end   % no-op in batch mode

            id = obj.mibModel.getActiveId();
            obj.BatchOpt.id = id;   % keep id current for split-panel mode

            options.blockModeSwitch = 0;  % full image, ignoring viewport crop
            [height, width, depth, colors, time] = ...
                obj.mibModel.I{id}.getDatasetDimensions('image', 3, options);

            % Update the read-only info label with current dimensions.
            obj.view.handles.infoText2.Text = ...
                sprintf('%d x %d x %d x %d x %d', height, width, depth, colors, time);

            % Update spinner defaults to the current image size so the user
            % starts at a sensible crop/resize value for the loaded dataset.
            % NOTE: upper limits remain 50 000 so Resize can upscale.
            obj.BatchOpt.xMinEdit{1}  = 1;
            obj.BatchOpt.yMinEdit{1}  = 1;
            obj.BatchOpt.widthEdit{1} = width;
            obj.BatchOpt.heightEdit{1} = height;

            % Rebuild the channel dropdown list from the actual channel count.
            colorsList = arrayfun(@(i) sprintf('Channel %d', i), ...
                1:colors, 'UniformOutput', false);
            obj.BatchOpt.colorDropdown{2} = colorsList;
            % If the previously-selected channel no longer exists (e.g. after
            % switching to a greyscale dataset) reset to the first channel.
            if ~ismember(obj.BatchOpt.colorDropdown{1}, colorsList)
                obj.BatchOpt.colorDropdown{1} = colorsList{1};
            end

            % Push all BatchOpt values into their matching widgets.
            % The shared utility iterates every BatchOpt field, looks up the
            % AppDesigner widget with a matching Tag, and assigns the value
            % using the appropriate property (Value, Limits, Items, …).
            obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);

            % Apply enable/disable rules for the currently-selected operation.
            obj.buttonGroup_Callback();
        end

        % ─────────────────────────────────────────────────────────────────────
        function helpBtn_Callback(obj)
        % helpBtn_Callback  Open the MIB tutorials page in the browser.
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'plugins', 'tutorials', 'gui-tutorial-batch.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/plugins/tutorials/gui-tutorial-batch.html');
        end

        % ─────────────────────────────────────────────────────────────────────
        function buttonGroup_Callback(obj)
        % buttonGroup_Callback  Sync BatchOpt from the widget and update enable states.
        %
        % In interactive mode this method is the AUTHORITATIVE source for
        % BatchOpt.OperationButtonGroup{1}.  It reads the currently selected
        % radio button via ButtonGroup.SelectedObject.Tag, which AppDesigner
        % keeps in sync automatically.  This avoids relying on
        % updateBatchOptFromGUI_Shared to iterate children and match Values,
        % which can silently fail if child order is unexpected.
        %
        % Called from:
        %   • mlapp OperationButtonGroup_SelectionChanged (after user clicks)
        %   • updateWidgets (after updateGUIFromBatchOpt_Shared pushes all values)
        %
        % Recommended mlapp wiring (GuiTutorialBatchGUI.mlapp):
        %   function OperationButtonGroup_SelectionChanged(app, event)
        %       app.winController.buttonGroup_Callback();
        %   end
        %
        % Note: updateBatchOptFromGUI(event) is NOT needed for the button group
        % because this method reads directly from SelectedObject.Tag.

            if isempty(obj.view); return; end   % no widgets to update in batch mode

            % Read the currently selected radio button directly from the widget.
            % SelectedObject is always up-to-date - no dependency on event order.
            bg = obj.view.handles.OperationButtonGroup;
            if ~isempty(bg.SelectedObject)
                obj.BatchOpt.OperationButtonGroup{1} = bg.SelectedObject.Tag;
            end

            selectedOp = obj.BatchOpt.OperationButtonGroup{1};

            % Start with all widgets enabled, then disable those that are
            % irrelevant for the selected operation.
            obj.view.handles.xMinEdit.Enable        = 'on';
            obj.view.handles.yMinEdit.Enable        = 'on';
            obj.view.handles.widthEdit.Enable       = 'on';
            obj.view.handles.heightEdit.Enable      = 'on';
            obj.view.handles.convertDropdown.Enable = 'on';
            obj.view.handles.colorDropdown.Enable   = 'on';

            switch selectedOp
                case 'cropRadio'
                    % Crop uses xMin/yMin (origin) and width/height (size).
                    obj.view.handles.convertDropdown.Enable = 'off';
                    obj.view.handles.colorDropdown.Enable   = 'off';

                case 'resizeRadio'
                    % Resize uses only width/height (target size).
                    obj.view.handles.xMinEdit.Enable        = 'off';
                    obj.view.handles.yMinEdit.Enable        = 'off';
                    obj.view.handles.convertDropdown.Enable = 'off';
                    obj.view.handles.colorDropdown.Enable   = 'off';

                case 'convertRadio'
                    % Convert uses only convertDropdown (target class).
                    obj.view.handles.xMinEdit.Enable        = 'off';
                    obj.view.handles.yMinEdit.Enable        = 'off';
                    obj.view.handles.widthEdit.Enable       = 'off';
                    obj.view.handles.heightEdit.Enable      = 'off';
                    obj.view.handles.colorDropdown.Enable   = 'off';

                case 'invertRadio'
                    % Invert uses only colorDropdown (channel selector).
                    obj.view.handles.xMinEdit.Enable        = 'off';
                    obj.view.handles.yMinEdit.Enable        = 'off';
                    obj.view.handles.widthEdit.Enable       = 'off';
                    obj.view.handles.heightEdit.Enable      = 'off';
                    obj.view.handles.convertDropdown.Enable = 'off';
            end
        end

        % ─────────────────────────────────────────────────────────────────────
        function updateBatchOptFromGUI(obj, event)
        % updateBatchOptFromGUI  Pull a changed widget value into BatchOpt.
        %
        % Wire this as the ValueChangedFcn for every interactive widget in
        % GuiTutorialBatchGUI.mlapp.  Example mlapp wiring:
        %
        %   function widthEdit_ValueChanged(app, event)
        %       app.winController.updateBatchOptFromGUI(event);
        %   end
        %
        % The shared utility inspects event.Source.Type to determine how to
        % extract the new value, then updates the BatchOpt field whose name
        % matches event.Source.Tag.
        %
        % For the button group, additionally call buttonGroup_Callback()
        % AFTER this method to update enable/disable states:
        %
        %   function OperationButtonGroup_SelectionChanged(app, event)
        %       app.winController.updateBatchOptFromGUI(event);
        %       app.winController.buttonGroup_Callback();
        %   end
        %
        % Parameters:
        % event: AppDesigner event - event.Source is the changed widget

            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared( ...
                obj.BatchOpt, event.Source);
        end

        % ─────────────────────────────────────────────────────────────────────
        function returnBatchOpt(obj, BatchOptOut)
        % returnBatchOpt  Send BatchOpt to the MIB macro recorder.
        %
        % Fires the SyncBatch event on mibModel with the current BatchOpt as
        % payload so the Batch Processing controller can record this operation
        % for later replay.
        %
        % Call this at the END of every successful Calculate() execution.
        % Also called in query mode (NaN passed to constructor) so the batch
        % controller can discover available parameters without running anything.
        %
        % Parameters:
        % BatchOptOut: [@em optional] override struct; defaults to obj.BatchOpt.

            if nargin < 2; BatchOptOut = obj.BatchOpt; end

            % Strip 'id' - the active-dataset index is session-specific and
            % meaningless when replaying a macro in a different session.
            if isfield(BatchOptOut, 'id')
                BatchOptOut = rmfield(BatchOptOut, 'id');
            end

            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        % ─────────────────────────────────────────────────────────────────────
        function continueBtn_Callback(obj)
        % continueBtn_Callback  Entry point for the Continue button.
        %
        % In interactive mode, BatchOpt is already kept current by the
        % per-widget updateBatchOptFromGUI hooks.  We therefore just delegate
        % to Calculate() which reads all parameters from BatchOpt.

            obj.Calculate();
        end

        % ─────────────────────────────────────────────────────────────────────
        function Calculate(obj)
        % Calculate  Dispatch to the selected operation and register with macro.
        %
        % Steps:
        %   1. Refresh the active-dataset id.
        %   2. Guard against virtual-stack datasets (not supported by the
        %      direct pixel-access operations in this plugin).
        %   3. Dispatch to the appropriate operation method based on
        %      BatchOpt.OperationButtonGroup{1}.
        %   4. If the operation succeeded, call returnBatchOpt() to register
        %      the run in the macro recorder.
        %   5. If the operation failed and we are in batch/headless mode,
        %      fire StopProtocol to halt the running macro sequence.

            % -- 1. Refresh id -----------------------------------------------
            % Always re-read at the start of Calculate() so headless batch
            % mode (which skips updateWidgets) targets the correct dataset.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            id              = obj.BatchOpt.id;

            % -- 2. Virtual-stack guard --------------------------------------
            % The Convert and Invert operations access pixels directly through
            % MibImage.data or getData2D, which require in-memory data.
            % Virtual datasets stream tiles from disk and do not support this.
            if isprop(obj.mibModel.I{id}, 'datasetType') && ...
                    strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.getDialogParent(), ...
                    '!!! Warning !!!', {''}, ...
                    {'This plugin is not compatible with the virtual stacking mode! Please switch to memory-resident mode and try again.'}, ...
                    'Not implemented', dlgOpt);
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            % -- 3. Dispatch -------------------------------------------------
            % Each operation method:
            %   • Reads all its inputs from BatchOpt (not from widget handles)
            %   • Returns true on success, false on validation failure
            success = false;
            switch obj.BatchOpt.OperationButtonGroup{1}
                case 'cropRadio'
                    success = obj.cropDataset();
                case 'resizeRadio'
                    success = obj.resizeDataset();
                case 'convertRadio'
                    success = obj.convertDataset();
                case 'invertRadio'
                    success = obj.invertDataset();
                otherwise
                    utils.dlgs.showErrorDialog(obj.getDialogParent(), ...
                        sprintf('Unknown operation: "%s"', ...
                            obj.BatchOpt.OperationButtonGroup{1}), ...
                        'GuiTutorialBatch error');
            end

            % -- 4. Macro recording ------------------------------------------
            % Only record when the operation actually ran.  This prevents
            % recording a failed crop (e.g. out-of-bounds rectangle) or a
            % no-op conversion (same source and target class).
            if success
                obj.returnBatchOpt();
            end

            % -- 5. Batch failure notification --------------------------------
            if ~success && isempty(obj.view)
                % In headless mode there is no GUI to show an error to the user.
                % StopProtocol halts a running macro sequence so the caller
                % knows something went wrong.
                notify(obj.mibModel, 'StopProtocol');
            end
        end

        % ─────────────────────────────────────────────────────────────────────
        function success = cropDataset(obj)
        % cropDataset  Crop the current dataset to the rectangle in BatchOpt.
        %
        % Reads xMinEdit, yMinEdit, widthEdit, heightEdit from BatchOpt,
        % validates the rectangle against the actual dataset dimensions, then
        % delegates to MibDataset.cropDataset() which handles all layers
        % (image, labels, mask, selection) in one call.
        %
        % Returns:
        % success: true if the crop succeeded; false if validation failed

            success = false;

            id      = obj.BatchOpt.id;
            x1      = obj.BatchOpt.xMinEdit{1};
            y1      = obj.BatchOpt.yMinEdit{1};
            width1  = obj.BatchOpt.widthEdit{1};
            height1 = obj.BatchOpt.heightEdit{1};

            % Get the full dataset extent for boundary validation.
            options.blockModeSwitch = 0;
            [height, width, depth, ~, time] = ...
                obj.mibModel.I{id}.getDatasetDimensions('image', 3, options);

            % Validate: the requested rectangle must lie entirely inside the image.
            if x1 < 1 || y1 < 1 || x1+width1-1 > width || y1+height1-1 > height
                utils.dlgs.showErrorDialog(obj.getDialogParent(), ...
                    sprintf(['Crop rectangle is out of bounds.\n' ...
                             'Requested: x=%d y=%d w=%d h=%d\n' ...
                             'Image size: %d x %d'], ...
                             x1, y1, width1, height1, width, height), ...
                    'Wrong dimensions');
                return;
            end

            % cropF = [x1, y1, dx, dy, z1, dz, t1, dt] - crop the full Z/T extents.
            cropF = [x1, y1, width1, height1, 1, depth, 1, time];
            cropOpts.showWaitbar = obj.canShowWaitbar();
            % UIFigure is the parent for the internal progress dialog.
            % In batch mode obj.view is [], so pass mibGUI (AppContainer);
            % MibDataset.cropDataset calls uiprogressdlg which accepts AppContainer.
            cropOpts.UIFigure = obj.getDialogParent();

            result = obj.mibModel.I{id}.cropDataset(cropF, cropOpts);

            if result
                % Notify MIB so the image canvas and toolbar are fully refreshed.
                notify(obj.mibModel, 'NewDataset');
                notify(obj.mibModel, 'ShowImage');
                success = true;
            end
        end

        % ─────────────────────────────────────────────────────────────────────
        function success = resizeDataset(obj)
        % resizeDataset  Resize the current dataset to new XY dimensions.
        %
        % setData4D cannot resize a dataset because it writes into a fixed-size
        % pre-allocated array.  Instead we launch controllers.ResampleDataset
        % in batch mode via utils.startController, passing target dimensions.
        %
        % Note: ResampleDataset supports upscaling (target > current size).
        % The xMinEdit / yMinEdit spinners in this plugin are not used by
        % Resize (only widthEdit and heightEdit are relevant).
        %
        % Returns:
        % success: true if the call to ResampleDataset was initiated successfully

            success = false;

            width1  = obj.BatchOpt.widthEdit{1};
            height1 = obj.BatchOpt.heightEdit{1};

            if width1 < 1 || height1 < 1
                utils.dlgs.showErrorDialog(obj.getDialogParent(), ...
                    'Target width and height must both be at least 1 pixel.', ...
                    'Wrong dimensions');
                return;
            end

            % Build the BatchOpt struct that ResampleDataset expects in batch mode.
            % 'Dimensions' mode sets an absolute pixel target (not a scale factor).
            % DimensionX / DimensionY are strings because ResampleDataset parses
            % them from a text-edit field in its own GUI.
            resampleBatchOpt.ResamplingMode = {'Dimensions'};
            resampleBatchOpt.DimensionX     = num2str(width1);
            resampleBatchOpt.DimensionY     = num2str(height1);
            resampleBatchOpt.showWaitbar    = obj.canShowWaitbar();

            % utils.startController checks if ResampleDataset is already open
            % (and re-focuses it) or creates it fresh.  With a BatchOpt struct
            % as the 3rd argument it executes silently without showing a GUI.
            utils.startController(obj, 'controllers.ResampleDataset', [], resampleBatchOpt);
            success = true;
        end

        % ─────────────────────────────────────────────────────────────────────
        function success = convertDataset(obj)
        % convertDataset  Convert the image data class (uint8 <-> uint16).
        %
        % Pixel values are scaled linearly so the full dynamic range of the
        % source class maps to the full dynamic range of the target class
        % (e.g. 0-255 → 0-65535).
        %
        % Important: setData4D cannot be used for a type conversion because
        % MibImage.setData writes into the existing typed container via
        % indexed assignment, which silently casts the incoming array back to
        % the original type.  We therefore write directly to MibImage.data
        % and manually update the three interdependent metadata properties.
        %
        % In contrast with GuiTutorial.convertDataset() (which uses
        % uiprogressdlg directly), this version uses core.PoolWaitbar so
        % progress works correctly in headless / batch mode.
        %
        % Returns:
        % success: true if conversion ran; false if image is already the target class

            success = false;

            id        = obj.BatchOpt.id;
            convertTo = obj.BatchOpt.convertDropdown{1};

            % Fetch the full 4-D volume.  col_channel=[] means all channels;
            % blockModeSwitch=0 ignores any active viewport crop.
            options.blockModeSwitch = 0;
            img       = obj.mibModel.getData4D('image', [], [], options);
            classFrom = class(img{1});

            if strcmp(classFrom, convertTo)
                % Nothing to do - warn the user and return without recording.
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon       = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.getDialogParent(), ...
                    sprintf('The dataset is already %s class!', convertTo), ...
                    {}, {}, 'No conversion needed', dlgOpt);
                return;
            end

            % canShowWaitbar() returns true only in interactive mode with a
            % valid plugin window - PoolWaitbar requires a matlab.ui.Figure and
            % rejects AppContainer (mibModel.mibGUI).  In batch mode progress
            % is shown by the Batch Processing GUI instead.
            showProgress = obj.canShowWaitbar();
            if showProgress
                % core.PoolWaitbar(N, message, parentFig, title, cancelable)
                progressBar = core.PoolWaitbar(2, ...
                    'Converting dataset...', ...
                    obj.view.gui, ...   % UIFigure - safe for PoolWaitbar
                    'Convert', false);
            end

            % Scale pixel values to fill the target type's full dynamic range.
            % coef = intmax(target) / intmax(source) preserves relative brightness.
            if strcmp(convertTo, 'uint16')
                coef   = double(intmax('uint16')) / double(intmax(class(img{1})));
                img{1} = uint16(double(img{1}) * coef);
            else
                coef   = double(intmax('uint8')) / double(intmax(class(img{1})));
                img{1} = uint8(double(img{1}) * coef);
            end

            if showProgress; progressBar.increment(); end  % step 1/2

            % Write the converted array directly to MibImage.data and update
            % the three interdependent metadata properties:
            %   dataClass - the MATLAB class string ('uint8', 'uint16', …)
            %   maxInt    - the maximum representable integer for this class
            %   viewPort  - per-channel display range [min, max, gamma]
            imageObj           = obj.mibModel.I{id}.image;
            imageObj.data   = img{1};
            imageObj.dataClass = class(img{1});
            imageObj.maxInt    = double(intmax(class(img{1})));
            imageObj.getDefaultViewPort();  % resets viewPort.max to the new maxInt
            imageObj.updateActionLog( ...
                sprintf('Converted from %s to %s', classFrom, class(img{1})));

            if showProgress
                progressBar.increment();        % step 2/2
                progressBar.deletePoolWaitbar();
            end

            % UpdateGuiWidgets refreshes the MIB toolbar (class label, etc.).
            % ShowImage redraws the canvas with the updated display range.
            notify(obj.mibModel, 'UpdateGuiWidgets');
            notify(obj.mibModel, 'ShowImage');
            success = true;
        end

        % ─────────────────────────────────────────────────────────────────────
        function success = invertDataset(obj)
        % invertDataset  Invert a single colour channel of the dataset.
        %
        % Processes one 2-D slice at a time (getData2D / setData2D) to
        % minimise peak memory usage for large datasets.
        %
        % Inversion formula: result = intmax(class) - pixel_value
        % which maps 0 → max and max → 0 while preserving the data type.
        %
        % In contrast with GuiTutorial.invertDataset() (which reads the
        % channel from a widget), this version reads from
        % BatchOpt.colorDropdown{1} and resolves the string to an index via
        % BatchOpt.colorDropdown{2} (the known items list).
        %
        % Returns:
        % success: true if inversion completed; false if channel is invalid

            success = false;

            id       = obj.BatchOpt.id;
            colChStr = obj.BatchOpt.colorDropdown{1};

            % Convert the channel name string back to a 1-based integer index.
            % BatchOpt.colorDropdown{2} holds the full items list, so we can
            % resolve the selection without needing the live widget state.
            colCh = find(strcmp(obj.BatchOpt.colorDropdown{2}, colChStr), 1);
            if isempty(colCh)
                utils.dlgs.showErrorDialog(obj.getDialogParent(), ...
                    sprintf('Channel "%s" not found in the current dataset.', colChStr), ...
                    'Invalid channel');
                return;
            end

            % Empty options struct - no ROI, no viewport crop.
            % Omitting 'roiId' disables ROI mode and processes the full image.
            options = struct();
            [~, ~, depth, ~, time] = ...
                obj.mibModel.I{id}.getDatasetDimensions('image');

            % Back up the full 3-D volume before modifying it so the user can
            % undo via Edit → Undo.  Skip backup for time-series (large undo
            % snapshot would be impractical).
            if time == 1
                obj.mibModel.backup('image', 1, struct());
            end

            totalFrames = depth * time;
            showProgress = obj.canShowWaitbar();   % false in batch mode; PoolWaitbar needs UIFigure
            if showProgress
                progressBar = core.PoolWaitbar(totalFrames, ...
                    'Inverting dataset...', ...
                    obj.view.gui, ...   % UIFigure - safe for PoolWaitbar
                    'Invert', true);    % true = add Cancel button
            end

            for t = 1:time
                for z = 1:depth
                    % getData2D returns a cell array - one entry per ROI region
                    % in ROI mode, or a single-entry cell here (no ROI).
                    img    = obj.mibModel.getData2D('image', z, [], colCh, options);
                    maxInt = intmax(class(img{1}));
                    for roiIdx = 1:numel(img)
                        img{roiIdx} = maxInt - img{roiIdx};
                    end
                    % setData2D: (dataset, type, slice_no, orient, col_channel, options)
                    % orient=[] means "use current orientation".
                    obj.mibModel.setData2D(img, 'image', z, [], colCh, options);

                    if showProgress
                        if progressBar.getCancelState()
                            progressBar.deletePoolWaitbar();
                            return;  % success remains false - operation was cancelled
                        end
                        progressBar.increment();
                    end
                end
            end

            % updateActionLog lives on MibImage (I{id}.image), not MibDataset (I{id}).
            obj.mibModel.I{id}.image.updateActionLog('Invert image');

            if showProgress; progressBar.deletePoolWaitbar(); end

            notify(obj.mibModel, 'ShowImage');
            success = true;
        end

    end  % public methods

    % =========================================================================
    methods (Access = private)

        % ─────────────────────────────────────────────────────────────────────
        function parent = getDialogParent(obj)
        % getDialogParent  Return the best available parent for error / warning dialogs.
        %
        % In interactive mode the plugin window (obj.view.gui) is used.
        % In batch/headless mode we fall back to mibModel.mibGUI (AppContainer).
        %
        % NOTE: use this only for utils.dlgs.* and uiprogressdlg calls, which
        % accept AppContainer as a parent.  Do NOT pass the result to
        % core.PoolWaitbar - that requires a matlab.ui.Figure (UIFigure).
        % Use canShowWaitbar() + obj.view.gui directly for PoolWaitbar instead.

            if ~isempty(obj.view) && isvalid(obj.view.gui)
                parent = obj.view.gui;
            else
                parent = obj.mibModel.mibGUI;
            end
        end

        % ─────────────────────────────────────────────────────────────────────
        function result = canShowWaitbar(obj)
        % canShowWaitbar  True when a progress bar can safely be shown.
        %
        % core.PoolWaitbar requires a matlab.ui.Figure (UIFigure), but in
        % batch/headless mode obj.view is [] (no plugin window) and
        % obj.mibModel.mibGUI is an AppContainer - which fails the
        % isa(...,'matlab.ui.Figure') check inside PoolWaitbar.
        %
        % This helper returns true only when:
        %   1. The user has opted in via BatchOpt.showWaitbar, AND
        %   2. The plugin window (a proper UIFigure) actually exists.
        %
        % In headless / batch mode progress is shown by the Batch Processing
        % GUI, so a plugin-level progress bar is neither needed nor possible.

            result = obj.BatchOpt.showWaitbar && ...
                     ~isempty(obj.view)       && ...
                     isvalid(obj.view.gui);
        end

        % ─────────────────────────────────────────────────────────────────────
        function normalizeBatchOptForCurrentDataset(obj)
        % normalizeBatchOptForCurrentDataset  Validate and normalise dynamic
        % BatchOpt fields for the current dataset in headless / batch mode.
        %
        % In interactive mode, updateWidgets() rebuilds dynamic fields (e.g.
        % the channel list) from the live dataset every time a new file is
        % opened.  In headless mode updateWidgets() is never called, so we
        % must do the same validation here after merging the caller's BatchOpt.
        %
        % On an unrecoverable validation error (invalid operation enum), sets
        % obj.BatchOpt to [] so the constructor can detect failure and exit.

            id = obj.mibModel.getActiveId();
            options.blockModeSwitch = 0;
            [~, ~, ~, colors, ~] = ...
                obj.mibModel.I{id}.getDatasetDimensions('image', 3, options);

            % --- Operation enum ---
            validOps = obj.BatchOpt.OperationButtonGroup{2};
            if ~ismember(obj.BatchOpt.OperationButtonGroup{1}, validOps)
                utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                    sprintf(['Invalid OperationButtonGroup value: "%s".\n' ...
                             'Valid values: %s'], ...
                             obj.BatchOpt.OperationButtonGroup{1}, ...
                             strjoin(validOps, ', ')), ...
                    'BatchOpt validation error');
                obj.BatchOpt = [];  % signal failure to caller
                return;
            end

            % --- Convert dropdown ---
            if ~ismember(obj.BatchOpt.convertDropdown{1}, ...
                    obj.BatchOpt.convertDropdown{2})
                % Reset to first valid option rather than hard-failing.
                obj.BatchOpt.convertDropdown{1} = obj.BatchOpt.convertDropdown{2}{1};
            end

            % --- Colour-channel dropdown ---
            % Rebuild the items list from the current channel count and ensure
            % the selected channel string is present.
            colorsList = arrayfun(@(i) sprintf('Channel %d', i), ...
                1:colors, 'UniformOutput', false);
            obj.BatchOpt.colorDropdown{2} = colorsList;
            if ~ismember(obj.BatchOpt.colorDropdown{1}, colorsList)
                % Requested channel does not exist in this dataset - default
                % to the first channel rather than aborting.
                fprintf(['GuiTutorialBatch: colorDropdown "%s" is not ' ...
                    'present in this dataset (channels: 1-%d). ' ...
                    'Defaulting to Channel 1.\n'], ...
                    obj.BatchOpt.colorDropdown{1}, colors);
                obj.BatchOpt.colorDropdown{1} = colorsList{1};
            end
        end

    end  % private methods

end
