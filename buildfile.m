function plan = buildfile
% Build tasks for MIB3 - code checks and automated tests.
%
% This file is the plan for MATLAB's build tool: typing "buildtool" in the
% repository root reads it and runs the tasks defined below. It is a
% development aid only - it does not compile or package MIB (the standalone
% app is built by the scripts in deployment\) and it is not needed to run MIB.
%
% Tasks:
%   check   - Code Analyzer scan of mib\ (warnings do not fail the build)
%   test    - Unit-tagged tests from tests\
%   testAll - Unit, Integration and Performance tests from tests\
%   perf    - Performance tests compared against the baseline stored in
%             tests\baselines for this machine and MATLAB release
%
% Usage:
%   buildtool            % default: check + Unit tests
%   buildtool check      % code issues in mib/ only
%   buildtool test       % Unit-tagged tests (fast, synthetic, offline)
%   buildtool testAll    % Unit + Integration + Performance tests
%   buildtool perf       % Performance tests vs committed baseline
%                        %   set MIB3_UPDATE_PERF_BASELINE=1 to write/update baseline:

% Record only in a freshly restarted MATLAB, and only after one normal
% "buildtool perf" run there:
%  - a session where a data-layer classdef (MibImage, MibLabels, ...) was
%    edited copies the whole layer on every slice write, so set2D_* records
%    ~10x too slow (1.5 ms instead of 0.16 ms) and the gate stops guarding them
%  - the first run after MATLAB starts is cold: labels63 image rows measured
%    up to 30x their warm value
% >> setenv('MIB3_UPDATE_PERF_BASELINE', '1');
% run to generate baseline performance scores to tests\baselines
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
% never skipped as "up-to-date" - tests always run when explicitly invoked.
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
% assertSuccess counts Incomplete (assumption-filtered) as failure - check only actual failures
assert(~any([results.Failed]), sprintf('%d performance test(s) failed', sum([results.Failed])));
end
