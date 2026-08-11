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
    end

    properties (Access = private)
        SyncedBatchOpt
        % last BatchOpt seen on the SyncBatch event
    end
end
