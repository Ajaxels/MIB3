function selectedActionTable_ContextCallback(obj, parameter)
% function selectedActionTable_ContextCallback(obj, parameter)
% handle right-click context menu actions on the selected-action parameter table
%
% Each context menu item performs a structural edit on obj.CurrentBatch or on
% the table's visual properties.  The function returns early if no row is
% selected or if obj.CurrentBatch is empty.
%
% Supported operations (parameter):
% @li 'add'               - prompt for a new numeric or logical parameter and
%                           append it to obj.CurrentBatch
% @li 'delete'            - remove the currently highlighted parameter from
%                           obj.CurrentBatch
% @li 'Add directories'   - open a multi-directory chooser and append the
%                           selected paths to the DirectoriesList of a
%                           DIRECTORY LOOP START step
% @li 'Modify directory'  - open a single-directory chooser to replace the
%                           currently selected directory entry; works for
%                           DIRECTORY LOOP START, FILE LOOP START,
%                           Directory operations, File operations, and generic
%                           cell/char directory fields
% @li 'Remove directories'- display a checklist and remove the ticked entries
%                           from the DirectoriesList of a DIRECTORY LOOP START step
% @li 'Set second column width' - prompt for a pixel width and apply it to
%                           the second column of selectedActionTable
%
% Parameters:
% parameter: string matching one of the case labels listed above
%
%|
% @b Examples:
% @code obj.selectedActionTable_ContextCallback('add'); @endcode
% @code obj.selectedActionTable_ContextCallback('Modify directory'); @endcode
% @code obj.selectedActionTable_ContextCallback('Set second column width'); @endcode
%
% Updates
%

if obj.selectedActionTableIndex == 0; return; end
if isempty(obj.CurrentBatch); return; end

