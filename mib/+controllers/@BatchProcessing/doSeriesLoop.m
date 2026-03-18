function status = doSeriesLoop(obj, startStep, finishStep)
% function status = doSeriesLoop(obj, startStep, finishStep)
% iterate over all Bio-Formats series in a multi-series container and execute protocol steps for each
%
% Opens the container defined by the 'Load and combine images' step at
% startStep using the Bio-Formats Memoizer reader, counts the available
% series, and then runs steps startStep..finishStep once per series.
% The current series index is passed to doBatchStep via stepOptions.seriesId.
% Requires the Bio-Formats MATLAB toolbox and Java to be available.
% Aborts immediately and returns false if any individual step fails.
%
% Parameters:
% startStep: index of the 'Load and combine images' step (Series-by-series mode)
%            that defines the container filename; also the first step executed
%            for each series
% finishStep: index of the last protocol step executed per series (inclusive)
%
% Return values:
% status: [logical] true on success, false if any step returned an error
%
%|
% @b Examples:
% @code status = obj.doSeriesLoop(startStep, finishStep); @endcode
%
% Updates
%

status = false;
options.FileLoopWaitbar = true;

stepOptions.seriesId = 1;   % define index of the first series

switch obj.Protocol(startStep).Batch.DirectoryName{1}
    case 'Current MIB path'
        filename = fullfile(obj.mibModel.currentDirectory, obj.Protocol(startStep).Batch.FilenameFilter);
    case 'Inherit from Directory/File loop'
        error('not implemented')
    otherwise
        filename = fullfile(obj.Protocol(startStep).Batch.DirectoryName{1}, ...
            obj.Protocol(startStep).Batch.FilenameFilter);
end
% get number of series in the container
hDataset = loci.formats.Memoizer(bfGetReader(), 0, ...
    java.io.File(obj.mibModel.preferences.ExternalDirs.BioFormatsMemoizerMemoDir));
hDataset.setId(filename);
numSeries = hDataset.getSeriesCount();

if options.FileLoopWaitbar
    wb = uiprogressdlg(obj.view.gui, 'Title', 'Processing series', ...
        'Message', sprintf('Processing: %s', filename), 'Value', 0, 'Cancelable', 'on', 'CancelText', 'Stop');
end
stepOptions.FileLoopWaitbar = options.FileLoopWaitbar;

for seriesId =  1:numSeries
    if options.FileLoopWaitbar
        wb.Value = seriesId / numSeries;
        if wb.CancelRequested; close(wb); return; end
    end
    stepOptions.seriesId = seriesId;    % set series id for doBatchStep function
    for stepId = startStep:finishStep
        status = obj.doBatchStep(stepId, stepOptions);
        if status == 0; return; end
    end
end
if options.FileLoopWaitbar; close(wb); end
status = true;
end
