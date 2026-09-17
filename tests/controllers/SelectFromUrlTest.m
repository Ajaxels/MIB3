classdef SelectFromUrlTest < matlab.unittest.TestCase
% SELECTFROMURLTEST - Tests for controllers.SelectFromUrl.
%
% The Unit block builds the controller **view-less** through the documented NaN
% path and asserts the parts that need no window and no network: the BatchOpt
% surface, and the mapping onto MibModel.loadImages options.
%
% The mapping is the load-bearing part. MibModel.loadImages only skips its
% fullfile() path joins when the incoming BatchOpt carries a Filenames field,
% and fullfile would rewrite https://host/group as https://host\group on
% Windows - so a URL that reaches the loader intact is a property worth pinning.
%
% The dialog itself is exercised in the RequiresGUI block, which opens a real
% window and talks to the public OpenOrganelle bucket, so it is excluded from
% the default suite.

    properties (Constant, Access = private)
        StoreRoot = ['https://janelia-cosem-datasets.s3.amazonaws.com/' ...
            'jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr'];
        Host = 'janelia-cosem-datasets.s3.amazonaws.com';
        ImageGroup = 'recon-1/em/fibsem-uint8';
        % The form an OpenOrganelle dataset page hands out, and the OME-Zarr
        % copy published beside it that MIB can actually read.
        N5Root = 's3://janelia-cosem-datasets/jrc_hela-2/jrc_hela-2.n5';
        ZarrTwin = ['https://janelia-cosem-datasets.s3.amazonaws.com/' ...
            'jrc_hela-2/jrc_hela-2.zarr'];
        % A COSEM ground-truth crop: 63 class groups plus a merged 'all', all at
        % 2 nm inside a 4 nm EM volume, so crop s1 pairs with image s0.
        CropGroup = 'recon-1/labels/groundtruth/crop1';
        % A crop whose merged 'all' group holds 17 classes in one array, keyed by
        % the publisher's ids (3, 4, 5, 8, ... 48) with no cellmap block.
        LiverStore = 's3://janelia-cosem-datasets/jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr';
        LiverCropAll = 'recon-1/labels/groundtruth/crop266/all';
    end

    methods (TestClassSetup)
        function addPaths(testCase)
            testCase.applyFixture(mibtest.fixtures.MibPathFixture);
        end
    end

    methods (Test, TestTags = {'Unit'})

        function buildsViewLessAndReturnsTheDocumentedBatchOpt(testCase)
            [controller, ~] = testCase.newViewLessController();

            testCase.verifyTrue(isempty(controller.view), ...
                'the NaN path must not open a window');
            % showWaitbar is intentionally BatchOpt-only, with no widget: the
            % dialog always shows progress, and only a batch protocol may
            % suppress it. So it must be in BatchOpt but absent from the view.
            for fieldName = {'Url', 'GroupPath', 'LoadAs', 'DatasetMode', 'showWaitbar'}
                testCase.verifyTrue(isfield(controller.BatchOpt, fieldName{1}), ...
                    sprintf('BatchOpt.%s is missing', fieldName{1}));
                testCase.verifyTrue(isfield(controller.BatchOpt.mibBatchTooltip, fieldName{1}), ...
                    sprintf('BatchOpt.mibBatchTooltip.%s is missing', fieldName{1}));
            end
            testCase.verifyTrue(controller.BatchOpt.showWaitbar, ...
                'the GUI path must default to showing the progress bar');
            testCase.verifyEqual(controller.BatchOpt.mibBatchSectionName, 'Ribbon -> Home');
            testCase.verifyEqual(controller.BatchOpt.LoadAs{2}, {'Image', 'Labels'});
            testCase.verifyEqual(controller.BatchOpt.DatasetMode{2}, ...
                {'BigData', 'Virtual', 'Standard'});
        end

        function syncBatchPayloadDropsTheDatasetId(testCase)
            % id is per-session state, not a protocol setting.
            [~, syncedBatchOpt] = testCase.newViewLessController();
            testCase.assertNotEmpty(syncedBatchOpt);
            testCase.verifyFalse(isfield(syncedBatchOpt, 'id'));
            testCase.verifyTrue(isfield(syncedBatchOpt, 'Url'));
        end

        function guiFigureIsEmptyWithoutAWindow(testCase)
            % Every dialog and progress bar in this controller is parented via
            % guiFigure(), which is what keeps batch mode from trying to draw.
            controller = testCase.newViewLessController();
            testCase.verifyEmpty(controller.guiFigure());
            testCase.verifyFalse(controller.hasView());
        end

        function buildLoadImagesBatchOptKeepsTheUrlIntact(testCase)
            controller = testCase.newViewLessController();
            controller.rootUrl = testCase.StoreRoot;
            controller.BatchOpt.GroupPath = testCase.ImageGroup;

            loadOptions = controller.buildLoadImagesBatchOpt();

            testCase.verifyEqual(loadOptions.Filenames, {testCase.StoreRoot});
            testCase.verifyFalse(contains(loadOptions.Filenames{1}, '\'), ...
                'fullfile must never touch the URL');
            testCase.verifyEqual(loadOptions.ZarrGroupPath, testCase.ImageGroup);
            testCase.verifyEqual(loadOptions.Mode, {'Combine datasets'});
            testCase.verifyTrue(isfield(loadOptions, 'Filenames'), ...
                'without Filenames, loadImages would rebuild the path with fullfile');
            testCase.verifyNotEqual(loadOptions.DirectoryName{1}, testCase.StoreRoot, ...
                'DirectoryName must stay a real directory, never the URL');
        end

        function connectSkipsAUrlItIsAlreadyConnectedTo(testCase)
            % Enter connects on its own, so pressing the button afterwards would
            % otherwise repeat the whole probe. The guard returns before rootUrl
            % is assigned, which is what makes this assertable with no network.
            controller = testCase.newViewLessController();
            controller.BatchOpt.Url  = testCase.StoreRoot;
            controller.connectedUrl  = testCase.StoreRoot;

            controller.connectBtn_Callback();

            testCase.verifyEmpty(controller.rootUrl, ...
                'a redundant connect must not start probing');
        end

        function onlyEnterTriggersAConnect(testCase)
            % Every key in the dialog reaches keyPress_Callback; all but Enter
            % must fall straight through, or typing a URL would fire a request
            % per character.
            controller = testCase.newViewLessController();
            controller.BatchOpt.Url = testCase.StoreRoot;

            controller.keyPress_Callback(struct('Key', 'a'));

            testCase.verifyEmpty(controller.rootUrl);
            testCase.verifyEmpty(controller.connectedUrl);
        end

        function n5SwapLeavesEveryOtherUrlAloneAndOffline(testCase)
            % resolveN5Sibling runs on every connect, so a URL with no '.n5'
            % path component must return before it touches the network - which
            % is exactly what makes this assertable in the offline suite.
            controller = testCase.newViewLessController();
            untouched = {testCase.StoreRoot, ...
                'https://example.org/some/picture.png', ...
                's3://bucket/dataset.n5x/group'};   % '.n5' not at a component end

            for candidate = untouched
                [resolvedUrl, swapped] = controller.resolveN5Sibling(candidate{1});
                testCase.verifyEqual(resolvedUrl, candidate{1});
                testCase.verifyFalse(swapped, ...
                    sprintf('%s must not be rewritten', candidate{1}));
            end
        end

        function statusAndWidgetWritesAreSafeWithoutAView(testCase)
            % Batch mode runs the same methods with view empty.
            controller = testCase.newViewLessController();
            testCase.verifyWarningFree(@() controller.setStatus('anything'));
            testCase.verifyWarningFree(@() controller.updateWidgets());
        end

        % ---- pre-filling from the dataset that is already open --------------

        function openRemoteContainerSplitsTheStoredGroupUrl(testCase)
            % The dialog pre-fills from the open dataset's filename, which is the
            % *group* URL. Connecting to that would root the tree at the image
            % group and hide the labels next door, so it is split at the store
            % component and the remainder becomes GroupPath.
            [controller, ~, mibModel] = testCase.newViewLessController();
            mibModel.I{mibModel.getActiveId()}.image.filename = ...
                [testCase.ZarrTwin '/' testCase.ImageGroup];

            [containerUrl, groupPath] = controller.openRemoteContainer();

            testCase.verifyEqual(containerUrl, testCase.ZarrTwin);
            testCase.verifyEqual(groupPath, testCase.ImageGroup);
            % and the two halves must rejoin into what was stored
            testCase.verifyEqual(io.RemoteStore.join(containerUrl, groupPath), ...
                [testCase.ZarrTwin '/' testCase.ImageGroup]);
        end

        function openRemoteContainerIgnoresLocalAndEmptyBuffers(testCase)
            % A local file, the empty-buffer placeholder and a plain image URL
            % must all leave the pre-fill to the clipboard.
            [controller, ~, mibModel] = testCase.newViewLessController();
            activeImage = mibModel.I{mibModel.getActiveId()}.image;

            for storedName = {'none.tif', 'C:\data\stack.tif', '/home/user/stack.tif'}
                activeImage.filename = storedName{1};
                [containerUrl, groupPath] = controller.openRemoteContainer();
                testCase.verifyEmpty(containerUrl, ...
                    sprintf('%s is not a remote store', storedName{1}));
                testCase.verifyEmpty(groupPath);
            end

            % remote, but no store component: usable as a URL, nothing to split
            activeImage.filename = 'https://example.org/pictures/slice.png';
            [containerUrl, groupPath] = controller.openRemoteContainer();
            testCase.verifyEqual(containerUrl, 'https://example.org/pictures/slice.png');
            testCase.verifyEmpty(groupPath);
        end

        function batchModeNeverInheritsTheOpenDatasetOrTheClipboard(testCase)
            % The pre-fill is a GUI convenience. A protocol that names a Url but
            % no GroupPath would otherwise replay against the group of whatever
            % dataset happened to be open, which is a different dataset on a
            % different machine.
            [controller, ~, mibModel] = testCase.newViewLessController();
            mibModel.I{mibModel.getActiveId()}.image.filename = ...
                [testCase.ZarrTwin '/' testCase.ImageGroup];

            testCase.verifyEmpty(controller.BatchOpt.Url);
            testCase.verifyEmpty(controller.BatchOpt.GroupPath);
        end

        function loadAsIsNotQuestionedWithoutAWindow(testCase)
            % The question exists so the user can go back to the dialog and
            % change the selection, so a controller with no dialog must skip it
            % and proceed. This also keeps the offline suite safe: the question
            % is modal, and asking it here would block the runner rather than
            % fail it.
            [controller, ~, mibModel] = testCase.newViewLessController();
            mibModel.I{mibModel.getActiveId()}.image.filename = ...
                [testCase.ZarrTwin '/' testCase.ImageGroup];

            proceed = controller.confirmLoadAs( ...
                [testCase.ZarrTwin '/' testCase.CropGroup '/all']);

            testCase.verifyTrue(proceed);
            testCase.verifyEqual(controller.BatchOpt.LoadAs{1}, 'Image', ...
                'nothing may be changed by a question that was never asked');
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresNetwork'})

        function n5UrlRedirectsToTheZarrCopyBesideIt(testCase)
            % Both links on an OpenOrganelle dataset page give the N5 form, and
            % MIB has no N5 reader, so this redirect is the only thing that makes
            % a copy-pasted dataset URL work at all.
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.Host), ...
                'skipped: the OpenOrganelle bucket is not reachable');
            controller = testCase.newViewLessController();

            [resolvedUrl, swapped] = controller.resolveN5Sibling( ...
                io.RemoteStore.normalise(testCase.N5Root));
            testCase.verifyTrue(swapped);
            testCase.verifyEqual(resolvedUrl, testCase.ZarrTwin);

            % A group path inside the container must survive the swap, or a URL
            % pointing at an image group would silently resolve to the root.
            deepN5 = [io.RemoteStore.normalise(testCase.N5Root), '/', testCase.ImageGroup];
            [resolvedDeep, swappedDeep] = controller.resolveN5Sibling(deepN5);
            testCase.verifyTrue(swappedDeep);
            testCase.verifyEqual(resolvedDeep, ...
                [testCase.ZarrTwin, '/', testCase.ImageGroup]);
        end
    end

    methods (Test, TestTags = {'Unit'})

        % ---- label crops: the offline half ---------------------------------

        function labelGroupsAreResolvedInPickOrder(testCase)
            % Pick order decides which class wins where two overlap, so it must
            % survive the round trip through BatchOpt exactly as clicked.
            controller = testCase.newViewLessController();
            controller.rootUrl = testCase.ZarrTwin;
            controller.BatchOpt.LabelGroups = 'a/mito_mem; a/mito_lum ;a/er_mem';

            urls = controller.selectedLabelGroupUrls();
            testCase.verifyEqual(urls, { ...
                [testCase.ZarrTwin '/a/mito_mem'], ...
                [testCase.ZarrTwin '/a/mito_lum'], ...
                [testCase.ZarrTwin '/a/er_mem']});
        end

        function asingleGroupPathStillWorksWithNoMultiSelection(testCase)
            controller = testCase.newViewLessController();
            controller.rootUrl = testCase.ZarrTwin;
            controller.BatchOpt.GroupPath = 'labels/mito';
            testCase.verifyEqual(controller.selectedLabelGroupUrls(), ...
                {[testCase.ZarrTwin '/labels/mito']});
        end

        function annotationPathsAreRecognisedByTheLabelsComponent(testCase)
            % The rule that stops crop1/all - a real pyramid with no cellmap
            % block that encloses the crop exactly - being offered as the image.
            controller = testCase.newViewLessController();
            controller.rootUrl = testCase.ZarrTwin;

            testCase.verifyTrue(controller.isAnnotationPath( ...
                [testCase.ZarrTwin '/recon-1/labels/groundtruth/crop1/all']));
            testCase.verifyFalse(controller.isAnnotationPath( ...
                [testCase.ZarrTwin '/recon-1/em/fibsem-uint8']));
        end

        function containmentRejectsAnnotationsAndVolumesThatMiss(testCase)
            controller = testCase.newViewLessController();
            cropBoxUm = [10 20 10 20 10 20];

            % Candidates declare micrometres here so their boxes compare
            % directly with the crop's; the nm conversion is covered separately
            % by OmeZarrWorldGeometryTest.
            enclosing = testCase.fakePyramid([0 100 0 100 0 100], [1 1 1], 'um');
            testCase.verifyTrue(controller.imageBoxContains(enclosing, cropBoxUm, [1 1 1]));

            tooSmall = testCase.fakePyramid([0 15 0 15 0 15], [1 1 1], 'um');
            testCase.verifyFalse(controller.imageBoxContains(tooSmall, cropBoxUm, [1 1 1]));

            annotated = enclosing;
            annotated.annotation = struct('class_name', 'mito');
            testCase.verifyFalse(controller.imageBoxContains(annotated, cropBoxUm, [1 1 1]), ...
                'a group carrying a cellmap annotation is never the image');
        end

        function containmentToleratesACropGridThatRoundsUp(testCase)
            % jrc_ctl-id8-1: the nuc segmentation is the EM downsampled 16x, and
            % 18500/16 rounds UP to 1157, so its declared extent overshoots the
            % EM's by 1157*64 - 18500*4 = 48 nm. Half an image voxel is 2 nm and
            % rejects that outright, which used to report the EM as "no sibling
            % image pyramid" for a segmentation published beside it.
            controller = testCase.newViewLessController();

            imagePyramid = testCase.fakePyramid( ...
                [0 73.996 0 12.796 0 41.74956], [0.004 0.004 0.00348], 'um');
            cropBoxUm = [-0.002 74.046 -0.002 12.798 -0.00174 41.75826];

            testCase.verifyFalse(controller.imageBoxContains(imagePyramid, cropBoxUm, [0 0 0]), ...
                'the candidate''s own half-voxel is not enough for a 48 nm overshoot');
            testCase.verifyTrue(controller.imageBoxContains(imagePyramid, cropBoxUm, ...
                [0.064 0.064 0.05568]), 'one label voxel bounds the overshoot');
        end

        function theCropPlanPicksTheLevelThatMatchesTheImageScale(testCase)
            % The COSEM case: labels at 2 nm, EM at 4 nm, so label s1 pairs with
            % image s0. Level 0 of each would NOT agree, which is the whole point.
            controller = testCase.newViewLessController();

            labelPyramid = testCase.fakePyramid( ...
                [25863 27861 899 2897 3132.21 3653.59], [2 2 2.62], 'nm');
            labelPyramid.levelNames         = {'s0', 's1'};
            labelPyramid.levelShapesYXZ     = [1000 1000 200; 500 500 100];
            labelPyramid.levelVoxelSizesXYZ = [2 2 2.62; 4 4 5.24];
            labelPyramid.levelWorldBoxes    = [ ...
                25863, 25863+999*2, 899, 899+999*2, 3132.21, 3132.21+199*2.62; ...
                25864, 25864+499*4, 900, 900+499*4, 3133.52, 3133.52+99*5.24];

            imagePyramid = testCase.fakePyramid([0 47996 0 6396 0 33363.08], [4 4 5.24], 'nm');
            imagePyramid.levelNames         = {'s0'};
            imagePyramid.levelShapesYXZ     = [1600 12000 6368];
            imagePyramid.levelVoxelSizesXYZ = [4 4 5.24];
            imagePyramid.levelWorldBoxes    = [0 47996 0 6396 0 33363.08];

            plan = controller.planLabelCrop(labelPyramid, imagePyramid);

            testCase.verifyTrue(plan.ok, plan.reason);
            testCase.verifyEqual(plan.labelLevel, 2, 'label s1 is the 4 nm level');
            testCase.verifyEqual(plan.imageLevel, 1);
            testCase.verifyEqual(plan.shapeYXZ, [500 500 100]);
            testCase.verifyEqual(plan.voxelSizeUm, [0.004 0.004 0.00524], 'AbsTol', 1e-12);
        end

        function theCropPlanPairsACoarseLabelPyramidWithAReducedImageLevel(testCase)
            % The other direction from the COSEM crops: jrc_ctl-id8-1's nuc
            % inference segmentation is published only from 64 nm down, which is
            % the EM's s4 exactly. Pinning the image to its finest level refused
            % this pair for sharing no common resolution; the image is the
            % pyramid that has to give up levels here.
            controller = testCase.newViewLessController();

            emShapes = [3200 18500 11998; 1600 9250 5999; 800 4625 3000; ...
                        400 2313 1500;    200 1157 750;   100 579 375];
            emVoxels = [4 4 3.48] .* 2.^((0:5)');
            % [x y z], as published: half the level's own voxel past the origin
            emTranslations = [0 0 0; 2 2 1.74; 6 6 5.22; 14 14 12.18; ...
                              30 30 26.1; 62 62 53.94];
            emBoxes = zeros(6, 6);
            for levelIndex = 1:6
                shapeXYZ = emShapes(levelIndex, [2 1 3]);
                % column-major read of [xmin ymin zmin; xmax ymax zmax] gives
                % the [xmin xmax ymin ymax zmin zmax] order the planner expects
                emBoxes(levelIndex, :) = reshape([emTranslations(levelIndex, :); ...
                    emTranslations(levelIndex, :) + (shapeXYZ - 1) .* emVoxels(levelIndex, :)], 1, 6);
            end

            imagePyramid = testCase.fakePyramid(emBoxes(1, :), emVoxels(1, :), 'nm');
            imagePyramid.levelNames         = {'s0', 's1', 's2', 's3', 's4', 's5'};
            imagePyramid.levelShapesYXZ     = emShapes;
            imagePyramid.levelVoxelSizesXYZ = emVoxels;
            imagePyramid.levelWorldBoxes    = emBoxes;

            % nuc s0 is byte-for-byte the same grid as EM s4
            labelPyramid = testCase.fakePyramid(emBoxes(5, :), emVoxels(5, :), 'nm');
            labelPyramid.levelNames         = {'s0'};
            labelPyramid.levelShapesYXZ     = emShapes(5, :);
            labelPyramid.levelVoxelSizesXYZ = emVoxels(5, :);
            labelPyramid.levelWorldBoxes    = emBoxes(5, :);

            plan = controller.planLabelCrop(labelPyramid, imagePyramid, 8 * 1024^3);

            testCase.verifyTrue(plan.ok, plan.reason);
            testCase.verifyEqual(plan.labelLevel, 1);
            testCase.verifyEqual(plan.imageLevel, 5, 'the EM s4 is the 64 nm level');
            testCase.verifyEqual(plan.imageLevelName, 's4');
            testCase.verifyEqual(plan.shapeYXZ, [200 1157 750]);
            testCase.verifyEqual(plan.voxelSizeUm, [0.064 0.064 0.05568], 'AbsTol', 1e-12);
            testCase.verifyEqual(plan.requiredBytes, 200 * 1157 * 750 * 2);
        end

        function theCropPlanStillPrefersTheFinestImageLevel(testCase)
            % Searching image levels must not quietly demote a ground-truth crop:
            % where several pairs match, the finest image level has to win. Both
            % image s0/label s1 (4 nm) and image s1/label s2 (8 nm) are valid
            % pairings of this pyramid, and only the first keeps full resolution.
            controller = testCase.newViewLessController();

            labelPyramid = testCase.fakePyramid([0 1998 0 1998 0 398], [2 2 2], 'nm');
            labelPyramid.levelNames         = {'s0', 's1', 's2'};
            labelPyramid.levelShapesYXZ     = [1000 1000 200; 500 500 100; 250 250 50];
            labelPyramid.levelVoxelSizesXYZ = [2 2 2; 4 4 4; 8 8 8];
            labelPyramid.levelWorldBoxes    = [0 1998 0 1998 0 398; ...
                                               1 1997 1 1997 1 397; ...
                                               3 1995 3 1995 3 395];
            labelPyramid.dataType = 'uint8';

            imagePyramid = testCase.fakePyramid([0 1996 0 1996 0 396], [4 4 4], 'nm');
            imagePyramid.levelNames         = {'s0', 's1'};
            imagePyramid.levelShapesYXZ     = [500 500 100; 250 250 50];
            imagePyramid.levelVoxelSizesXYZ = [4 4 4; 8 8 8];
            imagePyramid.levelWorldBoxes    = [0 1996 0 1996 0 396; 2 1994 2 1994 2 394];
            imagePyramid.dataType = 'uint8';

            plan = controller.planLabelCrop(labelPyramid, imagePyramid, 8 * 1024^3);

            testCase.verifyTrue(plan.ok, plan.reason);
            testCase.verifyEqual(plan.imageLevel, 1, 'the finest matching image level wins');
            testCase.verifyEqual(plan.labelLevel, 2);
            testCase.verifyEqual(plan.shapeYXZ, [500 500 100]);
        end

        function theCropPlanRefusesToResampleAScaleMismatch(testCase)
            % Sharing a common scale is a property of this store, not a promise.
            % Forcing a fit would produce labels that look plausible and sit one
            % structure away from the truth.
            controller = testCase.newViewLessController();

            labelPyramid = testCase.fakePyramid([0 6 0 6 0 6], [3 3 3], 'nm');
            labelPyramid.levelShapesYXZ     = [3 3 3];
            labelPyramid.levelVoxelSizesXYZ = [3 3 3];
            labelPyramid.levelWorldBoxes    = [0 6 0 6 0 6];

            imagePyramid = testCase.fakePyramid([0 396 0 396 0 396], [4 4 4], 'nm');
            imagePyramid.levelShapesYXZ     = [100 100 100];
            imagePyramid.levelVoxelSizesXYZ = [4 4 4];
            imagePyramid.levelWorldBoxes    = [0 396 0 396 0 396];

            plan = controller.planLabelCrop(labelPyramid, imagePyramid);
            testCase.verifyFalse(plan.ok);
            testCase.verifySubstring(plan.reason, 'resample');
        end

        function theCropPlanRefusesAWholeVolumeSegmentation(testCase)
            % The same metadata shape describes a ground-truth crop and a
            % whole-volume inference segmentation, and only the first can be
            % loaded this way: the image region is read into RAM with the model
            % beside it. jrc_mus-liver-6's er segmentation is 8500 x 8050 x 8000,
            % i.e. about a terabyte, and used to surface as a Python MemoryError
            % from inside the zarr read after the dataset had already been
            % switched to Standard mode.
            controller = testCase.newViewLessController();

            labelPyramid = testCase.fakePyramid([0 67992 0 63992 0 67992], [8 8 8], 'nm');
            labelPyramid.levelShapesYXZ     = [8050 8000 8500];
            labelPyramid.levelVoxelSizesXYZ = [8 8 8];
            labelPyramid.levelWorldBoxes    = [0 63992 0 67992 0 67992];
            labelPyramid.dataType           = 'uint8';

            imagePyramid = testCase.fakePyramid([0 67992 0 63992 0 68000], [8 8 8], 'nm');
            imagePyramid.levelShapesYXZ     = [8050 8000 8501];
            imagePyramid.levelVoxelSizesXYZ = [8 8 8];
            imagePyramid.levelWorldBoxes    = [0 63992 0 67992 0 68000];
            imagePyramid.dataType           = 'uint8';

            plan = controller.planLabelCrop(labelPyramid, imagePyramid, 8 * 1024^3);

            testCase.verifyFalse(plan.ok);
            testCase.verifySubstring(plan.reason, '8050 x 8000 x 8500');
            testCase.verifySubstring(plan.reason, 'Load as = Image');
            % image + model, one byte each per voxel
            testCase.verifyEqual(plan.requiredBytes, 8050 * 8000 * 8500 * 2);
        end

        function theCropPlanSizesTheRegionAgainstTheGivenLimit(testCase)
            % The limit is an argument so the verdict does not depend on the
            % machine the suite runs on. A COSEM crop passes a realistic one and
            % the same crop is refused by an unrealistic one, which is what pins
            % that the comparison happens at all.
            controller = testCase.newViewLessController();

            labelPyramid = testCase.fakePyramid([0 1996 0 1996 0 396], [4 4 4], 'nm');
            labelPyramid.levelShapesYXZ     = [500 500 100];
            labelPyramid.levelVoxelSizesXYZ = [4 4 4];
            labelPyramid.levelWorldBoxes    = [0 1996 0 1996 0 396];
            labelPyramid.dataType           = 'uint8';

            imagePyramid = testCase.fakePyramid([0 1996 0 1996 0 396], [4 4 4], 'nm');
            imagePyramid.levelShapesYXZ     = [500 500 100];
            imagePyramid.levelVoxelSizesXYZ = [4 4 4];
            imagePyramid.levelWorldBoxes    = [0 1996 0 1996 0 396];
            imagePyramid.dataType           = 'uint16';

            generous = controller.planLabelCrop(labelPyramid, imagePyramid, 8 * 1024^3);
            testCase.verifyTrue(generous.ok, generous.reason);
            % uint16 image + uint8 model = 3 bytes per voxel
            testCase.verifyEqual(generous.requiredBytes, 500 * 500 * 100 * 3);

            stingy = controller.planLabelCrop(labelPyramid, imagePyramid, 1024^2);
            testCase.verifyFalse(stingy.ok);
        end

        function anInstanceSegmentationIsWarnedAboutBeforeOpen(testCase)
            % An instance group can be loaded, as one material over every object,
            % but that loss has to be stated while the user is still choosing -
            % nothing in the resulting model shows that objects were merged.
            % jrc_ctl-id8-1's nuc is the case: a 4-level instance segmentation
            % over a 6-level EM, which nothing reached from the info panel until
            % coarse label pyramids started pairing.
            controller = testCase.newViewLessController();
            controller.rootUrl = testCase.ZarrTwin;
            controller.zarrFormat = 'zarr2';
            % The crop route is Standard-only, and the mode refusal now comes
            % first - so the instance note is only reachable once the mode is
            % the one this route can actually deliver.
            controller.BatchOpt.DatasetMode{1} = 'Standard';

            labelPyramid = testCase.fakePyramid([0 3996 0 3996 0 3996], [4 4 4], 'nm');
            labelPyramid.levelShapesYXZ     = [1000 1000 1000];
            labelPyramid.levelVoxelSizesXYZ = [4 4 4];
            labelPyramid.levelWorldBoxes    = [0 3996 0 3996 0 3996];
            labelPyramid.annotationType = 'instance_segmentation';
            labelPyramid.className      = 'nuc';
            labelPyramid.dataType       = 'uint8';
            controller.probeCache{"pyramid:" + string([testCase.ZarrTwin '/nuc'])} = labelPyramid;

            imagePyramid = testCase.fakePyramid([0 7996 0 7996 0 7996], [4 4 4], 'nm');
            imagePyramid.levelShapesYXZ     = [2000 2000 2000];
            imagePyramid.levelVoxelSizesXYZ = [4 4 4];
            imagePyramid.levelWorldBoxes    = [0 7996 0 7996 0 7996];
            imagePyramid.dataType           = 'uint8';
            controller.probeCache{"pyramid:" + string([testCase.ZarrTwin '/em'])} = imagePyramid;
            controller.BatchOpt.ImageGroupPath = 'em';

            groupSummary = struct('sizeYXZ', [2000 2000 2000]);
            [labelsFit, reason] = controller.resolveLabelRoute([testCase.ZarrTwin '/nuc'], groupSummary);

            testCase.verifyTrue(labelsFit, 'the group can be loaded');
            testCase.verifySubstring(reason, 'instance segmentation');
            testCase.verifySubstring(reason, 'nuc');
            testCase.verifySubstring(reason, 'one material per object');
            testCase.verifySubstring(reason, 'merge');
        end

        function aPlainImageImportForcesStandardAndSaysSo(testCase)
            % An ordinary image is one array in memory, so Standard is the only
            % mode it can be - initialize has always forced it. What was missing
            % is the Sets.datasetTypes cache the Datasets panel actually reads,
            % so importing a JPEG over an open BigData buffer left the panel
            % claiming BigData for a plain image.
            controller = testCase.newViewLessController();
            mibModel   = controller.mibModel;
            datasetId  = mibModel.getActiveId();

            placeholder = {fullfile(mibModel.mibPath, 'assets', 'images', 'default.h5')};
            testCase.assumeTrue(isfile(placeholder{1}), ...
                'skipped: the placeholder dataset is missing from this checkout');

            datasetsInSet = mibModel.Sets.datasetsInSet;
            targetSet     = floor((datasetId - 1) / datasetsInSet) + 1;
            targetLocalId = mod(datasetId - 1, datasetsInSet) + 1;

            % start from a BigData buffer, as the report did
            testCase.assertTrue(controller.ensureDatasetMode(datasetId, 'BigData'));
            testCase.assertEqual(mibModel.I{datasetId}.datasetType, 'BigData');

            % the mode the import needs, applied the same way the import applies it
            controller.BatchOpt.DatasetMode{1} = 'Standard';
            testCase.verifyTrue(controller.ensureDatasetMode(datasetId, 'Standard'));
            testCase.verifyEqual(mibModel.I{datasetId}.datasetType, 'Standard');
            testCase.verifyEqual(mibModel.Sets.datasetTypes{targetSet, targetLocalId}, 'Standard', ...
                'the panel cache must follow, or the dropdown keeps saying BigData');
        end

        function theCropRouteRefusesAModeItCannotDeliver(testCase)
            % The crop route reads the region and the model into memory, so it
            % can only produce a Standard buffer. It used to override Dataset
            % mode silently, leaving the user with something they had not asked
            % for and the Datasets panel showing the mode they had. Refusing
            % keeps the control meaning what it says - and the message has to
            % name both the mode to pick and what it will produce.
            controller = testCase.newViewLessController();
            controller.rootUrl = testCase.ZarrTwin;
            controller.zarrFormat = 'zarr2';
            controller.BatchOpt.ImageGroupPath = 'em';
            [labelUrl, imageUrl] = testCase.stageCropPyramids(controller);

            groupSummary = struct('sizeYXZ', [2000 2000 2000], 'annotationType', '');

            controller.BatchOpt.DatasetMode{1} = 'BigData';
            [labelsFit, reason] = controller.resolveLabelRoute(labelUrl, groupSummary);
            testCase.verifyFalse(labelsFit, 'BigData cannot be delivered by this route');
            % BigData is no longer impossible for a label group - a pyramid over
            % the same volume is served as an overlay - so the refusal has to say
            % why THIS store cannot be, and a sub-volume crop cannot because it
            % does not cover the open image.
            testCase.verifySubstring(reason, 'cannot be shown over the open dataset');
            testCase.verifySubstring(reason, 'do not describe the same volume');
            testCase.verifySubstring(reason, 'standard dataset type');
            % The instructions are the point of the message, not a decoration:
            % the first version ran cause and remedy together and was reported
            % as hard to follow.
            testCase.verifySubstring(reason, 'To continue:');
            testCase.verifySubstring(reason, 'set "Dataset mode" to Standard');
            testCase.verifyEmpty(controller.labelLoadRoute, ...
                'a refused mode must leave no route for Open to follow');

            % and the same group is accepted once the mode can deliver it
            controller.BatchOpt.DatasetMode{1} = 'Standard';
            testCase.verifyTrue(controller.resolveLabelRoute(labelUrl, groupSummary));
            testCase.verifyEqual(controller.labelLoadRoute, 'crop');
            testCase.assertNotEmpty(imageUrl);
        end

        function aCoarseWholeVolumePyramidTakesTheOverlayRoute(testCase)
            % The route that did not exist: labels covering the SAME volume as
            % the open image but only from a coarse level down. Reading them into
            % memory is what the crop route would do, and for a whole-volume
            % segmentation that is hundreds of megabytes at best; instead they are
            % served over the open BigData dataset as each slice is read.
            [controller, ~, mibModel] = testCase.newViewLessController();
            labelUrl = testCase.stageOverlayPyramids(controller, mibModel, 128);

            controller.BatchOpt.DatasetMode{1} = 'BigData';
            groupSummary = struct('sizeYXZ', [16 16 4], 'annotationType', '');
            [labelsFit, reason] = controller.resolveLabelRoute(labelUrl, groupSummary);

            testCase.verifyTrue(labelsFit, reason);
            testCase.verifyEqual(controller.labelLoadRoute, 'overlay', ...
                'neither model nor crop: the dimensions differ but the volume is the same');
            testCase.verifySubstring(reason, 'Label overlay');
            testCase.verifySubstring(reason, '128 nm');
            testCase.verifySubstring(reason, 'cannot be edited');
        end

        function theOverlayIsRefusedForAFractionalScale(testCase)
            % 12 nm labels over an 8 nm image register perfectly well at 1.5x -
            % nothing in the read path breaks. They are refused anyway: a label
            % would be split across an image voxel with no way to say which side
            % it belongs to, and the crop route gives an exact answer instead.
            [controller, ~, mibModel] = testCase.newViewLessController();
            testCase.stageOverlayPyramids(controller, mibModel, 12);
            labelPyramid = controller.probeCache{"pyramid:" + string([testCase.ZarrTwin '/nuc'])};

            openImage = mibModel.I{mibModel.getActiveId()}.image;
            [overlayFits, reason] = controller.resolveOverlayRoute(labelPyramid, openImage);

            testCase.verifyFalse(overlayFits);
            testCase.verifySubstring(reason, 'whole number of image voxels');
        end

        function theOverlayRefusesAPyramidOverADifferentVolume(testCase)
            % Two pyramids can share a voxel size and still not be the same
            % volume, and a scale factor alone cannot tell them apart. Nothing in
            % the overlay carries an origin offset, so placing one anyway would
            % put it at the origin at the wrong extent - the exact bug the crop
            % route exists to avoid.
            [controller, ~, mibModel] = testCase.newViewLessController();
            testCase.stageOverlayPyramids(controller, mibModel, 128);
            labelPyramid = controller.probeCache{"pyramid:" + string([testCase.ZarrTwin '/nuc'])};
            labelPyramid.levelWorldBoxes(1, :) = labelPyramid.levelWorldBoxes(1, :) / 2;

            openImage = mibModel.I{mibModel.getActiveId()}.image;
            [overlayFits, reason] = controller.resolveOverlayRoute(labelPyramid, openImage);

            testCase.verifyFalse(overlayFits);
            testCase.verifySubstring(reason, 'same volume');
        end

        function theOverlayNeedsAnImagePyramidToPlaceLabelsIn(testCase)
            % A Standard buffer has no pyramid and no scale space, so there is
            % nothing to register against. Reported rather than assumed, because
            % the route is offered from the same dropdown either way.
            [controller, ~, mibModel] = testCase.newViewLessController();
            testCase.stageOverlayPyramids(controller, mibModel, 128);
            labelPyramid = controller.probeCache{"pyramid:" + string([testCase.ZarrTwin '/nuc'])};

            openImage = mibModel.I{mibModel.getActiveId()}.image;
            openImage.pyramid = [];
            [overlayFits, reason] = controller.resolveOverlayRoute(labelPyramid, openImage);

            testCase.verifyFalse(overlayFits);
            testCase.verifySubstring(reason, 'no pyramid');
        end

        function anInstanceOverlayIsNamedAsOneMaterialBeforeOpen(testCase)
            % The overlay draws object ids as a single material by default, and
            % that is a decision the user should read before pressing Open rather
            % than infer from the result.
            [controller, ~, mibModel] = testCase.newViewLessController();
            testCase.stageOverlayPyramids(controller, mibModel, 128);
            labelPyramid = controller.probeCache{"pyramid:" + string([testCase.ZarrTwin '/nuc'])};
            labelPyramid.annotationType = 'instance_segmentation';

            openImage = mibModel.I{mibModel.getActiveId()}.image;
            [overlayFits, reason] = controller.resolveOverlayRoute(labelPyramid, openImage);

            testCase.verifyTrue(overlayFits, reason);
            testCase.verifySubstring(reason, 'single material');
        end

        function theLevelPickerOffersOnlyPairsThatLineUp(testCase)
            % Image levels with no matching label level are not choices: offering
            % one would mean resampling a pyramid to fit the other, which
            % planLabelCrop refuses. For a 3-level image against 1 coarse label
            % level there is exactly one pair, and the finest that fits is the
            % default so the preselected row is always openable.
            controller = testCase.newViewLessController();

            imageShapes = [800 800 800; 400 400 400; 200 200 200];
            imageVoxels = [4 4 4] .* 2.^((0:2)');
            imageBoxes  = zeros(3, 6);
            for levelIndex = 1:3
                extent = (imageShapes(levelIndex, [2 1 3]) - 1) .* imageVoxels(levelIndex, :);
                imageBoxes(levelIndex, :) = reshape([zeros(1, 3); extent], 1, 6);
            end

            imagePyramid = testCase.fakePyramid(imageBoxes(1, :), imageVoxels(1, :), 'nm');
            imagePyramid.levelNames         = {'s0', 's1', 's2'};
            imagePyramid.levelShapesYXZ     = imageShapes;
            imagePyramid.levelVoxelSizesXYZ = imageVoxels;
            imagePyramid.levelWorldBoxes    = imageBoxes;
            imagePyramid.dataType           = 'uint8';

            % labels only at 16 nm - the image's s2
            labelPyramid = testCase.fakePyramid(imageBoxes(3, :), imageVoxels(3, :), 'nm');
            labelPyramid.levelNames         = {'s0'};
            labelPyramid.levelShapesYXZ     = imageShapes(3, :);
            labelPyramid.levelVoxelSizesXYZ = imageVoxels(3, :);
            labelPyramid.levelWorldBoxes    = imageBoxes(3, :);
            labelPyramid.dataType           = 'uint8';

            plan = controller.planLabelCrop(labelPyramid, imagePyramid, 8 * 1024^3);

            testCase.verifyTrue(plan.ok, plan.reason);
            testCase.assertNumElements(plan.candidatePairs, 1, ...
                'only the level pair that shares a resolution is a choice');
            testCase.verifyEqual(plan.candidatePairs.imageLevel, 3);
            testCase.verifyEqual(plan.candidatePairs.imageLevelName, 's2');
            testCase.verifyTrue(plan.candidatePairs.fits);
            testCase.verifyEqual(plan.imageLevel, 3, 'the single pair is also the chosen one');
        end

        function theLevelPickerFallsBackToACoarserPairThatFits(testCase)
            % Two pairs line up but the finer one is far too big. The default
            % must be the finest that FITS, so the preselected row can actually
            % be opened - previously the plan took the finest outright and
            % refused, even though a usable pair existed.
            controller = testCase.newViewLessController();

            imageShapes = [4000 4000 4000; 2000 2000 2000];
            imageVoxels = [4 4 4; 8 8 8];
            imageBoxes  = [0 (4000-1)*4 0 (4000-1)*4 0 (4000-1)*4; ...
                           0 (2000-1)*8 0 (2000-1)*8 0 (2000-1)*8];

            imagePyramid = testCase.fakePyramid(imageBoxes(1, :), imageVoxels(1, :), 'nm');
            imagePyramid.levelNames         = {'s0', 's1'};
            imagePyramid.levelShapesYXZ     = imageShapes;
            imagePyramid.levelVoxelSizesXYZ = imageVoxels;
            imagePyramid.levelWorldBoxes    = imageBoxes;
            imagePyramid.dataType           = 'uint8';

            labelPyramid = testCase.fakePyramid(imageBoxes(1, :), imageVoxels(1, :), 'nm');
            labelPyramid.levelNames         = {'s0', 's1'};
            labelPyramid.levelShapesYXZ     = imageShapes;
            labelPyramid.levelVoxelSizesXYZ = imageVoxels;
            labelPyramid.levelWorldBoxes    = imageBoxes;
            labelPyramid.dataType           = 'uint8';

            % 4000^3 x 2 bytes = 119 GiB; 2000^3 x 2 = 14.9 GiB
            plan = controller.planLabelCrop(labelPyramid, imagePyramid, 30 * 1024^3);

            testCase.verifyTrue(plan.ok, plan.reason);
            testCase.assertNumElements(plan.candidatePairs, 2);
            testCase.verifyFalse(plan.candidatePairs(1).fits, 's0 is too large here');
            testCase.verifyTrue(plan.candidatePairs(2).fits);
            testCase.verifyEqual(plan.imageLevel, 2, ...
                'the default must be the finest pair that fits, not the finest pair');
        end

        function instanceObjectsAreKeptWithoutAWindowToAskIn(testCase)
            % Keeping every object is lossless and is what an in-memory model can
            % hold, so it needs no consent - headless and batch take it silently.
            % Only the merge is a choice, and only a protocol may state it.
            controller = testCase.newViewLessController();
            testCase.verifyFalse(controller.BatchOpt.MergeInstanceObjects, ...
                'keeping the objects is the default');
            testCase.verifyTrue(controller.chooseInstanceHandling({'nuc'}), ...
                'no window means keep them and carry on, not refuse');
            testCase.verifyFalse(controller.BatchOpt.MergeInstanceObjects);
        end

        function instanceObjectsAreKeptAsOneMaterialEachByDefault(testCase)
            % The correction to the first version of this: an in-memory model
            % holds up to 65535 materials, so there was never a reason to flatten
            % 864 nuclei into one. Ids become one material each, named by the id.
            controller = testCase.newViewLessController();
            controller.rootUrl = testCase.ZarrTwin;

            % 4 objects with ids 1, 2, 7, 9 plus a voxel of "unknown" (255)
            block = zeros(4, 5, 2, 'uint8');
            block(1, 1, 1) = 1;  block(2, 2, 1) = 2;
            block(3, 3, 2) = 7;  block(4, 4, 2) = 9;
            block(1, 5, 1) = 255;
            instanceGroup = struct('annotationType', 'instance_segmentation', 'className', 'nuc');

            [modelData, materialNames, report] = testCase.composeFromBlock( ...
                controller, block, instanceGroup);

            testCase.verifyEqual(unique(modelData(:))', uint8(0:4), ...
                'each object id keeps a material of its own');
            testCase.verifyEqual(materialNames, {'nuc_1', 'nuc_2', 'nuc_7', 'nuc_9'});
            testCase.verifyEqual(modelData(1, 5, 1), uint8(0), ...
                '"unknown" is not annotated, so it stays background');
            testCase.verifyEqual(report.instanceObjectCounts, 4);
            testCase.verifyTrue(any(contains(report.lines, 'kept as one material each')));
        end

        function overlapBetweenGroupsIsCountedPerPairInPickOrder(testCase)
            % The lookup-table rewrite (a per-class mask loop was O(classes x
            % volume) and took 375 s on 864 objects) also rewrote the overlap
            % bookkeeping, which is the part that can be wrong without looking
            % wrong: a later pick must win, and the voxels it took must be
            % attributed to the exact material it took them from.
            controller = testCase.newViewLessController();
            controller.rootUrl = testCase.ZarrTwin;

            % first group: an index map, values 1 and 2 on two separate rows
            first = zeros(3, 4, 1, 'uint8');
            first(1, :, 1) = 1;
            first(2, :, 1) = 2;

            % second group: a declared single class covering row 2 and row 3, so
            % it takes all 4 voxels of material 2 and none of material 1
            second = zeros(3, 4, 1, 'uint8');
            second(2:3, :, 1) = 1;

            annotations = struct( ...
                'annotationType', {'', 'semantic_segmentation'}, ...
                'className', {'idx', 'later'}, ...
                'encoding', {[], struct('present', 1, 'unknown', 255)});

            [modelData, materialNames, report] = testCase.composeFromBlock( ...
                controller, {first, second}, annotations);

            testCase.verifyEqual(materialNames, {'idx_1', 'idx_2', 'later'});
            testCase.verifyEqual(modelData(1, :, 1), uint8([1 1 1 1]), 'row 1 is untouched');
            testCase.verifyEqual(modelData(2, :, 1), uint8([3 3 3 3]), 'the later pick wins');
            testCase.verifyEqual(modelData(3, :, 1), uint8([3 3 3 3]));

            testCase.assertNumElements(report.overlaps, 1, ...
                'exactly one pair overlaps, and only one must be reported');
            testCase.verifyEqual(report.overlaps(1).later, 3);
            testCase.verifyEqual(report.overlaps(1).earlier, 2, ...
                'the voxels came from idx_2, not idx_1');
            testCase.verifyEqual(report.overlaps(1).voxels, 4);

            % voxelCounts is what each group contributed, before being overwritten
            testCase.verifyEqual(report.voxelCounts, [4 4 8]);
        end

        function mergingAnInstanceGroupIsOptedInto(testCase)
            % The merge is a view, taken only when asked for: every object id
            % becomes one material and the count is reported, because nothing in
            % the model afterwards shows that 4 objects went into it.
            controller = testCase.newViewLessController();
            controller.rootUrl = testCase.ZarrTwin;
            controller.BatchOpt.MergeInstanceObjects = true;

            block = zeros(4, 5, 2, 'uint8');
            block(1, 1, 1) = 1;  block(2, 2, 1) = 2;
            block(3, 3, 2) = 7;  block(4, 4, 2) = 9;
            block(1, 5, 1) = 255;

            [modelData, materialNames, report] = testCase.composeFromBlock(controller, block, ...
                struct('annotationType', 'instance_segmentation', 'className', 'nuc'));

            testCase.verifyEqual(unique(modelData(:))', uint8([0 1]), ...
                'every object id must land in the same material');
            testCase.verifyEqual(nnz(modelData), 4, 'all four objects, and only those');
            testCase.verifyEqual(materialNames, {'nuc'});
            testCase.verifyEqual(report.instanceObjectCounts, 4);
            testCase.verifyTrue(any(contains(report.lines, '4 object(s) were merged')), ...
                'the object count is invisible in the model, so it must be reported');
        end

        function theCropPlanReportsAMissingImagePyramid(testCase)
            controller = testCase.newViewLessController();
            labelPyramid = testCase.fakePyramid([0 6 0 6 0 6], [2 2 2], 'nm');
            labelPyramid.levelShapesYXZ     = [4 4 4];
            labelPyramid.levelVoxelSizesXYZ = [2 2 2];
            labelPyramid.levelWorldBoxes    = [0 6 0 6 0 6];

            plan = controller.planLabelCrop(labelPyramid, []);
            testCase.verifyFalse(plan.ok);
            testCase.verifySubstring(plan.reason, 'No sibling image pyramid');
        end

        function aDeclaredEncodingWins(testCase)
            controller = testCase.newViewLessController();

            declared = struct('encoding', struct('present', 7, 'unknown', 9));
            [present, unknown, isSemantic] = controller.labelEncodingValues(declared);
            testCase.verifyEqual([present unknown], [7 9], ...
                'a group states its own encoding and that must win');
            testCase.verifyTrue(isSemantic);
        end

        function aGroupWithNoEncodingIsAnIndexMapNotABinaryMask(testCase)
            % The bug this pins: assuming "binary, present == 1" for a group that
            % declares nothing looks for voxels equal to 1. A crop's merged 'all'
            % group has no cellmap block and ids starting at 3, so the assumption
            % finds nothing and yields an EMPTY model with no error at all.
            controller = testCase.newViewLessController();

            [~, unknown, isSemantic] = controller.labelEncodingValues(struct('encoding', []));
            testCase.verifyFalse(isSemantic, ...
                'no declared present value means a multi-class index map');
            testCase.verifyEqual(unknown, 255);

            % 'unknown' alone still does not make it binary.
            [~, ~, isSemantic] = controller.labelEncodingValues( ...
                struct('encoding', struct('absent', 0, 'unknown', 255)));
            testCase.verifyFalse(isSemantic);
        end

        function switchingABufferBackToStandardWorks(testCase)
            % switchDatasetMode's placeholder argument means different things per
            % mode: a numeric matrix for Standard, a cell of paths for
            % Virtual/BigData. Passing the cell form to Standard put a cell in
            % MibImage.data and blew up on intmax(class(data)) four frames down,
            % with a message that says nothing about dataset modes.
            controller = testCase.newViewLessController();
            mibModel = controller.mibModel;
            datasetId = mibModel.getActiveId();

            placeholder = {fullfile(mibModel.mibPath, 'assets', 'images', 'default.h5')};
            testCase.assumeTrue(isfile(placeholder{1}), ...
                'skipped: the placeholder dataset is missing from this checkout');

            % Standard -> Virtual -> Standard. The last leg is the one that broke.
            testCase.assertEqual(mibModel.I{datasetId}.datasetType, 'Standard');
            testCase.assertTrue(controller.ensureDatasetMode(datasetId, 'Virtual'));
            testCase.assertEqual(mibModel.I{datasetId}.datasetType, 'Virtual');

            testCase.verifyTrue(controller.ensureDatasetMode(datasetId, 'Standard'));
            testCase.verifyEqual(mibModel.I{datasetId}.datasetType, 'Standard');
            testCase.verifyTrue(ismember(mibModel.I{datasetId}.image.dataClass, ...
                {'uint8','uint16','uint32','uint64','int8','int16','int32','int64'}), ...
                'the Standard placeholder must be an integer image, not a path');
        end

        function switchingTheModeUpdatesTheDatasetsPanelCache(testCase)
            % The panel's type dropdown reads Sets.datasetTypes, NOT
            % I{id}.datasetType, and nothing repaints it when a buffer is loaded
            % into in place. So a programmatic switch left the panel showing
            % BigData over a buffer that had become Standard - reported against a
            % remote label crop, where the mode change is invisible otherwise.
            controller = testCase.newViewLessController();
            mibModel   = controller.mibModel;
            datasetId  = mibModel.getActiveId();

            datasetsInSet = mibModel.Sets.datasetsInSet;
            targetSet     = floor((datasetId - 1) / datasetsInSet) + 1;
            targetLocalId = mod(datasetId - 1, datasetsInSet) + 1;

            placeholder = {fullfile(mibModel.mibPath, 'assets', 'images', 'default.h5')};
            testCase.assumeTrue(isfile(placeholder{1}), ...
                'skipped: the placeholder dataset is missing from this checkout');

            testCase.PanelUpdateCount = 0;
            panelListener = addlistener(mibModel, 'DatasetsPanelUpdate', ...
                @(source, event) testCase.recordPanelUpdate());
            cleanup = onCleanup(@() delete(panelListener));

            % stale on purpose, as the reported case had it
            mibModel.Sets.datasetTypes{targetSet, targetLocalId} = 'BigData';

            testCase.assertTrue(controller.ensureDatasetMode(datasetId, 'Virtual'));
            testCase.verifyEqual(mibModel.Sets.datasetTypes{targetSet, targetLocalId}, ...
                'Virtual', 'the cache must follow the buffer');

            % ...and the repaint must NOT be fired from here. DatasetsPanelUpdate
            % reaches buffers_Callback -> ShowImage, and at this point the buffer
            % holds only the mode-switch placeholder: for Virtual/BigData that is
            % a path to default.h5 with no reader, and the repaint dies inside
            % MibVirtualImage.getDataVirt. Firing it here crashed every BigData
            % import until it was moved back after the load.
            testCase.verifyEqual(testCase.PanelUpdateCount, 0, ...
                'the buffer is not paintable yet - the caller notifies after loading');

            % A no-op for the mode still corrects the cache: the value can be
            % stale from anywhere, and this is the one place that knows.
            mibModel.Sets.datasetTypes{targetSet, targetLocalId} = 'Standard';
            testCase.assertTrue(controller.ensureDatasetMode(datasetId, 'Virtual'));
            testCase.verifyEqual(mibModel.Sets.datasetTypes{targetSet, targetLocalId}, 'Virtual');
            testCase.verifyEqual(testCase.PanelUpdateCount, 0);
        end

        function ensuringTheModeAlreadySetIsANoOp(testCase)
            % switchDatasetMode re-initialises the buffer with a placeholder, so
            % calling it needlessly would discard whatever is open.
            controller = testCase.newViewLessController();
            mibModel = controller.mibModel;
            datasetId = mibModel.getActiveId();
            originalDims = mibModel.I{datasetId}.image.dim_yxzct;

            testCase.verifyTrue(controller.ensureDatasetMode(datasetId, 'Standard'));
            testCase.verifyEqual(mibModel.I{datasetId}.image.dim_yxzct, originalDims, ...
                'a no-op switch must leave the open dataset untouched');
        end

        function theProgressBarIsIndeterminateAndAlwaysCleanedUp(testCase)
            % Nothing in a remote open can report a percentage until the label
            % groups are counted, so the bar starts Indeterminate. It is held on
            % the controller because every error path must close it before its
            % own dialog - a modal bar left up sits in front of the message.
            controller = testCase.newViewLessController();
            parentFigure = uifigure('Visible', 'on', 'Position', [50 50 300 120]);
            testCase.addTeardown(@() delete(parentFigure));
            controller.view = struct('gui', parentFigure, 'handles', struct());

            controller.startProgress('Opening the dataset...');
            progressBar = controller.progressDialog;
            testCase.assertNotEmpty(progressBar);
            testCase.verifyEqual(char(progressBar.Indeterminate), 'on');
            testCase.verifyEqual(progressBar.Message, 'Opening the dataset...');

            controller.stopProgress();
            testCase.verifyEmpty(controller.progressDialog);
            testCase.verifyFalse(isvalid(progressBar), 'the bar must actually be destroyed');

            % Error paths call stopProgress, then onCleanup calls it again.
            controller.stopProgress();

            % Restarting replaces rather than stacks a second modal bar.
            controller.startProgress('first');
            firstBar = controller.progressDialog;
            controller.startProgress('second');
            testCase.verifyFalse(isvalid(firstBar));
            testCase.verifyTrue(isvalid(controller.progressDialog));
            controller.stopProgress();
        end

        function theProgressBarNeverBlocksAnImport(testCase)
            % A progress bar reports work; it is never the work itself. Both a
            % suppressed waitbar and a parent uiprogressdlg refuses (it requires
            % Visible='on') must degrade to "no bar", not to a failed import.
            controller = testCase.newViewLessController();

            controller.BatchOpt.showWaitbar = false;
            controller.startProgress('suppressed');
            testCase.verifyEmpty(controller.progressDialog);

            % headless: no view and no main window to parent to
            controller.BatchOpt.showWaitbar = true;
            controller.view   = [];
            controller.mibGUI = [];
            controller.startProgress('headless');
            testCase.verifyEmpty(controller.progressDialog);

            hiddenFigure = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(hiddenFigure));
            controller.view = struct('gui', hiddenFigure, 'handles', struct());
            controller.startProgress('invisible parent');
            testCase.verifyEmpty(controller.progressDialog, ...
                'an invisible parent must give no bar rather than raise');
        end

        function aGroupNameIsNeverAUrl(testCase)
            % The fallback used to be relativePath(join(url, '..'), url), but
            % join() appends '..' instead of resolving it, so relativePath found
            % no common prefix and returned the whole URL - which then appeared
            % in the Segmentation panel as the material name.
            controller = testCase.newViewLessController();
            groupUrl = [testCase.ZarrTwin '/' testCase.CropGroup '/all'];

            testCase.verifyEqual(controller.labelGroupName(groupUrl, []), 'all');
            testCase.verifyEqual(controller.labelGroupName([groupUrl '/'], []), 'all');
            testCase.verifyEqual( ...
                controller.labelGroupName(groupUrl, struct('className', 'mito_mem')), ...
                'mito_mem', 'a declared class_name wins over the path');
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresNetwork'})

        function theJaneliaCropPairsWithItsEmRegion(testCase)
            % Pins the published crop1 geometry end to end against the live
            % store: which image group, which level of each, and the exact EM
            % voxel bounds. Every number here is a fraction of a voxel away from
            % labels that sit on the wrong structures.
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.Host), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            controller = testCase.newViewLessController();
            controller.rootUrl    = testCase.ZarrTwin;
            controller.zarrFormat = 'zarr2';

            labelUrl = [testCase.ZarrTwin '/' testCase.CropGroup '/mito_mem'];
            labelPyramid = controller.readGroupPyramid(labelUrl);
            testCase.assertTrue(labelPyramid.ok);
            testCase.verifyEqual(labelPyramid.className, 'mito_mem');
            testCase.verifyEqual(labelPyramid.annotationType, 'semantic_segmentation');
            testCase.verifyEqual(labelPyramid.levelShapesYXZ(2, :), [500 500 100]);

            [imageUrl, imagePyramid] = controller.resolveSiblingImageGroup(labelUrl, labelPyramid);
            testCase.verifyEqual(io.RemoteStore.relativePath(testCase.ZarrTwin, imageUrl), ...
                'recon-1/em/fibsem-uint8', ...
                'crop1/all is a pyramid enclosing the crop but is an annotation, not the image');

            plan = controller.planLabelCrop(labelPyramid, imagePyramid);
            testCase.verifyTrue(plan.ok, plan.reason);
            testCase.verifyEqual(plan.shapeYXZ, [500 500 100]);

            % The published EM bounds for crop1, as 1-based inclusive ranges.
            voxelRange = io.loaders.OmeZarrMetadataUtils.regionToVoxelRange( ...
                plan.cropOuterBoxUm * 1000, imagePyramid.levelWorldBoxes(1, :), ...
                imagePyramid.levelVoxelSizesXYZ(1, :), imagePyramid.levelShapesYXZ(1, [2 1 3]));
            testCase.verifyEqual(voxelRange, [6467 6966; 226 725; 599 698]);
        end

        function anInstanceGroupIsIdentifiedSoItCanBeRefused(testCase)
            % Instance values are object ids; blending one into a material index
            % map would merge every object into one material, invisibly.
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.Host), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            controller = testCase.newViewLessController();
            controller.rootUrl    = testCase.ZarrTwin;
            controller.zarrFormat = 'zarr2';

            instancePyramid = controller.readGroupPyramid( ...
                [testCase.ZarrTwin '/' testCase.CropGroup '/mito']);
            testCase.verifyEqual(instancePyramid.annotationType, 'instance_segmentation');
        end

        function theCropOpensAsAnImageRegionWithItsLabelsOnTop(testCase)
            % The whole feature, headless: image region plus a blended model,
            % with the labels asserted to sit on the EM structures rather than
            % merely to have the right shape.
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.Host), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            mibModel = mibtest.helpers.buildSyntheticModel();
            mibModel.preferences.System.DeveloperMode = false;

            BatchOpt = struct();
            BatchOpt.Url = testCase.ZarrTwin;
            BatchOpt.LabelGroups = strjoin(cellfun( ...
                @(className) [testCase.CropGroup '/' className], ...
                {'mito_mem', 'mito_lum'}, 'UniformOutput', false), ';');
            BatchOpt.LoadAs = {'Labels'};
            % The crop route reads a region into memory, so it is Standard-only
            % and now says so rather than overriding the mode silently. The
            % BatchOpt default is BigData, so a protocol taking this route has to
            % name Standard - which is the whole point of the refusal.
            BatchOpt.DatasetMode = {'Standard'};
            BatchOpt.showWaitbar = false;
            controllers.SelectFromUrl(mibModel, [], BatchOpt);

            datasetId = mibModel.getActiveId();
            image = mibModel.I{datasetId}.image;
            testCase.verifyEqual(mibModel.I{datasetId}.datasetType, 'Standard');
            testCase.verifyEqual([image.height, image.width, image.depth], [500 500 100]);
            % pixSize is in the store's own declared unit, so 4 nm, not 0.004 um.
            testCase.verifyEqual(image.pixSize.units, 'nm');
            testCase.verifyEqual(image.pixSize.x, 4, 'AbsTol', 1e-12);
            testCase.verifyEqual(image.pixSize.z, 5.24, 'AbsTol', 1e-12);

            testCase.assertTrue(mibModel.I{datasetId}.modelExist);
            testCase.verifyEqual(mibModel.I{datasetId}.labels.materialNames(:)', ...
                {'mito_mem', 'mito_lum'});

            model = mibModel.getData3D('labels', 1, 3, NaN, struct('id', datasetId));
            model = model{1};
            testCase.verifyEqual(size(model), [500 500 100]);
            testCase.verifyGreaterThan(nnz(model == 1), 0, 'mito_mem must have voxels here');
            testCase.verifyGreaterThan(nnz(model == 2), 0, 'mito_lum must have voxels here');

            % The alignment check that a shape comparison cannot make: membranes
            % are darker than the crop as a whole. A one-voxel or one-structure
            % misplacement would wash this difference out.
            imageBlock = mibModel.getData3D('image', 1, 3, 1, struct('id', datasetId));
            imageBlock = double(imageBlock{1});
            testCase.verifyLessThan(mean(imageBlock(model == 1)), mean(imageBlock(:)) - 10, ...
                'mito_mem must land on dark membrane, not on arbitrary voxels');
        end

        function aMergedAllGroupBecomesOneMaterialPerClassId(testCase)
            % 'all' holds every class of a crop in ONE array, keyed by the
            % publisher's class ids, and declares no encoding. It has to split
            % into a material per id; treating it as a binary mask gave an empty
            % model and no error.
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.Host), ...
                'skipped: the OpenOrganelle bucket is not reachable');

            mibModel = mibtest.helpers.buildSyntheticModel();
            mibModel.preferences.System.DeveloperMode = false;

            BatchOpt = struct();
            BatchOpt.Url = testCase.LiverStore;
            BatchOpt.LabelGroups = testCase.LiverCropAll;
            BatchOpt.LoadAs = {'Labels'};
            BatchOpt.DatasetMode = {'Standard'};   % crop route, see the test above
            BatchOpt.showWaitbar = false;
            controllers.SelectFromUrl(mibModel, [], BatchOpt);

            datasetId = mibModel.getActiveId();
            testCase.assertTrue(mibModel.I{datasetId}.modelExist);
            testCase.verifyEqual([mibModel.I{datasetId}.image.height, ...
                mibModel.I{datasetId}.image.width, mibModel.I{datasetId}.image.depth], ...
                [200 200 200]);

            model = mibModel.getData3D('labels', 1, 3, NaN, struct('id', datasetId));
            model = model{1};

            % Ground truth: the raw index map, remapped to 1..N in value order.
            rawUrl = [io.RemoteStore.normalise(testCase.LiverStore) '/' testCase.LiverCropAll '/s1'];
            raw = permute(io.zarr.Array(rawUrl).read(), [2 3 1]);   % [z,y,x] -> [y,x,z]
            classValues = unique(raw(raw ~= 0 & raw ~= 255))';
            expected = zeros(size(raw), 'uint8');
            for classIndex = 1:numel(classValues)
                expected(raw == classValues(classIndex)) = classIndex;
            end

            testCase.verifyGreaterThan(numel(classValues), 1, ...
                'this crop is meant to hold several classes in one array');
            testCase.verifyEqual(model, expected, ...
                'the model must reproduce the index map exactly, not a subset of it');

            % Materials are named by the store's own id, because the ids are the
            % publisher's table and NOT the crop's class_names order.
            names = mibModel.I{datasetId}.labels.materialNames(:)';
            testCase.verifyEqual(numel(names), numel(classValues));
            testCase.verifyEqual(names{1}, sprintf('all_%d', classValues(1)));
            testCase.verifyFalse(any(contains(names, 'http')), ...
                'a material name must never be a URL');
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresGUI'})

        function theSelectedNodeIsMarkedWhenItMatchesTheOpenDataset(testCase)
            % Offline, but it needs real graphics: uitree node styling is what
            % carries the verdict, and there is no headless stand-in for it.
            %
            % Both directions matter. The green node says "this one lines up";
            % the panel line says what it lines up WITH, which is the part a
            % colour cannot express - and on a mismatch it names the size the
            % group would have to have.
            mibModel = mibtest.helpers.buildSyntheticModel();
            mibModel.preferences.System.DeveloperMode = false;
            openImage = mibModel.I{mibModel.getActiveId()}.image;
            % A synthetic model keeps the empty-buffer placeholder name, and the
            % comparison is deliberately skipped for that: 'none.tif' is a blank
            % 512x512 nobody is loading labels onto.
            openImage.filename = 'C:\data\stack.tif';
            openSizeYXZ = [openImage.height, openImage.width, openImage.depth];

            controller = controllers.SelectFromUrl(mibModel, [], NaN);
            controller.rootUrl = 'https://host/store.zarr';

            figureHandle = uifigure('Visible', 'off');
            testCase.addTeardown(@() delete(figureHandle));
            groupTree = uitree(figureHandle);
            matchingNode  = uitreenode(groupTree, 'Text', 'sameSize');
            differingNode = uitreenode(groupTree, 'Text', 'otherSize');
            controller.view = struct('gui', figureHandle, 'handles', struct( ...
                'groupTree', groupTree, 'infoTextArea', uitextarea(figureHandle), ...
                'GroupPath', uieditfield(figureHandle), 'openButton', uibutton(figureHandle)));

            groupSummary = struct('hasMultiscales', true, 'sizeYXZ', openSizeYXZ, ...
                'levelCount', 3, 'dataType', 'uint8', 'voxelSize', [1 1 1], ...
                'units', 'nm', 'lines', {{'Levels : 3'}});

            groupTree.SelectedNodes = matchingNode;
            controller.applySummary('https://host/store.zarr/same', groupSummary);

            testCase.verifyTrue(any(contains(controller.view.handles.infoTextArea.Value, ...
                'same size as the open dataset')));
            testCase.assertEqual(height(groupTree.StyleConfigurations), 1, ...
                'the matching node must carry a style');
            testCase.verifyEqual(groupTree.StyleConfigurations.TargetIndex{1}.Text, 'sameSize');

            % A different group clears it: only the selection has been probed, so
            % a style left behind would credit a node nothing was checked for.
            groupSummary.sizeYXZ    = openSizeYXZ + [7 0 0];
            groupTree.SelectedNodes = differingNode;
            controller.applySummary('https://host/store.zarr/other', groupSummary);

            testCase.verifyEqual(height(groupTree.StyleConfigurations), 0);
            testCase.verifyTrue(any(contains(controller.view.handles.infoTextArea.Value, ...
                sprintf('%d x %d x %d', openSizeYXZ(2), openSizeYXZ(1), openSizeYXZ(3)))), ...
                'a mismatch must name the size the open dataset actually has');
        end
    end

    methods (Test, TestTags = {'Integration', 'RequiresNetwork', 'RequiresGUI'})

        function browsesTheContainerAndOpensTheImageGroup(testCase)
            testCase.assumeTrue(mibtest.helpers.hasNetwork(testCase.Host), ...
                'skipped: the OpenOrganelle bucket is not reachable');
            testCase.assumeTrue(io.zarr.PyBackend.hasRemoteSupport(), ...
                'skipped: the Python environment cannot reach remote stores');

            mibModel = mibtest.helpers.buildSyntheticModel();
            mibModel.preferences.System.DeveloperMode = false;
            controller = controllers.SelectFromUrl(mibModel);
            testCase.addTeardown(@() delete(controller.view.gui));

            widgets = controller.view.handles;
            % Enable is a matlab.lang.OnOffSwitchState, which converts to logical.
            testCase.verifyFalse(logical(widgets.openButton.Enable), ...
                'nothing is selected yet, so there is nothing to open');
            testCase.verifyEmpty(widgets.groupTree.Children, ...
                'placeholder nodes drawn in App Designer must be cleared at startup');
            testCase.verifyFalse(isfield(widgets, 'showWaitbar'), ...
                'showWaitbar is BatchOpt-only and must not appear in the dialog');

            widgets.Url.Value = testCase.StoreRoot;
            controller.BatchOpt.Url = testCase.StoreRoot;
            controller.connectBtn_Callback();
            testCase.verifyNumElements(widgets.groupTree.Children, 1, ...
                'connecting seeds exactly one root node');

            % The root must arrive already filled. NodeExpandedFcn fires only on
            % a click, never on the programmatic expand() that follows the seed,
            % so a root left with its placeholder would sit on "loading..." for
            % good - and the walk below would not catch it, because it calls the
            % expand callback directly rather than through the tree.
            rootNode = widgets.groupTree.Children(1);
            rootChildText = arrayfun(@(child) string(child.Text), rootNode.Children);
            testCase.verifyNotEmpty(rootChildText, 'the root node was never listed');
            testCase.verifyFalse(any(rootChildText == "loading..."), ...
                'the root placeholder was never replaced');
            testCase.verifyTrue(rootNode.NodeData.expanded);

            % walk down to the image group, one expand per level
            node = widgets.groupTree.Children(1);
            for depth = 1:3
                controller.treeNodeExpanded_Callback(struct('Node', node));
                children = node.Children;
                nextIndex = find(arrayfun(@(n) ismember(string(n.Text), ...
                    ["recon-1", "em", "fibsem-uint8"]), children), 1);
                testCase.assertNotEmpty(nextIndex, ...
                    sprintf('expected an image branch at depth %d', depth));
                node = children(nextIndex);
            end
            testCase.verifyEqual(node.Text, 'fibsem-uint8');

            controller.treeSelectionChanged_Callback(struct('SelectedNodes', node));
            testCase.verifyEqual(widgets.GroupPath.Value, testCase.ImageGroup);
            testCase.verifyTrue(logical(widgets.openButton.Enable), ...
                'a group with multiscales is openable');

            summaryText = strjoin(widgets.infoTextArea.Value, ' ');
            testCase.verifySubstring(summaryText, '15');
            testCase.verifySubstring(summaryText, 'uint8', ...
                'the data type must be the MATLAB class, not the numpy typestring');
            testCase.verifySubstring(summaryText, '49645');

            controller.openBtn_Callback();
            image = mibModel.I{mibModel.getActiveId()}.image;
            testCase.verifyEqual(image.dim_yxzct(1:3), [21451 23601 49645]);
            testCase.verifyEqual(mibModel.I{mibModel.getActiveId()}.datasetType, 'BigData');
        end
    end

    methods (Access = private)
        function [controller, syncedBatchOpt, mibModel] = newViewLessController(testCase)
            % NEWVIEWLESSCONTROLLER - Build through the documented NaN path.
            % The model is returned as well for tests that need to stage it -
            % never shared between methods, since MibModel is a handle.
            mibModel = mibtest.helpers.buildSyntheticModel();
            mibModel.preferences.System.DeveloperMode = false;

            testCase.SyncedBatchOpt = [];
            syncListener = addlistener(mibModel, 'SyncBatch', ...
                @(source, event) testCase.recordSync(event));
            controller = controllers.SelectFromUrl(mibModel, [], NaN);
            delete(syncListener);
            syncedBatchOpt = testCase.SyncedBatchOpt;
        end

        function recordSync(testCase, event)
            testCase.SyncedBatchOpt = event.Parameters;
        end

        function recordPanelUpdate(testCase)
            testCase.PanelUpdateCount = testCase.PanelUpdateCount + 1;
        end

        function [modelData, materialNames, report] = composeFromBlock(testCase, controller, blocks, annotations)
            % COMPOSEFROMBLOCK - Run composeLabelModel over real local zarr arrays.
            %
            % The composer reads pixels through io.zarr.Array, so a stub cannot
            % reach it - and the value handling is exactly what needs asserting.
            % One-array v2 stores built here keep that offline, the same way
            % ZarrRegionReadTest drives the loaders.
            %
            % ``blocks`` is one [y x z] array, or a cell of them for a
            % multi-group composition; ``annotations`` matches element for
            % element.
            import matlab.unittest.fixtures.TemporaryFolderFixture
            if ~iscell(blocks); blocks = {blocks}; end
            tempFixture = testCase.applyFixture(TemporaryFolderFixture);

            originalLibrary = io.zarr.Config.library();
            io.zarr.Config.setLibrary('native');
            testCase.addTeardown(@() io.zarr.Config.setLibrary(originalLibrary));

            storePaths   = cell(1, numel(blocks));
            pyramidInfos = cell(1, numel(blocks));
            for blockIndex = 1:numel(blocks)
                block = blocks{blockIndex};
                storePaths{blockIndex} = fullfile(tempFixture.Folder, ...
                    sprintf('labels%d.zarr2', blockIndex));
                group = io.zarr.Group.create(storePaths{blockIndex}, 'zarrFormat', 2);
                % the store's own C-order is [z y x]; the caller writes [y x z]
                raw = permute(block, [3 1 2]);
                levelArray = group.createArray('s0', size(raw), class(block), ...
                    'chunkShape', size(raw), 'fillValue', 0);
                levelArray.write(raw);

                pyramidInfo = testCase.fakePyramid([0 1 0 1 0 1], [1 1 1], 'nm');
                pyramidInfo.axisOrder      = 'zyx';
                pyramidInfo.levelNames     = {'s0'};
                pyramidInfo.annotationType = annotations(blockIndex).annotationType;
                pyramidInfo.className      = annotations(blockIndex).className;
                if isfield(annotations, 'encoding')
                    pyramidInfo.encoding = annotations(blockIndex).encoding;
                end
                pyramidInfos{blockIndex} = pyramidInfo;
            end

            cropPlan = struct('labelLevel', 1, 'shapeYXZ', size(blocks{1}));
            [modelData, materialNames, report] = controller.composeLabelModel( ...
                storePaths, pyramidInfos, cropPlan, []);
        end

        function [labelUrl, imageUrl] = stageCropPyramids(testCase, controller)
            % STAGECROPPYRAMIDS - Seed the probe cache with a label/image pair
            % that lines up, so resolveLabelRoute runs with no network.
            labelUrl = [testCase.ZarrTwin '/nuc'];
            imageUrl = [testCase.ZarrTwin '/em'];

            labelPyramid = testCase.fakePyramid([0 3996 0 3996 0 3996], [4 4 4], 'nm');
            labelPyramid.levelShapesYXZ     = [1000 1000 1000];
            labelPyramid.levelVoxelSizesXYZ = [4 4 4];
            labelPyramid.levelWorldBoxes    = [0 3996 0 3996 0 3996];
            labelPyramid.dataType           = 'uint8';
            controller.probeCache{"pyramid:" + string(labelUrl)} = labelPyramid;

            imagePyramid = testCase.fakePyramid([0 7996 0 7996 0 7996], [4 4 4], 'nm');
            imagePyramid.levelShapesYXZ     = [2000 2000 2000];
            imagePyramid.levelVoxelSizesXYZ = [4 4 4];
            imagePyramid.levelWorldBoxes    = [0 7996 0 7996 0 7996];
            imagePyramid.dataType           = 'uint8';
            controller.probeCache{"pyramid:" + string(imageUrl)} = imagePyramid;
        end

        function labelUrl = stageOverlayPyramids(testCase, controller, mibModel, labelVoxelNm)
            % STAGEOVERLAYPYRAMIDS - An open 8 nm BigData image plus a coarse
            % label pyramid over the SAME volume, both offline.
            %
            % The jrc_mus-kidney shape: 256 voxels of 8 nm against labels at
            % ``labelVoxelNm``, so the label pyramid's own level 0 is one of the
            % image's middle levels. World boxes are centre-based in nm, which is
            % the unit the zarr loaders leave pixSize in.
            labelUrl = [testCase.ZarrTwin '/nuc'];
            % readGroupPyramid returns an empty result without a format, so the
            % seeded cache would never be consulted and the route would be
            % decided on a pyramid that was never read.
            controller.zarrFormat = 'zarr2';

            openImage = mibModel.I{mibModel.getActiveId()}.image;
            openImage.height = 256;
            openImage.width  = 256;
            openImage.depth  = 64;
            pixSize = openImage.pixSize;
            pixSize.x = 8; pixSize.y = 8; pixSize.z = 8; pixSize.units = 'nm';
            openImage.pixSize = pixSize;
            openImage.boundingBox = [0 255*8 0 255*8 0 63*8];
            openImage.pyramid = struct('levelScaleFactors', 2 .^ (0:5)' * [1 1 1]);

            labelShape = [256 256 64] * 8 / labelVoxelNm;
            labelPyramid = testCase.fakePyramid( ...
                [0 (labelShape(2)-1)*labelVoxelNm, 0 (labelShape(1)-1)*labelVoxelNm, ...
                 0 (labelShape(3)-1)*labelVoxelNm], repmat(labelVoxelNm, 1, 3), 'nm');
            labelPyramid.levelNames         = {'s0', 's1', 's2'};
            labelPyramid.levelShapesYXZ     = round(labelShape ./ 2 .^ ((0:2)'));
            labelPyramid.levelVoxelSizesXYZ = repmat(labelVoxelNm, 3, 3) .* 2 .^ ((0:2)');
            labelPyramid.levelWorldBoxes    = repmat(labelPyramid.levelWorldBoxes(1, :), 3, 1);
            controller.probeCache{"pyramid:" + string(labelUrl)} = labelPyramid;
        end

        function pyramidInfo = fakePyramid(~, worldBox, voxelSizeXYZ, unit)
            % FAKEPYRAMID - A minimal readGroupPyramid result for offline tests.
            %
            % Only the geometry fields the planner reads are filled; anything
            % else stays at the shape readGroupPyramid documents, so a test
            % cannot accidentally depend on a field the real reader leaves empty.
            pyramidInfo = struct('ok', true, 'multiscale', [], 'axisOrder', 'zyx', ...
                'levelNames', {{'s0'}}, 'levelShapesYXZ', [1 1 1], ...
                'levelVoxelSizesXYZ', reshape(voxelSizeXYZ, 1, 3), ...
                'levelWorldBoxes', reshape(worldBox, 1, 6), 'unit', unit, ...
                'dataType', 'uint8', 'annotation', [], 'className', '', ...
                'annotationType', '', 'encoding', []);
        end
    end

    properties (Access = private)
        SyncedBatchOpt
        % last BatchOpt seen on the SyncBatch event
        PanelUpdateCount = 0
        % DatasetsPanelUpdate notifications seen since the counter was reset
    end
end
