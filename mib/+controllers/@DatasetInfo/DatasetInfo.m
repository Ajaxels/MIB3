classdef DatasetInfo < handle
% DATASETINFO - Controller for the Dataset Information window.
%
% Displays metadata of the currently active dataset in a tree view.
% Allows inserting, modifying, deleting, and searching metadata entries.
% Available via the Info button of the Path panel.
%
% The metadata dictionary is obtained from
% ``obj.mibModel.I{id}.image.getMeta()`` and written back via
% ``obj.mibModel.I{id}.image.setMeta(meta)``.  Standard keys (Filename,
% Height, Width, …) are always present; format-specific keys added by
% loaders appear under the **Extras** node.
%
% Usage:
%   .. code-block:: matlab
%
%      obj.mibController.startController('controllers.DatasetInfo');

    properties
        mibModel            % handle to MibModel
        view                % handle to DatasetInfoGUI (set by core.ChildView)
        listener            % cell array of listener handles
        selectedNodeText    % key name of the currently selected tree node
        foundNodeIndex      % index of the last found entry during search (into metaSearchList)
        allTreeNodes        % flat cell array of rendered tree nodes for tree navigation
        metaSearchList      % flat cell array of all metadata entries for search
    end

    events
        CloseEvent          % fired when the window closes
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static guarded listener callback.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        % External method file declarations
        gui_Callbacks(obj, source, event)
        updateWidgets(obj)
        treeNodeExpanded_Callback(obj, src, event)

        % ---------------------------------------------------------------
        function obj = DatasetInfo(mibModel)
            % DATASETINFO - Construct the dataset information controller.
            %
            % Input Arguments:
            %   - **mibModel** — handle to :class:`models.MibModel`.

            obj.mibModel = mibModel;
            obj.selectedNodeText = '';
            obj.foundNodeIndex = 0;
            obj.allTreeNodes = {};

            guiName = 'views.DatasetInfoGUI';
            obj.view = core.ChildView(obj, guiName);
            obj.addCallbacks();

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.closeButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'right');

            obj.view.handles.metaTree.Multiselect = 'on';
            obj.updateWidgets();

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj,src,evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(src,evnt) obj.ViewListner_Callback2(obj,src,evnt));
            obj.view.gui.Visible = 'on';
        end

        % ---------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Close the dialog and release listeners.
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % ---------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire every widget to the central gui_Callbacks dispatcher.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.gui.KeyPressFcn     = @(~,evt) obj.keyPress_Callback(evt);

            widgetHandles = obj.view.handles;
            cb = @(src,evt) obj.gui_Callbacks(src, evt);

            widgetHandles.refreshButton.ButtonPushedFcn   = cb;
            widgetHandles.simplifyButton.ButtonPushedFcn  = cb;
            widgetHandles.findNextButton.ButtonPushedFcn      = cb;
            widgetHandles.findPreviousButton.ButtonPushedFcn  = cb;
            widgetHandles.closeButton.ButtonPushedFcn         = cb;

            widgetHandles.searchEdit.ValueChangedFcn      = cb;
            widgetHandles.metaTree.SelectionChangedFcn    = @(~,~) obj.treeNodeSelected_Callback();

            contextMenu = uicontextmenu(obj.view.gui);
            uimenu(contextMenu, 'Text', 'Insert', 'MenuSelectedFcn', @(~,~) obj.insertButton_Callback());
            uimenu(contextMenu, 'Text', 'Modify', 'MenuSelectedFcn', @(~,~) obj.modifyButton_Callback());
            uimenu(contextMenu, 'Text', 'Delete', 'Separator', 'on', 'MenuSelectedFcn', @(~,~) obj.deleteButton_Callback());
            widgetHandles.metaTree.ContextMenu = contextMenu;
        end

        % ---------------------------------------------------------------
        function keyPress_Callback(obj, eventdata)
            % KEYPRESS_CALLBACK - Forward key presses to the main MIB key handler.
            if isempty(eventdata.Character); return; end
            evtData = struct('eventdata', eventdata);
            notify(obj.mibModel, 'keyPressEvent', core.ToggleEventData(evtData));
        end

        % ---------------------------------------------------------------
        function treeNodeSelected_Callback(obj)
            % TREENODESELECTED_CALLBACK - Update selectedParameterLabel when a tree node is selected.
            nodes = obj.view.handles.metaTree.SelectedNodes;
            if isempty(nodes); return; end

            nodeText = nodes(1).Text;
            colonPos = strfind(nodeText, ':');
            if ~isempty(colonPos)
                obj.selectedNodeText = strtrim(nodeText(1:colonPos(1)-1));
                selectedParameterValue = strtrim(nodeText(colonPos(1)+1:end));
            else
                obj.selectedNodeText = nodeText;
                selectedParameterValue = nodeText;
            end

            obj.view.handles.selectedParameterLabel.Text  = obj.selectedNodeText;
            obj.view.handles.selectedParameterValue.Value = selectedParameterValue;
            
        end

        % ---------------------------------------------------------------
        function simplifyButton_Callback(obj)
            % SIMPLIFYBUTTON_CALLBACK - Remove non-standard metadata entries.
            answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                sprintf('!!! Warning !!!\n\nYou are going to remove most of metadata.\nThe bounding box and the lut colors will be preserved\n\nContinue?'), ...
                'Remove metadata', 'Continue', 'Cancel', 'Cancel');
            if strcmp(answer, 'Cancel'); return; end

            datasetId = obj.mibModel.getActiveId();
            meta = obj.mibModel.I{datasetId}.image.getMeta();

            standardKeys = ["Filename", "Height", "Width", "Depth", "Time", ...
                "ImageDescription", "ColorType", "imgClass", "MaxInt", "Colors", ...
                "Colormap", "SliceName", "SliceSize", "pixSize", "viewPort", ...
                "lutColors", "ActionLog"];

            allKeys = keys(meta);
            removeKeys = allKeys(~ismember(allKeys, standardKeys));
            if ~isempty(removeKeys)
                % rebuild dictionary without extra keys
                keepKeys = allKeys(ismember(allKeys, standardKeys));
                cleanMeta = dictionary();
                for keyIdx = 1:numel(keepKeys)
                    cleanMeta{keepKeys(keyIdx)} = meta{keepKeys(keyIdx)};
                end
                obj.mibModel.I{datasetId}.image.setMeta(cleanMeta);
            end

            % clear custom metadata (BioFormats XML, etc.)
            obj.mibModel.I{datasetId}.image.customMeta = struct();

            obj.updateWidgets();
        end

        % ---------------------------------------------------------------
        function insertButton_Callback(obj)
            % INSERTBUTTON_CALLBACK - Insert a new metadata entry at the
            % depth of the selected node.
            %
            % - If a struct field is selected (e.g. ``pixSize.x``), the new
            %   entry is added as a field of that struct.
            % - If a cell/matrix sub-element is selected, a new element is
            %   appended to the parent array.
            % - Otherwise a new top-level key is added to the dictionary.

            datasetId = obj.mibModel.getActiveId();
            meta = obj.mibModel.I{datasetId}.image.getMeta();

            nodes = obj.view.handles.metaTree.SelectedNodes;
            if ~isempty(nodes)
                nodeData = nodes(1).NodeData;
            else
                nodeData = [];
            end

            % --- customMeta: insert into nested struct ---
            if ~isempty(nodeData) && strcmp(nodeData.key, 'customMeta') && isKey(meta, 'customMeta')
                customMetaValue = meta{'customMeta'};
                subsPath = obj.buildCustomMetaPath(nodes(1));

                prompts = {'New field name:', 'New field value:'};
                defAns = {'', ''};

                if ~isempty(subsPath)
                    [resolvedPath, currentValue] = obj.resolveCustomMetaPath(customMetaValue, subsPath);
                else
                    resolvedPath = [];
                    currentValue = customMetaValue;
                end

                if ~isempty(resolvedPath) && isstruct(currentValue) && isempty(nodes(1).Children)
                    % leaf selected → insert sibling into parent container
                    parentPath = resolvedPath(1:end-1);
                    if isempty(parentPath)
                        container = customMetaValue;
                    else
                        container = subsref(customMetaValue, parentPath);
                    end
                elseif ~isempty(resolvedPath) && isstruct(currentValue)
                    % parent selected → insert child into this container
                    parentPath = resolvedPath;
                    container = currentValue;
                else
                    % customMeta root or unresolved → insert at top level
                    parentPath = [];
                    container = customMetaValue;
                end

                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                    prompts, defAns, 'Insert an entry');
                if isempty(answer); return; end

                newValue = str2double(answer{2});
                if isnan(newValue); newValue = answer{2}; end
                safeName = matlab.lang.makeValidName(answer{1});
                container.(safeName) = newValue;

                if isempty(parentPath)
                    customMetaValue = container;
                else
                    customMetaValue = subsasgn(customMetaValue, parentPath, container);
                end

                meta{'customMeta'} = customMetaValue;
                obj.mibModel.I{datasetId}.image.setMeta(meta);
                obj.updateWidgets();
                return;
            end

            % determine target depth from the selected node
            if ~isempty(nodeData) && isKey(meta, nodeData.key)
                keyName = nodeData.key;
                value = meta{keyName};

                if isstruct(value) && (ischar(nodeData.subIndex) || strcmp(nodeData.populationType, 'struct_fields'))
                    % Struct: user selected a field or the struct section node → add a new field.
                    prompts = {'New field name:', 'New field value:'};
                    if ischar(nodeData.subIndex)
                        fieldValue = value.(char(nodeData.subIndex));
                        if isnumeric(fieldValue)
                            defAns = {'', num2str(fieldValue)};
                        else
                            defAns = {'', char(string(fieldValue))};
                        end
                    else
                        defAns = {'', ''};
                    end
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        sprintf('Add field to "%s"', keyName), ...
                        prompts, defAns, 'Insert an entry');
                    if isempty(answer); return; end
                    newValue = str2double(answer{2});
                    if isnan(newValue); newValue = answer{2}; end
                    value.(answer{1}) = newValue;
                    meta{keyName} = value;
                    obj.mibModel.I{datasetId}.image.setMeta(meta);
                    % Section node or field node — use section node as parent.
                    if strcmp(nodeData.populationType, 'struct_fields')
                        parentNode = nodes(1);
                    else
                        parentNode = nodes(1).Parent;
                    end
                    delete(parentNode.Children);
                    newFieldNode = [];
                    fieldNamesList = fieldnames(value);
                    for fieldIdx = 1:numel(fieldNamesList)
                        fieldValue = value.(fieldNamesList{fieldIdx});
                        if isnumeric(fieldValue)
                            displayText = sprintf('%s: %s', fieldNamesList{fieldIdx}, num2str(fieldValue));
                        else
                            displayText = sprintf('%s: %s', fieldNamesList{fieldIdx}, char(string(fieldValue)));
                        end
                        nd = uitreenode(parentNode, 'Text', displayText, ...
                            'NodeData', struct('key', keyName, 'subIndex', fieldNamesList{fieldIdx}, 'populationType', ''));
                        if strcmp(fieldNamesList{fieldIdx}, answer{1})
                            newFieldNode = nd;
                        end
                    end
                    expand(parentNode);
                    if ~isempty(newFieldNode)
                        obj.view.handles.metaTree.SelectedNodes = newFieldNode;
                        scroll(obj.view.handles.metaTree, newFieldNode);
                    end
                    obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);
                    return;

                elseif iscell(value)
                    % Cell: insert after item, or append if section/single-leaf selected.
                    prompts = {'New value:'};
                    if ~isempty(nodeData.subIndex) && isnumeric(nodeData.subIndex)
                        defAns = {char(string(value{nodeData.subIndex}))};
                    elseif isempty(nodeData.subIndex) && isempty(nodeData.populationType)
                        defAns = {char(string(value{1}))};  % single-item leaf
                    else
                        defAns = {''};
                    end
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        sprintf('Insert into "%s"', keyName), ...
                        prompts, defAns, 'Insert an entry');
                    if isempty(answer); return; end

                    if ~isempty(nodeData.subIndex) && isnumeric(nodeData.subIndex)
                        % A specific item is selected → insert after its index.
                        insertPos = nodeData.subIndex + 1;
                        % Preserve column vs row orientation of the cell array.
                        if size(value, 1) > 1
                            value = [value(1:nodeData.subIndex); {answer{1}}; value(nodeData.subIndex+1:end)];
                        else
                            value = [value(1:nodeData.subIndex), {answer{1}}, value(nodeData.subIndex+1:end)];
                        end
                        meta{keyName} = value;
                        obj.mibModel.I{datasetId}.image.setMeta(meta);
                        parentNode = nodes(1).Parent;
                        delete(parentNode.Children);
                        for itemIdx = 1:numel(value)
                            uitreenode(parentNode, 'Text', char(string(value{itemIdx})), ...
                                'NodeData', struct('key', keyName, 'subIndex', itemIdx, 'populationType', ''));
                        end
                        expand(parentNode);
                        if insertPos <= numel(parentNode.Children)
                            newNode = parentNode.Children(insertPos);
                            obj.view.handles.metaTree.SelectedNodes = newNode;
                            scroll(obj.view.handles.metaTree, newNode);
                        end
                        obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);

                    elseif strcmp(nodeData.populationType, 'cell_items')
                        % Section node selected → append to end and repopulate it.
                        value{end+1} = answer{1};
                        meta{keyName} = value;
                        obj.mibModel.I{datasetId}.image.setMeta(meta);
                        parentNode = nodes(1);
                        delete(parentNode.Children);
                        for itemIdx = 1:numel(value)
                            uitreenode(parentNode, 'Text', char(string(value{itemIdx})), ...
                                'NodeData', struct('key', keyName, 'subIndex', itemIdx, 'populationType', ''));
                        end
                        expand(parentNode);
                        newNode = parentNode.Children(end);
                        obj.view.handles.metaTree.SelectedNodes = newNode;
                        scroll(obj.view.handles.metaTree, newNode);
                        obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);

                    else
                        % Single-item leaf (subIndex=[]) → append; tree node type must change
                        % from leaf to section, so rebuild the skeleton then expand.
                        value{end+1} = answer{1};
                        meta{keyName} = value;
                        obj.mibModel.I{datasetId}.image.setMeta(meta);
                        obj.selectedNodeText = keyName;
                        obj.updateWidgets();
                        for nodeIdx = 1:numel(obj.allTreeNodes)
                            n = obj.allTreeNodes{nodeIdx};
                            if ~isstruct(n.NodeData); continue; end
                            if strcmp(n.NodeData.key, keyName) && strcmp(n.NodeData.populationType, 'cell_items')
                                obj.treeNodeExpanded_Callback([], struct('Node', n));
                                expand(n);
                                if ~isempty(n.Children)
                                    obj.view.handles.metaTree.SelectedNodes = n.Children(end);
                                    scroll(obj.view.handles.metaTree, n.Children(end));
                                end
                                obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);
                                break;
                            end
                        end
                    end
                    return;

                elseif isnumeric(value) && ~isempty(value)
                    % Matrix: insert after row, or append if section/single-leaf selected.
                    numCols = size(value, 2);
                    prompts = {'New row values:'};
                    if ~isempty(nodeData.subIndex) && isnumeric(nodeData.subIndex)
                        defAns = {num2str(value(nodeData.subIndex, :))};
                    elseif isempty(nodeData.subIndex) && isempty(nodeData.populationType)
                        defAns = {num2str(value)};  % single-row leaf
                    else
                        defAns = {num2str(zeros(1, numCols))};
                    end
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                        sprintf('Insert row into "%s"', keyName), ...
                        prompts, defAns, 'Insert an entry');
                    if isempty(answer); return; end
                    newRow = str2num(answer{1}); %#ok<ST2NM>
                    if numel(newRow) ~= numCols; return; end

                    if ~isempty(nodeData.subIndex) && isnumeric(nodeData.subIndex)
                        % A specific row is selected → insert after its index.
                        insertPos = nodeData.subIndex + 1;
                        value = [value(1:nodeData.subIndex, :); newRow; value(nodeData.subIndex+1:end, :)];
                        meta{keyName} = value;
                        obj.mibModel.I{datasetId}.image.setMeta(meta);
                        parentNode = nodes(1).Parent;
                        delete(parentNode.Children);
                        for rowIdx = 1:size(value, 1)
                            uitreenode(parentNode, 'Text', num2str(value(rowIdx, :)), ...
                                'NodeData', struct('key', keyName, 'subIndex', rowIdx, 'populationType', ''));
                        end
                        expand(parentNode);
                        if insertPos <= numel(parentNode.Children)
                            newNode = parentNode.Children(insertPos);
                            obj.view.handles.metaTree.SelectedNodes = newNode;
                            scroll(obj.view.handles.metaTree, newNode);
                        end
                        obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);

                    elseif strcmp(nodeData.populationType, 'matrix_rows')
                        % Section node selected → append to end and repopulate it.
                        value(end+1, :) = newRow;
                        meta{keyName} = value;
                        obj.mibModel.I{datasetId}.image.setMeta(meta);
                        parentNode = nodes(1);
                        delete(parentNode.Children);
                        for rowIdx = 1:size(value, 1)
                            uitreenode(parentNode, 'Text', num2str(value(rowIdx, :)), ...
                                'NodeData', struct('key', keyName, 'subIndex', rowIdx, 'populationType', ''));
                        end
                        expand(parentNode);
                        newNode = parentNode.Children(end);
                        obj.view.handles.metaTree.SelectedNodes = newNode;
                        scroll(obj.view.handles.metaTree, newNode);
                        obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);

                    else
                        % Single-row leaf → append; tree node type must change from leaf to
                        % section, so rebuild the skeleton then expand.
                        value(end+1, :) = newRow;
                        meta{keyName} = value;
                        obj.mibModel.I{datasetId}.image.setMeta(meta);
                        obj.selectedNodeText = keyName;
                        obj.updateWidgets();
                        for nodeIdx = 1:numel(obj.allTreeNodes)
                            n = obj.allTreeNodes{nodeIdx};
                            if ~isstruct(n.NodeData); continue; end
                            if strcmp(n.NodeData.key, keyName) && strcmp(n.NodeData.populationType, 'matrix_rows')
                                obj.treeNodeExpanded_Callback([], struct('Node', n));
                                expand(n);
                                if ~isempty(n.Children)
                                    obj.view.handles.metaTree.SelectedNodes = n.Children(end);
                                    scroll(obj.view.handles.metaTree, n.Children(end));
                                end
                                obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);
                                break;
                            end
                        end
                    end
                    return;
                end
            end

            % default: add a new top-level key
            prompts = {'New parameter name:', 'New parameter value:'};
            defAns = {'', ''};
            answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                prompts, defAns, 'Insert an entry');
            if isempty(answer); return; end

            meta{answer{1}} = answer{2};
            obj.mibModel.I{datasetId}.image.setMeta(meta);
            obj.updateWidgets();
        end

        % ---------------------------------------------------------------
        function modifyButton_Callback(obj)
            % MODIFYBUTTON_CALLBACK - Modify the selected metadata entry.
            nodes = obj.view.handles.metaTree.SelectedNodes;
            if isempty(nodes); return; end

            nodeData = nodes(1).NodeData;
            if isempty(nodeData); return; end

            keyName = nodeData.key;
            subIndex = nodeData.subIndex;

            datasetId = obj.mibModel.getActiveId();
            meta = obj.mibModel.I{datasetId}.image.getMeta();
            if ~isKey(meta, keyName); return; end

            value = meta{keyName};

            % --- customMeta: path-based navigation for nested structs ---
            if strcmp(keyName, 'customMeta')
                if isempty(subIndex); return; end
                customMetaValue = value;

                subsPath = obj.buildCustomMetaPath(nodes(1));
                if isempty(subsPath); return; end

                [resolvedPath, currentValue] = obj.resolveCustomMetaPath(customMetaValue, subsPath);
                if isempty(resolvedPath); return; end

                if isempty(nodes(1).Children)
                    % leaf node: modify name and value
                    nodeText = nodes(1).Text;
                    colonPos = strfind(nodeText, ':');
                    if ~isempty(colonPos)
                        currentName = strtrim(nodeText(1:colonPos(1)-1));
                        currentValueStr = strtrim(nodeText(colonPos(1)+1:end));
                    else
                        currentName = nodeText;
                        currentValueStr = char(string(currentValue));
                    end

                    prompts = {'Parameter name:', 'Parameter value:'};
                    defAns = {currentName, currentValueStr};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                        prompts, defAns, 'Modify the entry');
                    if isempty(answer); return; end

                    newValue = str2double(answer{2});
                    if isnan(newValue); newValue = answer{2}; end

                    parentPath = resolvedPath(1:end-1);
                    oldFieldName = resolvedPath(end).subs;
                    newFieldName = matlab.lang.makeValidName(answer{1});

                    if isempty(parentPath)
                        container = customMetaValue;
                    else
                        container = subsref(customMetaValue, parentPath);
                    end

                    if ~strcmp(newFieldName, oldFieldName)
                        container.(newFieldName) = newValue;
                        container = rmfield(container, oldFieldName);
                    else
                        container.(oldFieldName) = newValue;
                    end

                    if isempty(parentPath)
                        customMetaValue = container;
                    else
                        customMetaValue = subsasgn(customMetaValue, parentPath, container);
                    end

                    nodes(1).Text = sprintf('%s: %s', answer{1}, answer{2});
                else
                    % parent node: modify name
                    nodeText = nodes(1).Text;
                    parenPos = regexp(nodeText, ' \(\d+\)$');
                    if ~isempty(parenPos)
                        currentName = nodeText(1:parenPos-1);
                    else
                        currentName = nodeText;
                    end

                    prompts = {'Node name:'};
                    defAns = {currentName};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                        prompts, defAns, 'Modify the entry');
                    if isempty(answer); return; end

                    newName = answer{1};
                    if strcmp(newName, currentName); return; end
                    safeName = matlab.lang.makeValidName(newName);

                    % identify the '.' segment to rename
                    if isfield(nodeData, 'cellIndex') && ~isempty(nodeData.cellIndex)
                        dotPath = resolvedPath(1:end-2); % parent of cell array field
                        oldFieldName = resolvedPath(end-1).subs;
                    else
                        dotPath = resolvedPath(1:end-1);
                        oldFieldName = resolvedPath(end).subs;
                    end

                    if isempty(dotPath)
                        container = customMetaValue;
                    else
                        container = subsref(customMetaValue, dotPath);
                    end

                    container.(safeName) = container.(oldFieldName);
                    container = rmfield(container, oldFieldName);

                    if isempty(dotPath)
                        customMetaValue = container;
                    else
                        customMetaValue = subsasgn(customMetaValue, dotPath, container);
                    end

                    % update tree text for all siblings sharing the field
                    if isfield(nodeData, 'cellIndex') && ~isempty(nodeData.cellIndex)
                        siblings = nodes(1).Parent.Children;
                        for sibIdx = 1:numel(siblings)
                            sibData = siblings(sibIdx).NodeData;
                            if isfield(sibData, 'cellIndex') && ...
                                    strcmp(char(sibData.subIndex), oldFieldName)
                                sibData.subIndex = safeName;
                                siblings(sibIdx).NodeData = sibData;
                                siblings(sibIdx).Text = sprintf('%s (%d)', ...
                                    newName, sibData.cellIndex);
                            end
                        end
                    else
                        nodeData.subIndex = safeName;
                        nodes(1).NodeData = nodeData;
                        nodes(1).Text = newName;
                    end
                end

                meta{'customMeta'} = customMetaValue;
                obj.mibModel.I{datasetId}.image.setMeta(meta);
                obj.treeNodeSelected_Callback();
                return;
            end

            if isstruct(value) && ~isempty(subIndex) && ~isnumeric(subIndex)
                % struct field (e.g. pixSize.x, viewPort.min)
                fieldName = char(subIndex);
                fieldValue = value.(fieldName);
                prompts = {'Field name:', 'New value:'};
                defAns = {fieldName, num2str(fieldValue)};
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                    prompts, defAns, 'Modify the entry');
                if isempty(answer); return; end
                newValue = str2double(answer{2});
                if isnan(newValue); newValue = answer{2}; end
                if ~strcmp(answer{1}, fieldName)
                    value = rmfield(value, fieldName);
                end
                value.(answer{1}) = newValue;
                meta{keyName} = value;
                obj.mibModel.I{datasetId}.image.setMeta(meta);
                if isnumeric(newValue)
                    nodes(1).Text = sprintf('%s: %s', answer{1}, num2str(newValue));
                else
                    nodes(1).Text = sprintf('%s: %s', answer{1}, char(string(newValue)));
                end
                nd = nodes(1).NodeData; nd.subIndex = answer{1}; nodes(1).NodeData = nd;

            elseif isnumeric(value)
                if ~isempty(subIndex) && isnumeric(subIndex)
                    % row within a multi-row numeric array (e.g. lutColors row)
                    rowValue = value(subIndex, :);
                    prompts = {'Key name:', 'New value:'};
                    defAns = {char(keyName), num2str(rowValue)};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                        prompts, defAns, 'Modify the entry');
                    if isempty(answer); return; end
                    value(subIndex, :) = str2num(answer{2}); %#ok<ST2NM>
                    if ~strcmp(answer{1}, char(keyName))
                        meta = obj.removeDictKey(meta, keyName);
                    end
                    meta{answer{1}} = value;
                    obj.mibModel.I{datasetId}.image.setMeta(meta);
                    nodes(1).Text = num2str(value(subIndex, :));
                    if ~strcmp(answer{1}, char(keyName))
                        % Key renamed — update section node and all populated children.
                        sectionNode = nodes(1).Parent;
                        sectionNode.Text = answer{1};
                        nd = sectionNode.NodeData; nd.key = answer{1}; sectionNode.NodeData = nd;
                        for ci = 1:numel(sectionNode.Children)
                            cnd = sectionNode.Children(ci).NodeData;
                            if ~strcmp(cnd.key, '__loading__')
                                cnd.key = answer{1};
                                sectionNode.Children(ci).NodeData = cnd;
                            end
                        end
                    end
                else
                    % scalar or single-row numeric
                    prompts = {'Key name:', 'New value:'};
                    defAns = {char(keyName), num2str(value)};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                        prompts, defAns, 'Modify the entry');
                    if isempty(answer); return; end
                    newValue = str2num(answer{2}); %#ok<ST2NM>
                    if isempty(newValue); newValue = answer{2}; end
                    if ~strcmp(answer{1}, char(keyName))
                        meta = obj.removeDictKey(meta, keyName);
                    end
                    meta{answer{1}} = newValue;
                    obj.mibModel.I{datasetId}.image.setMeta(meta);
                    nodes(1).Text = sprintf('%s: %s', answer{1}, num2str(newValue));
                    nd = nodes(1).NodeData; nd.key = answer{1}; nodes(1).NodeData = nd;
                end

            elseif iscell(value)
                if ~isempty(subIndex) && isnumeric(subIndex)
                    % single element within a cell array (e.g. SliceName{3})
                    prompts = {'Key name:', 'New value:'};
                    defAns = {char(keyName), char(string(value{subIndex}))};
                    answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                        prompts, defAns, 'Modify the entry');
                    if isempty(answer); return; end
                    value{subIndex} = answer{2};
                    meta{keyName} = value;
                    obj.mibModel.I{datasetId}.image.setMeta(meta);
                    nodes(1).Text = char(string(answer{2}));
                else
                    if numel(value) == 1
                        % Single-item leaf — let the user edit the value (and optionally rename the key).
                        prompts = {'Key name:', 'New value:'};
                        defAns = {char(keyName), char(string(value{1}))};
                        answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                            prompts, defAns, 'Modify the entry');
                        if isempty(answer); return; end
                        value{1} = answer{2};
                        newKeyName = answer{1};
                        if ~strcmp(newKeyName, char(keyName))
                            meta = obj.removeDictKey(meta, keyName);
                        end
                        meta{newKeyName} = value;
                        obj.mibModel.I{datasetId}.image.setMeta(meta);
                        nodes(1).Text = sprintf('%s: %s', newKeyName, char(string(answer{2})));
                        nd = nodes(1).NodeData; nd.key = newKeyName; nodes(1).NodeData = nd;
                    else
                        % Section node selected — only allow renaming the key.
                        prompts = {'Key name:'};
                        defAns = {char(keyName)};
                        answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                            prompts, defAns, 'Modify the entry');
                        if isempty(answer); return; end
                        if ~strcmp(answer{1}, char(keyName))
                            meta = obj.removeDictKey(meta, keyName);
                            meta{answer{1}} = value;
                            obj.mibModel.I{datasetId}.image.setMeta(meta);
                            nodes(1).Text = answer{1};
                            nd = nodes(1).NodeData; nd.key = answer{1}; nodes(1).NodeData = nd;
                            for ci = 1:numel(nodes(1).Children)
                                cnd = nodes(1).Children(ci).NodeData;
                                if ~strcmp(cnd.key, '__loading__')
                                    cnd.key = answer{1};
                                    nodes(1).Children(ci).NodeData = cnd;
                                end
                            end
                        end
                    end
                end

            else
                % char / string values
                prompts = {'Key name:', 'New value:'};
                defAns = {char(keyName), char(string(value))};
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, '', ...
                    prompts, defAns, 'Modify the entry');
                if isempty(answer); return; end
                if ~strcmp(answer{1}, char(keyName))
                    meta = obj.removeDictKey(meta, keyName);
                end
                meta{answer{1}} = answer{2};
                obj.mibModel.I{datasetId}.image.setMeta(meta);
                nodes(1).Text = sprintf('%s: %s', answer{1}, char(string(answer{2})));
                nd = nodes(1).NodeData; nd.key = answer{1}; nodes(1).NodeData = nd;
            end

            % Scroll to the modified node without rebuilding the tree.
            obj.view.handles.metaTree.SelectedNodes = nodes(1);
            scroll(obj.view.handles.metaTree, nodes(1));
            obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);
        end

        % ---------------------------------------------------------------
        function deleteButton_Callback(obj)
            % DELETEBUTTON_CALLBACK - Delete the highlighted tree nodes.
            %
            % Directly removes tree nodes (preserving expand state) and
            % updates the underlying data.  After deletion the tree
            % scrolls to the node above the first deleted item.
            %
            % Handles all node depths:
            %
            % - **Top-level key** — removes the key from the dictionary
            %   (standard keys are protected).
            % - **Struct field** (e.g. ``pixSize.x``) — removes the field.
            % - **Cell element** (e.g. ``SliceName{3}``) — removes the
            %   element and updates sibling indices.
            % - **Matrix row** (e.g. ``lutColors`` row 2) — removes the
            %   row and updates sibling indices.
            % - **customMeta cell** (e.g. ``Instrument (2)``) — removes
            %   only that cell element, not the whole field.
            % - **Parent with children** — removes the key or its children
            %   depending on context.

            answer = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                sprintf('Warning!!!\n\nYou are going to delete the highlighted parameters!\nAre you sure?'), ...
                'Delete entries', 'Delete', 'Cancel', 'Cancel');
            if strcmp(answer, 'Cancel'); return; end

            standardKeys = ["Filename", "Height", "Width", "Depth", "Time", ...
                "ImageDescription", "ColorType", "imgClass", "MaxInt", "Colors", ...
                "Colormap", "SliceName", "SliceSize", "pixSize", "viewPort", ...
                "lutColors", "ActionLog"];

            nodes = obj.view.handles.metaTree.SelectedNodes;
            if isempty(nodes); return; end

            datasetId = obj.mibModel.getActiveId();
            meta = obj.mibModel.I{datasetId}.image.getMeta();

            % find the node visually above the first selected for scroll
            scrollTarget = [];
            for flatIdx = 1:numel(obj.allTreeNodes)
                if obj.allTreeNodes{flatIdx} == nodes(1)
                    if flatIdx > 1
                        scrollTarget = obj.allTreeNodes{flatIdx - 1};
                    end
                    break;
                end
            end

            deletedAny = false;
            parentsToExpand = {};

            for nodeIdx = 1:numel(nodes)
                node = nodes(nodeIdx);
                if ~isvalid(node); continue; end
                nodeData = node.NodeData;
                if isempty(nodeData); continue; end

                keyName = string(nodeData.key);
                subIndex = nodeData.subIndex;

                % --- container nodes (meta root) ---
                if strcmp(keyName, "meta"); continue; end

                % --- Extras group ---
                if strcmp(keyName, "Extras")
                    childNodes = node.Children;
                    for childIdx = numel(childNodes):-1:1
                        childData = childNodes(childIdx).NodeData;
                        if ~isempty(childData)
                            childKey = string(childData.key);
                            if ~ismember(childKey, standardKeys) && isKey(meta, childKey)
                                meta = obj.removeDictKey(meta, childKey);
                                parentsToExpand{end+1} = childNodes(childIdx).Parent; %#ok<AGROW>
                                delete(childNodes(childIdx));
                                deletedAny = true;
                            end
                        end
                    end
                    continue;
                end

                % --- customMeta nodes ---
                if strcmp(keyName, "customMeta")
                    if isempty(subIndex)
                        % customMeta root → clear all
                        if isKey(meta, 'customMeta')
                            meta = obj.removeDictKey(meta, 'customMeta');
                        end
                        parentsToExpand{end+1} = node.Parent; %#ok<AGROW>
                        delete(node);
                        deletedAny = true;
                        continue;
                    end

                    if ~isKey(meta, 'customMeta'); continue; end
                    customMetaValue = meta{'customMeta'};

                    % build substruct path from tree hierarchy
                    subsPath = obj.buildCustomMetaPath(node);
                    if isempty(subsPath); continue; end

                    try
                        if isfield(nodeData, 'cellIndex') && ~isempty(nodeData.cellIndex)
                            % cell element — remove from parent cell array
                            cellIdx = nodeData.cellIndex;
                            parentPath = subsPath(1:end-1); % path to the cell array
                            if isempty(parentPath)
                                parentField = customMetaValue.(char(subIndex));
                            else
                                parentField = subsref(customMetaValue, parentPath);
                            end
                            parentField(cellIdx) = [];
                            if isempty(parentField)
                                % remove the now-empty field from its container
                                containerPath = subsPath(1:end-2);
                                if isempty(containerPath)
                                    customMetaValue = rmfield(customMetaValue, char(subIndex));
                                else
                                    container = subsref(customMetaValue, containerPath);
                                    container = rmfield(container, char(subIndex));
                                    customMetaValue = subsasgn(customMetaValue, containerPath, container);
                                end
                            else
                                if isempty(parentPath)
                                    customMetaValue.(char(subIndex)) = parentField;
                                else
                                    customMetaValue = subsasgn(customMetaValue, parentPath, parentField);
                                end
                            end

                            % update sibling cellIndex values and text
                            fieldName = char(subIndex);
                            siblings = node.Parent.Children;
                            for sibIdx = 1:numel(siblings)
                                sibData = siblings(sibIdx).NodeData;
                                if isvalid(siblings(sibIdx)) && ...
                                        isfield(sibData, 'cellIndex') && ...
                                        strcmp(char(sibData.subIndex), fieldName) && ...
                                        sibData.cellIndex > cellIdx
                                    sibData.cellIndex = sibData.cellIndex - 1;
                                    siblings(sibIdx).NodeData = sibData;
                                    displayName = strrep(strrep(strrep(fieldName, ...
                                        '_dash_', '-'), '_colon_', ':'), '_dot_', '.');
                                    siblings(sibIdx).Text = sprintf('%s (%d)', ...
                                        displayName, sibData.cellIndex);
                                end
                            end
                        else
                            % struct field — remove from parent container
                            parentPath = subsPath(1:end-1);
                            if isempty(parentPath)
                                customMetaValue = rmfield(customMetaValue, char(subIndex));
                            else
                                container = subsref(customMetaValue, parentPath);
                                container = rmfield(container, char(subIndex));
                                customMetaValue = subsasgn(customMetaValue, parentPath, container);
                            end
                        end
                    catch
                        continue; % path doesn't match struct (e.g. inlined Attributes)
                    end

                    if isempty(fieldnames(customMetaValue))
                        meta = obj.removeDictKey(meta, 'customMeta');
                    else
                        meta{'customMeta'} = customMetaValue;
                    end
                    parentsToExpand{end+1} = node.Parent; %#ok<AGROW>
                    delete(node);
                    deletedAny = true;
                    continue;
                end

                % --- regular meta keys ---
                if ~isKey(meta, keyName); continue; end
                value = meta{keyName};

                % sub-element deletion
                if ~isempty(subIndex)
                    if isstruct(value) && ischar(subIndex) && isfield(value, subIndex)
                        value = rmfield(value, subIndex);
                        meta{keyName} = value;
                        parentsToExpand{end+1} = node.Parent; %#ok<AGROW>
                        delete(node);
                        deletedAny = true;

                    elseif iscell(value) && isnumeric(subIndex) && subIndex <= numel(value)
                        value(subIndex) = [];
                        meta{keyName} = value;
                        obj.updateSiblingIndices(node, subIndex);
                        parentsToExpand{end+1} = node.Parent; %#ok<AGROW>
                        delete(node);
                        deletedAny = true;

                    elseif isnumeric(value) && isnumeric(subIndex) && subIndex <= size(value, 1)
                        value(subIndex, :) = [];
                        meta{keyName} = value;
                        obj.updateSiblingIndices(node, subIndex);
                        parentsToExpand{end+1} = node.Parent; %#ok<AGROW>
                        delete(node);
                        deletedAny = true;
                    end
                    continue;
                end

                % top-level key
                if ismember(keyName, standardKeys)
                    continue;   % protect standard keys
                end

                if ~isempty(node.Children)
                    childData = node.Children(1).NodeData;
                    if ~isempty(childData) && strcmp(string(childData.key), keyName)
                        % children are sub-elements → delete entire key
                        meta = obj.removeDictKey(meta, keyName);
                        parentsToExpand{end+1} = node.Parent; %#ok<AGROW>
                        delete(node);
                        deletedAny = true;
                    else
                        % children are separate keys (Extras-like)
                        for childIdx = numel(node.Children):-1:1
                            childData = node.Children(childIdx).NodeData;
                            if ~isempty(childData)
                                childKey = string(childData.key);
                                if ~ismember(childKey, standardKeys) && isKey(meta, childKey)
                                    meta = obj.removeDictKey(meta, childKey);
                                    parentsToExpand{end+1} = node.Children(childIdx).Parent; %#ok<AGROW>
                                    delete(node.Children(childIdx));
                                    deletedAny = true;
                                end
                            end
                        end
                    end
                else
                    meta = obj.removeDictKey(meta, keyName);
                    parentsToExpand{end+1} = node.Parent; %#ok<AGROW>
                    delete(node);
                    deletedAny = true;
                end
            end

            if ~deletedAny
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                    'Standard metadata keys cannot be deleted!', ...
                    {}, {}, 'Delete', dlgOpt);
                return;
            end

            obj.mibModel.I{datasetId}.image.setMeta(meta);

            % re-expand parent nodes that lost a child
            for expandIdx = 1:numel(parentsToExpand)
                parentNode = parentsToExpand{expandIdx};
                if isvalid(parentNode) && ~isempty(parentNode.Children)
                    expand(parentNode);
                end
            end

            % rebuild flat node list after tree manipulation
            obj.allTreeNodes = obj.flattenTreeNodes(obj.view.handles.metaTree);

            % scroll to the node above the deleted one
            if ~isempty(scrollTarget) && isvalid(scrollTarget)
                obj.view.handles.metaTree.SelectedNodes = scrollTarget;
                scroll(obj.view.handles.metaTree, scrollTarget);
                obj.treeNodeSelected_Callback();
            end
        end

        % ---------------------------------------------------------------
        function searchEdit_Callback(obj, parameter)
            % SEARCHEDIT_CALLBACK - Search for text across all metadata entries.
            %
            % Searches the underlying metadata dictionary directly so that
            % entries in collapsed (not yet expanded) sections are found too.
            % When a match is located inside a deferred section, that section
            % is expanded automatically before selecting the tree node.
            %
            % Input Arguments:
            %   - **parameter** — ``'new'`` to start a forward search from
            %     the beginning, ``'next'`` to find the next match,
            %     ``'previous'`` to find the previous match.

            if strcmp(parameter, 'new') || isempty(obj.metaSearchList)
                obj.metaSearchList = obj.buildMetaSearchList();
            end

            % Always sync the search position with the currently selected tree
            % node so that 'next'/'previous' continues relative to wherever the
            % user clicked, not where the last programmatic result landed.
            selectedIdx = obj.getSelectedNodeListIndex();
            if selectedIdx > 0
                obj.foundNodeIndex = selectedIdx;
            elseif strcmp(parameter, 'new')
                obj.foundNodeIndex = 0;
            end

            searchString = lower(obj.view.handles.searchEdit.Value);
            if isempty(searchString); return; end

            listSize = numel(obj.metaSearchList);

            if strcmp(parameter, 'previous')
                startIdx = obj.foundNodeIndex - 1;
                if startIdx < 1; startIdx = listSize; end
                for idx = startIdx:-1:1
                    if contains(lower(obj.metaSearchList{idx}.text), searchString)
                        obj.foundNodeIndex = idx;
                        obj.navigateToMetaEntry(obj.metaSearchList{idx});
                        return;
                    end
                end
            else
                for idx = obj.foundNodeIndex + 1 : listSize
                    if contains(lower(obj.metaSearchList{idx}.text), searchString)
                        obj.foundNodeIndex = idx;
                        obj.navigateToMetaEntry(obj.metaSearchList{idx});
                        return;
                    end
                end
            end

            % no match found
            obj.foundNodeIndex = 0;
            dlgOpt.MsgBoxOnly = true;
            dlgOpt.Icon = 'puffin_warning';
            dlgOpt.WindowStyle = 'modal';
            dlgOpt.HeaderLines = 1;
            utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                'No matching results!', {}, {}, 'Search', dlgOpt);
        end

        % ---------------------------------------------------------------
        function nodeList = flattenTreeNodes(obj, rootNode) %#ok<INUSL>
            % FLATTENTREENODES - Build a flat cell array of all tree nodes (depth-first).
            % Uses an iterative stack to avoid O(N^2) cell-array concatenation
            % that the recursive version incurs when merging sub-lists.
            nodeAccum = {};
            stack = num2cell(rootNode.Children);
            while ~isempty(stack)
                node = stack{end};
                stack(end) = [];
                nodeAccum{end+1} = node; %#ok<AGROW>
                children = node.Children;
                for childIdx = numel(children):-1:1
                    stack{end+1} = children(childIdx); %#ok<AGROW>
                end
            end
            nodeList = nodeAccum;
        end

        % ---------------------------------------------------------------
        function updateSiblingIndices(~, deletedNode, deletedIndex)
            % UPDATESIBLINGINDICES - Decrement numeric subIndex of siblings
            % above the deleted index so that subsequent deletions stay
            % correct.
            parentNode = deletedNode.Parent;
            if isempty(parentNode); return; end
            siblings = parentNode.Children;
            for sibIdx = 1:numel(siblings)
                sibData = siblings(sibIdx).NodeData;
                if ~isempty(sibData) && isnumeric(sibData.subIndex) && ...
                        sibData.subIndex > deletedIndex
                    sibData.subIndex = sibData.subIndex - 1;
                    siblings(sibIdx).NodeData = sibData;
                end
            end
        end

        % ---------------------------------------------------------------
        function subsPath = buildCustomMetaPath(~, node)
            % BUILDCUSTOMMETAPATH - Walk from a customMeta tree node up to
            % the customMeta root, building a substruct path suitable for
            % ``subsref`` / ``subsasgn``.
            %
            % Returns a struct array with ``type`` (``.`` or ``{}``) and
            % ``subs`` fields, e.g.
            % ``[.Instrument, {2}, .Laser, {2}]`` for
            % ``customMeta.Instrument{2}.Laser{2}``.
            segments = {};
            currentNode = node;
            while ~isempty(currentNode)
                nodeData = currentNode.NodeData;
                if isempty(nodeData); subsPath = []; return; end
                if strcmp(string(nodeData.key), 'customMeta') && isempty(nodeData.subIndex)
                    break; % reached customMeta root
                end
                fieldSeg = struct('type', '.', 'subs', char(nodeData.subIndex));
                if isfield(nodeData, 'cellIndex') && ~isempty(nodeData.cellIndex)
                    cellSeg = struct('type', '{}', 'subs', {{nodeData.cellIndex}});
                    segments = [{fieldSeg}, {cellSeg}, segments]; %#ok<AGROW>
                else
                    segments = [{fieldSeg}, segments]; %#ok<AGROW>
                end
                currentNode = currentNode.Parent;
            end
            if isempty(segments)
                subsPath = [];
            else
                subsPath = [segments{:}];
            end
        end

        % ---------------------------------------------------------------
        function [resolvedPath, currentValue] = resolveCustomMetaPath(~, customMetaValue, subsPath)
            % RESOLVECUSTOMMETAPATH - Resolve a tree-derived substruct path
            % against the actual customMeta struct, handling inlined
            % Attributes transparently.
            %
            % First tries the direct path.  If that fails, inserts
            % ``.Attributes`` before the last ``.field`` segment (covers
            % fields inlined from XML Attributes sub-structs).

            % direct path
            try
                currentValue = subsref(customMetaValue, subsPath);
                resolvedPath = subsPath;
                return;
            catch
            end

            % insert .Attributes before the last '.' segment
            lastDotIdx = [];
            for idx = numel(subsPath):-1:1
                if strcmp(subsPath(idx).type, '.')
                    lastDotIdx = idx;
                    break;
                end
            end
            if ~isempty(lastDotIdx)
                attrSeg = struct('type', '.', 'subs', 'Attributes');
                altPath = [subsPath(1:lastDotIdx-1), attrSeg, subsPath(lastDotIdx:end)];
                try
                    currentValue = subsref(customMetaValue, altPath);
                    resolvedPath = altPath;
                    return;
                catch
                end
            end

            resolvedPath = [];
            currentValue = [];
        end

        % ---------------------------------------------------------------
        function newDict = removeDictKey(~, inputDict, keyToRemove)
            % REMOVEDICTKEY - Return a copy of inputDict without keyToRemove.
            %
            % Portable across MATLAB versions: rebuilds the dictionary
            % instead of relying on ``remove()`` which requires R2023b+.
            allKeys = keys(inputDict);
            keepKeys = allKeys(allKeys ~= string(keyToRemove));
            newDict = dictionary();
            for keyIdx = 1:numel(keepKeys)
                newDict{keepKeys(keyIdx)} = inputDict{keepKeys(keyIdx)};
            end
        end

        % ---------------------------------------------------------------
        function list = buildMetaSearchList(obj)
            % BUILDMETASEARCHLIST - Build a flat searchable list of all metadata entries.
            %
            % Scans the metadata dictionary directly (not the visible tree)
            % so that every entry is reachable regardless of which sections
            % are currently expanded.  The returned list is used by
            % :meth:`searchEdit_Callback` to drive forward/backward search.
            %
            % Each element of the returned cell array is a struct with:
            %
            %   - ``text`` — display text exactly as it appears in the tree node
            %   - ``sectionKey`` — ``NodeData.key`` of the deferred section node
            %     to expand before navigating; ``''`` when already visible
            %   - ``sectionPopulationType`` — ``NodeData.populationType`` of
            %     that section node

            list = {};
            datasetId = obj.mibModel.getActiveId();
            meta = obj.mibModel.I{datasetId}.image.getMeta();

            % ---- Scalar keys (always visible leaf nodes) ----
            scalarKeyNames = ["Filename", "Height", "Width", "Depth", "Time", ...
                "Colors", "ColorType", "imgClass", "MaxInt", "ImageDescription"];
            for keyIdx = 1:numel(scalarKeyNames)
                keyName = scalarKeyNames(keyIdx);
                if ~isKey(meta, keyName); continue; end
                value = meta{keyName};
                if isnumeric(value) && numel(value) <= 1
                    text = sprintf('%s: %s', keyName, num2str(value));
                elseif ischar(value) || isstring(value)
                    text = sprintf('%s: %s', keyName, char(value));
                else
                    text = sprintf('%s: %s', keyName, mat2str(value));
                end
                list{end+1} = struct('text', text, 'sectionKey', '', 'sectionPopulationType', ''); %#ok<AGROW>
            end

            % ---- Struct keys: pixSize, viewPort ----
            structKeyNames = ["pixSize", "viewPort"];
            for keyIdx = 1:numel(structKeyNames)
                keyName = char(structKeyNames(keyIdx));
                if ~isKey(meta, keyName); continue; end
                value = meta{keyName};
                if ~isstruct(value); continue; end
                list{end+1} = struct('text', keyName, 'sectionKey', '', 'sectionPopulationType', ''); %#ok<AGROW>
                fieldNamesList = fieldnames(value);
                for fieldIdx = 1:numel(fieldNamesList)
                    fieldValue = value.(fieldNamesList{fieldIdx});
                    if isnumeric(fieldValue)
                        text = sprintf('%s: %s', fieldNamesList{fieldIdx}, num2str(fieldValue));
                    else
                        text = sprintf('%s: %s', fieldNamesList{fieldIdx}, char(string(fieldValue)));
                    end
                    list{end+1} = struct('text', text, 'sectionKey', keyName, 'sectionPopulationType', 'struct_fields'); %#ok<AGROW>
                end
            end

            % ---- Cell array keys: SliceName, ActionLog ----
            cellKeyNames = ["SliceName", "ActionLog"];
            for keyIdx = 1:numel(cellKeyNames)
                keyName = char(cellKeyNames(keyIdx));
                if ~isKey(meta, keyName); continue; end
                value = meta{keyName};
                if isempty(value) || ~iscell(value); continue; end
                if numel(value) == 1
                    list{end+1} = struct('text', sprintf('%s: %s', keyName, char(string(value{1}))), ...
                        'sectionKey', '', 'sectionPopulationType', ''); %#ok<AGROW>
                else
                    list{end+1} = struct('text', keyName, 'sectionKey', '', 'sectionPopulationType', ''); %#ok<AGROW>
                    for itemIdx = 1:numel(value)
                        list{end+1} = struct('text', char(string(value{itemIdx})), ...
                            'sectionKey', keyName, 'sectionPopulationType', 'cell_items'); %#ok<AGROW>
                    end
                end
            end

            % ---- Matrix keys: lutColors, Colormap, SliceSize ----
            matrixKeyNames = ["lutColors", "Colormap", "SliceSize"];
            for keyIdx = 1:numel(matrixKeyNames)
                keyName = char(matrixKeyNames(keyIdx));
                if ~isKey(meta, keyName); continue; end
                value = meta{keyName};
                if isempty(value) || ~isnumeric(value); continue; end
                if size(value, 1) == 1
                    list{end+1} = struct('text', sprintf('%s: %s', keyName, num2str(value)), ...
                        'sectionKey', '', 'sectionPopulationType', ''); %#ok<AGROW>
                else
                    list{end+1} = struct('text', keyName, 'sectionKey', '', 'sectionPopulationType', ''); %#ok<AGROW>
                    for rowIdx = 1:size(value, 1)
                        list{end+1} = struct('text', num2str(value(rowIdx, :)), ...
                            'sectionKey', keyName, 'sectionPopulationType', 'matrix_rows'); %#ok<AGROW>
                    end
                end
            end

            % ---- customMeta ----
            if isKey(meta, 'customMeta')
                customMetaValue = meta{'customMeta'};
                if isstruct(customMetaValue) && ~isempty(fieldnames(customMetaValue))
                    list{end+1} = struct('text', 'customMeta', 'sectionKey', '', 'sectionPopulationType', ''); %#ok<AGROW>
                    customTexts = flattenCustomMetaTexts(customMetaValue);
                    for textIdx = 1:numel(customTexts)
                        list{end+1} = struct('text', customTexts{textIdx}, ...
                            'sectionKey', 'customMeta', 'sectionPopulationType', 'customMeta'); %#ok<AGROW>
                    end
                end
            end

            % ---- Extras ----
            processedKeyNames = ["Filename", "Height", "Width", "Depth", "Time", ...
                "Colors", "ColorType", "imgClass", "MaxInt", "ImageDescription", ...
                "pixSize", "viewPort", "SliceName", "ActionLog", ...
                "lutColors", "Colormap", "SliceSize", "customMeta"];
            allKeys = keys(meta);
            extraKeyNames = allKeys(~ismember(allKeys, processedKeyNames));
            if ~isempty(extraKeyNames)
                list{end+1} = struct('text', 'Extras', 'sectionKey', '', 'sectionPopulationType', ''); %#ok<AGROW>
                for keyIdx = 1:numel(extraKeyNames)
                    try
                        value = meta{extraKeyNames(keyIdx)};
                        extraTexts = flattenExtraValueTexts(char(extraKeyNames(keyIdx)), value);
                        for textIdx = 1:numel(extraTexts)
                            list{end+1} = struct('text', extraTexts{textIdx}, ...
                                'sectionKey', '__extras__', 'sectionPopulationType', 'extras'); %#ok<AGROW>
                        end
                    catch
                    end
                end
            end
        end

        % ---------------------------------------------------------------
        function navigateToMetaEntry(obj, entry)
            % NAVIGATETOMETAENTRY - Expand the relevant section and select the
            % tree node that corresponds to a metadata search list entry.
            %
            % If the entry lives inside a deferred (lazy-loaded) section that
            % still holds a ``'Loading...'`` placeholder, the section is
            % populated first.  After expanding, the flat node list is
            % refreshed and the matching node is selected and scrolled to.

            tree = obj.view.handles.metaTree;

            if ~isempty(entry.sectionKey)
                sectionNode = obj.findSectionNode(entry.sectionKey, entry.sectionPopulationType);
                if ~isempty(sectionNode)
                    if ~isempty(sectionNode.Children) && ...
                            isfield(sectionNode.Children(1).NodeData, 'key') && ...
                            strcmp(sectionNode.Children(1).NodeData.key, '__loading__')
                        obj.treeNodeExpanded_Callback([], struct('Node', sectionNode));
                    end
                    expand(sectionNode);
                    obj.allTreeNodes = obj.flattenTreeNodes(tree);
                end
            end

            for nodeIdx = 1:numel(obj.allTreeNodes)
                if strcmpi(obj.allTreeNodes{nodeIdx}.Text, entry.text)
                    tree.SelectedNodes = obj.allTreeNodes{nodeIdx};
                    scroll(tree, obj.allTreeNodes{nodeIdx});
                    obj.treeNodeSelected_Callback();
                    return;
                end
            end
        end

        % ---------------------------------------------------------------
        function idx = getSelectedNodeListIndex(obj)
            % GETSELECTEDNODELISTINDEX - Return the metaSearchList index that
            % corresponds to the currently selected tree node, or 0 if none.
            idx = 0;
            nodes = obj.view.handles.metaTree.SelectedNodes;
            if isempty(nodes); return; end
            selectedText = nodes(1).Text;
            for listIdx = 1:numel(obj.metaSearchList)
                if strcmpi(obj.metaSearchList{listIdx}.text, selectedText)
                    idx = listIdx;
                    return;
                end
            end
        end

        % ---------------------------------------------------------------
        function sectionNode = findSectionNode(obj, sectionKey, sectionPopulationType)
            % FINDSECTIONNODE - Locate a deferred section node by its
            % NodeData key and populationType in the current allTreeNodes list.
            sectionNode = [];
            for nodeIdx = 1:numel(obj.allTreeNodes)
                nd = obj.allTreeNodes{nodeIdx}.NodeData;
                if ~isstruct(nd); continue; end
                if strcmp(string(nd.key), sectionKey) && strcmp(nd.populationType, sectionPopulationType)
                    sectionNode = obj.allTreeNodes{nodeIdx};
                    return;
                end
            end
        end
    end
