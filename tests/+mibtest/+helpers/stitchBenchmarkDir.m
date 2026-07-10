function benchmarkDir = stitchBenchmarkDir()
% STITCHBENCHMARKDIR - Locate the MitoNet 2D->3D stitching benchmark data.
%
% Returns the folder that contains the ``easy`` and ``hard`` subfolders (each a
% 3D ground-truth TIFF plus a ``slices_2d_objects`` folder of per-slice 2D label
% TIFFs), or ``''`` when the data is not present on this machine so that
% Integration tests can self-skip.
%
% Resolution order:
%   1. environment variable ``MIB3_STITCH_BENCHMARK_DIR``
%   2. the default local path the data was copied to
%
% Syntax:
%   .. code-block:: matlab
%
%       d = mibtest.helpers.stitchBenchmarkDir();
%       assumeFalse(testCase, isempty(d));

candidates = { ...
    getenv('MIB3_STITCH_BENCHMARK_DIR'), ...
    'c:\MATLAB\Data\SOLOv2_Implementation\MitoNet_benchmark\examples'};

benchmarkDir = '';
for k = 1:numel(candidates)
    c = candidates{k};
    if ~isempty(c) && isfolder(fullfile(c, 'easy', 'slices_2d_objects'))
        benchmarkDir = c;
        return;
    end
end
end
