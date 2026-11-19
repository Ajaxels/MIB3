classdef QuantificationBigDataTest < matlab.unittest.TestCase
% QUANTIFICATIONBIGDATATEST - Quantification of a BigData dataset at a chosen pyramid level, through the batch path of controllers.Quantification.
%
% A synthetic OME-Zarr v3 pyramid (300 x 260 x 3, levels s0..s2, XY scale 2 per
% level) is opened as BigData with an empty model. Objects are written into
% the labels of level s1 (150 x 130 x 3), measured with
% ``controllers.Quantification(mibModel, [], BatchOpt)`` at s1, and compared
% with regionprops on the same level arrays: values in the voxels of the
% level, centroids and bounding boxes mapped to full resolution, and the
% selection written back at the level by ``highlightSelection``.
%
% Write to disk and drive the zarr savers/loaders, so tagged Integration.
%
% See also: controllers.Quantification, mibtest.helpers.buildBigDataModel

    methods (TestClassSetup)
        function addPaths(testCase)
            testsFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testsFolder));
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Integration'})

        function shape2DAreaAtCoarseLevel(testCase)
            [mibModel, levelLabels] = testCase.buildWithObjects();
            tool = controllers.Quantification(mibModel, [], testCase.quantBatchOpt('Shape2D', 'Area', 's1'));

            expected = testCase.expected2D(levelLabels, 'Area');
            testCase.verifyEqual(sort([tool.STATS.Area]), sort(expected.values));
            testCase.verifyEqual(tool.runPyramidLevel.level, 2);
            testCase.verifyEqual(tool.runPyramidLevel.size, [150 130 3]);

            % centroids in full-resolution pixels: (c - 0.5) * 2 + 0.5
            fullCentroids = sortrows(vertcat(tool.STATS.Centroid));
            testCase.verifyEqual(fullCentroids, sortrows((expected.centroids - 0.5) .* [2 2 1] + 0.5), 'AbsTol', 1e-9);
        end

        function physicalUnitsUseTheLevelVoxelSize(testCase)
            [mibModel, levelLabels] = testCase.buildWithObjects();
            BatchOpt = testCase.quantBatchOpt('Shape2D', 'Area', 's1');
            BatchOpt.Units = {'um'};
            tool = controllers.Quantification(mibModel, [], BatchOpt);

            expected = testCase.expected2D(levelLabels, 'Area');
            % s0 voxel 0.02 um, s1 voxel 0.04 um in XY
            testCase.verifyEqual(sort([tool.STATS.Area]), sort(expected.values) * 0.04^2, 'RelTol', 1e-12);
        end

        function shape3DMeanIntensityAtCoarseLevel(testCase)
            [mibModel, levelLabels] = testCase.buildWithObjects();
            tool = controllers.Quantification(mibModel, [], testCase.quantBatchOpt('Shape3D', 'MeanIntensity', 's1'));

            levelImage = mibModel.I{1}.image.getData('image', 3, 1, struct('pyramidLevel', 2));
            levelImage = reshape(levelImage, size(levelImage, 1), size(levelImage, 2), []);
            connected = bwconncomp(levelLabels == 1, 6);
            expected = regionprops(connected, double(levelImage), 'MeanIntensity');
            testCase.verifyEqual(numel(tool.STATS), connected.NumObjects);
            testCase.verifyEqual(sort([tool.STATS.MeanIntensity_Ch1]), sort([expected.MeanIntensity]), 'AbsTol', 1e-9);
        end

        function twoDSliceMeasuresTheLevelSliceOfTheShownSlice(testCase)
            [mibModel, levelLabels] = testCase.buildWithObjects();
            mibModel.I{1}.slices{3} = [2 2];
            BatchOpt = testCase.quantBatchOpt('Shape2D', 'Area', 's1');
            BatchOpt.DatasetType = {'2D, Slice'};
            tool = controllers.Quantification(mibModel, [], BatchOpt);

            expected = regionprops(bwconncomp(levelLabels(:, :, 2) == 1, 4), 'Area');
            testCase.verifyEqual(sort([tool.STATS.Area]), sort([expected.Area]));
            centroids = vertcat(tool.STATS.Centroid);
            testCase.verifyEqual(unique(centroids(:, 3)), 2);
        end

        function highlightWritesTheSelectionAtTheLevel(testCase)
            [mibModel, levelLabels, labels] = testCase.buildWithObjects();
            tool = controllers.Quantification(mibModel, [], testCase.quantBatchOpt('Shape3D', 'Volume', 's1'));
            testCase.verifyEqual(tool.runId(1), 1);     % highlightSelection refuses results of another dataset

            tool.highlightSelection(1:numel(tool.STATS), 'Add');
            selection = labels.getData63('selection', 3, [], struct('pyramidLevel', 2));
            testCase.verifyEqual(selection, uint8(levelLabels == 1));

            tool.highlightSelection(1, 'Remove');
            selection = labels.getData63('selection', 3, [], struct('pyramidLevel', 2));
            expectedSelection = uint8(levelLabels == 1);
            expectedSelection(tool.STATS(1).PixelIdxList) = 0;
            testCase.verifyEqual(selection, expectedSelection);
        end

        function standardDatasetHasOneLevelItem(testCase)
            mibModel = mibtest.helpers.buildSyntheticModel();
            tool = controllers.Quantification(mibModel, [], NaN);
            testCase.verifyEqual(tool.BatchOpt.BigData_PyramidLevel, {'s0', {'s0'}});
        end
    end

    methods (Access = private)
        function [mibModel, levelLabels, labels] = buildWithObjects(testCase)
            % Objects of material 1 written at level s1: two boxes per slice, one 3D bar.
            [mibModel, ~, scratch] = mibtest.helpers.buildBigDataModel(testCase, 1);
            labels = mibtest.helpers.attachBigDataLabels(testCase, mibModel, scratch);
            levelLabels = zeros(150, 130, 3, 'uint8');
            levelLabels(10:20, 15:40, 1) = 1;
            levelLabels(60:90, 70:75, 2) = 1;
            levelLabels(100:140, 20:30, 1:3) = 1;
            levelLabels(30:35, 100:120, 3) = 1;
            labels.setData63(levelLabels, 'labels', 3, [], struct('pyramidLevel', 2));
            mibModel.preferences.System.DeveloperMode = false;
        end
    end

    methods (Static)
        function BatchOpt = quantBatchOpt(shape, property, level)
            detection = 'Object';
            if contains(property, 'Intensity'); detection = 'Intensity'; end
            BatchOpt = struct('MaterialIndex', '1', 'DatasetType', {{'3D, Stack'}}, ...
                'ObjectShape', {{shape}}, 'DetectionType', {{detection}}, 'Property', {{property}}, ...
                'Units', {{'pixels'}}, 'ExportResultsTo', {{'Do not export'}}, ...
                'CropObjectsTo', {{'Do not crop'}}, 'showWaitbar', false, ...
                'BigData_PyramidLevel', {{level}});
        end

        function expected = expected2D(levelLabels, property)
            % regionprops per level slice, 4-connectivity, centroid [x y z]
            expected.values = [];
            expected.centroids = zeros(0, 3);
            for z = 1:size(levelLabels, 3)
                stats = regionprops(bwconncomp(levelLabels(:, :, z) == 1, 4), {property, 'Centroid'});
                expected.values = [expected.values, [stats.(property)]];
                for objectIndex = 1:numel(stats)
                    expected.centroids(end+1, :) = [stats(objectIndex).Centroid, z];
                end
            end
        end
    end
end
