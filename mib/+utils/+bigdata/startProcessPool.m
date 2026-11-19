function [pool, releaseWorkers, cancelled] = startProcessPool(workerCount, parentFigure)
% STARTPROCESSPOOL - The process pool for a BigData run on parallel workers.
%
% Syntax:
%   .. code-block:: matlab
%
%       [pool, releaseWorkers, cancelled] = utils.bigdata.startProcessPool(workerCount, parentFigure)
%
% The open pool is used as it is; when none is open, one of ``workerCount``
% workers is started (about 15 s for 4 workers), as the Standard filters do,
% with an indeterminate, cancelable progress dialog on ``parentFigure``.
% ``parpool`` cannot stop midway, so Cancel is checked once it returns; the pool
% then stays open (closing it is the user's step, Home ribbon -> Preferences ->
% Parallel pool).
%
% A thread pool is refused (``utils:bigdata:threadPool``): zarrMex and the
% loaders need process workers. On every worker zarrMex is pinned
% (``io.zarr.pinNativeLibrary``, as ``mib3.m`` does on the client), otherwise a
% worker may crash when the pool closes.
%
% Used by ``controllers.BigDataOptions`` (the BigData image tools) and
% ``controllers.CropDataset`` (crop to BigData).
%
% Input Arguments:
%   - **workerCount** - [double] workers of a new pool,
%     ``preferences.System.cpuParallelLimit``
%   - **parentFigure** - figure for the progress dialog, ``[]`` for none
%
% Output Arguments:
%   - **pool** - ``parallel.Pool``; ``[]`` when cancelled
%   - **releaseWorkers** - ``onCleanup`` that clears the chunk cache of every
%     worker; keep it until the run returns. The cache holds chunks of the source
%     (up to 512 MB per worker), and an overwrite changes them without changing
%     their cache keys, so a later run on the workers would read the old pixels
%   - **cancelled** - [logical] Cancel while the pool was starting
%
% See also: controllers.BigDataOptions, core.MibDataset.cropToBigData

% Updates
% 2026-11-19 moved here from controllers.BigDataOptions.startPool

pool = [];
releaseWorkers = [];
cancelled = false;
openPool = gcp('nocreate');
if isempty(openPool)
    progressDialog = [];
    if ~isempty(parentFigure) && isvalid(parentFigure)
        progressDialog = uiprogressdlg(parentFigure, 'Title', 'Parallel processing', ...
            'Message', sprintf('Starting a parallel pool of %d workers...', workerCount), ...
            'Indeterminate', 'on', 'Cancelable', 'on');
        cleanupDialog = onCleanup(@() delete(progressDialog));   % deletes the dialog on return
    end
    openPool = parpool(workerCount);
    if ~isempty(progressDialog) && progressDialog.CancelRequested
        cancelled = true;
        return;
    end
end
if isa(openPool, 'parallel.ThreadPool')
    error('utils:bigdata:threadPool', ['The open parallel pool runs on threads; BigData ' ...
        'processing needs a pool of processes.\nStop the pool (Home ribbon, Preferences, Parallel pool) and start again, or ' ...
        'clear Use parallel computing.']);
end
pool = openPool;
wait(parfevalOnAll(pool, @io.zarr.pinNativeLibrary, 0));
releaseWorkers = onCleanup(@() parfevalOnAll(pool, @io.zarr.ChunkCache.clear, 0));
end
