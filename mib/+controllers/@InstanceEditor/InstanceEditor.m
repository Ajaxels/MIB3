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
        internalEdit = false
        % true while this controller is applying an edit, so its own writes do
        % not mark the index it has just refreshed as stale
        sliceStats = []
        % cached per-object measurements of one slice, for the 2D object list;
        % see currentSliceStats
        tableSlice = []
        % slice the 2D object list was last painted from, so a list that no
        % longer describes the shown slice can say so
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
        runOperation(obj, action)                      % hand an operation to models.MibModel.editInstanceObjects
        highlightObjects(obj)                          % show the picked objects in the Selection layer
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
            % values are actually consumed; the widgets are named to match.
            obj.BatchOpt = struct();
            obj.BatchOpt.Mode3D = true;
            obj.BatchOpt.Connectivity = {'26'};
            obj.BatchOpt.Connectivity{2} = {'26', '6'};
            obj.BatchOpt.ConnectMode = {'interpolate'};
            obj.BatchOpt.ConnectMode{2} = {'interpolate', 'selection'};
            obj.BatchOpt.MinObjectVoxels = {0, [0, 1e9], 'on'};
            obj.BatchOpt.MinObjectSlices = {0, [0, 1e6], 'on'};
            obj.BatchOpt.AbsorbFragmentVoxels = {5, [0, 1e6], 'on'};
            obj.BatchOpt.MaxRows = {1000, [10, 1e5], 'on'};
            obj.BatchOpt.showWaitbar = true;

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
            % spinner limits, table behaviour - so that the two cannot drift
            % apart silently. The object table's column names are the exception
            % and belong to updateObjectTable, because they follow the mode.
            h = obj.view.handles;

            h.objectTable.ColumnSortable = true;
            h.objectTable.SelectionType = 'row';
            h.objectTable.Multiselect = 'on';
            h.selectedList.Multiselect = 'on';

            h.MaxRows.Limits = obj.BatchOpt.MaxRows{2};
            h.MaxRows.RoundFractionalValues = 'on';
            h.MaxRows.Value = obj.BatchOpt.MaxRows{1};

            h.Connectivity.Items = obj.BatchOpt.Connectivity{2};
            h.Connectivity.Value = obj.BatchOpt.Connectivity{1};
            h.ConnectMode.Items = obj.BatchOpt.ConnectMode{2};
            h.ConnectMode.Value = obj.BatchOpt.ConnectMode{1};
            h.Mode3D.Value = obj.BatchOpt.Mode3D;

            for spinner = {'MinObjectVoxels', 'MinObjectSlices', 'AbsorbFragmentVoxels'}
                name = spinner{1};
                h.(name).Limits = obj.BatchOpt.(name){2};
                h.(name).RoundFractionalValues = 'on';
                h.(name).Value = obj.BatchOpt.(name){1};
            end

            % 0 means "no filter" for the two list filters
            h.filterMaxVoxels.Value = 0;
            h.filterMaxSlices.Value = 0;
            h.jumpToIndex.Value = 0;
            h.autoUpdateTable.Value = true;

            obj.applyModeToWidgets();
        end

        % -----------------------------------------------------------
        function applyModeToWidgets(obj)
            % APPLYMODETOWIDGETS - Enable only the widgets the current mode uses.
            %
            % In 2D mode the list describes one slice, so it has a slice to
            % follow and no slice-count column to filter on; in 3D mode it
            % describes the whole model and neither applies.
            h = obj.view.handles;
            use3D = logical(h.Mode3D.Value);
            h.filterMaxSlices.Enable = use3D;
            h.autoUpdateTable.Enable = ~use3D;
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
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.figureKeyPress(%s): triggered\n', eventData.Key);
            end
            notify(obj.mibModel, 'KeyPressEvent', core.ToggleEventData(eventData));
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
            obj.BatchOpt.Connectivity{1} = h.Connectivity.Value;
            obj.BatchOpt.ConnectMode{1}  = h.ConnectMode.Value;
            for spinner = {'MinObjectVoxels', 'MinObjectSlices', 'AbsorbFragmentVoxels', 'MaxRows'}
                obj.BatchOpt.(spinner{1}){1} = h.(spinner{1}).Value;
            end
        end

        % -----------------------------------------------------------
        function mode3D_Callback(obj)
            % MODE3D_CALLBACK - Offer the connectivity values that belong to the mode.
            %
            % 26/6 are the 3-D neighbourhoods and 8/4 the 2-D ones; showing all
            % four at once would let the user pick a meaningless combination.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.mode3D_Callback: triggered\n');
            end

            h = obj.view.handles;
            wasFull = ismember(h.Connectivity.Value, {'26', '8'});
            if h.Mode3D.Value
                items = {'26', '6'};
            else
                items = {'8', '4'};
            end
            h.Connectivity.Items = items;
            if wasFull; h.Connectivity.Value = items{1}; else; h.Connectivity.Value = items{2}; end
            obj.BatchOpt.Connectivity{2} = items;
            obj.updateBatchOptFromGUI();

            % The two modes list different things, so the list has to be
            % repainted with the columns of the mode that is now current.
            obj.applyModeToWidgets();
            obj.updateObjectTable();
            obj.updateStatusLine();
        end

        % -----------------------------------------------------------
        function objectList_Callback(obj, hObject)
            % OBJECTLIST_CALLBACK - A list filter or the row cap changed.
            %
            % Input Arguments:
            %   - **hObject** - handle to the widget that changed
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.InstanceEditor.objectList_Callback(%s): triggered\n', hObject.Tag);
            end
            obj.updateObjectTable();
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
