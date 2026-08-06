classdef MibPathFixture < matlab.unittest.fixtures.Fixture
    % Adds mib/ and tests/ to the MATLAB path for headless unit tests.
    % Only mib/ is needed for model-layer tests (Phase 0 confirmed - no external
    % folders required for getData/setData/getRGBimage).
    methods
        function setup(fixture)
            % tests/+mibtest/+fixtures/ -> (x3 fileparts) -> tests/
            testsFolder = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            repoRoot    = fileparts(testsFolder);
            mibFolder   = fullfile(repoRoot, 'mib');
            fixture.applyFixture(matlab.unittest.fixtures.PathFixture({mibFolder, testsFolder}));
            fixture.SetupDescription = sprintf('Added mib/ and tests/ to path (repo: %s)', repoRoot);
        end
    end
    methods (Access = protected)
        function tf = isCompatible(~, ~)
            tf = true;   % shareable: all test classes can reuse one instance per run
        end
    end
end
