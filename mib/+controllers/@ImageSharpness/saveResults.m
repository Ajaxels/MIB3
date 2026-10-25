function saveResults(obj)
% SAVERESULTS - Save the results table to a .mibSharp file that Load can open again.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.saveResults()
%
% The file is a MAT file (version 7.3) with the extension ``.mibSharp`` and
% one variable, ``mibSharpness``, a struct with the fields:
%
%   - ``.fileFormat`` - [char] ``'MIB image sharpness and noise results'``,
%     checked by :func:`controllers.ImageSharpness.loadResults`; an
%     identifier, kept from the former name of the tool so that files saved
%     before the rename still load
%   - ``.formatVersion`` - [double] ``1``
%   - ``.created`` - [char] date and time of saving
%   - ``.results`` - [struct array] ``obj.results``, with all curves,
%     spectra and thumbnails, see :func:`controllers.ImageSharpness.calculate`
%
% The plain MAT container keeps the file readable in MATLAB without MIB
% (``load('name.mibSharp', '-mat')``).
%

% Updates
%

if obj.mibModel.preferences.System.DeveloperMode
    fprintf('controllers.ImageSharpness.saveResults: triggered\n');
end
if isempty(obj.results)
    uialert(obj.view.gui, 'The results table is empty.', 'Save results', 'Icon', 'info');
    return;
end

defaultName = fullfile(obj.mibModel.currentDirectory, 'image_sharpness.mibSharp');
[fileName, pathName] = uiputfile({'*.mibSharp', 'Sharpness and noise results (*.mibSharp)'}, ...
    'Save results', defaultName);
if isequal(fileName, 0); return; end
fullFileName = fullfile(pathName, fileName);

mibSharpness = struct('fileFormat', 'MIB image sharpness and noise results', 'formatVersion', 1, ...
    'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), 'results', {obj.results});
progressDialog = uiprogressdlg(obj.view.gui, 'Title', 'Save results', ...
    'Message', sprintf('Saving %d measurements...', numel(obj.results)), 'Indeterminate', 'on');
try
    save(fullFileName, 'mibSharpness', '-mat', '-v7.3');
catch err
    delete(progressDialog);
    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Save results');
    return;
end
delete(progressDialog);
fprintf('Sharpness and noise results were saved to %s\n', fullFileName);
end