end

% =====================================================================
%  Local function — recursively flatten a customMeta struct to a list
%  of node text strings.  Mirrors addStructToTree in
%  treeNodeExpanded_Callback.m so that texts match exactly.
% =====================================================================
function texts = flattenCustomMetaTexts(s)
texts = {};
fieldNamesList = fieldnames(s);
for fieldIdx = 1:numel(fieldNamesList)
    fieldName = fieldNamesList{fieldIdx};
    displayName = strrep(strrep(strrep(fieldName, '_dash_', '-'), '_colon_', ':'), '_dot_', '.');
    fieldValue = s.(fieldName);
    if strcmp(fieldName, 'Attributes')
        if isstruct(fieldValue)
            subTexts = flattenCustomMetaTexts(fieldValue);
            texts = [texts, subTexts]; %#ok<AGROW>
        end
    elseif strcmp(fieldName, 'AttributesText')
        % no tree node — skip
    elseif strcmp(fieldName, 'Text')
        if ~isempty(fieldValue)
            texts{end+1} = char(string(fieldValue)); %#ok<AGROW>
        end
    elseif isstruct(fieldValue)
        texts{end+1} = displayName; %#ok<AGROW>
        subTexts = flattenCustomMetaTexts(fieldValue);
        texts = [texts, subTexts]; %#ok<AGROW>
    elseif iscell(fieldValue)
        for cellIdx = 1:numel(fieldValue)
            texts{end+1} = sprintf('%s (%d)', displayName, cellIdx); %#ok<AGROW>
            if isstruct(fieldValue{cellIdx})
                subTexts = flattenCustomMetaTexts(fieldValue{cellIdx});
                texts = [texts, subTexts]; %#ok<AGROW>
            end
        end
    else
        texts{end+1} = sprintf('%s: %s', displayName, char(string(fieldValue))); %#ok<AGROW>
    end
