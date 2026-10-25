classdef StarDistIntegrationTest < matlab.unittest.TestCase
    % STARDISTINTEGRATIONTEST - pretrained StarDist end to end: download, normalise, predict, NMS, labels.
    %
    % Downloads the converted 2D_versatile_fluo model from mib.helsinki.fi into a temporary
    % folder (deepmib.stardist.loadPretrained) and segments a synthetic fluorescence image of
    % separate blurred disks, the kind of object the model was trained on, with the call
    % sequence of controllers.MibDeep.startPredictionInstances. Every disk must be found as one
    % object, matched at IoU 0.5.
    %
    % Self-skips when mib.helsinki.fi cannot be resolved.

    properties (Constant)
        DiskRadius = 9
        DiskCentres = [40 40; 40 110; 40 180; 110 40; 110 110; 110 180; 180 40; 180 110; 180 180]
    end

    methods (TestClassSetup)
        function addMibToPath(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
            mibFolder = fileparts(fileparts(fileparts(which('deepmib.stardist.nms'))));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(mibFolder, 'external', 'stardist')));
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresNetwork'})
        function pretrainedModelSegmentsDisks(testCase)
            testCase.assumeTrue(mibtest.helpers.hasNetwork('mib.helsinki.fi'), 'mib.helsinki.fi is not reachable');
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            [model, cancelled] = deepmib.stardist.loadPretrained('2D_versatile_fluo', folder);
            testCase.assertFalse(cancelled);
            testCase.verifyTrue(isfile(fullfile(folder, '2D_versatile_fluo_LICENSE.txt')), ...
                'the licence of the model is shipped with it');

            [image, groundTruth] = testCase.diskImage();
            config = model.config;
            normalizedImage = deepmib.stardist.normalizeImage(image, config.normalizePercentiles);
            [prob, dist] = deepmib.stardist.predictMaps(model.net, normalizedImage, config, ...
                struct('tileSize', [128 128], 'executionEnvironment', 'cpu'));
            [points, scores, rayDist] = deepmib.stardist.nms(prob, dist, config.grid, config.probThresh, config.nmsThresh);
            labels = deepmib.stardist.polygonsToLabel(points, rayDist, scores, size(image));

            stats = deepmib.stardist.matchInstances(groundTruth, labels, 0.5);
            numberOfDisks = size(testCase.DiskCentres, 1);
            testCase.verifyEqual(stats.nPred, numberOfDisks, 'one object per disk');
            testCase.verifyEqual(stats.truePositives, numberOfDisks, 'every disk matched at IoU 0.5');
        end
    end

    methods (Access = private)
        function [image, groundTruth] = diskImage(testCase)
            % dark background with mild noise, blurred bright disks; ground truth one id per disk
            [cols, rows] = meshgrid(1:220, 1:220);
            groundTruth = zeros(220, 220, 'uint16');
            for diskId = 1:size(testCase.DiskCentres, 1)
                inside = (rows - testCase.DiskCentres(diskId, 1)).^2 + (cols - testCase.DiskCentres(diskId, 2)).^2 ...
                    <= testCase.DiskRadius^2;
                groundTruth(inside) = diskId;
            end
            noiseStream = RandStream('mt19937ar', 'Seed', 11);
            intensity = imgaussfilt(double(groundTruth > 0), 1.5) * 180 + 20 + 5 * randn(noiseStream, 220, 220);
            image = uint8(intensity);
        end
    end
end
