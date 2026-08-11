classdef SelectFromUrl < handle
% SELECTFROMURL - Controller for Home -> Import -> URL / Zarr.
%
% Opens a dataset from a URL. Two very different sources share the entry point:
%
%   * an **OME-Zarr container** (http/https/s3), opened as a BigData, Virtual or
%     Standard dataset through the normal loader chain;
%   * any **ordinary image URL**, which keeps the original behaviour of this
%     menu item - ``imfinfo`` + ``imread`` into a Standard dataset.
%
% Which one applies is decided by probing the URL, not by asking the user.
%
% An **N5** container URL is redirected to the OME-Zarr copy published beside it
% (:meth:`resolveN5Sibling`). OpenOrganelle dataset pages hand out the N5 form of
% every volume, from both the "Fiji" link and the "Copy data url" button, and MIB
% has no N5 reader - so without this a user following the website would paste a
% URL that could never work.
%
% On an S3-compatible host the container is browsed **one level per expand**,
% costing a single ``ListObjectsV2`` request each time. That matters because
% published containers hide large subtrees below the image group - the
% OpenOrganelle labels tree holds 42 crops of about 40 class groups each - so an
% eager recursive walk would fire hundreds of requests to build a list nobody
% wants to read. Hosts that cannot be listed degrade to typing the group path.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.SelectFromUrl');
%
% Launch in batch mode::
%
%   BatchOpt.Url = 'https://janelia-cosem-datasets.s3.amazonaws.com/jrc_mus-liver-zon-1/jrc_mus-liver-zon-1.zarr';
%   BatchOpt.GroupPath = 'recon-1/em/fibsem-uint8';
%   obj.mibController.startController('controllers.SelectFromUrl', [], BatchOpt);
%
% Trigger return of possible options::
%
%   obj.mibController.startController('controllers.SelectFromUrl', [], NaN);

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.SelectFromUrlGUI); empty in batch mode
        mibGUI
        % handle to the main MIB figure, parent for dialogs
        listener
        % cell array of listener handles
        BatchOpt
        % structure compatible with batch processing; field names match widget Tags
        rootUrl
        % [char] normalised URL of the container currently connected to
        zarrFormat
        % [char] 'zarr2', 'zarr3', or '' when the URL is not a zarr store
        isListable
        % [logical] whether the host supports directory listing
        probeCache
        % [dictionary] url -> struct describing a probed group
        connectedUrl
        % [char] URL of the last successful connect; suppresses a repeated probe
    end

    events
        CloseEvent
        % fired when the window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static listener guard; safe when the view is gone.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = SelectFromUrl(mibModel, varargin)
            % SELECTFROMURL - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = SelectFromUrl(mibModel)
            %      obj = SelectFromUrl(mibModel, [], BatchOpt)
            %      obj = SelectFromUrl(mibModel, [], NaN)

            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;
            obj.rootUrl      = '';
            obj.zarrFormat   = '';
            obj.isListable   = false;
            obj.probeCache   = configureDictionary("string", "cell");
            obj.connectedUrl = '';

            % Pre-fill from the clipboard when it looks like a link, matching
            % what this menu item has always done.
            defaultUrl = '';
            try
                clipboardText = strtrim(clipboard('paste'));
                if contains(clipboardText, {'https://', 'http://', 's3://'})
                    defaultUrl = clipboardText;
                end
            catch
                % headless or no clipboard access - leave it empty
            end

            obj.BatchOpt.Url           = defaultUrl;
            obj.BatchOpt.GroupPath     = '';
            obj.BatchOpt.LoadAs        = {'Image'};
            obj.BatchOpt.LoadAs{2}     = {'Image', 'Labels'};
            obj.BatchOpt.DatasetMode   = {'BigData'};
            obj.BatchOpt.DatasetMode{2} = {'BigData', 'Virtual', 'Standard'};
            obj.BatchOpt.showWaitbar   = true;
            obj.BatchOpt.id            = obj.mibModel.getActiveId();

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
            obj.BatchOpt.mibBatchActionName  = 'Import from URL';
            obj.BatchOpt.mibBatchTooltip.Url = sprintf(['URL of the dataset.\nOME-Zarr container: ' ...
                'https://bucket.s3.amazonaws.com/key, https://s3.<region>.amazonaws.com/bucket/key ' ...
                'or s3://bucket/key.\nAn OpenOrganelle .n5 URL is switched to the .zarr copy ' ...
                'published beside it.\nAny ordinary image URL is opened with imread as before']);
            obj.BatchOpt.mibBatchTooltip.GroupPath = sprintf(['[OME-Zarr only] group to open, relative to Url\n' ...
                'e.g. recon-1/em/fibsem-uint8; leave empty to search the container']);
            obj.BatchOpt.mibBatchTooltip.LoadAs = sprintf(['Image: open the group as the dataset\n' ...
                'Labels: load it as a model onto the dataset that is already open']);
            obj.BatchOpt.mibBatchTooltip.DatasetMode = sprintf(['BigData: browse and segment, model stored locally\n' ...
                'Virtual: browse only\nStandard: read one pyramid level fully into memory']);
            obj.BatchOpt.mibBatchTooltip.showWaitbar = sprintf('Show or not the progress bar during execution');

            %% Batch / headless mode
            if nargin == 3
                BatchOptIn = varargin{2};
                if ~isstruct(BatchOptIn)
                    if isnan(BatchOptIn)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], ...
                            'A structure as the 3rd parameter is required!', 'Error');
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                obj.rootUrl    = io.RemoteStore.normalise(obj.BatchOpt.Url);
                % Same N5 -> OME-Zarr redirect the dialog applies, so a protocol
                % recorded (or hand-written) from an OpenOrganelle page replays.
                obj.rootUrl    = obj.resolveN5Sibling(obj.rootUrl);
                obj.zarrFormat = io.ExtensionRegistryLoad.probeRemoteZarr(obj.rootUrl);
                obj.openBtn_Callback(true);
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.SelectFromUrlGUI');
            % Guarded so the dialog can also be built in a test session, where
            % there is no main MIB window to position against.
            if ~isempty(obj.mibGUI) && isvalid(obj.mibGUI)
                obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'center', 'center');
            end
            utils.fontSizeUpdate(obj.view.gui, obj.mibModel.preferences.System.Font);

            obj.updateWidgets();
            obj.resetDialog();
            obj.addCallbacks();
            obj.view.gui.Visible = 'on';

            % Put the caret in the URL field with the clipboard pre-fill selected.
            % Both likely next actions then take one step: Enter accepts what was
            % on the clipboard, typing or pasting replaces it outright.
            drawnow;
            focus(obj.view.handles.Url);

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', ...
                @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        function addCallbacks(obj)
            % ADDCALLBACKS - Wire every widget callback after the view exists.
            %
            % No per-widget existence guards: the view creates every widget in
            % its constructor, so if one is missing that is a bug in the view
            % and should fail loudly here rather than be silently skipped.
            %
            % ``showWaitbar`` has no widget deliberately - the dialog always
            % shows progress, and the BatchOpt field exists only so a batch
            % protocol can turn the bar off.
            obj.view.gui.CloseRequestFcn                    = @(~,~) obj.closeWindow();
            obj.view.gui.WindowKeyPressFcn                  = @(~,evnt) obj.keyPress_Callback(evnt);
            obj.view.handles.connectButton.ButtonPushedFcn  = @(~,~) obj.connectBtn_Callback();
            obj.view.handles.Url.ValueChangedFcn            = @(h,e) obj.urlValueChanged(e);
            obj.view.handles.GroupPath.ValueChangedFcn      = @(h,e) obj.groupPathValueChanged(e);
            obj.view.handles.LoadAs.ValueChangedFcn         = @(h,e) obj.loadAsValueChanged(e);
            obj.view.handles.DatasetMode.ValueChangedFcn    = @(h,e) obj.updateBatchOptFromGUI(e);
            obj.view.handles.groupTree.NodeExpandedFcn      = @(~,e) obj.treeNodeExpanded_Callback(e);
            obj.view.handles.groupTree.SelectionChangedFcn  = @(~,e) obj.treeSelectionChanged_Callback(e);
            obj.view.handles.openButton.ButtonPushedFcn     = @(~,~) obj.openBtn_Callback();
            obj.view.handles.helpButton.ButtonPushedFcn     = @(~,~) obj.helpButton_Callback();
            obj.view.handles.closeButton.ButtonPushedFcn    = @(~,~) obj.closeWindow();
        end

        function keyPress_Callback(obj, event)
            % KEYPRESS_CALLBACK - Enter anywhere in the dialog connects the URL.
            %
            % Enter has to be handled here rather than in the URL field's own
            % ValueChangedFcn, for two reasons that pull in the same direction:
            %
            %   * ValueChangedFcn does **not** fire when Enter is pressed on text
            %     the user never edited - which is exactly the clipboard pre-fill
            %     case, the one this shortcut exists for;
            %   * it *does* fire when the field merely loses focus, so driving the
            %     connect from there would fetch over the network every time the
            %     user clicked away, and could import a plain image on the way to
            %     pressing Close.
            %
            % The figure sees the key before the field commits, so ``drawnow``
            % flushes any pending commit first - verified ordering, not a guess.
            % Re-connecting to a URL already connected to is skipped, which is
            % what keeps Enter on a button from repeating the whole probe.
            if ~strcmp(event.Key, 'return'); return; end

            drawnow;
            if ~obj.hasView(); return; end   % a commit may have opened and closed the dialog

            urlText = strtrim(obj.view.handles.Url.Value);
            if isempty(urlText); return; end
            if io.RemoteStore.isRemote(urlText) && ...
                    strcmp(io.RemoteStore.normalise(urlText), obj.connectedUrl)
                return;
            end
            obj.BatchOpt.Url = urlText;
            obj.connectBtn_Callback(true);
        end

        function loadAsValueChanged(obj, event)
            % LOADASVALUECHANGED - Switching Image/Labels re-checks the selection.
            %
            % The Labels branch has an extra requirement the Image branch does
            % not - the label store must match the open image - so the currently
            % selected group has to be re-evaluated, otherwise Open could stay
            % enabled for a combination that is about to be rejected.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.SelectFromUrl.loadAsValueChanged: triggered\n');
            end
            obj.updateBatchOptFromGUI(event);
            if isempty(obj.rootUrl); return; end
            obj.probeGroup(io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.GroupPath));
        end

        function closeWindow(obj)
            % CLOSEWINDOW - Destroy the view and fire CloseEvent.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.SelectFromUrl.closeWindow: triggered\n');
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        function parentFigure = guiFigure(obj)
            % GUIFIGURE - Dialog parent, or [] when running without a view.
            %
            % Keeps every dialog and progress bar call in this controller safe in
            % batch mode, where there is no window to parent them to.
            parentFigure = [];
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                parentFigure = obj.view.gui;
            elseif ~isempty(obj.mibGUI) && isvalid(obj.mibGUI)
                parentFigure = obj.mibGUI;
            end
        end

        function resetDialog(obj)
            % RESETDIALOG - Clear the dialog back to its "nothing connected" state.
            %
            % App Designer stores whatever placeholder tree nodes were drawn on
            % the canvas, and they are restored every time the app is built. They
            % are useful for laying the dialog out but must never be shown to a
            % user, so the tree is emptied here rather than by hand in the
            % designer, where they would have to be deleted to see the layout.
            if ~obj.hasView(); return; end

            delete(obj.view.handles.groupTree.Children);
            obj.view.handles.infoTextArea.Value = {''};
            obj.view.handles.openButton.Enable  = 'off';
            obj.setStatus('Paste a URL and press Enter.');
        end

        function tf = hasView(obj)
            % HASVIEW - True when widgets can be written to.
            tf = ~isempty(obj.view) && isvalid(obj.view.gui);
        end

        function setStatus(obj, message)
            % SETSTATUS - Show a one-line status message, no-op without a view.
            if obj.hasView(); obj.view.handles.statusLabel.Text = message; end
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets from BatchOpt and model state.
            if ~obj.hasView(); return; end
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.SelectFromUrl.updateBatchOptFromGUI(%s): triggered\n', event.Source.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        function urlValueChanged(obj, event)
            % URLVALUECHANGED - A new URL invalidates whatever was browsed before.
            %
            % Deliberately does no network work: this fires on focus loss as well
            % as on Enter, and only Enter means "act on this". See
            % keyPress_Callback, which runs right after this one.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.SelectFromUrl.urlValueChanged: triggered\n');
            end
            obj.updateBatchOptFromGUI(event);
            obj.rootUrl      = '';
            obj.zarrFormat   = '';
            obj.connectedUrl = '';
            obj.BatchOpt.GroupPath = '';
            if obj.hasView()
                obj.view.handles.GroupPath.Value = '';
                obj.view.handles.infoTextArea.Value = {''};
                obj.view.handles.openButton.Enable = 'off';
                delete(obj.view.handles.groupTree.Children);
            end
            obj.setStatus('Press Enter or Connect to inspect this URL.');
        end

        function groupPathValueChanged(obj, event)
            % GROUPPATHVALUECHANGED - Typed group path, the fallback for hosts
            % that cannot be listed; probe it so Open can be enabled.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.SelectFromUrl.groupPathValueChanged: triggered\n');
            end
            obj.updateBatchOptFromGUI(event);
            if isempty(obj.rootUrl); obj.connectBtn_Callback(); return; end
            obj.probeGroup(io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.GroupPath));
        end

        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open the documentation page.
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.SelectFromUrl.helpButton_Callback: triggered\n');
            end
            helpFilePath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'home', 'home-importfromurl.html');
            
            utils.openHelpPage(helpFilePath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-importfromurl.html');
        end

        function label = nodeLabel(~, ~, displayName)
            % NODELABEL - Text for a tree node.
            %
            % Deliberately just the name: deciding whether a node holds a pyramid
            % would need a metadata fetch per sibling, turning one request per
            % expand into one per child. The info panel answers that question for
            % the selected node instead.
            label = char(displayName);
        end

        function note = pythonNote(obj)
            % PYTHONNOTE - Suffix warning that the selected backend needs Python packages.
            %
            % Both zarr v2 and v3 are read natively over HTTP range requests, so
            % there is normally nothing to say. The note only appears when the
            % user has selected the python backend in Preferences and that
            % interpreter cannot reach the network, which is the one combination
            % that fails after Open is pressed.
            note = '';
            if ~io.zarr.Config.isPython(); return; end
            if ~io.zarr.PyBackend.hasRemoteSupport()
                note = '  (NEEDS Python packages: aiohttp, requests)';
            end
        end

        function applySummary(obj, groupUrl, groupSummary)
            % APPLYSUMMARY - Push a probe result into the widgets.
            %
            % Also decides whether Open may be pressed. For LoadAs = Labels that
            % includes the dimension check, so a store that cannot line up with
            % the open image is refused here with an explanation rather than
            % silently misplacing the labels later.

            obj.BatchOpt.GroupPath = io.RemoteStore.relativePath(obj.rootUrl, groupUrl);

            infoLines = groupSummary.lines;
            canOpen   = groupSummary.hasMultiscales;

            if canOpen && strcmp(obj.BatchOpt.LoadAs{1}, 'Labels')
                [labelsFit, reason] = obj.labelsMatchOpenImage(groupSummary);
                if ~labelsFit
                    canOpen = false;
                    infoLines = [infoLines, {'', reason}];
                end
            end

            if ~obj.hasView(); return; end
            obj.view.handles.GroupPath.Value    = obj.BatchOpt.GroupPath;
            obj.view.handles.infoTextArea.Value = infoLines;
            if canOpen
                obj.view.handles.openButton.Enable = 'on';
            else
                obj.view.handles.openButton.Enable = 'off';
            end
        end

        function [labelsFit, reason] = labelsMatchOpenImage(obj, groupSummary)
            % LABELSMATCHOPENIMAGE - Can this group be loaded as a model?
            %
            % MibModel.loadModel requires the model's finest level to match the
            % image exactly. core.MibBigDataLabelsZarr2 has no origin or
            % translation, so a sub-volume annotation (an OpenOrganelle
            % ground-truth crop, say) cannot be placed correctly on the parent
            % volume - it would land at the origin at the wrong scale.

            labelsFit = true;
            reason    = '';
            openImage = obj.mibModel.I{obj.mibModel.getActiveId()}.image;
            imageSize = [openImage.height, openImage.width, openImage.depth];

            if isequal(imageSize, groupSummary.sizeYXZ); return; end

            labelsFit = false;
            reason = sprintf(['Cannot load as Labels: this group is %d x %d x %d but the open ' ...
                'image is %d x %d x %d. A sub-volume annotation cannot be placed on its parent ' ...
                'volume yet - open it as an Image instead.'], ...
                groupSummary.sizeYXZ(1), groupSummary.sizeYXZ(2), groupSummary.sizeYXZ(3), ...
                imageSize(1), imageSize(2), imageSize(3));
        end

        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt to the batch controller.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
        end
    end
end
