classdef InstanceEditor < handle
% INSTANCEEDITOR - Controller for the Instance editor window.
%
% Proofreading tool for instance models: lists the objects of a 65535 or
% 4294967295 model and applies split, merge, connect and delete to the ones the
% user picks, either from the table or by clicking them in the image.
%
% Automatic 2D to 3D stitching (``utils.instances.stitch2Dto3D``) leaves errors
% that no threshold can remove - objects fused across many slices, one object
% carrying two indices - and this is where they are repaired by hand.
%
% Launch as a GUI tool::
%
%   obj.mibController.startController('controllers.InstanceEditor', obj.mibController);
%
% The controller holds no editing logic of its own: every operation goes to
% ``models.MibModel.editInstanceObjects``, which owns the undo, the writes and
% the refresh of ``core.MibDataset.instanceIndex``. What lives here is the
% object list, the click picking and the highlighting.
%
% See also: models.MibModel.editInstanceObjects, core.MibDataset.buildInstanceIndex,
% utils.instances.objectIndex, development/deepmib/split_and_merge_toolbox.md

    properties
        mibModel
        % handle to models.MibModel
        mibController
        % handle to controllers.MibController; needed for the image document and
        % for currentModifier, the only reliable source of the modifier keys
        view
        % handle to the view (views.InstanceEditorGUI)
        mibGUI
        % handle to the main MIB figure, used as a dialog parent
        listener
        % cell array of listener handles
        datasetListener
        % listener on the active dataset's SetData event; re-attached whenever
        % the dataset changes, because the event lives on core.MibDataset
        BatchOpt
        % structure compatible with batch processing; field names match widget Tags
        selectedObjects = []
        % indices of the objects currently picked, in the order they were picked
        displayedIds = []
        % object index behind each row currently in objectTable, so a row can be
        % resolved to an object even after the user has sorted the table
        pickModeActive = false
        % true while the editor owns the image mouse
        savedMouseState = []
        % what was taken over when pick mode was switched on, so it can be given
        % back exactly as it was
        shortcutModeActive = false
        % true while the editor owns the a / s / Ctrl+F keys; see setShortcutMode
        internalEdit = false
        % true while this controller is applying an edit, so its own writes do
        % not mark the index it has just refreshed as stale
        highlightState = []
        % what the highlight borrowed from the Selection layer: the box it was
        % painted into, what the user had there beforehand and what was painted
        % over it, so the layer can be handed back untouched; see releaseHighlight
        sliceStats = []
        % cached per-object measurements of one slice, for the 2D object list;
        % see currentSliceStats
        tableSlice = []
        % slice the 2D object list was last painted from, so a list that no
        % longer describes the shown slice can say so
        listOptions = struct('MaxRows', 1000, 'MaxVoxels', 0, 'MaxSlices', 0)
        % how much of the object list is drawn and what is left out of it: the
        % row cap and the two size filters (0 = no filter). They govern the
        % rendering of the list alone and are never sent to the model, which is
        % why they live here rather than in BatchOpt; see askDetectionSettings
    end

    events
        CloseEvent
        % fired when the window is closed
    end

    methods
        % declaration of methods in external files
        addCallbacks(obj)                              % wire the widget callbacks against the App Designer component names
        updateWidgets(obj)                             % refresh the window from the current state of the model
        updateObjectTable(obj)                         % repaint the object list
        stats = currentSliceStats(obj, forceRefresh)   % measure the objects of the shown slice, for the 2D list
        objectTable_SelectionChanged(obj, eventData)   % row selection in the object list
        pickMode_Callback(obj)                         % toggle "pick objects by clicking" from the checkbox
        setPickMode(obj, enable)                       % take over, or hand back, the mouse on the image document
        imageButtonDown(obj)                           % click on the image: select the object under the cursor
        pickObjectUnderCursor(obj, action)             % move the object under the mouse into or out of the selection
        setShortcutMode(obj, enable)                   % take over, or hand back, the a / s / Ctrl+F keys
        runOperation(obj, action)                      % hand an operation to models.MibModel.editInstanceObjects
        accepted = askCleanupSettings(obj, applyNow)   % ask for the three Cleanup thresholds
        askDetectionSettings(obj)                      % ask for the list settings and the connectivity
        highlightObjects(obj)                          % show the picked objects in the Selection layer
        releaseHighlight(obj)                          % take the highlight back out of the Selection layer
        updateStatusLine(obj)                          % report the object count and the state of the index cache
        rebuildIndex(obj)                              % rebuild the per-object index of the active instance model
        closeWindow(obj)                               % close the window and give back everything it took over
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static listener guard; safe even when the view is invalid.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case 'NewDataset'
                    % A different dataset: the object list and everything picked
                    % from the old one are meaningless.
                    obj.selectedObjects = [];
                    % The highlight is forgotten rather than given back: the
                    % buffer it was painted into may hold different data now, and
                    % restoring an old drawing into a freshly loaded dataset is
                    % worse than leaving a selection the user can clear.
                    obj.highlightState = [];
                    obj.attachDatasetListener();
                    obj.updateWidgets();
                case 'UpdateGuiWidgets'
                    obj.updateWidgets();
                    % This event is what MibController refreshes the image
                    % document's mouse callbacks from, so the takeover has to be
                    % renewed right after it.
                    obj.reassertPickMode();
                case 'SliceChanged'
                    obj.reassertPickMode();
                    obj.sliceChanged();
                case 'Undo'
                    % Undo rewinds voxels without telling the index, so its
                    % bounding boxes may now describe a model that is gone.
                    obj.markIndexStale();
                    obj.invalidateSliceStats();
                    obj.updateWidgets();
            end
        end
    end

    methods
        % -----------------------------------------------------------
        function obj = InstanceEditor(mibModel, varargin)
            % INSTANCEEDITOR - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = InstanceEditor(mibModel, mibController)
            %
            % Input Arguments:
            %   - **mibModel** - handle to models.MibModel
            %   - **varargin{1}** - handle to controllers.MibController
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;
            if ~isempty(varargin); obj.mibController = varargin{1}; end

            % Mirrors models.MibModel.editInstanceObjects, which is where these
            % values are actually consumed. Only Mode3D and ConnectMode are
            % carried by a widget named after their field; the rest are set in
            % the two settings dialogs - askDetectionSettings and
            % askCleanupSettings - and kept here between them.
            obj.BatchOpt = struct();
            % Opens in 2D: the list then describes the shown slice, which is the
            % only thing it can describe on a model that has not been stitched
            % into 3D yet - and that is what the editor is usually opened on.
            % The connectivity has to start in the same mode, or the dialog
            % offers 26/6 while the operations run per slice.
            obj.BatchOpt.Mode3D = false;
            obj.BatchOpt.Connectivity = {'8'};
            obj.BatchOpt.Connectivity{2} = {'8', '4'};
            obj.BatchOpt.ConnectMode = {'interpolate'};
            obj.BatchOpt.ConnectMode{2} = {'interpolate', 'selection'};
            obj.BatchOpt.cleanupMinObjectVoxels = {0, [0, 1e9], 'on'};
            obj.BatchOpt.cleanupMinObjectSlices = {0, [0, 1e6], 'on'};
            obj.BatchOpt.cleanupAbsorbFragmentVoxels = {5, [0, 1e6], 'on'};
            obj.BatchOpt.showWaitbar = true;

            % Neither settings dialog has widgets standing behind it, so what was
            % last answered is what the window knows. It is kept for the session:
            % settings that are chosen once for a whole proofreading run do not
            % earn permanent space in a window that is mostly a list, but they
            % must not be forgotten between two presses of the button either.
            if isfield(obj.mibModel.sessionSettings, 'instanceEditor')
                stored = obj.mibModel.sessionSettings.instanceEditor;
                for name = {'cleanupMinObjectVoxels', 'cleanupMinObjectSlices', 'cleanupAbsorbFragmentVoxels'}
                    if isfield(stored, name{1}); obj.BatchOpt.(name{1}){1} = stored.(name{1}); end
                end
                for name = {'MaxRows', 'MaxVoxels', 'MaxSlices'}
                    if isfield(stored, name{1}); obj.listOptions.(name{1}) = stored.(name{1}); end
                end
                % The stored connectivity may belong to the other mode - the
                % window always opens in 2D - so only the stance survives:
                % the full neighbourhood or the minimal one.
                if isfield(stored, 'Connectivity')
                    items = obj.BatchOpt.Connectivity{2};
                    if ismember(stored.Connectivity, {'26', '8'})
                        obj.BatchOpt.Connectivity{1} = items{1};
                    else
                        obj.BatchOpt.Connectivity{1} = items{2};
                    end
                end
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.InstanceEditorGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.closeButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.configureWidgets();
            obj.addCallbacks();
            obj.updateWidgets();
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{3} = addlistener(obj.mibModel, 'Undo',             @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{4} = addlistener(obj.mibModel, 'SliceChanged',     @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.attachDatasetListener();
        end

        % -----------------------------------------------------------
        function configureWidgets(obj)
            % CONFIGUREWIDGETS - Set the widget properties the layout does not carry.
            %
            % The .mlapp owns the layout **and the widget labels**; what is set
            % here is only what has to agree with the code - dropdown items,
            % table behaviour, opening values, tooltips - so that the two cannot
            % drift apart silently. The object table's column names are the
            % exception and belong to updateObjectTable, because they follow the
            % mode.
            h = obj.view.handles;

            h.objectTable.ColumnSortable = true;
            h.objectTable.SelectionType = 'row';
            h.objectTable.Multiselect = 'on';
            h.selectedList.Multiselect = 'on';

            h.ConnectMode.Items = obj.BatchOpt.ConnectMode{2};
            h.ConnectMode.Value = obj.BatchOpt.ConnectMode{1};
            h.Mode3D.Value = obj.BatchOpt.Mode3D;

            h.jumpToIndex.Value = 0;
            h.autoUpdateTable.Value = true;
            % Both takeovers start off and are owned by the controller state, so
            % neither can begin out of step with what the checkbox shows.
            h.pickByClick.Value = false;
            h.useShortcuts.Value = false;

            obj.applyTooltips();
            obj.applyModeToWidgets();
        end

        % -----------------------------------------------------------
        function applyTooltips(obj)
            % APPLYTOOLTIPS - Explain every widget in one hover.
            %
            % The .mlapp carries the labels and this carries the explanations,
            % so that a widget cannot promise something the code stopped doing.
            % Each row names the widgets that share a text: a setting and its
            % label are one row, because the label is what the eye lands on and
            % a tooltip that only answers over the spinner is half a tooltip.
            %
            % One reminder line each. What an operation does in full belongs in
            % the help page, not here.
            h = obj.view.handles;

            tooltips = {
                {'detectionSettings'}, ...
                    'Define settings for detection of objects and number of objects shown in the table';
                {'jumpToIndex', 'GotoobjectLabel'}, ...
                    'Pick an object by its number and move the view to it. Reaches objects the filters and the row limit keep off the list.'
                {'updateTable'}, ...
                    'Re-read the shown slice and repaint the list. 2D mode only.'
                {'autoUpdateTable'}, ...
                    ['Repaint the list every time the shown slice changes. Turn it off on a large ' ...
                     'stack and press "Update list" when you need it. 2D mode only.']
                {'pickByClick'}, ...
                    ['Pick objects by clicking them in the image: ' newline ...
                     '  - a click starts a new selection,' newline ...
                     '  - shift+click adds an object' newline ...
                     '  - ctrl+click takes the object out']
                {'useShortcuts'}, ...
                    ['Give these keys to the editor while it is open:' newline ...
                     '    - a: commit the drawing: merge what it covers, grow one object, or create a new one' newline ...
                     '    - s: split by the drawing' newline ...
                     '    - c: empty the list of picked objects (the drawing is kept)' newline ...
                     '   - ctrl+f: add the object under the mouse to the selection' newline ...
                     'Their usual meanings come back when this is unticked.']
                {'selectedList', 'SelectedobjectsLabel'}, ...
                    'Objects the next operation will act on. Right click to drop the highlighted ones or to clear the list.'
                {'Mode3D'}, ...
                    ['On: work with 3D objects' newline ...
                     'Off: work with 2D objects']
                {'ConnectMode', 'ConnectModeDropDownLabel'}, ...
                    ['How Connect bridges: interpolate morphs between the two facing cross-sections and ' ...
                     'needs a gap in Z; selection uses the shape drawn in the Selection layer and does ' ...
                     'not. 3D mode only.']
                {'mergeButton'}, ...
                    ['Join the picked objects into one, which keeps the smallest of their indices. ' ...
                     'With nothing picked the selection later decides what to join, and the background under it ' ...
                     'joins too: several objects become one connected piece, a single object grows by the ' ...
                     'drawing, and a drawing on empty space becomes a new object.']
                {'splitComponentsButton'}, ...
                    'Break each picked object into its separate pieces. The largest keeps the index, the rest get new ones.'
                {'splitBySelectionButton'}, ...
                    ['Cut the drawing out of the objects underneath it and split what is left. ' ...
                     'Nothing needs to be picked; picking first keeps the cut to those objects.']
                {'cutAtSliceButton'}, ...
                    'Split the picked object along Z: from the shown slice onwards becomes a new object. 3D mode only.'
                {'connectButton'}, ...
                    ['Bridge exactly two picked objects and join them. Only empty space is filled, ' ...
                     'so an object lying between them is never overwritten. 3D mode only.']
                {'deleteButton'}, ...
                    'Delete the picked objects.'
                {'cleanupButton'}, ...
                    ['Delete or absorb the noise of the whole model, without re-stitching it. ' ...
                     'Asks for the three filters first; object numbers are left alone.']
                {'cleanupOptions'}, ...
                    'Defone options used for cleanup of the model'
                {'compactButton'}, ...
                    'Renumber the objects to a continuous 1, 2, 3... after deletes and splits have left gaps. All numbers change.'
                {'rebuildButton'}, ...
                    'Re-read the whole model and rebuild the object list. Needed after another tool has changed the model.'
                {'helpButton'}, ...
                    'Open the help page for the Instance editor.'
                {'closeButton'}, ...
                    'Close the editor and give back the mouse and the keys it has taken over.'
                };

            for row = 1:size(tooltips, 1)
                for widget = tooltips{row, 1}
                    h.(widget{1}).Tooltip = tooltips{row, 2};
                end
            end
        end

        % -----------------------------------------------------------
        function applyModeToWidgets(obj)
            % APPLYMODETOWIDGETS - Enable only the widgets the current mode can use.
            %
            % Each name below is something the other mode cannot do at all,
            % rather than something it does differently:
            %
            % - **Volume only.** *Cut at slice* refuses a single slice outright.
            %   *Connect* bridges a gap along Z and then merges the **whole** of
            %   both objects - ``iPlanConnect`` passes ``use3D`` as ``true``
            %   whatever the mode says - so on one slice it would quietly reach
            %   through the entire stack, which is the worst of the three
            %   outcomes: an operation that appears to obey the mode and does
            %   not. *Connect mode* belongs to it and greys out with it. The
            %   slice-count filter has no such column to filter on in 2D, and is
            %   left out of the settings dialog there rather than greyed out.
            % - **Slice only.** The 2D list follows the shown slice, so the
            %   automatic refresh and the button that forces it exist for that
            %   mode alone. In 3D the list is painted from the cached index and
            %   *Rebuild* is what renews it.
            %
            % The whole-model operations stay on in both modes on purpose:
            % *Cleanup* and *Compact* read the whole volume whatever the mode
            % says, and someone working slice by slice on a stitched model still
            % has every reason to reach for them. The labels are switched with
            % their widgets, so a disabled setting does not keep a live-looking
            % caption next to it.
            h = obj.view.handles;
            use3D = logical(h.Mode3D.Value);

            volumeOnly = {'cutAtSliceButton', 'connectButton', ...
                'ConnectMode', 'ConnectModeDropDownLabel'};
            sliceOnly = {'autoUpdateTable', 'updateTable'};

            for widget = volumeOnly; h.(widget{1}).Enable = use3D;  end
            for widget = sliceOnly;  h.(widget{1}).Enable = ~use3D; end
        end

        % -----------------------------------------------------------
        function attachDatasetListener(obj)
            % ATTACHDATASETLISTENER - Watch the active dataset for edits made elsewhere.
            %
            % SetData is an event of core.MibDataset, not of MibModel, so the
            % listener has to follow whichever dataset is active. Brush strokes,
            % other tools and batch actions all come through here; the index
            % must be marked stale for every one of them, because acting on a
            % stale bounding box writes the wrong voxels.
            if ~isempty(obj.datasetListener) && isvalid(obj.datasetListener)
                delete(obj.datasetListener);
            end
            dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
            obj.datasetListener = addlistener(dataset, 'SetData', ...
                @(~, evnt) obj.dataChangedElsewhere(evnt));
        end

        % -----------------------------------------------------------
        function dataChangedElsewhere(obj, evnt)
            % DATACHANGEDELSEWHERE - SetData handler; marks the index stale.
            if obj.internalEdit; return; end     % our own write, already accounted for
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            changedType = '';
            if isprop(evnt, 'Parameters') && isstruct(evnt.Parameters) && isfield(evnt.Parameters, 'type')
                changedType = evnt.Parameters.type;
            end
            % The user has started drawing in the layer the highlight borrowed.
            % It goes back to them now, while the highlight and the drawing can
            % still be told apart - and because the drawing is very likely the
            % cut for the next Split by selection.
            if ismember(changedType, {'selection', 'everything'})
                obj.releaseHighlight();
            end

            % Only the model layer invalidates the index; a selection or mask
            % write leaves the objects exactly where they were.
            if isempty(changedType) || ismember(changedType, {'labels', 'model', 'everything'})
                obj.markIndexStale();
                obj.invalidateSliceStats();
                obj.updateStatusLine();
            end
        end

        % -----------------------------------------------------------
        function markIndexStale(obj)
            % MARKINDEXSTALE - Flag the cached object index as out of date.
            dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
            if ~isempty(dataset.instanceIndex) && isstruct(dataset.instanceIndex)
                dataset.instanceIndex.stale = true;
            end
        end

        % -----------------------------------------------------------
        function tf = indexIsUsable(obj)
            % INDEXISUSABLE - true when the cached index describes the shown model.
            dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
            index = dataset.instanceIndex;
            tf = ~isempty(index) && isstruct(index) && isfield(index, 'stale') && ...
                ~index.stale && isequal(index.timePoint, dataset.getCurrentTimePoint());
        end

        % -----------------------------------------------------------
        function tf = modelIsEditable(obj)
            % MODELISEDITABLE - true when the active dataset holds an instance model.
            dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
            tf = dataset.modelExist && dataset.enableSelection ~= 0 && ...
                dataset.labels.maxMaterials >= 65535 && ...
                strcmp(dataset.datasetType, 'Standard');
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.helpButton_Callback: triggered\n');
            end
            helpFilePath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', ...
                'user-interface', 'ribbon', 'model', 'model-instance-editor.html');
            utils.openHelpPage(helpFilePath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/model/model-instance-editor.html');
        end

        % -----------------------------------------------------------
        function figureKeyPress(obj, eventData)
            % FIGUREKEYPRESS - Forward key presses to MIB so its shortcuts keep working.
            %
            % Everything goes through, so ++ctrl+z++, ++i++ and the rest behave
            % in this window as they do over the image. The one exception is a
            % key typed into a field of this window: the re-broadcast reaches
            % ``MibController.gui_WindowKeyPressFcn`` with no ``CurrentObject``
            % to look at, so its own guard against that cannot fire and the
            % check has to happen here instead.
            focused = obj.view.gui.CurrentObject;
            if ~isempty(focused) && isprop(focused, 'Type') && ...
                    ismember(focused.Type, {'uieditfield', 'uinumericeditfield', 'uitextarea', 'uispinner'})
                return;
            end

            % A modifier on its own is not a shortcut and there is nothing at
            % the other end to do with it.
            if ismember(eventData.Key, {'control', 'shift', 'alt'}); return; end

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.figureKeyPress(%s): triggered\n', eventData.Key);
            end

            % The payload is a struct carrying the event under .eventdata, which
            % is what MibController.listner_ModelEvent unpacks
            % (``evnt.Parameters.eventdata``). Handing it the KeyData object
            % directly - as this did - throws inside the listener for every key
            % pressed in this window, which is silent enough that the window
            % simply looked deaf to MIB's shortcuts.
            payload = struct();
            payload.eventdata = eventData;
            notify(obj.mibModel, 'KeyPressEvent', core.ToggleEventData(payload));
        end

        % -----------------------------------------------------------
        function imageDocument = imageDocument(obj)
            % IMAGEDOCUMENT - Handle of the image document of the active dataset, or [].
            imageDocument = [];
            if isempty(obj.mibController); return; end
            selectedSet = obj.mibModel.Sets.selectedSet;
            if numel(obj.mibController.cImageDoc) < selectedSet; return; end
            candidate = obj.mibController.cImageDoc{selectedSet};
            if isempty(candidate) || ~isvalid(candidate); return; end
            imageDocument = candidate;
        end

        % -----------------------------------------------------------
        function reassertPickMode(obj)
            % REASSERTPICKMODE - Take the image mouse back after MIB has reclaimed it.
            %
            % ``MibController.updateGuiWidgets`` reinstalls every image
            % document's own ``WindowButtonDownFcn`` unconditionally, at the end
            % of its refresh. ``editInstanceObjects`` fires ``UpdateGuiWidgets``
            % when it finishes, and so does much of the rest of MIB, so without
            % this the takeover survives only until the first operation: clicking
            % silently goes back to painting with the active segmentation tool
            % while the checkbox still says the editor owns the mouse. Nothing on
            % screen explains it, because MIB's default pointer over the image is
            % a crosshair too.
            if ~obj.pickModeActive; return; end

            saved = obj.savedMouseState;
            if isempty(saved) || ~isvalid(saved.imageDocument) || ~isvalid(saved.imageDocument.UIFigure)
                % The document the mouse was taken from has gone; there is
                % nothing left to give back, so just drop the claim.
                obj.pickModeActive = false;
                obj.savedMouseState = [];
                if ~isempty(obj.view) && isvalid(obj.view.gui)
                    obj.view.handles.pickByClick.Value = false;
                end
                return;
            end

            % A different document is active now - hand the old one back rather
            % than owning the mouse of a window the user is no longer looking at.
            current = obj.imageDocument();
            if isempty(current) || ~isequal(current, saved.imageDocument)
                obj.setPickMode(false);
                return;
            end

            saved.imageDocument.UIFigure.WindowButtonDownFcn = @(~, ~) obj.imageButtonDown();
            saved.imageDocument.UIFigure.Pointer = 'crosshair';
        end

        % -----------------------------------------------------------
        function shortcutMode_Callback(obj)
            % SHORTCUTMODE_CALLBACK - Toggle the keyboard shortcuts from the checkbox.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.shortcutMode_Callback: triggered\n');
            end
            obj.setShortcutMode(logical(obj.view.handles.useShortcuts.Value));
        end

        % -----------------------------------------------------------
        function consumed = handleShortcut(obj, key, modifier)
            % HANDLESHORTCUT - Answer a key offered by MibController.gui_WindowKeyPressFcn.
            %
            % Returns whether the key was used. Anything this declines carries
            % on to MIB's own shortcuts, which is what makes the takeover safe:
            % with no instance model in front of the user, ``a`` and ``s`` go on
            % adding to and subtracting from the material as they always did.
            %
            % Input Arguments:
            %   - **key** - char, lowercase key name from the event
            %   - **modifier** - cell array of modifier names held at the time
            %
            % Output Arguments:
            %   - **consumed** - logical, true when the editor acted on the key
            consumed = false;
            if ~obj.shortcutModeActive; return; end
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            if ~obj.modelIsEditable(); return; end

            hasControl = any(strcmp(modifier, 'control'));
            hasAlt     = any(strcmp(modifier, 'alt'));

            switch key
                case 'a'
                    % ctrl and alt variants belong to MIB; shift does not,
                    % because shift+a is the same shortcut there as a.
                    if hasControl || hasAlt; return; end
                    obj.runOperation('Merge');
                case 's'
                    if hasControl || hasAlt; return; end
                    obj.runOperation('SplitBySelection');
                case 'c'
                    % Empties the list of picked objects, not the Selection
                    % layer as MIB's own 'c' does. Collecting objects with
                    % Ctrl+F is only comfortable if starting again is one key.
                    if hasControl || hasAlt; return; end
                    obj.selectedList_ContextMenu('clear');
                case 'f'
                    if ~hasControl || hasAlt; return; end
                    % Adds rather than replaces: the point of picking objects
                    % from the keyboard is to collect the two that a Merge
                    % needs. "Clear the selection" is on the right-click menu of
                    % the Selected objects list.
                    obj.pickObjectUnderCursor('add');
                otherwise
                    return;
            end

            % Printed only when the key was actually taken, so silence in the
            % trace means the takeover is not reaching this window - the failure
            % that killed pick mode twice.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.handleShortcut(%s): triggered\n', key);
            end
            consumed = true;
        end

        % -----------------------------------------------------------
        function clearInternalEditFlag(obj)
            % CLEARINTERNALEDITFLAG - onCleanup target, so the guard is dropped even on error.
            if isvalid(obj); obj.internalEdit = false; end
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, hObject)
            % UPDATEBATCHOPTFROMGUI - Read the operation settings out of the widgets.
            %
            % Input Arguments:
            %   - **hObject** - *(optional)* handle to the widget that changed.
            %     Supplied only by the widget callbacks; the internal callers
            %     read the same values without a user having touched anything,
            %     which is why the trace marker is theirs alone.
            if nargin < 2; hObject = []; end

            if ~isempty(hObject) && obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.updateBatchOptFromGUI(%s): triggered\n', hObject.Tag);
            end

            h = obj.view.handles;
            obj.BatchOpt.Mode3D = logical(h.Mode3D.Value);
            obj.BatchOpt.ConnectMode{1} = h.ConnectMode.Value;
        end

        % -----------------------------------------------------------
        function mode3D_Callback(obj)
            % MODE3D_CALLBACK - Move the connectivity to the values that belong to the mode.
            %
            % 26/6 are the 3-D neighbourhoods and 8/4 the 2-D ones, and only the
            % pair of the current mode is ever offered - a meaningless
            % combination should not be reachable. What survives the switch is
            % the stance rather than the number: the full neighbourhood stays
            % full and the minimal one stays minimal.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.mode3D_Callback: triggered\n');
            end

            wasFull = ismember(obj.BatchOpt.Connectivity{1}, {'26', '8'});
            if obj.view.handles.Mode3D.Value
                items = {'26', '6'};
            else
                items = {'8', '4'};
            end
            obj.BatchOpt.Connectivity{2} = items;
            if wasFull
                obj.BatchOpt.Connectivity{1} = items{1};
            else
                obj.BatchOpt.Connectivity{1} = items{2};
            end
            obj.updateBatchOptFromGUI();

            % The two modes list different things, so the list has to be
            % repainted with the columns of the mode that is now current.
            obj.applyModeToWidgets();
            obj.updateObjectTable();
            obj.updateStatusLine();
        end

        % -----------------------------------------------------------
        function autoUpdateTable_Callback(obj)
            % AUTOUPDATETABLE_CALLBACK - The automatic list refresh was switched on or off.
            %
            % Switching it on catches the list up straight away; leaving the user
            % to press "Update list" as well would be a click for nothing.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.autoUpdateTable_Callback: triggered\n');
            end
            obj.sliceChanged();
        end

        % -----------------------------------------------------------
        function invalidateSliceStats(obj)
            % INVALIDATESLICESTATS - Drop the cached measurements of the shown slice.
            %
            % Called whenever the model has been written to. The cache is keyed
            % on the slice and the time point, neither of which changes when an
            % object on the slice is split or deleted.
            obj.sliceStats = [];
        end

        % -----------------------------------------------------------
        function sliceChanged(obj)
            % SLICECHANGED - The shown slice moved.
            %
            % Only the 2D list depends on the slice; the 3D list describes the
            % whole model and is unaffected. Refreshing means reading the new
            % slice, which is cheap but not free, and a user scrolling through a
            % stack would pay for it on every step - hence the checkbox. With it
            % off, the list keeps describing the slice it was painted from and
            % the status line says which one that is.
            if isempty(obj.view) || ~isvalid(obj.view.gui); return; end
            if obj.view.handles.Mode3D.Value; return; end
            if ~obj.modelIsEditable(); return; end

            if obj.view.handles.autoUpdateTable.Value
                obj.refreshSliceList();
            else
                obj.updateStatusLine();
            end
        end

        % -----------------------------------------------------------
        function updateTable_Callback(obj)
            % UPDATETABLE_CALLBACK - "Update list" was pressed.
            %
            % Only the button comes through here. The automatic refresh calls
            % refreshSliceList directly, so that the trace marker means a user
            % pressed something rather than firing on every step through a stack.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.updateTable_Callback: triggered\n');
            end
            obj.refreshSliceList();
        end

        % -----------------------------------------------------------
        function refreshSliceList(obj)
            % REFRESHSLICELIST - Re-measure the shown slice and repaint the list.
            %
            % In 2D mode the objects picked on the previous slice are not the
            % objects carrying those indices on this one - the numbering starts
            % again from 1 on every slice - so a selection that the new slice
            % does not contain is dropped rather than silently re-pointed at a
            % different object.
            if ~obj.modelIsEditable(); return; end
            obj.invalidateSliceStats();

            if ~obj.view.handles.Mode3D.Value && ~isempty(obj.selectedObjects)
                stats = obj.currentSliceStats();
                obj.selectedObjects = obj.selectedObjects(ismember(obj.selectedObjects, stats.objectIds));
            end

            obj.updateObjectTable();
            obj.updateSelectedList();
            obj.updateStatusLine();
        end

        % -----------------------------------------------------------
        function updateSelectedList(obj)
            % UPDATESELECTEDLIST - Show what is currently picked.
            %
            % ItemsData carries the object index behind each row, so the context
            % menu can resolve what the user highlighted back to an object
            % without parsing the label.
            h = obj.view.handles.selectedList;
            h.ItemsData = [];      % avoid a transient length mismatch with Items
            if isempty(obj.selectedObjects)
                h.Items = {};
                return;
            end
            h.Items = arrayfun(@(k) sprintf('object %d', k), obj.selectedObjects, ...
                'UniformOutput', false);
            h.ItemsData = obj.selectedObjects;
            h.Value = [];          % nothing highlighted until the user says so
        end

        % -----------------------------------------------------------
        function selectedList_ContextMenu(obj, action)
            % SELECTEDLIST_CONTEXTMENU - Take objects back out of the selection.
            %
            % The selection is built up by clicking objects in the image, and one
            % click too many otherwise means starting the whole pick again.
            % Ctrl-clicking the object in the image removes it too, but only if
            % it is still findable there; this works from the list alone.
            %
            % ``'clear'`` is also the ``c`` key while shortcut mode is on, and it
            % empties the **list**, not the Selection layer - a drawing made for
            % the next operation survives it.
            %
            % Input Arguments:
            %   - **action** - char, ``'remove'`` or ``'clear'``
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.selectedList_ContextMenu(%s): triggered\n', action);
            end

            switch action
                case 'remove'
                    highlighted = obj.view.handles.selectedList.Value;
                    if isempty(highlighted); return; end
                    obj.selectedObjects = setdiff(obj.selectedObjects, highlighted, 'stable');
                case 'clear'
                    obj.selectedObjects = [];
            end

            obj.updateSelectedList();
            obj.updateObjectTable();
            obj.highlightObjects();
        end

        % -----------------------------------------------------------
        function restoreTableSelection(obj)
            % RESTORETABLESELECTION - Re-select the picked objects after a repaint.
            %
            % Selection is by row, and a repaint renumbers the rows, so the rows
            % have to be found again from the object indices behind them.
            h = obj.view.handles;
            if isempty(obj.selectedObjects) || isempty(h.objectTable.Data)
                h.objectTable.Selection = [];
                return;
            end
            displayed = h.objectTable.DisplayData;
            if isempty(displayed); return; end
            [~, rows] = ismember(obj.selectedObjects, displayed.Index);
            h.objectTable.Selection = rows(rows > 0);
        end

        % -----------------------------------------------------------
        function jumpToIndex_Callback(obj)
            % JUMPTOINDEX_CALLBACK - Select an object by typing its number.
            %
            % With the row cap in place a wanted object may not be on the list at
            % all, so being able to name it directly is the only way to reach it.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.jumpToIndex_Callback: triggered\n');
            end

            objectId = obj.view.handles.jumpToIndex.Value;
            if objectId <= 0 || ~obj.modelIsEditable(); return; end

            if obj.view.handles.Mode3D.Value
                if ~obj.indexIsUsable(); return; end
                index = obj.mibModel.I{obj.mibModel.getActiveId()}.instanceIndex;
                if objectId > index.maxIndex || ~index.exists(objectId)
                    uialert(obj.view.gui, sprintf('There is no object %d in this model.', objectId), ...
                        'Unknown object', 'Icon', 'warning');
                    return;
                end
            else
                % In 2D mode the list is the shown slice, so an object that is
                % somewhere else in the stack is not one this mode can reach.
                stats = obj.currentSliceStats();
                if ~ismember(objectId, stats.objectIds)
                    uialert(obj.view.gui, sprintf('There is no object %d on slice %d.', ...
                        objectId, stats.slice), 'Unknown object', 'Icon', 'warning');
                    return;
                end
            end
            obj.selectedObjects = objectId;
            obj.updateObjectTable();
            obj.updateSelectedList();
            obj.highlightObjects();
            obj.goToObject(objectId);
        end

        % -----------------------------------------------------------
        function goToObject(obj, objectId)
            % GOTOOBJECT - Centre the view on an object and show the slice it is on.
            %
            % Same navigation as controllers.Quantification does from its table:
            % without it, a list that names an object is of little use because
            % finding it in the image is a manual hunt.
            dataset = obj.mibModel.I{obj.mibModel.getActiveId()};
            use3D = logical(obj.view.handles.Mode3D.Value);

            if use3D
                if ~obj.indexIsUsable(); return; end
                index = dataset.instanceIndex;
                if objectId > index.maxIndex || ~index.exists(objectId); return; end
                centroid = double(index.centroid(objectId, :));
            else
                % The object is on the shown slice by definition here, so the
                % whole-volume centroid - the centre of every object that shares
                % this index, on every slice - would point somewhere else
                % entirely. Measure it on the slice, and do not move off it.
                stats = obj.currentSliceStats();
                row = find(stats.objectIds == objectId, 1);
                if isempty(row); return; end
                centroid = [stats.centroid(row, :), stats.slice];
            end

            % moveView recentres the visible window, so it needs one. A dataset
            % that has never been drawn carries NaN axes limits, and moveView
            % takes diff() of them: diff of a single NaN is empty, so it hands
            % setAxesLimits an empty range and that errors. Testing for a valid
            % two-element range rather than for emptiness is the difference.
            % Changing the slice below is still worth doing either way.
            [axesX, axesY] = dataset.getAxesLimits();
            axesAreDrawn = numel(axesX) >= 2 && numel(axesY) >= 2 && ...
                all(isfinite(axesX(1:2))) && all(isfinite(axesY(1:2)));
            if axesAreDrawn
                dataset.moveView(centroid(1), centroid(2));
            end

            if ~use3D
                % Already on the right slice; changing it would land on a
                % different object of the same index.
                notify(obj.mibModel, 'ShowImage');
                return;
            end

            orientation = dataset.orientation;
            sliceNumber = max(1, round(centroid(3)));
            dataset.slices{orientation}(1) = sliceNumber;
            dataset.slices{orientation}(2) = sliceNumber;
            notify(obj.mibModel, 'SliceChanged');
        end
    end
end
