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
            testCase.verifyTrue(controller.imageBoxContains(enclosing, cropBoxUm));

            tooSmall = testCase.fakePyramid([0 15 0 15 0 15], [1 1 1], 'um');
            testCase.verifyFalse(controller.imageBoxContains(tooSmall, cropBoxUm));

            annotated = enclosing;
            annotated.annotation = struct('class_name', 'mito');
            testCase.verifyFalse(controller.imageBoxContains(annotated, cropBoxUm), ...
                'a group carrying a cellmap annotation is never the image');
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
        function [controller, syncedBatchOpt] = newViewLessController(testCase)
            % NEWVIEWLESSCONTROLLER - Build through the documented NaN path.
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
    end
end
