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

plan = buildplan(localfunctions);

plan("check") = CodeIssuesTask("mib", IncludeSubfolders=true, ...
    WarningThreshold=Inf);   % non-blocking on warnings; tighten later

% test / testAll / perf are custom function tasks (see below) so they are
% never skipped as "up-to-date" — tests always run when explicitly invoked.
plan("test").Dependencies    = "addTestPath";
plan("testAll").Dependencies = "addTestPath";
plan("perf").Dependencies    = "addTestPath";

plan.DefaultTasks = ["check" "test"];
end

function testTask(context)
% TEST - run Unit-tagged tests (fast, synthetic, offline).
testsFolder = fullfile(context.Plan.RootFolder, "tests");
results = runtests(testsFolder, IncludeSubfolders=true, Tag="Unit");
assert(~any([results.Failed]), sprintf('%d unit test(s) failed', sum([results.Failed])));
end

function testAllTask(context)
% TESTALL - run Unit + Integration + Performance tests.
testsFolder = fullfile(context.Plan.RootFolder, "tests");
results = runtests(testsFolder, IncludeSubfolders=true, Tag=["Unit" "Integration" "Performance"]);
assert(~any([results.Failed]), sprintf('%d test(s) failed', sum([results.Failed])));
end

function addTestPathTask(context)
% ADDTESTPATH - put the tests\ root on the path so the +mibtest package
% (fixtures, helpers) resolves during test setup.
addpath(fullfile(context.Plan.RootFolder, "tests"));
end

function perfTask(context)
% PERF - run Performance-tagged tests and compare timings to the committed
% baseline for this machine+release. Set MIB3_UPDATE_PERF_BASELINE=1 to
% (re)write the baseline instead of comparing.
testsFolder = fullfile(context.Plan.RootFolder, "tests");
% tests\ is already on the path via the addTestPath dependency
results = runtests(testsFolder, IncludeSubfolders=true, Tag="Performance");
mibtest.perf.PerfBaselineStore.finalizeRun();   % write/print before asserting
% assertSuccess counts Incomplete (assumption-filtered) as failure — check only actual failures
assert(~any([results.Failed]), sprintf('%d performance test(s) failed', sum([results.Failed])));
end
