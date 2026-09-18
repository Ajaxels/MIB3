classdef MakeMovie < handle
    % MAKEMOVIE - Controller for the Make Movie dialog.
    %
    % Renders a video file from the currently shown image stack. Supports
    % z-stack and time-series directions, ROI/shown area cropping, scale bars,
    % split channels, and volume viewer animations.

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (core.ChildView)
        listener
        % cell array of listener handles
        extraController
        % optional extra controller for volume rendering (VolRenApp)
        extraOptions
        % struct with extra rendering parameters; .mode = 'spin'|'animation'
        origHeight
        % original height of the image area in pixels
        origWidth
        % original width of the image area in pixels
        resizedWidth
        % pixel width adjusted for anisotropic pixel size
    end

    events
        CloseEvent
        % event firing when window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Standard listener callback with validity guard.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset'}
                    obj.updateWidgets();
                case 'AxesLimitsChanged'
                    if obj.view.handles.shownAreaRadio.Value
                        obj.crop_Callback();
                    end
            end
        end
    end

    methods (Access = private)
        function updateMovieProgress(~, progressDialog, frameId, noFrames, frameTimer)
            % UPDATEMOVIEPROGRESS - Show the frame count and a time estimate while recording.
            %
            % Grabbing one frame out of the volume viewer costs close to a second, so the
            % dialog is refreshed on every frame and tells the user how long is left.
            %
            % Input Arguments:
            %   - **progressDialog** - [handle] the ``uiprogressdlg`` to update
            %   - **frameId** - [numeric] index of the frame just written
            %   - **noFrames** - [numeric] total number of frames to write
            %   - **frameTimer** - [uint64] ``tic`` identifier taken when recording started

            secondsLeft = toc(frameTimer)/frameId*(noFrames-frameId);
            if ~isfinite(secondsLeft) || secondsLeft <= 0
                remainingText = 'almost done';
            elseif secondsLeft < 90
                remainingText = sprintf('about %.0f s left', max(1, round(secondsLeft)));
            else
                remainingText = sprintf('about %.0f min left', round(secondsLeft/60));
            end

            progressDialog.Value   = frameId / noFrames;
            progressDialog.Message = sprintf('Frame %d / %d\n%s', frameId, noFrames, remainingText);
        end
    end

    methods
        function obj = MakeMovie(mibModel, varargin)
            % MAKEMOVIE - Constructor for the MakeMovie controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       controller = controllers.MakeMovie(mibModel)
            %       controller = controllers.MakeMovie(mibModel, extraController)
            %       controller = controllers.MakeMovie(mibModel, extraController, extraOptions)
            %
            % Parameters:
            %   **mibModel** - handle to the MibModel instance
            %
            %   **extraController** *(optional)* - handle to VolRenApp for volume animations
            %
            %   **extraOptions** *(optional)* - struct; ``.mode`` = ``'spin'`` or ``'animation'``

            obj.mibModel = mibModel;

            if nargin >= 2 && ~isempty(varargin{1})
                obj.extraController = varargin{1};
            else
                obj.extraController = [];
            end

            if nargin >= 3
                obj.extraOptions = varargin{2};
            else
                obj.extraOptions = struct();
            end

            obj.view = core.ChildView(obj, 'views.MakeMovieGUI');
            obj.addCallbacks();
            obj.updateWidgets();

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.closeBtn.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.closeBtn.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            % move window to the left of the main MIB window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');
            % add listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{3} = addlistener(obj.mibModel, 'AxesLimitsChanged', @(src, evnt) obj.ViewListner_Callback2(obj, src, evnt));

            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end
            % show the dialog
            obj.view.gui.Visible = true;
        end

        function closeWindow(obj)
            % CLOSEWINDOW - Close the dialog and clean up listeners.
            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'CloseEvent');
        end

        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks to the gui_Callbacks dispatcher.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            h = obj.view.handles;

            % buttons
            h.continueBtn.ButtonPushedFcn   = @obj.gui_Callbacks;
            h.closeBtn.ButtonPushedFcn      = @obj.gui_Callbacks;
            h.helpButton.ButtonPushedFcn    = @obj.gui_Callbacks;
            h.selectFileBtn.ButtonPushedFcn = @obj.gui_Callbacks;

            % crop radio button group (cropPanel must be a uibuttongroup in the mlapp)
            h.cropPanel.SelectionChangedFcn = @obj.gui_Callbacks;

            % dropdowns
            h.Format.ValueChangedFcn        = @obj.gui_Callbacks;
            h.directionPopup.ValueChangedFcn    = @obj.gui_Callbacks;
            h.resizeMethodPopup.ValueChangedFcn = @obj.gui_Callbacks;
            h.roiPopup.ValueChangedFcn          = @obj.gui_Callbacks;

            % checkboxes
            h.splitChannelsCheck.ValueChangedFcn = @obj.gui_Callbacks;
            h.grayscaleCheck.ValueChangedFcn     = @obj.gui_Callbacks;
            h.scalebarCheck.ValueChangedFcn      = @obj.gui_Callbacks;
            h.backandforthCheck.ValueChangedFcn  = @obj.gui_Callbacks;
            h.whiteBgCheck.ValueChangedFcn       = @obj.gui_Callbacks;

            % numeric edit fields
            h.widthEdit.ValueChangedFcn      = @obj.gui_Callbacks;
            h.heightEdit.ValueChangedFcn     = @obj.gui_Callbacks;
            h.firstFrameEdit.ValueChangedFcn = @obj.gui_Callbacks;
            h.lastFrameEdit.ValueChangedFcn  = @obj.gui_Callbacks;
            h.framerateEdit.ValueChangedFcn  = @obj.gui_Callbacks;
            h.qualityEdit.ValueChangedFcn    = @obj.gui_Callbacks;
            h.colsNoEdit.ValueChangedFcn     = @obj.gui_Callbacks;
            h.rowNoEdit.ValueChangedFcn      = @obj.gui_Callbacks;
            h.marginEdit.ValueChangedFcn     = @obj.gui_Callbacks;

            % text edit field
            h.outputDir.ValueChangedFcn = @obj.gui_Callbacks;
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh all widgets to match the current dataset state.
            activeId = obj.mibModel.getActiveId();
            dataset  = obj.mibModel.I{activeId};
            h        = obj.view.handles;

            if dataset.image.colors > 1
                h.splitChannelsCheck.Enable = 'on';
            else
                h.splitChannelsCheck.Enable = 'off';
                h.splitChannelsCheck.Value  = false;
            end

            % volume viewer mode: override crop panel labels to Spin / Animation
            if ~isempty(obj.extraController)
                h.cropPanel.Title           = 'Mode';
                if strcmp(obj.extraOptions.mode, 'animation')
                    h.shownAreaRadio.Value = true;
                else
                    h.fullImageRadio.Value = true;
                end
                h.fullImageRadio.Text           = 'Spin';
                h.shownAreaRadio.Text           = 'Animation';
                h.splitChannelsCheck.Enable     = 'off';
                h.roiRadio.Visible              = 'off';
                h.roiPopup.Visible              = 'off';
                h.scalebarCheck.Enable          = 'off';
                h.lastFrameEdit.Visible         = 'off';
                h.firstFrameEdit.Value          = 360;
                h.framerateEdit.Value           = 24;
                h.lastFrameEditLabel.Visible    = 'off';
                h.FirstframenumberEditFieldLabel.Text = 'Number of frames';
            end

            % initialize filename if not yet set for this dataset
            if isempty(dataset.movieFilename)
                [filePath, baseName] = fileparts(dataset.image.filename);
                if isempty(filePath) || strcmp(baseName, 'none')
                    filePath = obj.mibModel.currentDirectory;
                    baseName = '';   % no dataset-specific prefix available
                end
                switch h.Format.Value
                    case 'Archival';          ext = '.mj2';
                    case 'Motion JPEG AVI';   ext = '.avi';
                    case 'Motion JPEG 2000';  ext = '.mj2';
                    case 'MPEG-4';            ext = '.mp4';
                    case 'Uncompressed AVI';  ext = '.avi';
                    otherwise;                ext = '.avi';
                end
                dataset.movieFilename = fullfile(filePath, [baseName '_movie' ext]);
            end

            % sync codec dropdown to match the saved filename extension
            [~, ~, ext] = fileparts(dataset.movieFilename);
            switch ext(2:end)
                case 'avi'; h.Format.Value = 'Motion JPEG AVI';
                case 'mj2'; h.Format.Value = 'Motion JPEG 2000';
                case 'mp4'; h.Format.Value = 'MPEG-4';
            end
            h.outputDir.Value = dataset.movieFilename;

            if isempty(obj.extraController)
                if dataset.image.time > 1
                    h.directionPopup.Enable = 'on';
                end

                [numberOfROI, indices] = dataset.hROI.getNumberOfROI();
                if numberOfROI == 0
                    h.roiRadio.Enable = 'off';
                    h.roiPopup.Enable = 'off';
                    if h.roiRadio.Value
                        h.fullImageRadio.Value = true;
                    end
                else
                    h.roiRadio.Enable = 'on';
                    h.roiPopup.Enable = 'on';
                    roiNames = cell([numberOfROI 1]);
                    for i = 1:numberOfROI
                        roiNames(i) = dataset.hROI.Data(indices(i)).label;
                    end
                    if numel(roiNames) < numel(h.roiPopup.Items)
                        h.roiPopup.Value = roiNames{1};
                    end
                    h.roiPopup.Items = roiNames;
                end
            end

            obj.updateWidthHeight();
            obj.splitChannelsCheck_Callback();
        end

        function updateWidthHeight(obj)
            % UPDATEWIDTHHEIGHT - Recompute and apply image dimensions to the width/height fields.
            %
            % Called from ``updateWidgets`` and ``crop_Callback`` whenever the
            % crop mode or dataset changes.  Mirrors ``Snapshot.updateWidthHeight``.
            activeId = obj.mibModel.getActiveId();
            dataset  = obj.mibModel.I{activeId};
            h        = obj.view.handles;

            if isempty(obj.extraController)
                blockModeSwitch = h.shownAreaRadio.Value;
                % See Snapshot.updateWidthHeight: the shown block lives on the
                % DATASET (dataset.slices), so routing this through the image
                % errored on every "shown area" run. This file mirrored the
                % Snapshot code, and mirrored its bug with it.
                [height, width] = dataset.getDatasetDimensions('image', [], ...
                    struct('blockModeSwitch', blockModeSwitch));
                obj.origWidth   = width;

                orientation = dataset.orientation;
                pixSize     = dataset.image.pixSize;
                if orientation == 1
                    width = width * pixSize.z / pixSize.x;
                elseif orientation == 2
                    width = width * pixSize.z / pixSize.y;
                elseif orientation == 3
                    width = width * pixSize.x / pixSize.y;
                end
                width = ceil(width);

                h.lastFrameEdit.Limits = [1 dataset.image.depth];
                h.lastFrameEdit.Value = dataset.image.depth;
                h.firstFrameEdit.Limits = [1 dataset.image.depth];
            else
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch')
                    curUnits = obj.extraController.view.handles.volViewPanel.Units;
                    obj.extraController.view.handles.volViewPanel.Units = 'pixels';
                    height = ceil(obj.extraController.view.handles.volViewPanel.Position(4));
                    width  = ceil(obj.extraController.view.handles.volViewPanel.Position(3));
                    obj.extraController.view.handles.volViewPanel.Units = curUnits;
                    obj.origWidth = width;
                elseif strcmp(obj.extraController.view.gui.Name, '3D Controls')
                    height = ceil(obj.extraController.childControllers{1}.view.handles.volumeViewerPanel.Position(4));
                    width  = ceil(obj.extraController.childControllers{1}.view.handles.volumeViewerPanel.Position(3));
                    obj.origWidth = width;
                end
            end

            h.widthEdit.Value  = width;
            h.heightEdit.Value = height;
            obj.origHeight     = height;
            obj.resizedWidth   = width;
        end

        function splitChannelsCheck_Callback(obj)
            % SPLITCHANNELSCHECK_CALLBACK - Enable/disable split channel controls.
            h     = obj.view.handles;
            onOff = 'off';
            if h.splitChannelsCheck.Value; onOff = 'on'; end
            h.grayscaleCheck.Enable = onOff;
            h.colsNoEdit.Enable     = onOff;
            h.rowNoEdit.Enable      = onOff;
            h.marginEdit.Enable     = onOff;
        end

        function roiPopup_Callback(obj)
            % ROIPOPUP_CALLBACK - Update the selected ROI and refresh the view.
            activeId = obj.mibModel.getActiveId();
            roiItems = obj.view.handles.roiPopup.Items;
            roiValue = obj.view.handles.roiPopup.Value;
            roiIdx   = find(strcmp(roiItems, roiValue), 1);
            obj.mibModel.I{activeId}.selectedROI = roiIdx;

            eventdata = core.ToggleEventData({'roi'});
            notify(obj.mibModel, 'UpdateGuiWidgets', eventdata);
            notify(obj.mibModel, 'ShowImage');
            obj.crop_Callback();
        end

        function crop_Callback(obj)
            % CROP_CALLBACK - Update dimensions based on the crop/mode radio selection.

            % volume viewer mode: update extraOptions.mode, no dimension changes needed
            if ~isempty(obj.extraController)
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch') || ...
                        strcmp(obj.extraController.view.gui.Name, '3D Controls')
                    if obj.view.handles.fullImageRadio.Value
                        obj.extraOptions.mode = 'spin';
                    elseif obj.view.handles.shownAreaRadio.Value
                        obj.extraOptions.mode = 'animation';
                    end
                end
                return;
            end

            h        = obj.view.handles;
            activeId = obj.mibModel.getActiveId();

            if h.roiRadio.Value
                roiImg = obj.mibModel.I{activeId}.hROI.returnMask(h.roiPopup.Value);
                STATS  = regionprops(roiImg, 'BoundingBox');
                width  = ceil(STATS.BoundingBox(3));
                height = ceil(STATS.BoundingBox(4));
            else
                options.blockModeSwitch = h.shownAreaRadio.Value;
                [height, width] = obj.mibModel.I{activeId}.getDatasetDimensions('image', [], options);
            end

            obj.origWidth      = width;
            h.heightEdit.Value = height;

            orientation = obj.mibModel.I{activeId}.orientation;
            pixSize     = obj.mibModel.I{activeId}.image.pixSize;
            if orientation == 1
                width = width * pixSize.z / pixSize.x;
            elseif orientation == 2
                width = width * pixSize.z / pixSize.y;
            elseif orientation == 3
                width = width * pixSize.x / pixSize.y;
            end

            h.widthEdit.Value = ceil(width);
            obj.origHeight    = height;
            obj.resizedWidth  = width;
        end

        function scalebarCheck_Callback(obj)
            % SCALEBAR_CALLBACK - Verify pixel size when scale bar is enabled.
            if obj.view.handles.scalebarCheck.Value
                activeId = obj.mibModel.getActiveId();
                dataset  = obj.mibModel.I{activeId};
                dlgOpts.showDialog   = true;
                dlgOpts.ParentFigure = obj.view.gui;
                dlgOpts.mibPath      = obj.mibModel.mibPath;
                dlgOpts.WindowStyle  = 'modal';
                [~, newPixSize, dlgResult] = utils.updatePixSizeAndResolution([], dataset.image.pixSize, dlgOpts);
                if dlgResult; dataset.setPixSize(newPixSize); end
            end
        end

        function formatPopup_Callback(obj)
            % CODECPOPUP_CALLBACK - Update filename extension based on the selected codec.
            activeId = obj.mibModel.getActiveId();
            codec    = obj.view.handles.Format.Value;
            fn       = obj.view.handles.outputDir.Value;
            [filePath, baseName] = fileparts(fn);

            obj.view.handles.qualityEdit.Enable = 'on';
            switch codec
                case 'Archival'
                    fn = fullfile(filePath, [baseName '.mj2']);
                    obj.view.handles.qualityEdit.Enable = 'off';
                case 'Motion JPEG AVI'
                    fn = fullfile(filePath, [baseName '.avi']);
                case 'Motion JPEG 2000'
                    fn = fullfile(filePath, [baseName '.mj2']);
                    obj.view.handles.qualityEdit.Enable = 'off';
                case 'MPEG-4'
                    fn = fullfile(filePath, [baseName '.mp4']);
                case 'Uncompressed AVI'
                    fn = fullfile(filePath, [baseName '.avi']);
                    obj.view.handles.qualityEdit.Enable = 'off';
            end
            obj.view.handles.outputDir.Value          = fn;
            obj.mibModel.I{activeId}.movieFilename    = fn;
        end

        function outputDir_Callback(obj)
            % OUTPUTDIR_CALLBACK - Validate and update the output filename.
            activeId = obj.mibModel.getActiveId();
            fn = obj.view.handles.outputDir.Value;
            if isequal(fn, 0)
                obj.view.handles.outputDir.Value = obj.mibModel.I{activeId}.movieFilename;
                return;
            end
            if exist(fn, 'file')
                button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('Warning!\nThe file already exists!\n\nOverwrite?'), ...
                    'Overwrite?', 'Cancel', 'Overwrite', 'Cancel');
                if strcmp(button, 'Cancel'); return; end
            end
            obj.mibModel.I{activeId}.movieFilename = fn;
        end

        function selectFileBtn_Callback(obj)
            % SELECTFILEBTN_CALLBACK - Open a save dialog for the output file.
            activeId = obj.mibModel.getActiveId();
            switch obj.view.handles.Format.Value
                case 'Archival'
                    formatText = {'*.mj2', 'Motion JPEG 2000 lossless (*.mj2)'};
                case 'Motion JPEG AVI'
                    formatText = {'*.avi', 'Motion JPEG AVI (*.avi)'};
                case 'Motion JPEG 2000'
                    formatText = {'*.mj2', 'Compressed Motion JPEG 2000 (*.mj2)'};
                case 'MPEG-4'
                    formatText = {'*.mp4', 'MPEG-4 H.264 (*.mp4)'};
                case 'Uncompressed AVI'
                    formatText = {'*.avi', 'Uncompressed AVI RGB24 (*.avi)'};
                otherwise
                    formatText = {'*.avi', 'AVI (*.avi)'};
            end
            [filename, pathname] = uiputfile(formatText, 'Select filename', obj.mibModel.I{activeId}.movieFilename);
            if isequal(filename, 0) || isequal(pathname, 0); return; end
            obj.mibModel.I{activeId}.movieFilename = fullfile(pathname, filename);
            obj.view.handles.outputDir.Value       = obj.mibModel.I{activeId}.movieFilename;
        end

        function widthEdit_Callback(obj)
            % WIDTHEDIT_CALLBACK - Update height to maintain aspect ratio when width changes.
            newWidth = obj.view.handles.widthEdit.Value;
            if isempty(obj.extraController)
                ratio = obj.origHeight / obj.resizedWidth;
                obj.view.handles.heightEdit.Value = round(newWidth * ratio);
            else
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch') || ...
                        strcmp(obj.extraController.view.gui.Name, '3D Controls')
                    screensize = get(groot, 'Screensize');
                    if screensize(3) < newWidth
                        utils.dlgs.showErrorDialog(obj.view.gui, ...
                            'The output dimensions should be smaller than the screen size!', 'Size is too large');
                        obj.view.handles.widthEdit.Value = ceil(obj.resizedWidth);
                    end
                end
            end
        end

        function heightEdit_Callback(obj)
            % HEIGHTEDIT_CALLBACK - Update width to maintain aspect ratio when height changes.
            newHeight = obj.view.handles.heightEdit.Value;
            if isempty(obj.extraController)
                ratio = obj.origHeight / obj.resizedWidth;
                obj.view.handles.widthEdit.Value = round(newHeight / ratio);
            else
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch')
                    screensize = get(groot, 'Screensize');
                    if screensize(4) < newHeight
                        utils.dlgs.showErrorDialog(obj.view.gui, ...
                            'The output dimensions should be smaller than the screen size!', 'Size is too large');
                        obj.view.handles.heightEdit.Value = obj.origHeight;
                    end
                end
            end
        end

        function directionPopup_Callback(obj)
            % DIRECTIONPOPUP_CALLBACK - Update last frame when direction changes.
            % BUG FIX from MIB2: used `handles.mibModel` (undefined var); fixed to `obj.mibModel`.
            activeId = obj.mibModel.getActiveId();
            if strcmp(obj.view.handles.directionPopup.Value, 'Z stack')
                obj.view.handles.firstFrameEdit.Limits = [1 obj.mibModel.I{activeId}.image.depth];
                obj.view.handles.lastFrameEdit.Limits = [1 obj.mibModel.I{activeId}.image.depth];
                obj.view.handles.lastFrameEdit.Value = obj.mibModel.I{activeId}.image.depth;
            else
                obj.view.handles.firstFrameEdit.Limits = [1 obj.mibModel.I{activeId}.image.time];
                obj.view.handles.lastFrameEdit.Limits = [1 obj.mibModel.I{activeId}.image.time];
                obj.view.handles.lastFrameEdit.Value = obj.mibModel.I{activeId}.image.time;
            end
        end

        function help(obj)
            % show help page
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'home', 'home-makevideo.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/home/home-makevideo.html');

        end

        function continueBtn_Callback(obj)
            % CONTINUEBTN_CALLBACK - Render and save a movie from the current dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.continueBtn_Callback()
            %
            % Iterates over the selected frame range (Z-stack or time series), fetches
            % each RGB frame via ``obj.mibModel.getRGBimage``, optionally crops to an
            % ROI, resizes, optionally overlays a scale bar, and writes all frames
            % into the movie file configured in ``obj.view.handles``.
            %
            % **BigData pyramid-level selection** - for BigData datasets (OME-Zarr / WSI),
            % the function selects the *finest* pyramid level whose native resolution still
            % covers the requested frame dimensions, avoiding full-res loads for every frame:
            %
            %   - Shown-area mode - fetches at ``dataset.magFactor`` (current viewport resolution).
            %   - Full-image mode - selects the coarsest level ``L`` where
            %     ``levelScaleFactors(L) ≤ min(fullW/newW, fullH/newH)``.
            %   - ROI mode       - same formula using ``obj.origWidth``/``obj.origHeight``
            %     (ROI extent in full-res pixels); the bounding box is stored as
            %     ``bigDataRoiBB`` and divided by ``levelScaleFactors(L)`` per frame
            %     via ``imcrop`` (rather than passing ``options.x``/``options.y`` which
            %     are full-res coords incompatible with a downsampled pyramid level).
            %
            % **Scale bar correction** - computed once on the first frame and reused as a
            % cached strip for all subsequent frames.  Uses ``levelImageSizes(1,2)``
            % (FullImage), ``scale / magFactor`` (ShownArea), or ``newWidth / obj.origWidth``
            % (ROI) so that ``utils.addScaleBar`` receives ``scale = newWidth / fullResWidth``
            % instead of a pyramid-level-relative ratio.  ZX / ZY orientations are unaffected
            % because the Z dimension is never pyramided.
            %
            % **Example** - triggered by pressing the Continue / Render button in the
            % MakeMovie dialog:
            %
            %   .. code-block:: matlab
            %
            %      obj.continueBtn_Callback();   % all parameters read from obj.view.handles

            activeId = obj.mibModel.getActiveId();
            dataset  = obj.mibModel.I{activeId};
            h        = obj.view.handles;

            h.continueBtn.BackgroundColor = [1 0 0];
            drawnow;

            codec        = h.Format.Value;
            quality      = h.qualityEdit.Value;
            frameRate    = h.framerateEdit.Value;
            newWidth     = h.widthEdit.Value;
            newHeight    = h.heightEdit.Value;
            startFrame   = h.firstFrameEdit.Value;
            lastFrame    = h.lastFrameEdit.Value;
            resizeMethod = h.resizeMethodPopup.Value;

            options.resizeToMagnification = false;
            options.markerType            = 'Label + Value';
            options.blockModeSwitch       = h.shownAreaRadio.Value;

            bgColor = double(h.whiteBgCheck.Value);   % 1 = white, 0 = black

            % BigData: pick the finest pyramid level that still covers the output size.
            % Without this, getData2D defaults to magFactor=1 (full-res) and the entire
            % WSI level-0 image would be loaded for every frame.
            isBigData    = strcmp(dataset.image.type, 'bigdata') && ~isempty(dataset.image.pyramid.levelNames);
            bigDataRoiBB = [];   % full-res ROI bounding box; filled below for BigData ROI mode

            if isBigData
                if h.shownAreaRadio.Value
                    options.magFactor = dataset.magFactor;
                elseif h.fullImageRadio.Value
                    fullH = dataset.image.pyramid.levelImageSizes(1, 1);
                    fullW = dataset.image.pyramid.levelImageSizes(1, 2);
                    targetMagFactor = min(fullW / newWidth, fullH / newHeight);
                    scales = dataset.image.pyramid.levelScaleFactors(:, 1);
                    validIdx = find(scales <= targetMagFactor);
                    if isempty(validIdx)
                        options.pyramidLevel = 1;
                    else
                        options.pyramidLevel = validIdx(end);
                    end
                else  % ROI
                    if obj.origWidth > 0 && obj.origHeight > 0
                        targetMagFactor = min(obj.origWidth / newWidth, obj.origHeight / newHeight);
                        scales = dataset.image.pyramid.levelScaleFactors(:, 1);
                        validIdx = find(scales <= targetMagFactor);
                        if isempty(validIdx)
                            options.pyramidLevel = 1;
                        else
                            options.pyramidLevel = validIdx(end);
                        end
                    end
                end
            end

            movieFilename = dataset.movieFilename;
            if exist(movieFilename, 'file')
                button = utils.dlgs.inputQuestDlg(obj.view.gui, ...
                    sprintf('Warning!\nThe file already exists!\n\nOverwrite?'), ...
                    'Overwrite?', 'Overwrite', 'Cancel', 'Cancel');
                if strcmp(button, 'Cancel')
                    h.continueBtn.BackgroundColor = [0.149 0.902 0.1804];
                    return;
                end
            end

            try
                writerObj = VideoWriter(movieFilename, codec);
            catch err
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('Cannot create the video file (it may be open elsewhere).\n\n%s', err.identifier), ...
                    'File Error');
                h.continueBtn.BackgroundColor = [0.149 0.902 0.1804];
                return;
            end

            slices        = dataset.slices;
            colorChannels = slices{4};   % MIB3: color channels are at slices index 4 (was 3 in MIB2)

            if h.splitChannelsCheck.Value
                rowNo  = h.rowNoEdit.Value;
                colNo  = h.colsNoEdit.Value;
                if numel(colorChannels) + 1 > rowNo * colNo
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('Number of selected color channels is larger than the number of panels!\nIncrease columns or rows and try again.'), ...
                        'Too many color channels');
                    h.continueBtn.BackgroundColor = [0.149 0.902 0.1804];
                    return;
                end
                maxImageIndex = min([numel(colorChannels) + 1, rowNo * colNo]);
                imageShift    = h.marginEdit.Value;
            else
                rowNo         = 1;
                colNo         = 1;
                maxImageIndex = 1;
                imageShift    = 0;
            end

            writerObj.FrameRate = frameRate;
            if ~strcmp(codec, 'Archival') && ~strcmp(codec, 'Uncompressed AVI') && ~strcmp(codec, 'Motion JPEG 2000')
                writerObj.Quality = quality;
            end

            progressDialog = uiprogressdlg(obj.view.gui, ...
                'Title',     'Movie rendering...', ...
                'Message',   sprintf('%s\nPlease wait...', movieFilename), ...
                'Cancelable', 'on', ...
                'Value',     0);
            framesWritten = 0;   % how many frames actually reached the file

            if isempty(obj.extraController)
                % --- MIB image view rendering ---
                if strcmp(h.directionPopup.Value, 'Z stack')
                    orientation = dataset.orientation;
                    switch orientation
                        case 3; maxZ = dataset.image.depth;    % XY (was orientation 4 in MIB2)
                        case 1; maxZ = dataset.image.height;
                        case 2; maxZ = dataset.image.width;
                    end
                    zStackSwitch = true;
                    timePoint    = slices{5}(1);
                else
                    maxZ         = dataset.image.time;
                    zStackSwitch = false;
                    sliceNo      = slices{3}(1);   % current z-slice (replaces getImageMethod('getCurrentSliceNumber'))
                end

                if maxZ < lastFrame
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('Last frame (%d) exceeds the dataset maximum (%d).', lastFrame, maxZ), ...
                        'Frame Error');
                    h.continueBtn.BackgroundColor = [0.149 0.902 0.1804];
                    close(progressDialog);
                    return;
                end

                if h.roiRadio.Value
                    roiImg = dataset.hROI.returnMask(h.roiPopup.Value);
                    STATS  = regionprops(roiImg, 'BoundingBox');
                    if isBigData && isfield(options, 'pyramidLevel')
                        % BigData: fetch full image at pyramid level, then imcrop per frame
                        bigDataRoiBB = STATS.BoundingBox;
                    else
                        options.x = [floor(STATS.BoundingBox(1)), floor(STATS.BoundingBox(1)) + STATS.BoundingBox(3) - 1];
                        options.y = [floor(STATS.BoundingBox(2)), floor(STATS.BoundingBox(2)) + STATS.BoundingBox(4) - 1];
                    end
                end

                framePnts = startFrame:lastFrame;
                if h.backandforthCheck.Value
                    framePnts = [framePnts, lastFrame-1:-1:startFrame];
                end
                noFrames = numel(framePnts);

                open(writerObj);
                scaleBar = [];

                for frameIdx = 1:noFrames
                    frame = framePnts(frameIdx);

                    if progressDialog.CancelRequested
                        close(writerObj);
                        close(progressDialog);
                        dataset.slices{4} = colorChannels;
                        h.continueBtn.BackgroundColor = [0.149 0.902 0.1804];
                        fprintf('MIB: movie recording cancelled, %d of %d frames written to: %s\n', ...
                            framesWritten, noFrames, movieFilename);
                        return;
                    end

                    if zStackSwitch
                        options.sliceNo = frame;
                        options.t       = [timePoint timePoint];
                    else
                        options.sliceNo = sliceNo;
                        options.t       = [frame frame];
                    end

                    for imageId = 1:maxImageIndex
                        if imageId == maxImageIndex
                            if isfield(options, 'useLut'); options = rmfield(options, 'useLut'); end
                            dataset.slices{4} = colorChannels;
                        else
                            if h.grayscaleCheck.Value; options.useLut = 0; end
                            dataset.slices{4} = colorChannels(imageId);
                        end
                        img = obj.mibModel.getRGBimage(options);

                        if ~isempty(bigDataRoiBB)
                            scaleFactor = dataset.image.pyramid.levelScaleFactors(options.pyramidLevel, 1);
                            img = imcrop(img, bigDataRoiBB / scaleFactor);
                        end

                        % resize
                        scale = newWidth / size(img, 2);
                        if newWidth ~= size(img, 2) || newHeight ~= size(img, 1)
                            img = imresize(img, [newHeight newWidth], resizeMethod);
                        end

                        % convert to uint8 for VideoWriter
                        % BUG FIX: MIB2 used uint8(img/255) which is wrong for uint16 data
                        if ~isa(img, 'uint8')
                            img = im2uint8(img);
                        end

                        % scale bar: computed once on first frame and reused as a strip
                        if h.scalebarCheck.Value
                            scalebarOptions.orientation = dataset.orientation;
                            scalebarOptions.bgColor     = bgColor;

                            % For BigData XY the fetched image is from a downsampled pyramid
                            % level or display-resolution viewport, so scale = newWidth/size(img,2)
                            % does not equal newWidth/fullResWidth - which is what addScaleBar requires.
                            scaleForBar = scale;
                            if isBigData && dataset.orientation == 3
                                if h.fullImageRadio.Value
                                    scaleForBar = newWidth / dataset.image.pyramid.levelImageSizes(1, 2);
                                elseif h.shownAreaRadio.Value
                                    scaleForBar = scale / dataset.magFactor;
                                elseif h.roiRadio.Value && obj.origWidth > 0
                                    scaleForBar = newWidth / obj.origWidth;
                                end
                            end

                            if frameIdx == 1 && imageId == 1
                                imgWithBar = utils.addScaleBar(img, dataset.image.pixSize, scaleForBar, scalebarOptions);
                                scaleBar   = imgWithBar(size(img,1)+1:end, :, :);
                                img        = imgWithBar;
                            else
                                img = cat(1, img, scaleBar);
                            end
                        end

                        if maxImageIndex == 1
                            imgOut = img;
                        else
                            if imageId == 1
                                outH   = size(img, 1);
                                outW   = size(img, 2);
                                colId  = 1;
                                rowId  = 1;
                                maxInt = double(intmax(class(img)));
                                imgOut = zeros([outH*rowNo + (rowNo-1)*imageShift, ...
                                                outW*colNo + (colNo-1)*imageShift, ...
                                                size(img, 3)], class(img)) + bgColor * maxInt;
                            end
                            y1 = (rowId-1)*outH + 1 + imageShift*(rowId-1);
                            y2 = y1 + outH - 1;
                            x1 = (colId-1)*outW + 1 + imageShift*(colId-1);
                            x2 = x1 + outW - 1;
                            imgOut(y1:y2, x1:x2, :) = img;
                            colId = colId + 1;
                            if colId > colNo; colId = 1; rowId = rowId + 1; end
                        end
                    end

                    writeVideo(writerObj, im2frame(imgOut));
                    framesWritten = frameIdx;
                    if mod(frameIdx, 10) == 0
                        progressDialog.Value   = frameIdx / noFrames;
                        progressDialog.Message = sprintf('Frame %d / %d', frameIdx, noFrames);
                    end
                end

                dataset.slices{4} = colorChannels;   % restore color channels

            else
                % --- Volume viewer rendering ---
                if strcmp(obj.extraController.view.gui.Name, '3D onFlyImageStretch')
                    cameraObject = 'volume';
                elseif strcmp(obj.extraController.view.gui.Name, '3D Controls')
                    cameraObject = 'viewer';
                end

                open(writerObj);
                noFrames = startFrame;   % firstFrameEdit repurposed as "number of frames" in volume mode
                extraOpts.back_and_forth = h.backandforthCheck.Value;

                grabOpts.showWaitbar  = 0;
                grabOpts.resizeWindow = 0;

                % grabbing a frame out of the volume viewer costs close to a second
                % (see development/notes/volren_movie_capture_speed.md), so the progress
                % dialog is updated on every frame and carries a time estimate
                frameTimer = tic;

                % grabFrame throws when the requested frame does not fit on the screen;
                % the viewer window is left resized for capture at that moment, so it has
                % to be restored here before the error reaches the user
                try
                    switch obj.extraOptions.mode
                        case 'animation'
                            positions   = obj.extraController.generatePositionsForKeyFramesAnimation(noFrames, extraOpts);
                            noFrames    = size(positions.CameraPosition, 1);
                            hasTarget   = ~isempty(positions.CameraTarget);   % hoist out of loop
                            obj.extraController.prepareWindowForGrabFrame(newWidth, newHeight);
                            if hasTarget
                                for frameId = 1:noFrames
                                    if progressDialog.CancelRequested; break; end
                                    obj.extraController.(cameraObject).CameraPosition = positions.CameraPosition(frameId, :);
                                    obj.extraController.(cameraObject).CameraUpVector = positions.CameraUpVector(frameId, :);
                                    obj.extraController.(cameraObject).CameraTarget   = positions.CameraTarget(frameId, :);
                                    writeVideo(writerObj, obj.extraController.grabFrame(newWidth, newHeight, grabOpts));
                                    framesWritten = frameId;
                                    obj.updateMovieProgress(progressDialog, frameId, noFrames, frameTimer);
                                end
                            else
                                for frameId = 1:noFrames
                                    if progressDialog.CancelRequested; break; end
                                    obj.extraController.(cameraObject).CameraPosition = positions.CameraPosition(frameId, :);
                                    obj.extraController.(cameraObject).CameraUpVector = positions.CameraUpVector(frameId, :);
                                    writeVideo(writerObj, obj.extraController.grabFrame(newWidth, newHeight, grabOpts));
                                    framesWritten = frameId;
                                    obj.updateMovieProgress(progressDialog, frameId, noFrames, frameTimer);
                                end
                            end
                            obj.extraController.restoreWindowAfterGrabFrame();

                        case 'spin'
                            positions   = obj.extraController.generatePositionsForSpinAnimation(noFrames, extraOpts);
                            noFrames    = size(positions.CameraPosition, 1);
                            obj.extraController.prepareWindowForGrabFrame(newWidth, newHeight);
                            obj.extraController.(cameraObject).CameraUpVector = positions.CameraUpVector;
                            obj.extraController.(cameraObject).CameraTarget   = positions.CameraTarget;
                            for frameId = 1:noFrames
                                if progressDialog.CancelRequested; break; end
                                obj.extraController.(cameraObject).CameraPosition = positions.CameraPosition(frameId, :);
                                writeVideo(writerObj, obj.extraController.grabFrame(newWidth, newHeight, grabOpts));
                                framesWritten = frameId;
                                obj.updateMovieProgress(progressDialog, frameId, noFrames, frameTimer);
                            end
                            obj.extraController.restoreWindowAfterGrabFrame();
                    end
                catch err
                    if isstruct(obj.extraController.figPosStored) && ~isempty(obj.extraController.figPosStored.mibVolRenAppFigure)
                        obj.extraController.restoreWindowAfterGrabFrame();
                    end
                    close(writerObj);
                    close(progressDialog);
                    utils.dlgs.showErrorDialog(obj.view.gui, err, 'Movie error', ...
                        sprintf('The movie was stopped after %d frames', framesWritten), '', ...
                        struct('Icon', 'puffin_warning'));
                    h.continueBtn.BackgroundColor = [0.149 0.902 0.1804];
                    return;
                end
            end

            % read before the dialog is deleted; pressing cancel during the very last frame
            % still leaves a complete file, so only an incomplete one counts as cancelled
            cancelled = progressDialog.CancelRequested && framesWritten < noFrames;
            close(writerObj);
            close(progressDialog);

            if cancelled
                % the file holds whatever was recorded before the user stopped
                fprintf('MIB: movie recording cancelled, %d of %d frames written to: %s\n', ...
                    framesWritten, noFrames, movieFilename);
                h.continueBtn.BackgroundColor = [0.149 0.902 0.1804];
                return;
            end

            obj.mibModel.preferences.Users.Tiers.numberOfSnapAndMovies = ...
                obj.mibModel.preferences.Users.Tiers.numberOfSnapAndMovies + 1;
            eventdata = core.ToggleEventData(2);
            notify(obj.mibModel, 'UpdateUserScore', eventdata);

            fprintf('MIB: movie saved: %s\n', movieFilename);
            h.continueBtn.BackgroundColor = [0.149 0.902 0.1804];
        end

    end
end
