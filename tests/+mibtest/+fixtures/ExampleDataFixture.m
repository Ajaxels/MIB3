classdef ExampleDataFixture < matlab.unittest.fixtures.Fixture
% EXAMPLEDATAFIXTURE - Shared fixture that downloads and caches a real MIB demo dataset.
%
% Downloads once per test run (or loads from local cache). Multiple test
% classes that request the same dataset name share one fixture instance,
% so the download+reshape runs at most once regardless of how many test
% methods use it.
%
% Usage in a test class:
%   methods (TestClassSetup)
%       function setupPaths(testCase)
%           testCase.applyFixture(mibtest.fixtures.MibPathFixture);
%       end
%   end
%   methods (Test, TestTags = {'Integration', 'RequiresNetwork'})
%       function myTest(testCase)
%           testCase.assumeTrue(mibtest.helpers.hasTestData( ...
%               mibtest.helpers.datasetSpec('Trypanosoma')), 'no cache and offline');
%           dataFixture = testCase.applyFixture( ...
%               mibtest.fixtures.ExampleDataFixture('Trypanosoma'));
%           imageVolume  = dataFixture.Image;
%           labelVolume  = dataFixture.Labels;
%       end
%   end

    properties (SetAccess = immutable)
        DatasetName  (1,:) char
    end

    properties (SetAccess = private)
        Image
        Labels
        MaterialNames
        PixSize
    end

    methods
        function fixture = ExampleDataFixture(datasetName)
            fixture.DatasetName = datasetName;
        end

        function setup(fixture)
            spec = mibtest.helpers.datasetSpec(fixture.DatasetName);
            [fixture.Image, fixture.Labels] = mibtest.helpers.cachedRawDataset(spec);
            fixture.MaterialNames = spec.materialNames;
            fixture.PixSize       = spec.pixSize;
            fixture.SetupDescription = sprintf('Loaded %s dataset (%d MB)', ...
                fixture.DatasetName, round(numel(fixture.Image) / 1e6));
        end
    end

    methods (Access = protected)
        function tf = isCompatible(fixtureA, fixtureB)
            tf = strcmp(fixtureA.DatasetName, fixtureB.DatasetName);
        end
    end
end
