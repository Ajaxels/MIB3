classdef MibFormatRoundTripTest < matlab.unittest.TestCase
% Unit tests for MibModel.exportDatasetToMib + importDatasetFromMib.
%
% These methods copy a layer (labels or mask) between MIB containers
% entirely in memory — no file I/O.  A second container is set up via
% deepCopyDataset so the dimensions match; then the layer is modified
% in the destination to distinguish it from the source, the transfer
% is performed, and the result is verified.
%
% Verification strategies:
%   export labels — overwrite container 2 labels with zeros, export from 1,
%                   verify container 2 matches gt.labels
%   import labels — export to container 2, overwrite container 1 with zeros,
%                   import from container 2, verify container 1 = gt.labels
%   export mask   — overwrite container 2 mask with zeros, export from 1,
%                   verify container 2 checksum matches container 1

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function exportModel_toContainer2_labelsMatch(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);
            mibModel.I{1}.addMaterial('mat1');

            deepOpts.showWaitbar = false;
            deepOpts.UIFigure    = [];
            mibModel.deepCopyDataset(1, 2, deepOpts);  % I{2} = full copy of I{1}

            % Reset I{2} labels to zeros so the export has a detectable effect
            zeroLabels = zeros(16, 24, 4, 'uint8');
            setOpt2.id = 2;  setOpt2.blockModeSwitch = 0;
            mibModel.setData3D(zeroLabels, 'labels', 1, 3, [], setOpt2);

            % Export labels from I{1} to I{2}
            exportOpt.Destination = {'Container 2'};
            exportOpt.showWaitbar = false;
            mibModel.exportDatasetToMib('model', exportOpt);

            opt2   = struct('id', 2, 'blockModeSwitch', 0);
            result = mibModel.getData3D('labels', 1, 3, [], opt2);
            testCase.verifyEqual(squeeze(result{1}), gt.labels, ...
                'exported labels in container 2 must match source container 1');
        end

        function importModel_fromContainer2_restoresLabels(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);
            mibModel.I{1}.addMaterial('mat1');

            deepOpts.showWaitbar = false;
            deepOpts.UIFigure    = [];
            mibModel.deepCopyDataset(1, 2, deepOpts);  % I{2} carries gt.labels

            % Reset I{1} labels to zeros before the import
            zeroLabels = zeros(16, 24, 4, 'uint8');
            setOpt1.id = 1;  setOpt1.blockModeSwitch = 0;
            mibModel.setData3D(zeroLabels, 'labels', 1, 3, [], setOpt1);

            % Import labels from I{2} to I{1}
            importOpt.Source      = {'Container 2'};
            importOpt.showWaitbar = false;
            importOpt.id          = 1;
            mibModel.importDatasetFromMib('model', importOpt);

            opt1   = struct('id', 1, 'blockModeSwitch', 0);
            result = mibModel.getData3D('labels', 1, 3, [], opt1);
            testCase.verifyEqual(squeeze(result{1}), gt.labels, ...
                'importing from container 2 must restore the original label values');
        end

        function exportMask_toContainer2_checksumMatch(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 24 4]);

            deepOpts.showWaitbar = false;
            deepOpts.UIFigure    = [];
            mibModel.deepCopyDataset(1, 2, deepOpts);  % I{2} carries gt.mask

            % Reset I{2} mask to zeros
            zeroMask = zeros(16, 24, 4, 'uint8');
            setOpt2.id = 2;  setOpt2.blockModeSwitch = 0;
            mibModel.setData3D(zeroMask, 'mask', 1, 3, [], setOpt2);

            % Export mask from I{1} to I{2}
            exportOpt.Destination = {'Container 2'};
            exportOpt.showWaitbar = false;
            mibModel.exportDatasetToMib('mask', exportOpt);

            opt1 = struct('id', 1, 'blockModeSwitch', 0);
            opt2 = struct('id', 2, 'blockModeSwitch', 0);
            res1 = mibModel.getData3D('mask', 1, 3, NaN, opt1);
            res2 = mibModel.getData3D('mask', 1, 3, NaN, opt2);

            testCase.verifyEqual(sum(double(squeeze(res2{1})), 'all'), ...
                sum(double(squeeze(res1{1})), 'all'), ...
                'exported mask checksum in container 2 must match source container 1');
            testCase.verifyEqual(squeeze(res2{1}), squeeze(res1{1}), ...
                'exported mask pixel values must match source container 1');
        end

    end

end
