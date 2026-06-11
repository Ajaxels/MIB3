function plan = buildfile
% Build tasks for MIB3.
%
% Usage:
%   buildtool            % default: check + Unit tests
%   buildtool check      % code issues in mib/ only
%   buildtool test       % Unit-tagged tests (fast, synthetic, offline)
%   buildtool testAll    % Unit + Integration + Performance tests
%   buildtool perf       % Performance tests vs committed baseline
%                        %   set MIB3_UPDATE_PERF_BASELINE=1 to write/update baseline:
                         
% >> setenv('MIB3_UPDATE_PERF_BASELINE', '1');
% run to generate baseline performance scores to tests\baseline
% >> buildtool perf
% remove the baseline recording:
% >> setenv('MIB3_UPDATE_PERF_BASELINE', '');
% test a new build
% >> buildtool perf

import matlab.buildtool.tasks.CodeIssuesTask
import matlab.buildtool.tasks.TestTask

plan = buildplan(localfunctions);

plan("check") = CodeIssuesTask("mib", IncludeSubfolders=true, ...
    WarningThreshold=Inf);   % non-blocking on warnings; tighten later

plan("test") = TestTask("tests", IncludeSubfolders=true, Tag="Unit", ...
    SourceFiles="mib");

plan("testAll") = TestTask("tests", IncludeSubfolders=true, ...
    Tag=["Unit" "Integration" "Performance"], SourceFiles="mib");

plan.DefaultTasks = ["check" "test"];
end

function perfTask(context)
% PERF - run Performance-tagged tests and compare timings to the committed
% baseline for this machine+release. Set MIB3_UPDATE_PERF_BASELINE=1 to
% (re)write the baseline instead of comparing.
testsFolder = fullfile(context.Plan.RootFolder, "tests");
addpath(testsFolder);   % make +mibtest visible
results = runtests(testsFolder, IncludeSubfolders=true, Tag="Performance");
mibtest.perf.PerfBaselineStore.finalizeRun();   % write/print before asserting
% assertSuccess counts Incomplete (assumption-filtered) as failure — check only actual failures
assert(~any([results.Failed]), sprintf('%d performance test(s) failed', sum([results.Failed])));
end
