function fileFilters_ContextMenu(obj, menuEntry, selectedData)
% FILEFILTERS_CONTEXTMENU - callbacks for the context menu of the file filters widget.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.fileFilters_ContextMenu(menuEntry, selectedData)
%
% (obj.handles.panels.activeDataset.handles.fileFilters)
%
% Input Arguments:
%   - **menuEntry** — handle to the pressed context menu entry, 'matlab.ui.container.Menu' class
%   - **selectedData** — handle to the pressed
%     'matlab.ui.eventdata.MenuSelectedData' class, it can be used to find the
%     button that has the context menu (selectedData.ContextObject)
%
%   Available menu options available from 'menuEntry.Tag':
%   fileFiltersContextRegister - register a new extension and add it to the list of available filename extensions
%   fileFiltersContextUnregister - remove extension from the list of available filename extensions
%

% Updates
%

arguments (Input)
    obj controllers.MibDirContents
    menuEntry matlab.ui.container.Menu
    selectedData matlab.ui.eventdata.MenuSelectedData 
end

% get the reader for files
reader = 'Default';
if obj.mibModel.useBioFormats; reader = 'BioFormats'; end
% get dataset type: Standard, Virtual, BigData
datasetType = obj.mibModel.I{obj.mibModel.id}.datasetType;

switch menuEntry.Tag
    case 'fileFiltersContextRegister'
        prompts = {'Standard file reader:'; ...
                   'Standard file reader, virtual mode:'; ...
                   'Bioformats file reader:'; ...
                   'Bioformats file reader, virtual mode:'};
        defAns = {'', '', '', ''};
        dlgTitle = 'Register file extension';
        header = sprintf('Add file extension to the list of filters.\nMultiple extensions should be separated with semicolon, for example:\n"tif; png; jpg"');
        options.HeaderLines = 3;
        options.WindowHeight = 320;
        options.mibPath = obj.mibModel.mibPath;
        output = utils.dlgs.inputUniversalDlg(obj.view.gui, header, prompts, defAns, dlgTitle, options);
        if isempty(output); return; end

        withoutDots = true;
        if ~isempty(output{1})
            newExt = strsplit(strrep(output{1}, ' ', ''), ';');
            curExt = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'Default', withoutDots);
            newExt(ismember(newExt, curExt)) = [];
            obj.mibModel.extensionRegistryLoad.setAllowedExtensions('Standard', 'Default', sort([curExt, newExt]));
        end
        if ~isempty(output{2})
            newExt = strsplit(strrep(output{2}, ' ', ''), ';');
            curExt = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Virtual', 'Default', withoutDots);
            newExt(ismember(newExt, curExt)) = [];
            obj.mibModel.extensionRegistryLoad.setAllowedExtensions('Virtual', 'Default', sort([curExt, newExt]));
        end
        if ~isempty(output{3})
            newExt = strsplit(strrep(output{3}, ' ', ''), ';');
            curExt = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Standard', 'BioFormats', withoutDots);
            newExt(ismember(newExt, curExt)) = [];
            obj.mibModel.extensionRegistryLoad.setAllowedExtensions('Standard', 'BioFormats', sort([curExt, newExt]));
        end
        if ~isempty(output{4})
            newExt = strsplit(strrep(output{4}, ' ', ''), ';');
            curExt = obj.mibModel.extensionRegistryLoad.getAllowedExtensions('Virtual', 'BioFormats', withoutDots);
            newExt(ismember(newExt, curExt)) = [];
            obj.mibModel.extensionRegistryLoad.setAllowedExtensions('Virtual', 'BioFormats', sort([curExt, newExt]));
        end

    case 'fileFiltersContextUnregister'
        selVal = obj.view.handles.panels.dirContents.handles.fileFilters.Value;
        if strcmp(selVal, 'all known')
            uialert(obj.UIFigure, sprintf('The extension was not selected,\nplease select an extension and try again!\n\nNote!\nIt is not possible to remove "all known"'), 'Wrong selection');
            return
        end
        answer = uiconfirm(obj.view.gui, ...
            sprintf('You are going to remove\n "%s"\n\nfrom the list of extensions!', selVal), ...
            'Remove extension', 'Options', {'Continue', 'Cancel'}, 'Icon', 'warning', 'DefaultOption', 'Cancel', 'CancelOption', 'Cancel');
        if strcmp(answer, 'Cancel'); return; end

        curExt = obj.mibModel.extensionRegistryLoad.getAllowedExtensions(datasetType, reader);
        curExt(ismember(curExt, selVal)) = [];
        obj.mibModel.extensionRegistryLoad.setAllowedExtensions(datasetType, reader, curExt);
end

% Refresh the file filters widget with updated extensions
obj.bioFormats_Callback();
end
