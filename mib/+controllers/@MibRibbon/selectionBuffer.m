function selectionBuffer(obj, parameter)
% SELECTIONBUFFER - Copy/Paste/Clear the selection of the current layer to/from a buffer.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.selectionBuffer(parameter)
%
% Input Arguments:
%   - **parameter** — action to perform:
%
%     - ``'copy'`` — store the selection from the current slice into the buffer
%     - ``'paste'`` — OR the buffered selection into the current slice
%     - ``'pasteall'`` — OR the buffered selection into all Z-slices of the current stack
%     - ``'clear'`` — clear the selection buffer
%
% Updates
% 01.06.2026, IB, ported from MIB2 menuSelectionBuffer_Callback

arguments (Input)
    obj controllers.MibRibbon
    parameter (1,:) char {mustBeMember(parameter, {'copy', 'paste', 'pasteall', 'clear'})}
end

activeId = obj.mibModel.getActiveId();

%% Virtual stacking mode guard
if strcmp(obj.mibModel.I{activeId}.datasetType, 'Virtual')
    dlgOpt.MsgBoxOnly = true;
    dlgOpt.Icon = 'puffin_warning';
    dlgOpt.HeaderLines = 1;
    utils.dlgs.inputUniversalDlg(obj.mibModel.mibGUI, ...
        '!!! Warning !!!', {''}, ...
        {sprintf('This action is not yet available in the virtual stacking mode.\nPlease switch to the memory-resident mode and try again')}, ...
        'Not implemented', dlgOpt);
    return;
end

%% enableSelection guard
if obj.mibModel.I{activeId}.enableSelection == 0; return; end

options.blockModeSwitch = 0;
options.id = activeId;

switch parameter
    case 'copy'
        obj.mibModel.storedSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], NaN, options));

    case 'paste'
        if isempty(obj.mibModel.storedSelection)
            utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, 'The selection buffer is empty!', 'Error!');
            return;
        end
        
        currentSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], NaN, options));
        %currentSelection  = cell2mat(obj.mibModel.I{id}.getData2D('selection', [], [], NaN, options));
        
        if all(size(currentSelection) == size(obj.mibModel.storedSelection))
            backupOptions.id = activeId;
            obj.mibModel.backup('selection', 0, backupOptions);
            obj.mibModel.setData2D(bitor(obj.mibModel.storedSelection, currentSelection), 'selection', [], [], NaN, options);
            notify(obj.mibModel, 'ShowImage');
        else
            utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                sprintf('The size of the buffered and current selections mismatch!\nTry to change the orientation of the dataset...'), ...
                'Error!');
        end

    case 'pasteall'
        if isempty(obj.mibModel.storedSelection)
            utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, 'The selection buffer is empty!', 'Error!');
            return;
        end
        currentSelection = cell2mat(obj.mibModel.getData2D('selection', [], [], NaN, options));
        if all(size(currentSelection) == size(obj.mibModel.storedSelection))
            depth = obj.mibModel.I{activeId}.image.depth;
            backupOptions.id = activeId;
            obj.mibModel.backup('selection', 1, backupOptions);
            progressBar = uiprogressdlg(obj.mibModel.mibGUI, 'Value', 0, ...
                'Message', 'Pasting selection to layers...', ...
                'Title', 'Paste selection');
            for sliceIndex = 1:depth
                currentSelection = cell2mat(obj.mibModel.getData2D('selection', sliceIndex, [], NaN, options));
                obj.mibModel.setData2D(bitor(obj.mibModel.storedSelection, currentSelection), 'selection', sliceIndex, [], NaN, options);
                progressBar.Value = sliceIndex / depth;
            end
            delete(progressBar);
            notify(obj.mibModel, 'ShowImage');
        else
            utils.dlgs.showErrorDialog(obj.mibModel.mibGUI, ...
                sprintf('The size of the buffered and current selections mismatch!\nTry to change the orientation of the dataset...'), ...
                'Error!');
        end

    case 'clear'
        obj.mibModel.storedSelection = [];
end
end