end
end

% =====================================================================
%  Local function — flatten an Extras key value to a list of node text
%  strings.  Mirrors addExtraNode in treeNodeExpanded_Callback.m so
%  that texts match exactly.
% =====================================================================
function texts = flattenExtraValueTexts(keyName, value)
texts = {};
if isnumeric(value) && numel(value) <= 10
    texts{end+1} = sprintf('%s: %s', keyName, num2str(value));
elseif ischar(value) || isstring(value)
    texts{end+1} = sprintf('%s: %s', keyName, char(value));
elseif iscell(value)
    if numel(value) == 1
        texts{end+1} = sprintf('%s: %s', keyName, char(string(value{1})));
    else
        texts{end+1} = keyName;
        for itemIdx = 1:numel(value)
            texts{end+1} = char(string(value{itemIdx})); %#ok<AGROW>
        end
    end
elseif isstruct(value)
    texts{end+1} = keyName;
    fieldNamesList = fieldnames(value);
    for fieldIdx = 1:numel(fieldNamesList)
        fieldValue = value.(fieldNamesList{fieldIdx});
        if isnumeric(fieldValue)
            texts{end+1} = sprintf('%s: %s', fieldNamesList{fieldIdx}, num2str(fieldValue)); %#ok<AGROW>
        elseif ~isstruct(fieldValue)
            texts{end+1} = sprintf('%s: %s', fieldNamesList{fieldIdx}, char(string(fieldValue))); %#ok<AGROW>
        else
            texts{end+1} = fieldNamesList{fieldIdx}; %#ok<AGROW>
        end
    end
elseif isnumeric(value)
    texts{end+1} = sprintf('%s: [%s]', keyName, num2str(size(value)));
else
    texts{end+1} = sprintf('%s: %s', keyName, char(string(value)));
end
end
