classdef PerfBaselineStore
    % PERFBASELINESTORE - record and compare performance measurements to committed baselines.
    %
    % Usage pattern in a Performance-tagged test:
    %   samples = mibtest.perf.timeCallSamples(@() ..., N);
    %   mibtest.perf.PerfBaselineStore.verifyAgainstBaseline(testCase, 'MyTest/op/variant', samples);
    %
    % After running: buildtool perf (or set MIB3_UPDATE_PERF_BASELINE=1 to write/update baseline).
    %
    % Baseline JSON lives at: tests/baselines/perf_<COMPUTERNAME>_R<release>.json

    properties (Constant)
        WarnRatio          = 1.15;   % >this ratio -> warning (no test failure)
        FailRatio          = 1.30;   % >this ratio -> testCase.verifyFail
        % Measurements below this are recorded and reported but not gated on: a ratio
        % threshold is meaningless there. getData3D/getData4D return the stored array
        % whole for labels255/labels65535, so the call is O(1) copy-on-write and lands
        % at 7-50 us on any dataset size - a figure set by CPU frequency and cache
        % state, not by MIB. Two full buildtool perf runs minutes apart measured the
        % same keys at 0.043 ms and 0.007 ms with min ~= mean in both, so the shift is
        % between runs and no statistic taken within a run can correct for it.
        % 120 us sits above that cluster (0.086 ms worst case observed) and below the
        % cheapest measurement that does scale with the code (get2D_labels, ~0.14 ms).
        % Gating resumes as soon as either side crosses the floor, so an accessor that
        % started copying - jumping to milliseconds - still fails the build.
        MinGatedSeconds    = 120e-6;
        DefaultIterations2D = 100;
        DefaultIterations3D = 5;
        DefaultIterationsRGB = 20;
    end

    methods (Static)

        function record(measurementKey, secondsSamples)
            % Store measurement into session buffer (persistent, lives for this run).
            buffer = mibtest.perf.PerfBaselineStore.sessionBuffer();
            entry.meanSeconds = mean(secondsSamples);
            entry.minSeconds  = min(secondsSamples);
            entry.samples     = numel(secondsSamples);
            buffer(measurementKey) = entry;
            mibtest.perf.PerfBaselineStore.sessionBuffer(buffer);
        end

        function verifyAgainstBaseline(testCase, measurementKey, secondsSamples)
            % Record measurement, then compare to baseline if one exists.
            mibtest.perf.PerfBaselineStore.record(measurementKey, secondsSamples);

            % Recording a baseline and gating against it are mutually exclusive: in update
            % mode the committed numbers are the ones being replaced, so comparing to them
            % would fail the build for every measurement that legitimately changed.
            if strcmp(getenv('MIB3_UPDATE_PERF_BASELINE'), '1')
                return
            end

            baselineFile = mibtest.perf.PerfBaselineStore.baselineFilePath();
            if ~isfile(baselineFile)
                fprintf('[PerfBaseline] no baseline file - %s = %.3f ms\n', ...
                    measurementKey, mean(secondsSamples)*1000);
                return
            end

            baselineText = fileread(baselineFile);
            baseline     = jsondecode(baselineText);
            if ~isfield(baseline, 'measurements')
                return
            end

            safeKey = mibtest.perf.PerfBaselineStore.safeFieldName(measurementKey);
            if isfield(baseline.measurements, safeKey)
                refEntry = baseline.measurements.(safeKey);
            else
                fprintf('[PerfBaseline] no baseline entry for %s = %.3f ms\n', ...
                    measurementKey, mean(secondsSamples)*1000);
                return
            end

            % Below the floor on BOTH sides the ratio is noise - report only.
            floorSeconds = mibtest.perf.PerfBaselineStore.MinGatedSeconds;
            if mean(secondsSamples) < floorSeconds && refEntry.meanSeconds < floorSeconds
                return
            end

            ratio = mean(secondsSamples) / refEntry.meanSeconds;
            if ratio > mibtest.perf.PerfBaselineStore.FailRatio
                testCase.verifyFail(sprintf( ...
                    'PERF REGRESSION: %s\n  measured %.3f ms  baseline %.3f ms  ratio %.2fx (threshold %.2fx)', ...
                    measurementKey, mean(secondsSamples)*1000, refEntry.meanSeconds*1000, ...
                    ratio, mibtest.perf.PerfBaselineStore.FailRatio));
            elseif ratio > mibtest.perf.PerfBaselineStore.WarnRatio
                fprintf('[PerfBaseline] WARNING: %s %.3f ms vs baseline %.3f ms (%.2fx)\n', ...
                    measurementKey, mean(secondsSamples)*1000, refEntry.meanSeconds*1000, ratio);
            end
        end

        function finalizeRun()
            % Called by buildtool perfTask after all Performance tests complete.
            % MIB3_UPDATE_PERF_BASELINE=1: write/update baseline JSON.
            % Otherwise: print summary table comparing to existing baseline.
            % Always writes a human-readable markdown report to tests/baselines/.
            buffer = mibtest.perf.PerfBaselineStore.sessionBuffer();
            if numEntries(buffer) == 0
                fprintf('[PerfBaseline] no measurements recorded this run\n');
                return
            end

            if strcmp(getenv('MIB3_UPDATE_PERF_BASELINE'), '1')
                mibtest.perf.PerfBaselineStore.writeBaseline(buffer);
            else
                mibtest.perf.PerfBaselineStore.printSummary(buffer);
            end
            mibtest.perf.PerfBaselineStore.writeReport(buffer);
        end

        function filePath = baselineFilePath()
            % tests/+mibtest/+perf/ -> (x3 fileparts) -> tests/
            testsFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            filePath = fullfile(testsFolder, 'baselines', ...
                sprintf('perf_%s_R%s.json', getenv('COMPUTERNAME'), version('-release')));
        end

        function filePath = reportFilePath()
            testsFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            filePath = fullfile(testsFolder, 'baselines', ...
                sprintf('perf_report_%s_R%s.md', getenv('COMPUTERNAME'), version('-release')));
        end

    end

    methods (Static, Access = private)

        function safeKey = safeFieldName(measurementKey)
            % Encode a measurement key ('MyTest/op/variant') as a valid struct/JSON field name.
            % Writing and reading the baseline MUST use this same function - a mismatch makes every
            % lookup miss and every test report "no baseline entry" right after a baseline was written.
            safeKey = strrep(char(measurementKey), '/', '_SLASH_');
            safeKey = strrep(safeKey, '-', '_');
        end

        function buffer = sessionBuffer(newBuffer)
            % Persistent dictionary acting as the session measurement buffer.
            persistent buf
            if isempty(buf)
                buf = dictionary(string.empty, struct.empty);
            end
            if nargin == 1
                buf = newBuffer;
            end
            buffer = buf;
        end

        function writeBaseline(buffer)
            baselineFile = mibtest.perf.PerfBaselineStore.baselineFilePath();
            baselineDir  = fileparts(baselineFile);
            if ~isfolder(baselineDir)
                mkdir(baselineDir);
            end

            % Load existing baseline if present (to merge/update individual keys)
            if isfile(baselineFile)
                existing = jsondecode(fileread(baselineFile));
                measurements = existing.measurements;
            else
                measurements = struct();
            end

            keys = buffer.keys();
            for k = 1:numel(keys)
                key   = keys(k);
                entry = buffer(key);
                safeKey = mibtest.perf.PerfBaselineStore.safeFieldName(key);
                measurements.(safeKey) = entry;
                fprintf('[PerfBaseline] wrote %s = %.3f ms\n', key, entry.meanSeconds*1000);
            end

            output.schemaVersion  = 1;
            output.host           = getenv('COMPUTERNAME');
            output.matlabRelease  = sprintf('R%s', version('-release'));
            output.createdUtc     = char(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyy-MM-dd'T'HH:mm:ss'Z'"));
            output.measurements   = measurements;

            fid = fopen(baselineFile, 'w');
            fprintf(fid, '%s', jsonencode(output, 'PrettyPrint', true));
            fclose(fid);
            fprintf('[PerfBaseline] baseline written to %s\n', baselineFile);
        end

        function writeReport(buffer)
            reportFile  = mibtest.perf.PerfBaselineStore.reportFilePath();
            baselineFile = mibtest.perf.PerfBaselineStore.baselineFilePath();
            reportDir = fileparts(reportFile);
            if ~isfolder(reportDir); mkdir(reportDir); end

            hasSaved = isfile(baselineFile);
            if hasSaved
                baseline = jsondecode(fileread(baselineFile));
            end

            fid = fopen(reportFile, 'w');
            fprintf(fid, '# MIB3 Performance Report\n\n');
            fprintf(fid, '- **Host:** %s\n', getenv('COMPUTERNAME'));
            fprintf(fid, '- **MATLAB:** R%s\n', version('-release'));
            fprintf(fid, '- **MIB version:** %s\n', mibtest.perf.PerfBaselineStore.getMibVersion());
            fprintf(fid, '- **Generated:** %s\n\n', ...
                char(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyy-MM-dd'T'HH:mm:ss'Z'")));
            fprintf(fid, '| Measurement | ms/call | baseline | ratio | status |\n');
            fprintf(fid, '|-------------|--------:|--------:|------:|--------|\n');

            keys = buffer.keys();
            for k = 1:numel(keys)
                key   = char(keys(k));
                entry = buffer(keys(k));
                safeKey = mibtest.perf.PerfBaselineStore.safeFieldName(key);
                measMs = entry.meanSeconds * 1000;
                if hasSaved && isfield(baseline, 'measurements') && isfield(baseline.measurements, safeKey)
                    refEntry = baseline.measurements.(safeKey);
                    ratio = entry.meanSeconds / refEntry.meanSeconds;
                    baseMs = refEntry.meanSeconds * 1000;
                    floorSeconds = mibtest.perf.PerfBaselineStore.MinGatedSeconds;
                    if entry.meanSeconds < floorSeconds && refEntry.meanSeconds < floorSeconds
                        status = 'not gated';   % see MinGatedSeconds
                    elseif ratio > mibtest.perf.PerfBaselineStore.FailRatio
                        status = 'FAIL';
                    elseif ratio > mibtest.perf.PerfBaselineStore.WarnRatio
                        status = 'WARN';
                    else
                        status = 'OK';
                    end
                    fprintf(fid, '| %s | %.3f | %.3f | %.2f | %s |\n', key, measMs, baseMs, ratio, status);
                else
                    fprintf(fid, '| %s | %.3f | - | - | (new) |\n', key, measMs);
                end
            end
            fclose(fid);
            fprintf('[PerfBaseline] report written to %s\n', reportFile);
        end

        function versionString = getMibVersion()
            % utils.getMibVersion is the single place the version string is written down, so
            % call it when mib\ is on the path. finalizeRun() runs after runtests() has torn
            % down MibPathFixture, which may already have removed mib\ - read the literal out
            % of that same file in that case rather than reporting 'unknown'.
            versionString = 'unknown';
            try
                versionString = utils.getMibVersion();
                return
            catch
                % mib\ not on the path - fall through to reading the file
            end
            testsFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            versionFile = fullfile(fileparts(testsFolder), 'mib', '+utils', 'getMibVersion.m');
            if ~isfile(versionFile); return; end
            tokens = regexp(fileread(versionFile), "mibVersion\s*=\s*'([^']+)'", 'tokens', 'once');
            if ~isempty(tokens)
                versionString = tokens{1};
            end
        end

        function printSummary(buffer)
            baselineFile = mibtest.perf.PerfBaselineStore.baselineFilePath();
            hasSaved = isfile(baselineFile);
            if hasSaved
                baseline = jsondecode(fileread(baselineFile));
            end

            fprintf('\n%-50s %10s %10s %8s\n', 'Measurement', 'ms/call', 'baseline', 'ratio');
            fprintf('%s\n', repmat('-', 1, 82));

            keys = buffer.keys();
            for k = 1:numel(keys)
                key   = char(keys(k));
                entry = buffer(keys(k));
                safeKey = mibtest.perf.PerfBaselineStore.safeFieldName(key);
                if hasSaved && isfield(baseline, 'measurements') && isfield(baseline.measurements, safeKey)
                    refEntry = baseline.measurements.(safeKey);
                    ratio = entry.meanSeconds / refEntry.meanSeconds;
                    fprintf('%-50s %10.3f %10.3f %8.2f\n', key, ...
                        entry.meanSeconds*1000, refEntry.meanSeconds*1000, ratio);
                else
                    fprintf('%-50s %10.3f %10s %8s\n', key, entry.meanSeconds*1000, '-', '-');
                end
            end
            fprintf('\n');
        end

    end
end
