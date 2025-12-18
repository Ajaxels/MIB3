function bioFormats_Callback(obj, hWidget, hData)
% function bioFormats_Callback(obj, hWidget, hData)
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
    hWidget matlab.ui.control.CheckBox
    hData matlab.ui.eventdata.ValueChangedData
end

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDirContents.bioFormats_Callback: clicked on "obj.view.handles.panels.dirContents.handles.bioFormats" -> state=%d\n', hWidget.Value);
end

obj.mibModel.useBioFormats = obj.view.handles.panels.dirContents.handles.bioFormats.Value;
if obj.mibModel.useBioFormats
    % ------------------------- USE BIO-FORMATS READER -------------------------

    % check for temp directory for the Memoizer
    if ~isfield(obj.mibModel.preferences.ExternalDirs, 'BioFormatsMemoizerMemoDir')
        obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir = 'c:\temp\mibVirtual';
    end

    if isdir(obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir) == 0 %#ok<ISDIR>
        try
            mkdir(obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir);
        catch err
            errorText = sprintf(['<b>!!! Warning !!!</b>\n\n' ...
                'Use of the BioFormats reader requires a directory to keep Memoizer class temporary files!\n\n' ...
                '                    Please specify it in\n' ...
                '                    <em>Menu->File->Preferences->External dirs...</em>']);

            utils.dlgs.showErrorDialog(obj.view.gui, errorText, 'Missing Memoizer directory');
            return;
        end
    end

    switch obj.mibModel.I{obj.mibModel.id}.datasetType(1)
        case 'S'    % "Std"
            extentions = ['all known', obj.mibModel.preferences.System.Files.BioFormatsExt];
        case 'V'    % "Virtual", add amira-mesh for the virtual mode
            extentions = ['all known', obj.mibModel.preferences.System.Files.BioFormatsVirtExt];
        case 'B'    % "BigData", not implemented
            error('controllers.MibDirContents.bioFormats_Callback: not implemented');
    end

else
    % ------------------------- USE STANDARD READER -------------------------

    switch obj.mibModel.I{obj.mibModel.id}.datasetType(1)
        case 'S'    % "Std"
            extentions = ['all known', obj.mibModel.preferences.System.Files.StdExt];
        case 'V'    % "Virtual", add amira-mesh for the virtual mode
            extentions = ['all known', obj.mibModel.preferences.System.Files.StdVirtExt];
        case 'B'    % "BigData", not implemented
            error('controllers.MibDirContents.bioFormats_Callback: not implemented');
    end

end
obj.view.handles.panels.dirContents.handles.fileFilters.Items = extentions;
obj.view.handles.panels.dirContents.handles.fileFilters.Value = obj.mibModel.selectedFileFilter{obj.mibModel.useBioFormats+1};
obj.mibModel.selectedFileFilter{obj.mibModel.useBioFormats+1} = obj.view.handles.panels.dirContents.handles.fileFilters.Value;

% update the file list and
% highlight the selected file in it
[~, fn, ext] = fileparts(obj.mibModel.I{obj.mibModel.id}.image.filename);
obj.updateFileList_Callback([fn, ext]);

end