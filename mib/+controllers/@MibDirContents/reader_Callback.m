function reader_Callback(obj)
% READER_CALLBACK - callback for the file-reader dropdown in the Directory Contents panel.
%
% Syntax:
%   .. code-block:: matlab
%
%       obj.reader_Callback()
%
% Reads ``obj.view.handles.panels.dirContents.handles.reader`` (a dropdown with
% ``'Default'`` | ``'BioFormats'`` | ``'OpenSlide'``), updates the file-filter
% dropdown (``fileFilters``) with the extensions allowed for the active dataset
% type + selected reader, and refreshes the file list. Replaces the former
% binary ``bioFormats`` checkbox / ``bioFormats_Callback``.
%
% The BioFormats engine (MIB-Java vs MATLAB ``bioformatsread``) is the separate
% global preference ``IO.BioFormats.Library`` - not selected here.
%
% Input Arguments:
%   (none)
%

arguments (Input)
    obj controllers.MibDirContents
end

reader = obj.view.handles.panels.dirContents.handles.reader.Value;   % 'Default'|'BioFormats'|'OpenSlide'

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.MibDirContents.reader_Callback: reader -> "%s"\n', reader);
end

% update model state (+ back-compat boolean alias still consumed by some code)
obj.mibModel.selectedReader = reader;
obj.mibModel.useBioFormats  = ~strcmp(reader, 'Default');

% BioFormats (MIB-Java engine) needs a writable Memoizer directory
if strcmp(reader, 'BioFormats')
    if ~isfield(obj.mibModel.preferences.ExternalDirs, 'BioFormatsMemoizerMemoDir')
        obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir = 'c:\temp\mibVirtual';
    end
    if isfolder(obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir) == 0
        try
            mkdir(obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir);
        catch
            errorText = sprintf(['Use of the BioFormats reader requires a directory to keep Memoizer class temporary files!\n\n' ...
                'Please specify it in\n' ...
                'Menu->File->Preferences->External dirs...']);
            errorOpts.mibPath = obj.mibModel.mibPath;
            utils.dlgs.showErrorDialog(obj.view.gui, errorText, 'Missing Memoizer directory', ...
                'Error in MibDirContents.reader_Callback', '', errorOpts);
            return;
        end
    end
end

% get list of allowed extensions for the active dataset type + reader.
% getAllowedExtensions is forced to a cellstr ROW so the dropdown .Items is always
% valid (a single-element / empty extension set must not collapse to a char).
allowed = obj.mibModel.extensionRegistryLoad.getAllowedExtensions(obj.mibModel.I{obj.mibModel.id}.datasetType, reader);
allowed = reshape(cellstr(allowed), 1, []);
extentions = [{'all known'}, allowed];

obj.view.handles.panels.dirContents.handles.fileFilters.Items = extentions;

idx = models.MibModel.readerToIndex(reader);
% defensively grow the per-reader filter cell (older sessions had only 2 slots)
if numel(obj.mibModel.selectedFileFilter) < idx
    obj.mibModel.selectedFileFilter(end+1:idx) = {'all known'};
end
if ~ismember(obj.mibModel.selectedFileFilter{idx}, extentions)
    obj.mibModel.selectedFileFilter{idx} = 'all known';
end
obj.view.handles.panels.dirContents.handles.fileFilters.Value = obj.mibModel.selectedFileFilter{idx};
obj.mibModel.selectedFileFilter{idx} = obj.view.handles.panels.dirContents.handles.fileFilters.Value;

% update the file list and highlight the selected file in it
[~, fn, ext] = fileparts(obj.mibModel.I{obj.mibModel.id}.image.filename);
obj.updateFileList_Callback([fn, ext]);

end
