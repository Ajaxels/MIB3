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
        labelLoadRoute
        % [char] how LoadAs = Labels will be honoured for the current selection:
        % 'model' - the group matches the open image, load it straight onto it;
        % 'crop'  - it is a sub-volume, so its image region is opened too;
        % ''      - it cannot be loaded as labels at all
        cropPlan
        % [struct] last result of planLabelCrop, valid while labelLoadRoute is 'crop'
        progressDialog
        % [handle] the import's progress bar, or empty. Held on the controller
        % rather than passed around because every error path has to close it
        % before showing its own dialog - a modal progress bar left up would sit
        % in front of the message explaining why the import stopped.
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
            obj.labelLoadRoute = '';
            obj.cropPlan       = [];
            obj.progressDialog = [];

            % Url and GroupPath start empty and are pre-filled further down, in
            % the GUI branch only. A convenience default drawn from the session
            % (the clipboard, or the dataset in the active buffer) has no place
            % in a batch run: a protocol that names a Url but no GroupPath would
            % otherwise inherit the group of whatever happened to be open, and
            % replay something it never asked for.
            obj.BatchOpt.Url           = '';
            obj.BatchOpt.GroupPath     = '';
            obj.BatchOpt.LabelGroups   = '';
            obj.BatchOpt.ImageGroupPath = '';
            obj.BatchOpt.LoadAs        = {'Image'};
            obj.BatchOpt.LoadAs{2}     = {'Image', 'Labels'};
            obj.BatchOpt.DatasetMode   = {'BigData'};
            obj.BatchOpt.DatasetMode{2} = {'BigData', 'Virtual', 'Standard'};
            % Default false so a protocol written before this existed keeps
            % refusing an instance group rather than quietly merging it. The GUI
            % sets it from the question openLabelCrop asks.
            obj.BatchOpt.MergeInstanceObjects = false;
            % Empty means "ask"; a protocol names the image pyramid level it
            % wants so it never stops for the level dialog.
            obj.BatchOpt.ZarrLevel     = [];
            obj.BatchOpt.showWaitbar   = true;
            obj.BatchOpt.id            = obj.mibModel.getActiveId();

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Home';
            obj.BatchOpt.mibBatchActionName  = 'Import from URL / Zarr';
            obj.BatchOpt.mibBatchTooltip.Url = sprintf(['URL of the dataset.\nOME-Zarr container: ' ...
                'https://bucket.s3.amazonaws.com/key, https://s3.<region>.amazonaws.com/bucket/key ' ...
                'or s3://bucket/key.\nAn OpenOrganelle .n5 URL is switched to the .zarr copy ' ...
                'published beside it.\nAny ordinary image URL is opened with imread as before']);
            obj.BatchOpt.mibBatchTooltip.GroupPath = sprintf(['[OME-Zarr only] group to open, relative to Url\n' ...
                'e.g. recon-1/em/fibsem-uint8; leave empty to search the container']);
            obj.BatchOpt.mibBatchTooltip.LabelGroups = sprintf(['[Load as = Labels] semicolon-separated ' ...
                'label groups to blend into one model, relative to Url\n' ...
                'e.g. recon-1/labels/groundtruth/crop1/mito_mem;.../mito_lum\n' ...
                'pick order matters: where two classes overlap the later one wins\n' ...
                'leave empty to use the single group in Group path']);
            obj.BatchOpt.mibBatchTooltip.ImageGroupPath = sprintf(['[Load as = Labels] image group to open ' ...
                'the labels onto, relative to Url\nleave empty to find the volume the crop was cut from ' ...
                'by its coordinates']);
            obj.BatchOpt.mibBatchTooltip.LoadAs = sprintf(['Image: open the group as the dataset\n' ...
                'Labels: load it as a model onto the dataset that is already open,\n' ...
                'or, for a ground-truth crop, open its image region and put the labels on that']);
            obj.BatchOpt.mibBatchTooltip.DatasetMode = sprintf(['BigData: browse and segment, model stored locally\n' ...
                'Virtual: browse only\nStandard: read one pyramid level fully into memory']);
            obj.BatchOpt.mibBatchTooltip.MergeInstanceObjects = sprintf([ ...
                '[Load as = Labels] merge an instance segmentation into one material per group\n' ...
                'its values are object ids, so every object becomes the same material\n' ...
                'leave off to refuse such a group instead']);
            obj.BatchOpt.mibBatchTooltip.ZarrLevel = sprintf([ ...
                '[Load as = Labels] 1-based image pyramid level to read the region at\n' ...
                'must be a level that has a matching label level; leave empty to be asked']);
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
            % Pre-fill the URL. A remote dataset that is already open wins over
            % the clipboard: the next thing anyone does after opening a remote
            % volume is go back to the same container for its labels, and by
            % then the clipboard usually still holds whatever was copied before.
            [obj.BatchOpt.Url, obj.BatchOpt.GroupPath] = obj.openRemoteContainer();
            connectOnOpen = ~isempty(obj.BatchOpt.Url);
            if ~connectOnOpen
                try
                    clipboardText = strtrim(clipboard('paste'));
                    if contains(clipboardText, {'https://', 'http://', 's3://'})
                        obj.BatchOpt.Url = clipboardText;
                    end
                catch
                    % headless or no clipboard access - leave it empty
                end
            end

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

            % Put the caret in the URL field with the pre-fill selected. Both
            % likely next actions then take one step: Enter accepts the URL that
            % is there, typing or pasting replaces it outright.
            drawnow;
            focus(obj.view.handles.Url);

            % Connect straight away when the URL came from the dataset already
            % open. That container is known to be reachable and known to be a
            % zarr store - MIB is reading from it right now - so the Connect
            % press asks a question already answered, and the tree is what the
            % user came for. Deliberately NOT done for a clipboard URL, which
            % may be anything at all and would be an unasked-for network call.
            if connectOnOpen
                obj.connectBtn_Callback();
            end

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
            % Several groups at once, because a ground-truth crop keeps every
            % class in its own group and a useful model blends them. Set here
            % rather than on the canvas so the behaviour lives beside the
            % callback that depends on it.
            obj.view.handles.groupTree.Multiselect           = 'on';

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
            % The bar is parented to this window; closing the window out from
            % under it would leave an orphan.
            obj.stopProgress();
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

        function [containerUrl, groupPath] = openRemoteContainer(obj)
            % OPENREMOTECONTAINER - Where the active dataset came from, split in two.
            %
            % Returns empty strings unless the dataset in the active buffer was
            % itself opened from a URL. A local dataset, an empty buffer
            % (``none.tif``) and a plain image URL all give ``''``.
            %
            % Split into container plus group rather than handed back whole,
            % because the stored filename is the **group** URL - something like
            % ``.../jrc_hela-2.zarr/recon-1/em/fibsem-uint8``. Connecting to that
            % roots the tree at the image group, which holds nothing but its own
            % pyramid levels, so the labels next door would be unreachable
            % without editing the URL by hand. Rooting at the container instead
            % keeps the whole dataset browsable while ``GroupPath`` still names
            % exactly what is open.
            containerUrl = '';
            groupPath    = '';

            datasetId = obj.mibModel.getActiveId();
            filename  = obj.mibModel.I{datasetId}.image.filename;
            if isempty(filename) || ~(ischar(filename) || isstring(filename)); return; end
            filename = char(filename);
            if ~io.RemoteStore.isRemote(filename); return; end

            % The container is the last path component naming a store. Matched
            % by suffix rather than by asking the server, since this runs while
            % the dialog is being built and must not reach the network.
            % CollapseDelimiters off, or the empty segment between the scheme's
            % two slashes is dropped and rejoining gives https:/host
            segments     = strsplit(regexprep(filename, '/+$', ''), '/', ...
                'CollapseDelimiters', false);
            containerIdx = find(endsWith(segments, ...
                {'.zarr', '.zarr2', '.zarr3', '.n5'}, 'IgnoreCase', true), 1, 'last');
            if isempty(containerIdx)
                containerUrl = filename;   % not a recognisable store layout
                return;
            end
            containerUrl = strjoin(segments(1:containerIdx), '/');
            groupPath    = strjoin(segments(containerIdx + 1:end), '/');
        end

        function proceed = confirmLoadAs(obj, targetUrl)
            % CONFIRMLOADAS - Ask what a second remote dataset should be opened as.
            %
            % Opening a **different** group while a remote dataset is already up
            % is the one case where ``Load as`` is genuinely ambiguous, and the
            % two outcomes are far apart: Image replaces the buffer, Labels puts
            % the group on top of what is already there. The browse that leads
            % here - open the EM volume, then go back for its annotations - ends
            % on the wrong setting more often than not, because Image is the
            % default and nothing about picking a label group changes it.
            %
            % Only asked in the GUI: a batch protocol states what it wants and
            % must never stop for a question. Re-opening the same group is not
            % ambiguous either, so that goes through untouched.
            %
            % Cancel returns to the dialog with the selection intact, which is
            % why this reports back rather than deciding on its own - and why
            % there is nothing to ask without a window to return to.
            proceed = true;
            if ~obj.hasView(); return; end

            [openContainer, openGroup] = obj.openRemoteContainer();
            if isempty(openContainer); return; end
            openUrl = io.RemoteStore.join(openContainer, openGroup);
            if strcmp(regexprep(openUrl, '/+$', ''), regexprep(targetUrl, '/+$', '')); return; end

            % The bar is modal and would sit in front of the question.
            obj.stopProgress();

            questionOptions.WindowWidth  = 620;
            questionOptions.WindowHeight = 300;
            questionOptions.Icon         = 'puffin_question';
            choice = utils.dlgs.inputQuestDlg(obj.guiFigure(), ...
                sprintf(['This dataset is already open:\n  %s\n\n' ...
                         'and you are opening a different one:\n  %s\n\n' ...
                         'Open it as a new Image, or load it as Labels onto the dataset ' ...
                         'that is already open?'], openUrl, targetUrl), ...
                'Load as', 'Image', 'Labels', 'Cancel', 'Image', questionOptions);

            switch choice
                case 'Image'
                    obj.startProgress('Opening the dataset...');
                case 'Labels'
                    obj.BatchOpt.LoadAs{1} = 'Labels';
                    % The route was resolved for LoadAs = Image (or not at all),
                    % so let the Labels branch work it out for this group.
                    obj.labelLoadRoute = '';
                    if obj.hasView(); obj.view.handles.LoadAs.Value = 'Labels'; end
                    obj.startProgress('Opening the dataset...');
                otherwise   % Cancel, or the dialog was closed
                    proceed = false;
            end
        end

        function [cropPlan, proceed] = chooseCropLevel(obj, cropPlan)
            % CHOOSECROPLEVEL - Ask which pyramid level pair to read.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      [cropPlan, proceed] = obj.chooseCropLevel(cropPlan)
            %
            % The pairing settles which label level goes with which image level,
            % but not **which pair** - and the difference is the resolution of
            % the dataset the user ends up with, plus how much memory it costs.
            % For jrc_mus-kidney the choice runs from 128 nm / 1010 MB to
            % 2048 nm / a few MB, and nothing on screen would otherwise say so.
            %
            % **Only pairs that line up are offered.** Image levels with no
            % matching label level are not choices at all - offering them would
            % mean resampling one pyramid to fit the other, which
            % :meth:`planLabelCrop` refuses to do. For jrc_mus-kidney that is EM
            % ``s4..s8``; ``s0..s3`` have no counterpart.
            %
            % A single candidate is not a question, and is taken silently.
            % ``BatchOpt.ZarrLevel`` answers it for a protocol, which must never
            % stop for a dialog; an unusable value there is reported rather than
            % quietly replaced, so a stale protocol does not open a different
            % resolution than it names.
            %
            % Input Arguments:
            %   - **cropPlan** - [struct] from :meth:`planLabelCrop`
            %
            % Output Arguments:
            %   - **cropPlan** - [struct] with the chosen pair promoted
            %   - **proceed** - [logical] false when the user cancelled

            proceed    = true;
            candidates = cropPlan.candidatePairs;
            if isempty(candidates); return; end

            % ---- a protocol states it outright ----------------------------
            if ~isempty(obj.BatchOpt.ZarrLevel)
                wanted = find([candidates.imageLevel] == obj.BatchOpt.ZarrLevel, 1);
                if isempty(wanted)
                    proceed = false;
                    obj.stopProgress();
                    utils.dlgs.showErrorDialog(obj.guiFigure(), sprintf( ...
                        ['ZarrLevel %d has no matching label level, so it cannot be read with ' ...
                         'these labels. Levels that do line up: %s.'], ...
                        obj.BatchOpt.ZarrLevel, strjoin(arrayfun(@(c) num2str(c.imageLevel), ...
                        candidates, 'UniformOutput', false), ', ')), 'Import label crop');
                    return;
                end
                cropPlan = applyChosenPair(cropPlan, candidates(wanted));
                return;
            end

            if isscalar(candidates) || ~obj.hasView(); return; end

            obj.stopProgress();   % the bar is modal and would sit in front of the question

            rowLabels = cell(1, numel(candidates));
            for candidateIndex = 1:numel(candidates)
                candidate = candidates(candidateIndex);
                note = '';
                if ~candidate.fits; note = '  [too large for this machine]'; end
                rowLabels{candidateIndex} = sprintf('%s: %d x %d x %d px at %g nm - %s%s', ...
                    candidate.imageLevelName, ...
                    candidate.shapeYXZ(2), candidate.shapeYXZ(1), candidate.shapeYXZ(3), ...
                    candidate.voxelSizeUm(1) * 1000, ...
                    formatMegabytes(candidate.requiredBytes), note);
            end
            defaultIndex = find([candidates.imageLevel] == cropPlan.imageLevel, 1);

            dialogOptions = struct('WindowWidth', 560, 'WindowHeight', 200, ...
                'LabelPosition', 'top');
            [answer, selectedIndices] = utils.dlgs.inputUniversalDlg(obj.guiFigure(), '', ...
                {sprintf(['The labels and the image share these resolutions.\n' ...
                          'Both are read into memory, so the level decides the detail and ' ...
                          'the cost:'])}, ...
                {rowLabels, {defaultIndex}}, 'Select the level to read', dialogOptions);
            if isempty(answer); proceed = false; return; end

            chosen = candidates(selectedIndices(1));
            if ~chosen.fits
                proceed = false;
                utils.dlgs.showErrorDialog(obj.guiFigure(), sprintf( ...
                    ['Level %s needs about %s, which does not fit in memory here. Pick a ' ...
                     'coarser level.'], chosen.imageLevelName, ...
                    formatMegabytes(chosen.requiredBytes)), 'Import label crop');
                return;
            end
            cropPlan = applyChosenPair(cropPlan, chosen);
            obj.startProgress('Reading crop metadata...');
        end

        function proceed = chooseInstanceHandling(obj, instanceNames)
            % CHOOSEINSTANCEHANDLING - Keep an instance segmentation's objects, or merge them.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      proceed = obj.chooseInstanceHandling(instanceNames)
            %
            % This route builds an **ordinary in-memory model**, which holds up
            % to 65535 materials, so an instance segmentation's objects can
            % simply be kept - one material each - and that is the default.
            % Merging them all into a single material is a view, not a necessity:
            % useful when the question is "where are the nuclei" and the 864
            % separate entries would only be in the way.
            %
            % **Keeping is lossless, so it needs no consent** - headless and
            % batch take it silently. Only the merge is asked about, and only
            % where there is a window; a protocol states it outright with
            % ``BatchOpt.MergeInstanceObjects``.
            %
            % Input Arguments:
            %   - **instanceNames** - {1xN cell} the selected groups that are
            %     instance segmentations
            %
            % Output Arguments:
            %   - **proceed** - [logical] false only when the user cancelled;
            %     :attr:`BatchOpt`.``MergeInstanceObjects`` carries the choice

            proceed = true;
            if ~obj.hasView(); return; end   % keep the objects, nothing to ask

            nameList = strjoin(instanceNames, ', ');
            obj.stopProgress();   % the bar is modal and would sit in front of the question

            questionOptions.WindowWidth  = 640;
            questionOptions.WindowHeight = 320;
            questionOptions.Icon         = 'puffin_question';
            choice = utils.dlgs.inputQuestDlg(obj.guiFigure(), ...
                sprintf(['"%s" is an instance segmentation: every voxel carries the id of the ' ...
                         'object it belongs to.\n\nKeep objects: one material per object, so ' ...
                         'they stay separable and the instance tools apply.\n\nMerge: a single ' ...
                         'material covering all of them - a mask of where they are, which is ' ...
                         'easier to look at when there are hundreds. Which voxel belonged to ' ...
                         'which object is then lost.'], nameList), ...
                'Instance segmentation', 'Keep objects', 'Merge into one material', 'Cancel', ...
                'Keep objects', questionOptions);

            switch choice
                case 'Keep objects'
                    obj.BatchOpt.MergeInstanceObjects = false;
                case 'Merge into one material'
                    obj.BatchOpt.MergeInstanceObjects = true;
                otherwise   % Cancel, or the dialog was closed
                    proceed = false;
                    return;
            end
            obj.startProgress('Reading crop metadata...');
        end

        function setStatus(obj, message)
            % SETSTATUS - Show a one-line status message, no-op without a view.
            if obj.hasView(); obj.view.handles.statusLabel.Text = message; end
        end

        function startProgress(obj, message)
            % STARTPROGRESS - Raise the import's progress bar in Indeterminate mode.
            %
            % **Indeterminate because nothing here can report a percentage.**
            % Opening a remote dataset probes the store format, lists a
            % container, resolves a group and reads level metadata, all before a
            % single pixel is fetched - a sequence of round trips whose count is
            % not known in advance and whose duration depends on the host. A bar
            % that sat at 0% through all of it would say less than a moving one.
            %
            % :meth:`openLabelCrop` takes this same bar over and switches it to a
            % real percentage once it knows how many label groups it will read.
            %
            % A no-op in batch mode (no figure to parent to) and when the caller
            % asked for no waitbar.
            obj.stopProgress();
            parentFigure = obj.guiFigure();
            if ~obj.BatchOpt.showWaitbar || isempty(parentFigure); return; end

            % uiprogressdlg refuses a figure whose Visible is 'off', and there is
            % no reading of that failure under which the import should stop. A
            % progress bar reports work; it is never the work itself.
            try
                obj.progressDialog = uiprogressdlg(parentFigure, ...
                    'Indeterminate', 'on', 'Message', message, 'Title', 'Import from URL');
                drawnow limitrate;
            catch
                obj.progressDialog = [];
            end
        end

        function stopProgress(obj)
            % STOPPROGRESS - Close the progress bar if one is up.
            %
            % Must be called before every error dialog, not only on success: a
            % modal progress bar left on screen sits in front of the message
            % explaining why the import stopped.
            %
            % The isvalid(obj) guard is for the onCleanup handlers in
            % openBtn_Callback and openLabelCrop: a successful import ends with
            % closeWindow, whose CloseEvent makes MibController delete this
            % controller, and the onCleanup then fires on a deleted handle.
            % Touching any property there raises "Invalid or deleted object"
            % from inside a destructor, where it can only be warned about.
            if ~isvalid(obj); return; end
            if ~isempty(obj.progressDialog) && isvalid(obj.progressDialog)
                delete(obj.progressDialog);
            end
            obj.progressDialog = [];
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

            % Load as and Dataset mode both change the VERDICT on the selected
            % group - whether it can be loaded at all, and what it would produce.
            % Without this the panel keeps the answer for the old setting and
            % Open stays disabled (or enabled) against the wrong question. The
            % probe is cached per URL for the session, so this is free.
            if ismember(event.Source.Tag, {'LoadAs', 'DatasetMode'}) && ...
                    ~isempty(obj.rootUrl) && ~isempty(obj.BatchOpt.GroupPath)
                obj.probeGroup(io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.GroupPath));
            end
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
            obj.labelLoadRoute = '';
            obj.cropPlan       = [];
            obj.BatchOpt.GroupPath      = '';
            obj.BatchOpt.LabelGroups    = '';
            obj.BatchOpt.ImageGroupPath = '';
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
            %
            % Not covered here: an array whose codec configuration the native
            % engine refuses falls back to python on its first read even under
            % the native setting (see io.zarr.Array.fallbackToPython). Nothing
            % known before Open distinguishes such a store, so it reports itself
            % when the fallback happens rather than being predicted here.
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

            % ---- how it compares with the dataset already open -------------
            % Whether the sizes agree is what decides how (and whether)
            % LoadAs = Labels can work, so it is answered while the user is
            % choosing rather than in a refusal after Open. Said in words AND
            % shown on the node below, because a colour alone states that
            % something is special without saying what.
            %
            % Computed here rather than taken from probeGroup: that result is
            % cached per URL for the session, and the active buffer can change
            % underneath it.
            matchesOpenDataset = false;
            if groupSummary.hasMultiscales
                openImage = obj.mibModel.I{obj.mibModel.getActiveId()}.image;
                if ~isempty(openImage.filename) && ~strcmp(openImage.filename, 'none.tif')
                    openSizeYXZ = [openImage.height, openImage.width, openImage.depth];
                    matchesOpenDataset = isequal(groupSummary.sizeYXZ, openSizeYXZ);
                    if matchesOpenDataset
                        infoLines{end+1} = 'Match  : same size as the open dataset';
                    else
                        infoLines{end+1} = sprintf( ...
                            'Match  : differs, the open dataset is %d x %d x %d  (X x Y x Z)', ...
                            openSizeYXZ(2), openSizeYXZ(1), openSizeYXZ(3));
                    end
                end
            end

            if canOpen && strcmp(obj.BatchOpt.LoadAs{1}, 'Labels')
                [labelsFit, reason] = obj.resolveLabelRoute(groupUrl, groupSummary);
                % Split on newline: a reason may be several sentences (the mode
                % refusal is a paragraph plus numbered steps), and a text area
                % shows one cell per row.
                %
                % CollapseDelimiters off, or a blank line between paragraphs is
                % swallowed and the whole message arrives as one dense block -
                % which is what made the first mode refusal hard to read.
                if ~isempty(reason)
                    infoLines = [infoLines, {''}, ...
                        strsplit(reason, newline, 'CollapseDelimiters', false)];
                end
                canOpen = labelsFit;
            else
                obj.labelLoadRoute = '';
            end

            if ~obj.hasView(); return; end
            obj.view.handles.GroupPath.Value    = obj.BatchOpt.GroupPath;
            obj.view.handles.infoTextArea.Value = infoLines;
            if canOpen
                obj.view.handles.openButton.Enable = 'on';
            else
                obj.view.handles.openButton.Enable = 'off';
            end

            % Mark the matching group green in the tree. Only the selection can
            % carry a verdict - it is the one node whose metadata was fetched -
            % so the previous one's style is cleared first; deciding this for
            % every sibling would cost a metadata request each (see nodeLabel).
            groupTree = obj.view.handles.groupTree;
            removeStyle(groupTree);
            if matchesOpenDataset && ~isempty(groupTree.SelectedNodes)
                addStyle(groupTree, ...
                    uistyle('FontColor', [0.05 0.45 0.05], 'FontWeight', 'bold'), ...
                    'node', groupTree.SelectedNodes);
            end
        end

        function [labelsFit, reason] = resolveLabelRoute(obj, groupUrl, groupSummary)
            % RESOLVELABELROUTE - Decide how this group can be loaded as a model.
            %
            % Three routes exist and they are not interchangeable:
            %
            %   * **model** - the group's finest level already matches the open
            %     image, so ``MibModel.loadModel`` puts it straight on top. This
            %     is what a label store published beside its own volume looks like.
            %   * **overlay** - the group covers the same volume as the open image
            %     but at a coarser resolution, which a whole-volume inference
            %     segmentation published from a coarse level down looks like. With
            %     ``Dataset mode = BigData`` it is served over the open dataset
            %     slice by slice, read-only, nothing downloaded in bulk. See
            %     :meth:`resolveOverlayRoute`.
            %   * **crop** - the group is a sub-volume of a larger image, an
            %     OpenOrganelle ground-truth crop being the case this was built
            %     for. Placing it on the open parent volume is impossible -
            %     ``loadModel`` requires matching dimensions and
            %     ``core.MibBigDataLabelsZarr2`` has no origin concept - so
            %     instead the crop's own image *region* is opened and the labels
            %     go onto that. See :meth:`openLabelCrop`.
            %
            % Deciding here rather than at Open matters: both failure modes are
            % silent otherwise, and the answer is what the info panel should be
            % showing while the user is still choosing.
            %
            % Input Arguments:
            %   - **groupUrl** - [char] URL of the selected group
            %   - **groupSummary** - [struct] from :meth:`probeGroup`
            %
            % Output Arguments:
            %   - **labelsFit** - [logical] whether Open may be pressed
            %   - **reason** - [char] the explanation to show, either why it
            %     cannot be loaded or what loading it will do

            obj.labelLoadRoute = '';
            obj.cropPlan       = [];
            reason             = '';

            openImage = obj.mibModel.I{obj.mibModel.getActiveId()}.image;
            imageSize = [openImage.height, openImage.width, openImage.depth];

            if isequal(imageSize, groupSummary.sizeYXZ)
                obj.labelLoadRoute = 'model';
                labelsFit = true;
                % The model route goes through core.MibBigDataLabelsZarr2, which
                % decides from the pixels whether the values are an index map or
                % a mask - so an instance group comes out as one material per
                % object where the ids fit MIB's 63, and as a single merged mask
                % where they do not. Both are defensible; neither is obvious from
                % the result, so the kind of store is named here. Unlike the crop
                % route there is nothing to confirm: no information is discarded
                % that reloading would not recover.
                if isfield(groupSummary, 'annotationType') && ...
                        strcmp(groupSummary.annotationType, 'instance_segmentation')
                    reason = ['Note: this is an instance segmentation - its values are object ' ...
                        'ids. Objects numbered within MIB''s 63 materials become one material ' ...
                        'each; beyond that they all merge into a single material.'];
                end
                return;
            end

            % Dimensions differ - the overlay route if the pyramid registers
            % against the open image, otherwise the crop route if the store's
            % coordinates support it.
            labelPyramid = obj.readGroupPyramid(groupUrl);

            % ---- BigData: serve the labels over the open image -------------
            % Tried before the crop route because it needs nothing further from
            % the network - the label pyramid is already in hand - while the crop
            % route has to go and find a sibling image group first.
            overlayReason = '';
            if strcmp(obj.BatchOpt.DatasetMode{1}, 'BigData')
                [overlayFits, overlayReason] = obj.resolveOverlayRoute(labelPyramid, openImage);
                if overlayFits
                    obj.labelLoadRoute = 'overlay';
                    labelsFit          = true;
                    reason             = overlayReason;
                    return;
                end
            end

            if ~isempty(obj.BatchOpt.ImageGroupPath)
                imagePyramid = obj.readGroupPyramid( ...
                    io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.ImageGroupPath));
                imageGroupUrl = io.RemoteStore.join(obj.rootUrl, obj.BatchOpt.ImageGroupPath);
            else
                [imageGroupUrl, imagePyramid] = obj.resolveSiblingImageGroup(groupUrl, labelPyramid);
            end

            plan = obj.planLabelCrop(labelPyramid, imagePyramid);
            if ~plan.ok
                labelsFit = false;
                reason = sprintf(['Cannot load as Labels: this group is %d x %d x %d but the open ' ...
                    'image is %d x %d x %d. %s'], ...
                    groupSummary.sizeYXZ(1), groupSummary.sizeYXZ(2), groupSummary.sizeYXZ(3), ...
                    imageSize(1), imageSize(2), imageSize(3), plan.reason);
                return;
            end

            obj.cropPlan = plan;

            % ---- the crop route is Standard-mode, and says so --------------
            % It reads the image region and the model into memory, so it cannot
            % honour BigData or Virtual. Overriding the choice silently is what
            % this used to do, and it left the user with a buffer they had not
            % asked for - reported against jrc_mus-kidney, where "a crop" was in
            % fact the whole volume at 128 nm and 505 MB. Refusing here instead
            % keeps Dataset mode meaning exactly what it says, and the message
            % names the mode to pick rather than just the problem.
            if ~strcmp(obj.BatchOpt.DatasetMode{1}, 'Standard')
                labelsFit = false;
                obj.labelLoadRoute = '';
                % Three separate things, each on its own line, because running
                % them together is what made the first version unreadable: what
                % is wrong, what you would get, and what to do about it. The
                % steps are numbered so there is nothing to work out.
                %
                % It states the OUTCOME rather than the cause: naming a
                % resolution gap reads as nonsense whenever the two agree, which
                % a sub-volume crop at full resolution does.
                %
                % The first block is conditional because BigData became a real
                % answer for a label pyramid that registers against the open
                % image: this one did not, so the refusal has to say why THIS
                % store cannot be shown rather than implying none can.
                if isempty(overlayReason)
                    firstBlock = sprintf(['The labels do not completely match the %s dataset ' ...
                        'dimensions and can not be opened!'], obj.BatchOpt.DatasetMode{1});
                else
                    firstBlock = sprintf(['These labels cannot be shown over the open dataset:\n' ...
                        '    %s'], overlayReason);
                end
                reason = sprintf([ ...
                    '%s\n ' ...
                    '\n' ...
                    'It is possible to load labels using the standard dataset type resulting in\n' ...
                    '    %d x %d x %d px at %g nm\n' ...
                    '   (image level %s), about %.0f MB\n' ...
                    '\n' ...
                    'To continue:\n' ...
                    '    1. set "Dataset mode" to Standard\n' ...
                    '    2. press Open\n' ...
                    '    3. pick the pyramid level when asked'], ...
                    firstBlock, ...
                    plan.shapeYXZ(2), plan.shapeYXZ(1), plan.shapeYXZ(3), ...
                    plan.voxelSizeUm(1) * 1000, plan.imageLevelName, ...
                    plan.requiredBytes / 1024^2);
                return;
            end

            obj.labelLoadRoute = 'crop';
            labelsFit          = true;

            % ImageGroupPath has no widget on the canvas, so the resolved group
            % is reported in the info panel below rather than shown in a field.
            % Overriding it is a batch/protocol parameter until one is drawn.
            if isempty(obj.BatchOpt.ImageGroupPath)
                obj.BatchOpt.ImageGroupPath = io.RemoteStore.relativePath(obj.rootUrl, imageGroupUrl);
            end

            if plan.imageLevel > 1
                % The labels are published only from a coarse level down, so the
                % image gives up its finer ones. Saying so before Open matters:
                % the buffer that comes back cannot be zoomed to the resolution
                % the currently open dataset is showing, and nothing on screen
                % afterwards reveals that the finer levels were dropped.
                reason = sprintf(['Coarse label pyramid: these labels start at %g nm, so the ' ...
                    'image is read at %s level %s (%d x %d x %d) - its finer levels are not ' ...
                    'available in that buffer.'], ...
                    plan.voxelSizeUm(1) * 1000, obj.BatchOpt.ImageGroupPath, plan.imageLevelName, ...
                    plan.shapeYXZ(1), plan.shapeYXZ(2), plan.shapeYXZ(3));
            else
                reason = sprintf(['Sub-volume crop: Open will load the matching image region ' ...
                    '(%d x %d x %d at %g nm) from %s and put these labels on it.'], ...
                    plan.shapeYXZ(1), plan.shapeYXZ(2), plan.shapeYXZ(3), ...
                    plan.voxelSizeUm(1) * 1000, obj.BatchOpt.ImageGroupPath);
            end

            % The level above is only the default once there is more than one
            % pair to choose from, so do not let the panel promise it.
            if numel(plan.candidatePairs) > 1
                reason = sprintf('%s\nOpen will ask which of the %d matching levels to read.', ...
                    reason, numel(plan.candidatePairs));
            end

            % Which of the two outcomes you get is a question Open asks, so name
            % it here - the info panel is where the user decides whether to press
            % Open at all.
            if strcmp(labelPyramid.annotationType, 'instance_segmentation')
                reason = sprintf(['Note: "%s" is an instance segmentation - its values are ' ...
                    'object ids, not a class. Open will ask whether to keep one material per ' ...
                    'object or merge them all into a single mask.\n%s'], ...
                    obj.labelGroupName(groupUrl, labelPyramid), reason);
            end
        end

        function [overlayFits, reason] = resolveOverlayRoute(~, labelPyramid, openImage)
            % RESOLVEOVERLAYROUTE - Can these labels be shown over the open BigData image?
            %
            % The third route out of :meth:`resolveLabelRoute`, and the only one
            % that leaves the open dataset alone: the labels are served slice by
            % slice from their own store as the view is read, upsampled where the
            % image is finer, with nothing downloaded in bulk. It applies when the
            % label pyramid registers against the open image's scale space - see
            % ``io.loaders.OmeZarrMetadataUtils.registerLevelScales``, which is
            % what refuses a pyramid describing a different volume.
            %
            % A **fractional** scale is refused even though it registers. Nothing
            % in the read path breaks on it; a label would simply be split across
            % an image voxel with no way to say which side it belongs to, and
            % refusing is honest where the crop route would give an exact answer.
            %
            % Deciding here rather than at Open is what lets the info panel say
            % which of the three things Open will do. It costs no further network
            % traffic: the label pyramid is already in hand and the image is open.
            %
            % Input Arguments:
            %   - **labelPyramid** - [struct] from :meth:`readGroupPyramid`
            %   - **openImage** - [core.MibImage] the open dataset's image layer
            %
            % Output Arguments:
            %   - **overlayFits** - [logical] whether the overlay route applies
            %   - **reason** - [char] what Open will do when it fits, or why it
            %     does not

            overlayFits = false;

            if isempty(labelPyramid) || ~labelPyramid.ok
                reason = 'This group has no usable image pyramid.';
                return;
            end

            reference = core.MibBigDataLabelsIndex.imageReference(openImage);
            if ~reference.ok; reason = reference.reason; return; end

            labelToUm = io.loaders.OmeZarrMetadataUtils.unitToMicrometreFactor(labelPyramid.unit);
            labelOuterBoxUm = io.loaders.OmeZarrMetadataUtils.outerBoundingBox( ...
                labelPyramid.levelWorldBoxes(1, :), ...
                labelPyramid.levelVoxelSizesXYZ(1, :)) * labelToUm;

            registration = io.loaders.OmeZarrMetadataUtils.registerLevelScales( ...
                labelPyramid.levelVoxelSizesXYZ * labelToUm, labelOuterBoxUm, ...
                reference.voxelSizesXYZ, reference.outerBoxUm);
            if ~registration.ok; reason = registration.reason; return; end

            finestScale = registration.scaleFactorsYXZ(1, 1);
            if ~registration.isIntegerScale
                reason = sprintf(['these labels are %g x the image''s voxel size, which is not ' ...
                    'a whole number of image voxels, so they cannot be laid on its grid without ' ...
                    'splitting a label across one.'], finestScale);
                return;
            end

            overlayFits = true;

            finestVoxelNm = labelPyramid.levelVoxelSizesXYZ(1, 1) * labelToUm * 1000;
            reason = sprintf(['Label overlay: these labels start at %g nm, %g x the open ' ...
                'image''s voxel, and will be drawn over it as each slice is read - upsampled ' ...
                'where the image is finer. Nothing is downloaded in bulk, and they cannot ' ...
                'be edited.'], finestVoxelNm, finestScale);

            if strcmp(labelPyramid.annotationType, 'instance_segmentation')
                reason = sprintf(['%s\nNote: this is an instance segmentation - its values are ' ...
                    'object ids, and each object is drawn in its own colour. Right-click ' ...
                    '"Show model" to show them as a single material instead.'], reason);
            end
        end

        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt to the batch controller.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
        end
    end
end

% =========================================================================
function cropPlan = applyChosenPair(cropPlan, candidate)
% APPLYCHOSENPAIR - Promote one candidate level pair to the plan's chosen pair.
% Mirrors the same step inside planLabelCrop, which picks the default.
cropPlan.labelLevel     = candidate.labelLevel;
cropPlan.imageLevel     = candidate.imageLevel;
cropPlan.imageLevelName = candidate.imageLevelName;
cropPlan.shapeYXZ       = candidate.shapeYXZ;
cropPlan.voxelSizeUm    = candidate.voxelSizeUm;
cropPlan.requiredBytes  = candidate.requiredBytes;
end

% =========================================================================
function text = formatMegabytes(nBytes)
% FORMATMEGABYTES - Size for a level row. The coarsest levels of a deep pyramid
% are well under a megabyte, and "0 MB" reads like a broken row rather than a
% cheap one, so those get KB.
if nBytes >= 1024^3
    text = sprintf('%.1f GB', nBytes / 1024^3);
elseif nBytes >= 1024^2
    text = sprintf('%.0f MB', nBytes / 1024^2);
else
    text = sprintf('%.0f KB', nBytes / 1024);
end
end