switch parameter
    case 'add'  % add parameter
        prompts = {'Parameter type'; 'Parameter name'; 'Custom parameter name';'Parameter value'};
        defAns = {{'numeric', 'logical', 1}; {'z', 'x', 'y', 't', 'c', 'id', 'custom name', 1}; ''; '1'};
        dlgTitle = 'Specify parameter to add';
        options.WindowStyle = 'normal';
        options.PromptLines = [1, 1, 1, 1];
        options.WindowHeight = 260;
        [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, 'Add parameter', prompts, defAns, dlgTitle, options);
        if isempty(answer); return; end

        % select existing or new parameter name
        if ~isempty(answer{3})
            newParName = answer{3};
        else
            newParName = answer{2};
        end

        switch answer{1}
            case 'numeric'
                newValue =  str2num(answer{4});      %#ok<ST2NM>
                if ismember(newParName, {'x', 'y', 'z', 't', 'c'}) && numel(newValue) == 1
                    newValue = [newValue newValue];
                end
                obj.CurrentBatch.(newParName) = newValue;
            case 'logical'
                obj.CurrentBatch.(newParName) = logical(str2num(answer{4})); %#ok<ST2NM>
        end
        obj.updateSelectedActionTable(obj.CurrentBatch);
    case 'delete'   % delete parameter
        fieldNames = fieldnames(obj.CurrentBatch);
        % remove mibBatchSectionName and mibBatchActionName
        fieldNames(ismember(fieldNames, {'mibBatchSectionName', 'mibBatchActionName', 'mibBatchTooltip'})) = [];
        obj.CurrentBatch = rmfield(obj.CurrentBatch, fieldNames{obj.selectedActionTableIndex});
        obj.selectedActionTableIndex = obj.selectedActionTableIndex - 1;
        obj.updateSelectedActionTable(obj.CurrentBatch);
    case 'Add directories'   % add file or directory to the list
        switch obj.CurrentBatch.mibBatchActionName
            case 'DIRECTORY LOOP START'
                selpath = uigetfile_n_dir(fileparts(obj.CurrentBatch.DirectoriesList{1}), 'Select directories');
                if isempty(selpath); return; end

                % look for duplicates
                duplicateIds = ismember(lower(selpath), lower(obj.CurrentBatch.DirectoriesList{2}));
                selpath(duplicateIds) = []; % remove duplicates
                obj.CurrentBatch.DirectoriesList{2} = [obj.CurrentBatch.DirectoriesList{2}; selpath'];     % add to the list
                obj.CurrentBatch.DirectoriesList(1) = obj.CurrentBatch.DirectoriesList{2}(1);      % set as selected option
                obj.updateSelectedActionTable(obj.CurrentBatch);
                obj.displaySelectedActionTableItems();
                obj.selectedActionTableIndex = 1;   % for some strange reason, selectedActionTableIndex gets reset to 0...
            case {'FILE LOOP START', 'Directory operations', 'File operations'}
                warnOpts.MsgBoxOnly = true; warnOpts.Icon = 'puffin_warning';
                header = 'Only Modify directory is available for this action';
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Not available', warnOpts);
                return;
            otherwise
                return;
        end
    case 'Modify directory'
        switch obj.CurrentBatch.mibBatchActionName
            case 'DIRECTORY LOOP START'
                selpath = uigetdir(obj.CurrentBatch.DirectoriesList{1}, 'Update directory');
                if selpath == 0; return; end
                if ismember({lower(selpath)}, lower(obj.CurrentBatch.DirectoriesList{2}))   % check whether it already exists
                    warnOpts.MsgBoxOnly = true; warnOpts.Icon = 'puffin_warning';
                    header = sprintf('Directory\n%s\nis already in the list', selpath);
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Already present', warnOpts);
                    return;
                end
                obj.CurrentBatch.DirectoriesList{2}(ismember(obj.CurrentBatch.DirectoriesList{2}, obj.CurrentBatch.DirectoriesList{1})) = {selpath};
                obj.CurrentBatch.DirectoriesList{1} = selpath;      % set as selected option
                obj.updateSelectedActionTable(obj.CurrentBatch);
                obj.displaySelectedActionTableItems();
            case {'FILE LOOP START', 'Load and combine images'}
                if strcmp(obj.CurrentBatch.DirectoryName{1}, 'Current MIB path')
                    warnOpts.MsgBoxOnly = true; warnOpts.Icon = 'puffin_warning';
                    header = sprintf('This directory parameter:\n"%s"\ncan not be modified!', obj.CurrentBatch.DirectoryName{1});
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Warning', warnOpts);
                    return;
                end
                if strcmp(obj.CurrentBatch.DirectoryName{1}, 'Current MIB path') || strcmp(obj.CurrentBatch.DirectoryName{1}, 'Inherit from Directory loop')
                    warnOpts.MsgBoxOnly = true; warnOpts.Icon = 'puffin_warning';
                    header = sprintf('The option "%s" can not be modified!\nPlease select a directory first and after that modify it...', obj.CurrentBatch.DirectoryName{1});
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Warning', warnOpts);
                    return;
                end
                selpath = uigetdir(obj.CurrentBatch.DirectoryName{1}, 'Update directory');
                if selpath == 0; return; end
                obj.CurrentBatch.DirectoryName{2}(3) = {selpath};
                obj.CurrentBatch.DirectoryName{1} = selpath;      % set as selected option
                obj.updateSelectedActionTable(obj.CurrentBatch);
                obj.displaySelectedActionTableItems();
            case 'Directory operations'
                if ~isfolder(obj.CurrentBatch.DirectoryName)
                    selpath = uigetdir(obj.mibModel.currentDirectory, 'Update directory');
                else
                    selpath = uigetdir(obj.CurrentBatch.DirectoryName, 'Update directory');
                end
                if selpath == 0; return; end
                obj.CurrentBatch.DirectoryName = selpath;
                obj.CurrentBatch.Mode(1) = obj.CurrentBatch.Mode{2}(ismember(obj.CurrentBatch.Mode{2}, 'Absolute'));
                obj.updateSelectedActionTable(obj.CurrentBatch);
                obj.displaySelectedActionTableItems();
            case 'File operations'
                if obj.selectedActionTableIndex == 3
                    modeField = 'CurrentDirectoryMode';
                    curDirField = 'CurrentDirectory';
                elseif obj.selectedActionTableIndex == 5
                    modeField = 'TargetDirectoryMode';
                    curDirField = 'TargetDirectory';
                else
                    return;
                end
                if ~isfolder(obj.CurrentBatch.(curDirField))
                    selpath = uigetdir(obj.mibModel.currentDirectory, 'Update directory');
                else
                    selpath = uigetdir(obj.CurrentBatch.(curDirField), 'Update directory');
                end
                if selpath == 0; return; end

                obj.CurrentBatch.(curDirField) = selpath;
                obj.CurrentBatch.(modeField)(1) = obj.CurrentBatch.(modeField){2}(ismember(obj.CurrentBatch.(modeField){2}, 'Absolute'));
                obj.updateSelectedActionTable(obj.CurrentBatch);
                obj.displaySelectedActionTableItems();
            otherwise
                fieldNames = fieldnames(obj.CurrentBatch);
                curDirField = fieldNames{obj.selectedActionTableIndex};
                switch class(obj.CurrentBatch.(curDirField))
                    case 'cell'
                        if strcmp(obj.CurrentBatch.(curDirField){1}, 'Inherit from dataset filename'); return; end
                        selpath = uigetdir(obj.CurrentBatch.(curDirField){1}, 'Update directory');
                        obj.CurrentBatch.(curDirField){2}(ismember(obj.CurrentBatch.(curDirField){2}, obj.CurrentBatch.(curDirField){1})) = {selpath};
                        obj.CurrentBatch.(curDirField)(1) = {selpath};
                    case 'char'
                        if ~isfolder(obj.CurrentBatch.(curDirField))
                            selpath = uigetdir(obj.mibModel.currentDirectory, 'Update directory');
                        else
                            selpath = uigetdir(obj.CurrentBatch.(curDirField), 'Update directory');
                        end
                        if selpath == 0; return; end
                        obj.CurrentBatch.(curDirField) = selpath;
                end
                obj.updateSelectedActionTable(obj.CurrentBatch);
                obj.displaySelectedActionTableItems();
                return;
        end
    case 'Remove directories'    % remove selected file or directory from the list
        switch obj.CurrentBatch.mibBatchActionName
            case 'DIRECTORY LOOP START'
                if numel(obj.CurrentBatch.DirectoriesList{2}) == 1
                    warnOpts.MsgBoxOnly = true; warnOpts.Icon = 'puffin_warning';
                    header = 'The last directory can not be removed!';
                    utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Warning', warnOpts);
                    return;
                end

                prompts = obj.CurrentBatch.DirectoriesList{2};
                defAns = repmat({false}, [numel(obj.CurrentBatch.DirectoriesList{2}) 1]);
                dlgTitle = 'Remove directories';
                header = 'Check directories to be removed from the list';
                options.WindowHeight = 350;
                options.LabelPosition = 'left';
                answer = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, dlgTitle, options);
                if isempty(answer); return; end

                obj.CurrentBatch.DirectoriesList{2}(cell2mat(answer)==1) = [];
                obj.CurrentBatch.DirectoriesList(1) = obj.CurrentBatch.DirectoriesList{2}(1);
                obj.updateSelectedActionTable(obj.CurrentBatch);
                obj.displaySelectedActionTableItems();
            case {'FILE LOOP START', 'Directory operations', 'File operations'}
                warnOpts.MsgBoxOnly = true; warnOpts.Icon = 'puffin_warning';
                header = 'Only Modify directory is available for this action';
                utils.dlgs.inputUniversalDlg(obj.view.gui, header, {}, {}, 'Not available', warnOpts);
                return;
            otherwise
                return;
        end
    case 'Set second column width'
        currentWidths = obj.view.handles.selectedActionTable.ColumnWidth;
        if iscell(currentWidths) && numel(currentWidths) >= 2
            defWidth = num2str(currentWidths{2});
        else
            defWidth = '200';
        end
        prompts = {'New width of the second column (pixels)'};
        defAns = {defWidth};
        dlgTitle = 'Set column width';
        [answer, selIndex] = utils.dlgs.inputUniversalDlg(obj.view.gui, '', prompts, defAns, dlgTitle);
        if isempty(answer); return; end
        obj.view.handles.selectedActionTable.ColumnWidth = {'auto', str2double(answer{1})};
end
end
