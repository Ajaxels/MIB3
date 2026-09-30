classdef GetSetDataCorrectnessTest < matlab.unittest.TestCase
    % Correctness regression suite for MibModel getData2D/3D/4D and setData2D/3D/4D.
    %
    % Checks are ported 1:1 from benchmarkGetSetData in homeDevTest_Callback.m.
    % Each test method exercises one focused path; a failure pinpoints the broken
    % accessor rather than a mega-test that stops at the first failure.
    %
    % Ground-truth: raw numeric arrays from buildSyntheticModel, compared against
    % the accessor results using verifyEqual.
    %
    % Labels63 bit layout: bits 1-6 = material (bitand(x,63)),
    %                      bit 7 = mask (bitand(x,64)/64),
    %                      bit 8 = selection (bitand(x,128)/128).

    properties (TestParameter)
        modelType = {'labels63', 'labels255', 'labels65535'};
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    % =====================================================================
    % Read correctness - accessor output vs raw ground truth
    % =====================================================================
    methods (Test, TestTags = {'Unit'})

        function get2DImageMatchesRaw(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            result   = mibModel.getData2D('image', midSlice, 3, NaN, opt);
            testCase.verifyEqual(result{1}, squeeze(gt.image(:, :, midSlice, :, 1)));
        end

        function get2DLabelsMatchesRaw(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            result   = mibModel.getData2D('labels', midSlice, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.labels(:, :, midSlice, 1, 1)));
        end

        function get3DImageMatchesRaw(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(result{1}, gt.image(:, :, :, :, 1));
        end

        function get3DLabelsMatchesRaw(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            result = mibModel.getData3D('labels', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.labels));
        end

        function get3DMaskMatchesRaw(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            result = mibModel.getData3D('mask', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.mask));
        end

        function get3DSelectionMatchesRaw(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            result = mibModel.getData3D('selection', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.selection));
        end

        function get3DLabelsMaterialExtraction(testCase, modelType)
            % getData3D with a numeric material index returns binary mask of that material.
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt           = struct('id', 1, 'blockModeSwitch', 0);
            materialIndex = 1;
            result        = mibModel.getData3D('labels', 1, 3, materialIndex, opt);
            expected      = squeeze(uint8(gt.labels == materialIndex));
            testCase.verifyEqual(squeeze(result{1}), expected);
        end

        function get3DImageOrient1(testCase, modelType)
            % Orient 1 (ZX): row=Z, col=X, depth=Y -> permute([h w z c t], [3 2 1 4 5]),
            % so X stays horizontal as in the YX view
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            result   = mibModel.getData3D('image', 1, 1, NaN, opt);
            expected = permute(gt.image(:, :, :, :, 1), [3 2 1 4 5]);
            testCase.verifyEqual(result{1}, expected);
        end

        function get3DImageOrient2(testCase, modelType)
            % Orient 2 (ZY): row=X, col=Z, depth=Y -> permute([h w z c t], [1 3 2 4 5])
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            result   = mibModel.getData3D('image', 1, 2, NaN, opt);
            expected = permute(gt.image(:, :, :, :, 1), [1 3 2 4 5]);
            testCase.verifyEqual(result{1}, expected);
        end

        function get4DImageMatchesRaw(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            result = mibModel.getData4D('image', 3, NaN, opt);
            testCase.verifyEqual(result{1}, gt.image);
        end

        function get4DLabelsMatchesRaw(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            result = mibModel.getData4D('labels', 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(gt.labels));
        end

        function get3DEverythingMatchesRaw(testCase, modelType)
            % 'everything' returns the raw packed uint8 array - labels63 only.
            testCase.assumeTrue(strcmp(modelType, 'labels63'), ...
                'everything type only applies to labels63 datasets');
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt         = struct('id', 1, 'blockModeSwitch', 0);
            rawPacked   = mibModel.I{1}.labels.data;
            result      = mibModel.getData3D('everything', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), squeeze(rawPacked));
        end

    end

    % =====================================================================
    % Set roundtrip correctness - write a modified value, read back, compare
    % =====================================================================
    methods (Test, TestTags = {'Unit'})

        function set2DImageRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.image, 3) / 2);
            newSlice = zeros([size(gt.image, 1) size(gt.image, 2) size(gt.image, 4)], 'uint8');
            mibModel.setData2D(newSlice, 'image', midSlice, 3, NaN, opt);
            result   = mibModel.getData2D('image', midSlice, 3, NaN, opt);
            testCase.verifyEqual(result{1}, newSlice);
        end

        function set2DLabelsRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.labels, 3) / 2);
            current  = mibModel.getData2D('labels', midSlice, 3, [], opt);
            newSlice = zeros(size(current{1}), class(current{1}));
            mibModel.setData2D(newSlice, 'labels', midSlice, 3, [], opt);
            result   = mibModel.getData2D('labels', midSlice, 3, [], opt);
            testCase.verifyEqual(result{1}, newSlice);
        end

        function set2DMaskRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.mask, 3) / 2);
            newSlice = ones([size(gt.mask, 1) size(gt.mask, 2)], 'uint8');
            mibModel.setData2D(newSlice, 'mask', midSlice, 3, [], opt);
            result   = mibModel.getData2D('mask', midSlice, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), newSlice);
        end

        function set2DSelectionRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = round(size(gt.selection, 3) / 2);
            newSlice = zeros([size(gt.selection, 1) size(gt.selection, 2)], 'uint8');
            mibModel.setData2D(newSlice, 'selection', midSlice, 3, [], opt);
            result   = mibModel.getData2D('selection', midSlice, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), newSlice);
        end

        function set2DLabelsMaterialRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt           = struct('id', 1, 'blockModeSwitch', 0);
            midSlice      = round(size(gt.labels, 3) / 2);
            materialIndex = 1;
            newSlice      = zeros([size(gt.labels, 1) size(gt.labels, 2)], 'uint8');
            mibModel.setData2D(newSlice, 'labels', midSlice, 3, materialIndex, opt);
            result = mibModel.getData2D('labels', midSlice, 3, materialIndex, opt);
            testCase.verifyEqual(squeeze(result{1}), newSlice);
        end

        function set3DImageRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            newVol = zeros(size(gt.image), 'uint8');
            mibModel.setData3D(newVol, 'image', 1, 3, NaN, opt);
            result = mibModel.getData3D('image', 1, 3, NaN, opt);
            testCase.verifyEqual(result{1}, newVol);
        end

        function set3DLabelsRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            newVol = zeros(size(gt.labels), class(gt.labels));
            mibModel.setData3D(newVol, 'labels', 1, 3, [], opt);
            result = mibModel.getData3D('labels', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), newVol);
        end

        function set3DMaskRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            newVol = ones(size(gt.mask), 'uint8');
            mibModel.setData3D(newVol, 'mask', 1, 3, [], opt);
            result = mibModel.getData3D('mask', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), newVol);
        end

        function set3DSelectionRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            newVol = zeros(size(gt.selection), 'uint8');
            mibModel.setData3D(newVol, 'selection', 1, 3, [], opt);
            result = mibModel.getData3D('selection', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), newVol);
        end

        function set3DLabelsMaterialRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt           = struct('id', 1, 'blockModeSwitch', 0);
            materialIndex = 1;
            newVol        = zeros(size(gt.labels), 'uint8');
            mibModel.setData3D(newVol, 'labels', 1, 3, materialIndex, opt);
            result = mibModel.getData3D('labels', 1, 3, materialIndex, opt);
            testCase.verifyEqual(squeeze(result{1}), newVol);
        end

        function set3DEverythingRoundtrip(testCase, modelType)
            % Write a modified packed array and verify the accessor returns it.
            testCase.assumeTrue(strcmp(modelType, 'labels63'), ...
                'everything type only applies to labels63 datasets');
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            newVol = zeros(size(mibModel.I{1}.labels.data), 'uint8');
            mibModel.setData3D(newVol, 'everything', 1, 3, [], opt);
            result = mibModel.getData3D('everything', 1, 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), newVol);
        end

        function set4DImageRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            newVol = zeros(size(gt.image), 'uint8');
            mibModel.setData4D(newVol, 'image', 3, NaN, opt);
            result = mibModel.getData4D('image', 3, NaN, opt);
            testCase.verifyEqual(result{1}, newVol);
        end

        function set4DLabelsRoundtrip(testCase, modelType)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt    = struct('id', 1, 'blockModeSwitch', 0);
            newVol = zeros(size(gt.labels), class(gt.labels));
            mibModel.setData4D(newVol, 'labels', 3, [], opt);
            result = mibModel.getData4D('labels', 3, [], opt);
            testCase.verifyEqual(squeeze(result{1}), newVol);
        end

    end

    % =====================================================================
    % Multi-channel (numColors=2) - read isolation, write isolation
    % =====================================================================
    methods (Test, TestTags = {'Unit'})

        function twoChannel_colorCountIsTwo(testCase)
            [mibModel, ~] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4], 'numColors', 2);
            testCase.verifyEqual(mibModel.I{1}.image.colors, 2);
        end

        function get3D_twoChannel_nanCol_returnsBothChannels(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4], 'numColors', 2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            result = mibModel.getData3D('image', 1, 3, NaN, opt);

            testCase.verifyEqual(result{1}, gt.image(:,:,:,:,1), ...
                'getData3D with col=NaN on 2-channel must return [h w z 2]');
        end

        function get2D_twoChannel_colIndex_isolatesEachChannel(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4], 'numColors', 2);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = 2;

            result1 = mibModel.getData2D('image', midSlice, 3, 1, opt);
            result2 = mibModel.getData2D('image', midSlice, 3, 2, opt);

            testCase.verifyEqual(result1{1}, squeeze(gt.image(:,:,midSlice,1)), ...
                'getData2D col=1 must return only the first channel');
            testCase.verifyEqual(result2{1}, squeeze(gt.image(:,:,midSlice,2)), ...
                'getData2D col=2 must return only the second channel');
        end

        function set2D_twoChannel_writeDoesNotBleedToOtherChannel(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4], 'numColors', 2);
            opt      = struct('id', 1, 'blockModeSwitch', 0);
            midSlice = 2;

            zeros2D = zeros(16, 16, 'uint8');
            mibModel.setData2D(zeros2D, 'image', midSlice, 3, 1, opt);

            result2 = mibModel.getData2D('image', midSlice, 3, 2, opt);
            testCase.verifyEqual(result2{1}, squeeze(gt.image(:,:,midSlice,2)), ...
                'setData2D to channel 1 must not alter channel 2');
        end

        function set3D_twoChannel_writeDoesNotBleedToOtherChannel(testCase)
            [mibModel, gt] = mibtest.helpers.buildSyntheticModel( ...
                'modelType', 'labels255', 'dims', [16 16 4], 'numColors', 2);
            opt = struct('id', 1, 'blockModeSwitch', 0);

            zeros3D = zeros(16, 16, 4, 1, 'uint8');
            mibModel.setData3D(zeros3D, 'image', 1, 3, 1, opt);

            result2 = mibModel.getData3D('image', 1, 3, 2, opt);
            testCase.verifyEqual(result2{1}, gt.image(:,:,:,2,1), ...
                'setData3D to channel 1 must not alter channel 2');
        end

    end

    % =====================================================================
    % State preservation - all pure roundtrip writes leave data unchanged
    % =====================================================================
    methods (Test, TestTags = {'Unit'})

        function statePreservedAfterRoundtrips(testCase, modelType)
            % Ported from the stateChecksum check in benchmarkGetSetData.
            % After writing back what was read (pure roundtrip) for every layer,
            % the per-layer checksums must be identical to before.
            [mibModel, ~]  = mibtest.helpers.buildSyntheticModel(modelType=modelType);
            opt            = struct('id', 1, 'blockModeSwitch', 0);
            is63           = strcmp(modelType, 'labels63');
            checksumBefore = GetSetDataCorrectnessTest.stateChecksum(mibModel, 1, is63);

            % Pure roundtrips for all non-'everything' paths
            imageVol = mibModel.getData3D('image', 1, 3, NaN, opt); imageVol = imageVol{1};
            mibModel.setData3D(imageVol, 'image', 1, 3, NaN, opt);

            labelsVol = mibModel.getData3D('labels', 1, 3, [], opt); labelsVol = labelsVol{1};
            mibModel.setData3D(labelsVol, 'labels', 1, 3, [], opt);

            maskVol = mibModel.getData3D('mask', 1, 3, [], opt); maskVol = maskVol{1};
            mibModel.setData3D(maskVol, 'mask', 1, 3, [], opt);

            selVol = mibModel.getData3D('selection', 1, 3, [], opt); selVol = selVol{1};
            mibModel.setData3D(selVol, 'selection', 1, 3, [], opt);

            checksumAfter = GetSetDataCorrectnessTest.stateChecksum(mibModel, 1, is63);
            testCase.verifyEqual(checksumAfter, checksumBefore, ...
                'State changed after pure roundtrip writes - data was mutated unexpectedly');
        end

    end

    % =====================================================================
    % Private helpers - ported from homeDevTest_Callback.m
    % =====================================================================
    methods (Static, Access = private)

        function checksum = stateChecksum(mibModel, datasetId, is63)
            % Lightweight fingerprint of all data layers to detect accidental mutation.
            dataset   = mibModel.I{datasetId};
            checksum  = GetSetDataCorrectnessTest.layerChecksum(dataset.image.data);
            if is63
                checksum = [checksum, ...
                    GetSetDataCorrectnessTest.layerChecksum(dataset.labels.data)];
            else
                checksum = [checksum, ...
                    GetSetDataCorrectnessTest.layerChecksum(dataset.labels.data), ...
                    GetSetDataCorrectnessTest.layerChecksum(dataset.mask.data), ...
                    GetSetDataCorrectnessTest.layerChecksum(dataset.selection.data)];
            end
        end

        function checksum = layerChecksum(dataArray)
            checksum = [sum(dataArray(:), 'double'), nnz(dataArray), numel(dataArray)];
        end

    end
end
