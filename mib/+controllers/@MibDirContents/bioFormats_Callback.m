function bioFormats_Callback(obj)
% function bioFormats_Callback(obj)
% callback for selection of the bio-formats reader by press on
% obj.view.handles.panels.dirContents.handles.bioFormats, updates the
% contents of obj.view.handles.panels.dirContents.handles.fileFilters and
% refresh the list of files in obj.view.handles.panels.dirContents.handles.fileList
%
% Parameters:
% hWidget: handle to the pressed widget
% hData: handle to supporting data class

arguments (Input)
    obj controllers.MibDirContents
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDirContents.bioFormats_Callback: clicked on "obj.view.handles.panels.dirContents.handles.bioFormats (obj.mibController.cDirContents.handles.bioFormats)" -> state=%d\n', obj.view.handles.panels.dirContents.handles.bioFormats.Value);
end

obj.mibModel.useBioFormats = obj.view.handles.panels.dirContents.handles.bioFormats.Value;
reader = 'Default';

if obj.mibModel.useBioFormats
    reader = 'BioFormats';
    % ------------------------- USE BIO-FORMATS READER -------------------------

    % check for temp directory for the Memoizer
    if ~isfield(obj.mibModel.preferences.ExternalDirs, 'BioFormatsMemoizerMemoDir')
        obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir = 'c:\temp\mibVirtual';
    end

    if isdir(obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir) == 0 %#ok<ISDIR>
        try
            mkdir(obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir);
        catch err
            errorText = sprintf(['Use of the BioFormats reader requires a directory to keep Memoizer class temporary files!\n\n' ...
                'Please specify it in\n' ...
                'Menu->File->Preferences->External dirs...']);

            errorOpts.mibPath = obj.mibModel.mibPath;
            utils.dlgs.showErrorDialog(obj.view.gui, errorText, 'Missing Memoizer directory', ...
                'Error in MibDirContents.bioFormats_Callback', '', errorOpts);
            return;
        end
    end
end

% get list of extensions
extentions = ['all known', obj.mibModel.extensionRegistryLoad.getAllowedExtensions(obj.mibModel.I{obj.mibModel.id}.datasetType, reader)];

obj.view.handles.panels.dirContents.handles.fileFilters.Items = extentions;
if ~ismember(obj.mibModel.selectedFileFilter{obj.mibModel.useBioFormats+1}, extentions)
    obj.mibModel.selectedFileFilter{obj.mibModel.useBioFormats+1} = 'all known';
end

obj.view.handles.panels.dirContents.handles.fileFilters.Value = obj.mibModel.selectedFileFilter{obj.mibModel.useBioFormats+1};
obj.mibModel.selectedFileFilter{obj.mibModel.useBioFormats+1} = obj.view.handles.panels.dirContents.handles.fileFilters.Value;

% update the file list and
% highlight the selected file in it
[~, fn, ext] = fileparts(obj.mibModel.I{obj.mibModel.id}.image.filename);
obj.updateFileList_Callback([fn, ext]);

end