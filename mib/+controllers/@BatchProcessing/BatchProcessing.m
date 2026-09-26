classdef BatchProcessing < handle
% BATCHPROCESSING - Controller for the Batch Processing tool - MIB3 port of mibBatchController.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.startController('controllers.BatchProcessing');

    properties
        mibController
        % handle to mibController
        mibModel
        % handles to the model
        view
        % handle to the view
        listener
        % a cell array with handles to listeners
        CurrentBatch
        % a structure with selected Batch options, returned by returnBatchOpt function of the controller
        Protocol = []
        % a structure with picked actions that should be executed
        protocolBackups = {}
        % a cell array with backuped protocols
        protocolBackupsCurrNumber = 0
        % current number of the protocol history
        protocolBackupsMaxNumber = 10
        % maximal number of protocol history for backup
        Sections
        % a strutcure with available Sections and corresponding actions
        % Sections(id).Name -> name of available section (i.e. 'Menu -> File', 'Menu -> Dataset')
        % Sections(id).Actions(id2).Name -> name of an action available for the selected section (i.e. 'Tools for Images -> Image Arithmetics', 'Semi-automatic segmentation --> Global thresholding')
        % Sections(id).Actions(id2).Parameters -> a structure with parameters for the action
        selectedActionTableIndex = 0
        % index of a row selected in the selectedActionTable
        protocolListIndex = 0
        % index of a row selected in the protocolList
        selectedSection = 1
        % index of the selected section, i.e. id for obj.Sections(id) updated by obj.view.handles.selectProtocolSection
        selectedAction = 1
        % index of the selected action for the current section, i.e. id2 for Sections(id).Actions(id2) updated by obj.view.handles.selectProtocolAction
    end

    properties (SetObservable)
        stopProtocolSwitch
        % stop protocol property
    end

    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
        stopProtocol
        % stop batch
    end

    methods
        % declaration of functions in the external files, keep empty line in between for the doc generator
        backupProtocol(obj)                                                                           % backup current protocol for undo/redo
        backupProtocolRestore(obj, mode)                                                              % restore protocol from backup (undo/redo)
        deleteProtocol(obj)                                                                           % delete current protocol
        directoryLoopAction_Callback(obj, BatchOptInput)                                              % callback for Directory Loop action
        directoryOperationsAction_Callback(obj, BatchOptInput)                                        % callback for Directory operations action
        displaySelectedActionTableItems(obj, evnt)                                                    % display options for selected table row
        status = doBatchStep(obj, stepId, stepOptions)                                                % execute a single protocol step
        status = doFileLoop(obj, startStep, finishStep, options)                                      % loop over files in a directory
        status = doSeriesLoop(obj, startStep, finishStep)                                             % loop over Bio-Formats series
        fileLoopAction_Callback(obj, BatchOptInput)                                                   % callback for File Loop action
        fileOperationsAction_Callback(obj, BatchOptInput)                                             % callback for File operations action
        helpBtn_Callback(obj)                                                                         % show help page
        initialize(obj)                                                                               % build the obj.Sections catalogue of all available batch actions
        listenMIB_Callback(obj)                                                                       % enable/disable listener to MIB events
        loadProtocol(obj)                                                                             % load protocol from file
        dirOut = obtainDirectoryForAction(obj, dirModeField, filenameField, stepId, stepOptions)      % resolve directory paths for batch steps
        protocolActions_Callback(obj, options)                                                        % modify protocol (add/insert/update/delete/move/etc.)
        protocolList_SelectionCallback(obj)                                                           % callback for row selection in protocolList
        runProtocol_Callback(obj, parameter)                                                       % run protocol (complete/from/step/stepadvance)
        saveProtocol(obj)                                                                             % save protocol to file
        selectProtocolSection_Callback(obj, hObject)                                                           % callback for section/action popups
        selectedActionTable_ContextCallback(obj, parameter)                                           % context menu callback for selectedActionTable
        selectedActionTableItem_Update(obj, hObject)                                                  % update selected action in table
        updateProtocolList(obj)                                                                       % update the protocol list display
        updateSelectedActionTable(obj, BatchOpt)                                                      % update selected action table from BatchOpt

        function obj = BatchProcessing(mibModel, varargin)
            % BATCHPROCESSING - Constructor - create a BatchProcessing controller and open its GUI window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = BatchProcessing(mibModel, mibController)
            %
            % Builds the obj.Sections action catalogue (via initialize()), creates the
            % AppDesigner view, adjusts fonts, positions the window to the left of the
            % main MIB window, wires all GUI callbacks, registers three model listeners,
            % and makes the window visible.
            %
            % Input Arguments:
            %   - **mibModel** - handle to the application MibModel instance
            %   - **varargin{1}** - handle to the parent MibController
            %
            % **Example** - start the batch processing controller:
            %
            %   .. code-block:: matlab
            %
            %      obj.startController('controllers.BatchProcessing');
            obj.mibModel = mibModel;    % assign model
            obj.mibController = varargin{1};    % obtain mibController

            % generate Actions structure
            obj.initialize();

            guiName = 'views.BatchProcessingGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme
            obj.view.handles.protocolComments.BackgroundColorMode = 'auto';   % the mlapp light grey is unreadable with the dark theme font

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.valueLabel.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.valueLabel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            % populate section dropdown
            obj.view.handles.selectProtocolSection.Items = {obj.Sections.Name}';

            % show column headers (provides drag handles for user resize)
            obj.view.handles.selectedActionTable.ColumnName = {'Parameter', 'Value'};

            % add images to buttons
            obj.view.handles.runProtocolStep.Icon = core.MibIconCache.get('alpha_cache', 'step_16px'); % obj.mibModel.sessionSettings.guiImages.step; 
            obj.view.handles.runProtocolStepAdvance.Icon = core.MibIconCache.get('alpha_cache', 'step_and_advance_16px'); % obj.mibModel.sessionSettings.guiImages.step_and_advance;

            % wire all callbacks
            obj.addCallbacks();

            % create context menus
            obj.createContextMenus();

            obj.updateWidgets();

            % add handle tags to the tooltips
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end
            % show the gui
            obj.view.gui.Visible = 'on';    % turn on the window

            % re-fit table columns whenever the parent panel is resized;
            % AutoResizeChildren must be off or SizeChangedFcn will never fire
            obj.view.handles.selectProtocolSectionPanel.AutoResizeChildren = 'off';
            obj.view.handles.selectProtocolSectionPanel.SizeChangedFcn = @(~,~) obj.fitTableColumns();

            % add listeners to obj.mibModel
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.listener_Callbacks(src, evnt));    % listen for update of widgets
            obj.listener{2} = addlistener(obj.mibModel, 'SyncBatch', @(src,evnt) obj.listener_Callbacks(src, evnt));           % listen for return of the batch structure
            obj.listener{3} = addlistener(obj.mibModel, 'StopProtocol', @(src,evnt) obj.listener_Callbacks(src, evnt));        % listen for stop protocol event

            % populate the parameter table for the first section/action at startup;
            % must be called AFTER listeners are registered so that the SyncBatch
            % event fired by eval() is caught by listener{2}
            obj.selectProtocolSection_Callback(obj.view.handles.selectProtocolSection);
        end

        function listener_Callbacks(obj, src, evnt)
            % LISTENER_CALLBACKS - dispatch MibModel events to the appropriate GUI update methods.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.listener_Callbacks(src, evnt)
            %
            % Handles three model events:
            % - UpdateGuiWidgets - refresh all GUI widgets via updateWidgets()
            % - SyncBatch        - populate the parameter table with the BatchOpt
            % returned by the last action; auto-add to protocol when the
            % autoAddToProtocol checkbox is checked
            % - StopProtocol     - set stopProtocolSwitch and reset the Run button
            %
            % Input Arguments:
            %   - **src** - source object that fired the event (unused, required by MATLAB)
            %   - **evnt** - event data; for SyncBatch, evnt.Parameter carries the BatchOpt struct
            %
            % **Example** - register listeners for model events:
            %
            %   .. code-block:: matlab
            %
            %      obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.listener_Callbacks(src, evnt));
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view) || ~isvalid(obj.view.gui); return; end
            switch evnt.EventName
                case 'UpdateGuiWidgets'
                    obj.updateWidgets();
                case 'SyncBatch'
                    obj.selectedActionTableIndex = 1;
                    % NOTE: do NOT call updateWidgets() here - setting dropdown .Value
                    % from within a ValueChangedFcn callback causes re-entrant execution
                    % which makes the figure handle invalid.
                    % remove batchModeFlag
                    if isfield(evnt.Parameters, 'batchModeFlag')
                        evnt.Parameters = rmfield(evnt.Parameters, 'batchModeFlag');
                    end
                    obj.updateSelectedActionTable(evnt.Parameters);  % update the selected action table
                    if obj.view.handles.autoAddToProtocol.Value == true     % add to protocol
                        obj.protocolActions_Callback('add');
                    end
                case 'StopProtocol'
                    obj.stopProtocolSwitch = true;
                    obj.view.handles.runProtocol.Text = 'Run protocol';
                    obj.view.handles.runProtocol.BackgroundColor = utils.themeColors(obj.view.gui).dialogAction;
            end
        end

        function closeWindow(obj)
            % CLOSEWINDOW - close the BatchProcessing window and clean up listeners.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.closeWindow()
            %
            % **Example** - close the batch processing window:
            %
            %   .. code-block:: matlab
            %
            %      obj.closeWindow();

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.BatchProcessing.closeWindow: triggered\n');
            end

            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end

            % delete listeners, otherwise they stay after deleting of the controller
            for i=1:numel(obj.listener)
                delete(obj.listener{i});
            end

            notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
        end

        function addCallbacks(obj)
            % ADDCALLBACKS - attach ValueChangedFcn / ButtonPushedFcn callbacks to every GUI widget.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.addCallbacks()
            %
            % Called once from the constructor after the view has been created.
            % Wires callbacks to all GUI widgets:
            %
            %   - ``selectProtocolSection`` / ``selectProtocolAction`` - ``selectProtocolSection_Callback``
            %   - ``protocolList`` - ``protocolList_SelectionCallback``
            %   - ``runProtocol`` - ``runProtocol_Callback('complete')``
            %   - ``runProtocolFromSelected`` - ``runProtocol_Callback('from')``
            %   - ``runProtocolStep`` - ``runProtocol_Callback('step')``
            %   - ``runProtocolStepAdvance`` - ``runProtocol_Callback('stepadvance')``
            %   - ``helpBtn`` - ``helpBtn_Callback``
            %   - ``loadProtocol``, ``saveProtocol``, ``deleteProtocol`` - respective methods
            %   - ``undo``, ``redo`` - ``backupProtocolRestore('undo'/'redo')``
            %   - ``addToProtocol``, ``insertIntoProtocol``, ``updateProtocol`` - ``protocolActions_Callback``
            %   - ``listenMIB`` - ``listenMIB_Callback``
            %   - ``selectedActionTableCell*`` - ``selectedActionTableItem_Update``
            %   - ``selectedActionTable`` - ``displaySelectedActionTableItems``
            %
            % **Example** - attach all GUI callbacks:
            %
            %   .. code-block:: matlab
            %
            %      obj.addCallbacks();
            h = obj.view.handles;

            % section / action dropdowns
            h.selectProtocolSection.ValueChangedFcn = @(src,~) obj.selectProtocolSection_Callback(src);
            h.selectProtocolAction.ValueChangedFcn  = @(src,~) obj.selectProtocolSection_Callback(src);

            % protocol list
            h.protocolList.ValueChangedFcn = @(~,~) obj.protocolList_SelectionCallback();

            % run buttons
            h.runProtocol.ButtonPushedFcn             = @(~,~) obj.runProtocol_Callback('complete');
            h.runProtocolFromSelected.ButtonPushedFcn = @(~,~) obj.runProtocol_Callback('from');
            h.runProtocolStep.ButtonPushedFcn                 = @(~,~) obj.runProtocol_Callback('step');
            h.runProtocolStepAdvance.ButtonPushedFcn          = @(~,~) obj.runProtocol_Callback('stepadvance');

            % protocol management buttons
            h.helpBtn.ButtonPushedFcn        = @(~,~) obj.helpBtn_Callback();
            h.loadProtocol.ButtonPushedFcn   = @(~,~) obj.loadProtocol();
            h.saveProtocol.ButtonPushedFcn   = @(~,~) obj.saveProtocol();
            h.deleteProtocol.ButtonPushedFcn = @(~,~) obj.deleteProtocol();
            h.undo.ButtonPushedFcn           = @(~,~) obj.backupProtocolRestore('undo');
            h.redo.ButtonPushedFcn           = @(~,~) obj.backupProtocolRestore('redo');
            h.closeButton.ButtonPushedFcn    = @(~,~) obj.closeWindow(); 

            % add / insert / update protocol steps
            h.addToProtocol.ButtonPushedFcn = @(~,~) obj.protocolActions_Callback('add');
            h.insertIntoProtocol.ButtonPushedFcn = @(~,~) obj.protocolActions_Callback('insert');
            h.updateProtocol.ButtonPushedFcn   = @(~,~) obj.protocolActions_Callback('update');

            % listen-to-MIB checkbox
            h.listenMIB.ValueChangedFcn = @(~,~) obj.listenMIB_Callback();

            % parameter editing widgets
            h.selectedActionTableCellEdit.ValueChangedFcn        = @(src,~) obj.selectedActionTableItem_Update(src);
            h.selectedActionTableCellNumericEdit.ValueChangedFcn = @(src,~) obj.selectedActionTableItem_Update(src);
            h.selectedActionTableCellPopup.ValueChangedFcn       = @(src,~) obj.selectedActionTableItem_Update(src);
            h.selectedActionTableCellCheck.ValueChangedFcn       = @(src,~) obj.selectedActionTableItem_Update(src);

            % selected action table cell selection
            h.selectedActionTable.CellSelectionCallback = @(~,evnt) obj.displaySelectedActionTableItems(evnt);
        end

        function createContextMenus(obj)
            % CREATECONTEXTMENUS - create and attach the right-click context menu to selectedActionTable.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.createContextMenus()
            %
            % Builds two context menus:
            %
            % **protocolList context menu** (calls ``protocolActions_Callback``):
            %
            %   - ``Show settings`` - display settings of the selected step
            %   - ``Duplicate`` - duplicate the selected step
            %   - ``Insert STOP EXECUTION event`` - insert a stop step before the selected step
            %   - ``Move up`` - move the selected step one position up
            %   - ``Move down`` - move the selected step one position down
            %   - ``Delete from protocol`` - remove the selected step from the protocol
            %
            % **selectedActionTable context menu** (calls ``selectedActionTable_ContextCallback``):
            %
            %   - ``Add parameter`` - append a new numeric/logical field to CurrentBatch
            %   - ``Delete parameter`` - remove the highlighted field from CurrentBatch
            %   - ``Add directories`` - extend the directory list of a DIR LOOP step
            %   - ``Modify directory`` - replace the selected directory with a new path
            %   - ``Remove directories`` - remove checked entries from a DIR LOOP list
            %   - ``Set second column width`` - resize the value column of the parameter table
            %
            % **Example** - build context menus:
            %
            %   .. code-block:: matlab
            %
            %      obj.createContextMenus();
            cmProtocol = uicontextmenu(obj.view.gui);
            uimenu(cmProtocol, 'Label', 'Show settings',               'MenuSelectedFcn', @(~,~) obj.protocolActions_Callback('show'));
            uimenu(cmProtocol, 'Label', 'Duplicate',                   'MenuSelectedFcn', @(~,~) obj.protocolActions_Callback('duplicate'),   'Separator', 'on');
            uimenu(cmProtocol, 'Label', 'Insert STOP EXECUTION event', 'MenuSelectedFcn', @(~,~) obj.protocolActions_Callback('insertstop'));
            uimenu(cmProtocol, 'Label', 'Move up',                     'MenuSelectedFcn', @(~,~) obj.protocolActions_Callback('moveup'),       'Separator', 'on');
            uimenu(cmProtocol, 'Label', 'Move down',                   'MenuSelectedFcn', @(~,~) obj.protocolActions_Callback('movedown'));
            uimenu(cmProtocol, 'Label', 'Delete from protocol',        'MenuSelectedFcn', @(~,~) obj.protocolActions_Callback('delete'),       'Separator', 'on');
            obj.view.handles.protocolList.ContextMenu = cmProtocol;

            % context menu for selectedActionTable
            cm = uicontextmenu(obj.view.gui);
            uimenu(cm, 'Label', 'Add parameter',           'MenuSelectedFcn', @(~,~) obj.selectedActionTable_ContextCallback('add'));
            uimenu(cm, 'Label', 'Delete parameter',        'MenuSelectedFcn', @(~,~) obj.selectedActionTable_ContextCallback('delete'));
            uimenu(cm, 'Label', 'Add directories',         'MenuSelectedFcn', @(~,~) obj.selectedActionTable_ContextCallback('Add directories'), 'Separator', 'on');
            uimenu(cm, 'Label', 'Modify directory',        'MenuSelectedFcn', @(~,~) obj.selectedActionTable_ContextCallback('Modify directory'));
            uimenu(cm, 'Label', 'Remove directories',      'MenuSelectedFcn', @(~,~) obj.selectedActionTable_ContextCallback('Remove directories'));
            uimenu(cm, 'Label', 'Set second column width', 'MenuSelectedFcn', @(~,~) obj.selectedActionTable_ContextCallback('Set second column width'), 'Separator', 'on');
            obj.view.handles.selectedActionTable.ContextMenu = cm;
        end

        function fitTableColumns(obj)
            % FITTABLECOLUMNS - split selectedActionTable columns to fill the table container width.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.fitTableColumns()
            %
            % Called from the selectProtocolSectionPanel SizeChangedFcn so that columns
            % always fill the available width after window resize, and from
            % updateSelectedActionTable after new data is loaded.
            % Column 1 (parameter names) gets ~38% of inner width; column 2 (values) takes remainder.
            %
            % **Example** - resize table columns to fit container:
            %
            %   .. code-block:: matlab
            %
            %      obj.fitTableColumns();
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view) || ~isvalid(obj.view.gui); return; end
            w = obj.view.handles.selectedActionTable.InnerPosition(3);
            if w < 20; return; end
            col1 = max(70, round(w * 0.38));
            obj.view.handles.selectedActionTable.ColumnWidth = {col1, max(50, w - col1 - 2)};
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - refresh the section and action dropdowns to reflect current state.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateWidgets()
            %
            % **Example** - refresh all GUI widgets:
            %
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets();

            sectionItems = {obj.Sections.Name}';
            obj.view.handles.selectProtocolSection.Items = sectionItems;
            obj.view.handles.selectProtocolSection.Value = sectionItems{obj.selectedSection};

            actionItems = {obj.Sections(obj.selectedSection).Actions.Name}';
            obj.view.handles.selectProtocolAction.Items = actionItems;
            obj.view.handles.selectProtocolAction.Value = actionItems{obj.selectedAction};
        end
    end
end
