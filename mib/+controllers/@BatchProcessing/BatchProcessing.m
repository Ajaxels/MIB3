classdef BatchProcessing < handle
    % classdef BatchProcessing < handle
    % Controller for the Batch Processing tool — MIB3 port of mibBatchController.
    %
    % @code
    % obj.startController('controllers.BatchProcessing'); // as GUI tool
    % @endcode

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
        closeEvent
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
            % function obj = BatchProcessing(mibModel, varargin)
            % Constructor — create a BatchProcessing controller and open its GUI window
            %
            % Builds the obj.Sections action catalogue (via initialize()), creates the
            % AppDesigner view, adjusts fonts, positions the window to the left of the
            % main MIB window, wires all GUI callbacks, registers three model listeners,
            % and makes the window visible.
            %
            % Parameters:
            % mibModel: handle to the application MibModel instance
            % varargin{1}: handle to the parent MibController
            %
            %|
            % @b Examples:
            % @code obj.startController('controllers.BatchProcessing'); @endcode
            %
            % Updates
            %
            obj.mibModel = mibModel;    % assign model
            obj.mibController = varargin{1};    % obtain mibController

            % generate Actions structure
            obj.initialize();

            guiName = 'views.BatchProcessingGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view

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
            obj.view.gui.Icon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
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
            % function listener_Callbacks(obj, src, evnt)
            % dispatch MibModel events to the appropriate GUI update methods
            %
            % Handles three model events:
            % @li UpdateGuiWidgets - refresh all GUI widgets via updateWidgets()
            % @li SyncBatch        - populate the parameter table with the BatchOpt
            %     returned by the last action; auto-add to protocol when the
            %     autoAddToProtocol checkbox is checked
            % @li StopProtocol     - set stopProtocolSwitch and reset the Run button
            %
            % Parameters:
            % src:  source object that fired the event (unused, required by MATLAB)
            % evnt: event data; for SyncBatch, evnt.Parameter carries the BatchOpt struct
            %
            %|
            % @b Examples:
            % @code obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.listener_Callbacks(src, evnt)); @endcode
            %
            % Updates
            %
            % listener_Callbacks - process model events (UpdateGuiWidgets, SyncBatch, StopProtocol)
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            switch evnt.EventName
                case 'UpdateGuiWidgets'
                    obj.updateWidgets();
                case 'SyncBatch'
                    obj.selectedActionTableIndex = 1;
                    % NOTE: do NOT call updateWidgets() here — setting dropdown .Value
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
                    obj.view.handles.runProtocol.BackgroundColor = [0.149 0.902 0.1804];
            end
        end

        function closeWindow(obj)
            % function closeWindow(obj)
            % close the BatchProcessing window and clean up listeners
            %
            %|
            % @b Examples:
            % @code obj.closeWindow(); @endcode
            %
            % Updates
            %

            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end

            % delete listeners, otherwise they stay after deleting of the controller
            for i=1:numel(obj.listener)
                delete(obj.listener{i});
            end

            notify(obj, 'closeEvent');      % notify mibController that this child window is closed
        end

        function addCallbacks(obj)
            % function addCallbacks(obj)
            % attach ValueChangedFcn / ButtonPushedFcn callbacks to every GUI widget
            %
            % Called once from the constructor after the view has been created.
            % Wires the following widgets:
            % @li selectProtocolSection / selectProtocolAction          - selectProtocolSection_Callback
            % @li protocolList                        - protocolList_SelectionCallback
            % @li runProtocol                      - runProtocol_Callback('complete')
            % @li runProtocolFromSelected          - runProtocol_Callback('from')
            % @li runProtocolStep                          - runProtocol_Callback('step')
            % @li runProtocolStepAdvance                   - runProtocol_Callback('stepadvance')
            % @li helpBtn                             - helpBtn_Callback
            % @li loadProtocol / saveProtocol / deleteProtocol - respective methods
            % @li undo / redo                   - backupProtocolRestore('undo'/'redo')
            % @li addToListButton / insertIntoProtocol / updateProtocol - protocolActions_Callback
            % @li listenMIB                           - listenMIB_Callback
            % @li selectedActionTableCell*            - selectedActionTableItem_Update
            % @li selectedActionTable                 - displaySelectedActionTableItems
            %
            %|
            % @b Examples:
            % @code obj.addCallbacks(); @endcode
            %
            % Updates
            %
            % addCallbacks - wire all GUI widget callbacks
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
            % function createContextMenus(obj)
            % create and attach the right-click context menu to selectedActionTable
            %
            % Builds two context menus:
            %
            % protocolList context menu (calls protocolActions_Callback):
            % @li 'Show settings'               - display settings of the selected step
            % @li 'Duplicate'                   - duplicate the selected step
            % @li 'Insert STOP EXECUTION event' - insert a stop step before the selected step
            % @li 'Move up'                     - move the selected step one position up
            % @li 'Move down'                   - move the selected step one position down
            % @li 'Delete from protocol'        - remove the selected step from the protocol
            %
            % selectedActionTable context menu (calls selectedActionTable_ContextCallback):
            % @li 'Add parameter'           - append a new numeric/logical field to CurrentBatch
            % @li 'Delete parameter'        - remove the highlighted field from CurrentBatch
            % @li 'Add directories'         - extend the directory list of a DIR LOOP step
            % @li 'Modify directory'        - replace the selected directory with a new path
            % @li 'Remove directories'      - remove checked entries from a DIR LOOP list
            % @li 'Set second column width' - resize the value column of the parameter table
            %
            %|
            % @b Examples:
            % @code obj.createContextMenus(); @endcode
            %
            % Updates
            %
            % createContextMenus - create programmatic context menus for selectedActionTable
            % context menu for protocolList
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
            % function fitTableColumns(obj)
            % split selectedActionTable columns to fill the table container width
            %
            % Called from the selectProtocolSectionPanel SizeChangedFcn so that columns
            % always fill the available width after window resize, and from
            % updateSelectedActionTable after new data is loaded.
            % Column 1 (parameter names) gets ~38 % of the inner width;
            % column 2 (values) takes the remainder.
            %
            %|
            % @b Examples:
            % @code obj.fitTableColumns(); @endcode
            %
            % Updates
            %
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            w = obj.view.handles.selectedActionTable.InnerPosition(3);
            if w < 20; return; end
            col1 = max(70, round(w * 0.38));
            obj.view.handles.selectedActionTable.ColumnWidth = {col1, max(50, w - col1 - 2)};
        end

        function updateWidgets(obj)
            % function updateWidgets(obj)
            % refresh the section and action dropdowns to reflect current state
            %
            %|
            % @b Examples:
            % @code obj.updateWidgets(); @endcode
            %
            % Updates
            %

            sectionItems = {obj.Sections.Name}';
            obj.view.handles.selectProtocolSection.Items = sectionItems;
            obj.view.handles.selectProtocolSection.Value = sectionItems{obj.selectedSection};

            actionItems = {obj.Sections(obj.selectedSection).Actions.Name}';
            obj.view.handles.selectProtocolAction.Items = actionItems;
            obj.view.handles.selectProtocolAction.Value = actionItems{obj.selectedAction};
        end
    end
end
