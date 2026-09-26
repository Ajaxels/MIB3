% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi
% Date: 19.08.2025

classdef DemoPlugin < handle
% DemoPlugin < handle
% Tutorial plugin demonstrating the BatchOpt parameter system and
% batch-processing compatibility in MIB3.
%
% This plugin is intentionally kept simple so that its code is easy to
% follow.  It illustrates five concepts that every batch-compatible plugin
% must implement:
%
%   1. BATCHOPT STRUCTURE
%      A single struct (obj.BatchOpt) holds every tunable parameter.
%      Field names must exactly match the Tag of the corresponding
%      AppDesigner widget so the two shared utilities can auto-sync them.
%
%   2. GUI ↔ BATCHOPT SYNC
%      utils.updateGUIFromBatchOpt_Shared pushes BatchOpt values into
%      widgets; utils.updateBatchOptFromGUI_Shared pulls a changed widget
%      value back into BatchOpt.  Both are called via standardised hooks.
%
%   3. THREE CALLING MODES (see constructor for details)
%      • Interactive - normal GUI mode launched from the Plugins ribbon
%      • Headless    - run without a GUI when a BatchOpt struct is passed
%                      as the 3rd constructor argument (macro replay)
%      • Query       - NaN as 3rd argument returns default settings to the
%                      batch controller without performing any work
%
%   4. PROGRESS REPORTING
%      core.PoolWaitbar wraps uiprogressdlg and is safe inside parfor.
%      Always use it instead of calling uiprogressdlg.Value directly in
%      parallel code.
%
%   5. MACRO REGISTRATION
%      returnBatchOpt() fires the SyncBatch event on mibModel so the MIB
%      batch controller can record the operation for later replay.
%
% @b Calling @b conventions:
% @code
%   % Interactive GUI mode (via Plugins ribbon):
%   utils.startController(parentObj, 'DemoPlugin');
%
%   % Batch / headless mode (BatchOpt provided - e.g. from macro replay):
%   BatchOpt.Parameter = 'hello';
%   BatchOpt.Checkbox  = false;
%   DemoPlugin(mibModel, parentObj, BatchOpt);
%
%   % Query mode - return default BatchOpt without executing:
%   DemoPlugin(mibModel, parentObj, NaN);
% @endcode
%
% @b See @b also:
%   README.md and instruction.md in this folder
%   mib/plugins/FileProcessing/ImageConverter/ImageConverter.m
%     (full-featured batch-compatible plugin)

    properties
        mibModel
        % Handle to the central MibModel instance.
        view
        % core.ChildView wrapper for the AppDesigner GUI.
        %   obj.view.gui           - uifigure handle
        %   obj.view.handles.<Tag> - individual widget handles
        % In headless / batch mode this property is [] (never assigned).
        listener
        % Cell array of event listener handles.  Deleted in closeWindow()
        % so they do not fire after the controller is destroyed.
        BatchOpt
        % Parameter structure compatible with MIB batch processing.
        %
        % IMPORTANT: every field name must match the Tag of the
        % corresponding AppDesigner widget EXACTLY (case-sensitive).
        % The two shared utility functions find widgets by Tag, so a
        % mismatch silently skips the widget.
        %
        % Supported widget types and their BatchOpt encoding:
        %
        %  Widget type     Field format
        %  --------------- -----------------------------------------------
        %  uieditfield     scalar string / char
        %  uicheckbox      logical (true / false)
        %  uidropdown      {selectedString, {'opt1','opt2',...}}
        %                    element 2 is optional - omit to keep items
        %  uibuttongroup   {selectedRadioTag, {'Tag1','Tag2',...}}
        %                    element 2 is metadata only (not pushed to GUI)
        %  uispinner       {value, [min max], 'on'/'off'}
        %                    'on' = round to integer, 'off' = allow float
        %
        childControllers    = {}
        % Cell array of handles to child controllers opened by this plugin.
        % Required by utils.startController / utils.purgeChildController.
        childControllersIds = {}
        % Class-name strings matching childControllers{}.
    end

    events
        % CloseEvent is fired by closeWindow() after the GUI is destroyed.
        % utils.startController wires a listener to this event so the
        % parent controller removes this plugin from its childControllers
        % list automatically.
        CloseEvent
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
        % ViewListner_Callback2  Dispatch MibModel events to update methods.
        %
        % Static scope prevents a strong reference cycle: the listener
        % holds a function handle that references obj, but because this
        % is a static method MATLAB does not count it as a strong
        % handle reference, allowing normal garbage collection.
        %
        % Only acts when the GUI is actually open - the isempty(obj.view)
        % guard makes this a no-op in headless / batch mode.
            if isempty(obj.view); return; end   % no GUI in batch mode
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    % A new dataset was loaded or another tool changed the
                    % image.  Re-read state and refresh the widgets.
                    obj.updateWidgets();
            end
        end
    end

    methods

        % =================================================================
        function obj = DemoPlugin(mibModel, varargin)
        % DemoPlugin  Constructor - initialise the controller.
        %
        % Parameters:
        % mibModel: handle to MibModel
        % varargin{1}: parent controller object (passed by utils.startController;
        %              not used in this plugin but must be accepted)
        % varargin{2}: [@em optional]
        %   • struct   - BatchOpt for headless / batch mode
        %   • NaN      - query mode: send default BatchOpt via SyncBatch
        %   • (absent) - interactive GUI mode

            obj.mibModel = mibModel;
            obj.view     = [];  % stays [] in batch / headless mode

            % ---------------------------------------------------------
            % STEP 1 - Define BatchOpt defaults.
            %
            % These values are used as the starting state for the GUI AND
            % as defaults when batch mode is called with a partial BatchOpt
            % (missing fields keep the defaults below via
            % updateBatchOptCombineFields_Shared).
            %
            % Rule: each field name MUST match the Tag of the AppDesigner
            % widget that displays / edits it.
            % ---------------------------------------------------------

            % Text edit box (uieditfield, Tag = 'Parameter')
            obj.BatchOpt.Parameter = 'my parameter';

            % Checkbox (uicheckbox, Tag = 'Checkbox')
            obj.BatchOpt.Checkbox = true;

            % Dropdown (uidropdown, Tag = 'Dropdown')
            % Cell element 1 : currently selected item string
            % Cell element 2 : all available options  →  populates the widget
            obj.BatchOpt.Dropdown{1} = 'Option 3';
            obj.BatchOpt.Dropdown{2} = {'Option 1', 'Option 2', 'Option 3'};

            % Radio button group (uibuttongroup, Tag = 'RadioButtonGroup')
            % Cell element 1 : Tag of the currently selected radio button
            % Cell element 2 : Tags of all radio buttons (documentation only;
            %                  not used by updateGUIFromBatchOpt_Shared)
            obj.BatchOpt.RadioButtonGroup{1} = 'Radio2';
            obj.BatchOpt.RadioButtonGroup{2} = {'Radio1', 'Radio2', 'Radio3'};

            % Numeric spinner (uispinner, Tag = 'ParameterNumeric')
            % Cell element 1 : numeric value
            % Cell element 2 : [min  max] spinner limits
            % Cell element 3 : 'on' = integer-round, 'off' = allow fractions
            obj.BatchOpt.ParameterNumeric{1} = 512.125;
            obj.BatchOpt.ParameterNumeric{2} = [0, 1024];
            obj.BatchOpt.ParameterNumeric{3} = 'off';

            % Show/hide progress dialog (uicheckbox, Tag = 'showWaitbar')
            obj.BatchOpt.showWaitbar = true;

            % Active dataset index - NOT a widget field.
            % Refreshed in updateWidgets() and at the top of Calculate().
            % Stripped from BatchOpt before macro recording (returnBatchOpt)
            % because the index is session-specific.
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            % ---------------------------------------------------------
            % STEP 2 - Batch registration metadata.
            %
            % mibBatchSectionName : category in the batch GUI menu
            % mibBatchActionName  : label for this specific action
            % mibBatchTooltip     : per-field help strings shown in the
            %                       batch GUI (sub-field name = field name)
            % Initialized in controllers.BatchProcessing.initialize as:
            % obj.Sections(secIndex).Actions(actionId).Name = 'Demo Plugin';
            % obj.Sections(secIndex).Actions(actionId).Command = 'obj.mibController.startController(''DemoPlugin'', [], Batch);'; actionId = actionId + 1;

            % ---------------------------------------------------------
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Plugins';
            obj.BatchOpt.mibBatchActionName  = 'Demo Plugin';

            obj.BatchOpt.mibBatchTooltip.Parameter        = 'Text or numeric string';
            obj.BatchOpt.mibBatchTooltip.Checkbox         = 'Logical flag (true / false)';
            obj.BatchOpt.mibBatchTooltip.Dropdown         = 'Dropdown - pass a cell with the selected item string';
            obj.BatchOpt.mibBatchTooltip.RadioButtonGroup = 'Radio button group - pass a cell with the selected radio Tag';
            obj.BatchOpt.mibBatchTooltip.ParameterNumeric = 'Numeric value - pass a cell {value, [min max], roundFlag}';
            obj.BatchOpt.mibBatchTooltip.showWaitbar      = 'Show or suppress the progress dialog';

            % ---------------------------------------------------------
            % STEP 3 - Batch / headless execution branch.
            %
            % utils.startController calls the constructor as:
            %   DemoPlugin(mibModel)                            interactive
            %   DemoPlugin(mibModel, parentObj, BatchOptIn)     batch
            %
            % varargin{1} = parentObj   (the calling controller)
            % varargin{2} = BatchOptIn  (struct / NaN / other)
            % ---------------------------------------------------------
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

                % Merge supplied fields onto defaults.
                % Fields present in BatchOptIn override the defaults above;
                % fields absent in BatchOptIn keep their default values.
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared( ...
                    obj.BatchOpt, BatchOptIn);

                obj.Calculate();
                notify(obj, 'CloseEvent');
                return;
            end

            % ---------------------------------------------------------
            % STEP 4 - Interactive GUI mode.
            % ---------------------------------------------------------

            % core.ChildView(controller, appClassName) does three things:
            %   a) Instantiates the AppDesigner app:  DemoPluginGUI(obj)
            %   b) Calls the app's startupFcn(app, obj) to store the
            %      controller reference
            %   c) Collects all named component properties into
            %      obj.view.handles so they are accessible as
            %      obj.view.handles.<Tag>
            %   After construction: obj.view.gui  = uifigure handle
            %                       obj.view.Figure = AppDesigner app
            obj.view = core.ChildView(obj, 'DemoPluginGUI');
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme

            % Window title-bar icon.
            % Use a plugin-specific 16 px PNG when present next to this
            % file; otherwise fall back to the shared MIB application icon.
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

            % Match the application font to the global MIB preference.
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.Parameter.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.Parameter.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % Wire the OS window-close button (×) to our closeWindow method.
            % Without this the figure would be deleted but the controller
            % object and its listeners would remain alive.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            % Populate all widgets from the current BatchOpt values and
            % sync the active-dataset id field.
            obj.updateWidgets();

            % Subscribe to MibModel events so the plugin stays current when
            % the user loads a new dataset or another tool runs.
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % =================================================================
        function closeWindow(obj)
        % closeWindow  Tear down the plugin window and release resources.
        %
        % Teardown order:
        %   1. Close any open child controllers (reverse order avoids
        %      index-shift bugs when removeChildController also fires)
        %   2. Delete the AppDesigner uifigure
        %   3. Delete event listeners
        %   4. Fire CloseEvent so utils.startController removes this plugin
        %      from the parent's childControllers list

            % 1. Close child controllers in reverse order.
            for i = numel(obj.childControllers):-1:1
                child = obj.childControllers{i};
                % isvalid() errors on non-handle types (e.g. []) - always
                % guard with isa() first.
                if isa(child, 'handle') && isvalid(child)
                    child.closeWindow();
                end
            end
            obj.childControllers    = {};
            obj.childControllersIds = {};

            % 2. Delete the figure (guard: interactive mode only).
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                % Clear CloseRequestFcn first to prevent a recursive call
                % if deleting the figure triggers another close event.
                obj.view.gui.CloseRequestFcn = '';
                delete(obj.view.gui);
            end

            % 3. Delete event listeners so they do not fire after deletion.
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end

            % 4. Notify the parent so it can clean up its childControllers.
            notify(obj, 'CloseEvent');
        end

        % =================================================================
        function updateWidgets(obj)
        % updateWidgets  Push current BatchOpt values into all GUI widgets.
        %
        % Called:
        %   • once during construction (after the view is built)
        %   • by ViewListner_Callback2 when UpdateGuiWidgets or NewDataset
        %     fires on MibModel (e.g. the user opens a new file)
        %
        % Flow:
        %   1. Update data-dependent BatchOpt fields
        %   2. Push all fields into their matching widgets via the shared
        %      utility (field name → widget Tag → widget type → assignment)

            % Guard: this method must be a no-op in headless / batch mode.
            if isempty(obj.view); return; end

            % Keep the active-dataset id current; in split-panel mode the
            % active panel can change between calls.
            if isfield(obj.BatchOpt, 'id')
                obj.BatchOpt.id = obj.mibModel.getActiveId();
            end

            % utils.updateGUIFromBatchOpt_Shared iterates every BatchOpt
            % field, finds the AppDesigner widget with a matching Tag, and
            % assigns the value using the appropriate widget property
            % (Value, Limits, RoundFractionalValues, Items, ...).
            obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        % =================================================================
        function updateBatchOptFromGUI(obj, event)
        % updateBatchOptFromGUI  Pull a changed widget value into BatchOpt.
        %
        % Wire this as the ValueChangedFcn for every interactive widget in
        % DemoPluginGUI.mlapp.  The AppDesigner callback signature is:
        %   function MyWidget_ValueChanged(app, event)
        %       app.winController.updateBatchOptFromGUI(event);
        %   end
        %
        % The shared utility inspects event.Source.Type to know how to
        % extract the new value (e.g. .Value for editfields/checkboxes,
        % .Value+.Limits+.RoundFractionalValues for spinners) and which
        % BatchOpt field to update (using event.Source.Tag).
        %
        % Parameters:
        % event: AppDesigner event - event.Source is the changed widget

            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared( ...
                obj.BatchOpt, event.Source);
        end

        % =================================================================
        function returnBatchOpt(obj, BatchOptOut)
        % returnBatchOpt  Send BatchOpt to the MIB macro recorder.
        %
        % Fires the 'SyncBatch' event on mibModel, carrying the current
        % BatchOpt wrapped in a core.ToggleEventData.  The MIB batch
        % controller listens for SyncBatch to record the operation into the
        % macro script for later replay.
        %
        % Call this at the END of every Calculate() execution so the
        % operation is recorded with the parameters that were actually used.
        %
        % Also called in query mode (NaN passed to constructor) so the
        % batch controller can discover available parameters without running
        % the plugin.
        %
        % Parameters:
        % BatchOptOut: [@em optional] override struct; defaults to obj.BatchOpt.
        %   Use this when Calculate() builds a local BatchOptLoc with extra
        %   transient fields that should not appear in the macro.

            if nargin < 2; BatchOptOut = obj.BatchOpt; end

            % Strip the 'id' field - the active-dataset index is
            % session-specific and meaningless when replaying in a
            % different session with a different file order.
            if isfield(BatchOptOut, 'id')
                BatchOptOut = rmfield(BatchOptOut, 'id');
            end

            % ToggleEventData is a thin wrapper that lets us attach a
            % struct payload to a MATLAB event notification.
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        % =================================================================
        function Calculate(obj)
        % Calculate  Main action - demonstrates BatchOpt round-tripping.
        %
        % In a real plugin this is where the image processing would happen.
        % Here we just read every BatchOpt value and display them in the
        % GUI text area to confirm that all widget types round-trip
        % correctly through the BatchOpt structure.
        %
        % Steps demonstrated:
        %   1. Refresh the active-dataset id at the start
        %   2. Create a cancellable progress dialog (core.PoolWaitbar)
        %   3. Check for virtual-stack mode and abort gracefully if needed
        %   4. Do the work; write results to the GUI or command window
        %   5. Poll the cancel state between work units
        %   6. Clean up the progress dialog
        %   7. Call returnBatchOpt() to register the run in the macro

            % -- 1. Active dataset id -----------------------------------
            % Refresh here so headless batch mode (which skips updateWidgets)
            % always targets the correct dataset.
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            id = obj.BatchOpt.id;

            % -- 2. Progress dialog ------------------------------------
            % Determine the parent figure for the progress dialog.
            % In interactive mode use the plugin window; in batch mode
            % (no GUI) fall back to the main MIB application window.
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                progressParent = obj.view.gui;
            else
                progressParent = obj.mibModel.mibGUI;
            end

            if obj.BatchOpt.showWaitbar
                % core.PoolWaitbar arguments:
                %   (N, message, parentFig, title, cancelable)
                % N = total steps; set to 3 for the three phases below.
                progressBar = core.PoolWaitbar(3, ...
                    sprintf('Starting calculations\nPlease wait...'), ...
                    progressParent, ...
                    'Demo Plugin', ...
                    true);  % true = add a Cancel button
            end

            % -- 3. Virtual-stack guard --------------------------------
            % Plugins that require in-memory pixel access must abort when
            % the dataset is in virtual (out-of-core) mode.
            % Remove this block if your plugin supports virtual stacks.
            if isprop(obj.mibModel.I{id}, 'datasetType') && ...
                    strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, ...
                    '!!! Warning !!!', {''}, ...
                    {'This plugin is not compatible with the virtual stacking mode! Please switch to memory-resident mode and try again.'}, ...
                    'Not implemented', dlgOpt);
                % StopProtocol halts a running batch sequence.
                notify(obj.mibModel, 'StopProtocol');
                if obj.BatchOpt.showWaitbar; progressBar.deletePoolWaitbar(); end
                obj.closeWindow();
                return;
            end

            % -- 4. Core work ------------------------------------------
            % Build a human-readable summary of all current BatchOpt
            % values and display it.
            outputText{1} = sprintf('Parameter:      %s',  obj.BatchOpt.Parameter);
            outputText{2} = sprintf('Checkbox:       %d',  obj.BatchOpt.Checkbox);
            outputText{3} = sprintf('Dropdown:       %s',  obj.BatchOpt.Dropdown{1});
            outputText{4} = sprintf('RadioButton:    %s',  obj.BatchOpt.RadioButtonGroup{1});
            outputText{5} = sprintf('Numeric value:  %g',  obj.BatchOpt.ParameterNumeric{1});

            % Display the results differently depending on whether a GUI
            % is open (interactive mode) or not (batch / headless mode).
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                % Interactive mode: write results into the GUI text area.
                try
                    obj.view.handles.TextArea.Value = outputText;
                catch err
                    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Error writing to TextArea');
                    if obj.BatchOpt.showWaitbar; progressBar.deletePoolWaitbar(); end
                    return;
                end
            else
                % Batch / headless mode: print to the command window so
                % macro recordings produce visible output.
                fprintf('DemoPlugin results:\n');
                for lineId = 1:numel(outputText)
                    fprintf('  %s\n', outputText{lineId});
                end
            end

            % -- 5a. Cancel check after first work unit ----------------
            if obj.BatchOpt.showWaitbar
                if progressBar.getCancelState()
                    progressBar.deletePoolWaitbar(); return;
                end
                progressBar.updateText(sprintf('Updating display\nPlease wait...'));
                progressBar.increment();    % progress: 1/3
            end

            % -- 5b. Simulate a second work unit (replace with real code)
            % ... do more work here ...

            if obj.BatchOpt.showWaitbar
                if progressBar.getCancelState()
                    progressBar.deletePoolWaitbar(); return;
                end
                progressBar.updateText(sprintf('Finishing\nPlease wait...'));
                progressBar.increment();    % progress: 2/3
            end

            fprintf('DemoPlugin.Calculate: completed\n');

            % -- 6. Clean up progress dialog ---------------------------
            if obj.BatchOpt.showWaitbar
                progressBar.increment();    % progress: 3/3
                progressBar.deletePoolWaitbar();
            end

            % -- 7a. Refresh image display -----------------------------
            % Uncomment the line below if your plugin modifies image,
            % labels, mask, or selection data and you want MIB to redraw.
            % notify(obj.mibModel, 'ShowImage');

            % -- 7b. Register the operation with the macro recorder ----
            % This MUST be the last call in Calculate().  It sends the
            % current BatchOpt to the batch controller so the operation
            % can be replayed later with the same parameters.
            obj.returnBatchOpt();
        end

    end
end
