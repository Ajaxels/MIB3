classdef BoundingBox < handle
% BOUNDINGBOX - Controller for the Bounding Box editor dialog.
%
% Available from Ribbon → Dataset → Bounding Box.  Allows viewing and
% editing the spatial bounding box and voxel size of the current dataset.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.startController('controllers.BoundingBox');

    % Updates
    % 20.05.2019, updated for the batch mode
    % ported to MIB3 AppDesigner framework

    properties
        mibModel
        % handles to the model
        view
        % handle to the view / views.BoundingBoxGUI
        listener
        % a cell array with handles to listeners
        bb
        % matrix [xmin xmax ymin ymax zmin zmax] with current bounding box
        oldBB
        % original bounding box before edits
        pixSize
        % a structure with the pixel size information
        BatchOpt
        % a structure compatible with batch operation, see details in the constructor
    end

    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, src, evnt)
            % VIEWLISTNER_CALLBACK2 - Guard: clean up listeners and return silently if the view was closed.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      BoundingBox.ViewListner_Callback2(obj, src, evnt)
            %
            % If the view window was closed (e.g. via the X button before
            % CloseRequestFcn was registered, or by external deletion), deletes
            % all listeners and returns silently.
            %
            % Input Arguments:
            %   - **obj** - handle to the BoundingBox controller instance
            %   - **src** - event source (handle to MibModel)
            %   - **evnt** - event data; ``evnt.EventName`` identifies the event
            %
            % Output Arguments:
            %   (none)
            %
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener)
                    delete(obj.listener{i});
                end
                return;
            end
            switch evnt.EventName
                case {'UpdateGuiWidgets', 'NewDataset', 'UpdateDialog'}
                    obj.updateWidgets();
            end
        end
    end

    methods
        function obj = BoundingBox(mibModel, varargin)
            obj.mibModel = mibModel;    % assign model

            % -------------- fill BatchOpt structure with default values
            obj.BatchOpt.id = obj.mibModel.id;  % optional

            obj.pixSize = obj.mibModel.I{obj.BatchOpt.id}.image.pixSize;
            obj.bb = obj.mibModel.I{obj.BatchOpt.id}.image.boundingBox;    % current bounding box
            obj.BatchOpt.Xmin = num2str(obj.bb(1));
            obj.BatchOpt.Ymin = num2str(obj.bb(3));
            obj.BatchOpt.Zmin = num2str(obj.bb(5));
            obj.BatchOpt.Xcenter = '';
            obj.BatchOpt.Ycenter = '';
            obj.BatchOpt.Xmax = '';
            obj.BatchOpt.Ymax = '';
            obj.BatchOpt.Zmax = '';
            obj.BatchOpt.StageRotationBias = '';
            obj.BatchOpt.ImportFromClipboard = false;
            % add section name and action name for the batch tool
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Dataset';
            obj.BatchOpt.mibBatchActionName = 'Bounding Box';
            % tooltips that will accompany the BatchOpt
            obj.BatchOpt.mibBatchTooltip.Xmin = sprintf('Min X point of the bounding box');
            obj.BatchOpt.mibBatchTooltip.Ymin = sprintf('Min Y point of the bounding box');
            obj.BatchOpt.mibBatchTooltip.Zmin = sprintf('Min Z point of the bounding box');
            obj.BatchOpt.mibBatchTooltip.Xcenter = sprintf('Center X point of the bounding box');
            obj.BatchOpt.mibBatchTooltip.Ycenter = sprintf('Center Y point of the bounding box');
            obj.BatchOpt.mibBatchTooltip.Xmax = sprintf('Max X point of the bounding box');
            obj.BatchOpt.mibBatchTooltip.Ymax = sprintf('Max Y point of the bounding box');
            obj.BatchOpt.mibBatchTooltip.Zmax = sprintf('Max Z point of the bounding box');
            obj.BatchOpt.mibBatchTooltip.StageRotationBias = sprintf('Stage rotation bias, used for 3view system, where it is normally 45 degrees');
            obj.BatchOpt.mibBatchTooltip.ImportFromClipboard = sprintf('Acquire bounding box information from the system clipboard, see more in the Help section');

            % ---- Batch mode processing code
            % if the BatchOpt structure is provided the controller is initialized
            % using those parameters and performs the function in headless mode without GUI
            if nargin == 3
                BatchOptInput = varargin{2};
                if isstruct(BatchOptInput) == 0
                    if isnan(BatchOptInput)
                        obj.returnBatchOpt();   % obtain Batch parameters
                    else
                        errorOpts.mibPath = obj.mibModel.mibPath;
                        errorOpts.WindowHeight = 150;
                        utils.dlgs.showErrorDialog([], sprintf('A structure as the 4rd parameter is required!'), 'Error', 'Error in controllers.BoundingBox', '', errorOpts);
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end

                % combine fields from input and default structures
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                if obj.BatchOpt.ImportFromClipboard
                    obj.importBtn_Callback(1);  % 1 - batch mode switch
                end
                obj.applyButton_Callback(1);   % 1 - batch mode switch
                
                Parameters.DialogName = 'BoundingBox';
                eventdata = core.ToggleEventData(Parameters);
                notify(obj.mibModel, 'UpdateDialog', eventdata);                
                return;
            end

            guiName = 'views.BoundingBoxGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme

            obj.addCallbacks(); % add callbacks to widgets

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.BoundingBoxTitleLabel.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.BoundingBoxTitleLabel.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            % move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            % update GUI widgets using the provided BatchOpt
            obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.updateWidgets();
            
            % add handle tags to the tooltips
            if obj.mibModel.preferences.System.DeveloperMode
                utils.overrideDescriptions(obj.view.handles, true, 'obj.view.handles');
            end
            % show the gui
            obj.view.gui.Visible = 'on';    % turn on the window 

            % add listener to obj.mibModel and call controller function as a callback
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{3} = addlistener(obj.mibModel, 'UpdateDialog', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        function closeWindow(obj)
            % CLOSEWINDOW - Close the BoundingBox window and release all listeners.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.closeWindow()
            %
            % Output Arguments:
            %   (none)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.BoundingBox.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end

            % delete listeners, otherwise they stay after deleting of the controller
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end

            notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh all widgets of the BoundingBox dialog from the current model state.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()
            %
            % Output Arguments:
            %   (none)
            %

            obj.BatchOpt.id = obj.mibModel.id;  % = obj.mibModel.getActiveId
            
            obj.bb = obj.mibModel.I{obj.BatchOpt.id}.image.boundingBox;
            obj.pixSize = obj.mibModel.I{obj.BatchOpt.id}.image.pixSize;
            obj.oldBB = obj.bb;

            obj.view.handles.BoundingBoxLabel.Text = ...
                sprintf('X: %g - %g\nY: %g - %g\nZ: %g - %g', ...
                obj.bb(1), obj.bb(2), obj.bb(3), obj.bb(4), obj.bb(5), obj.bb(6));
            obj.view.handles.pixSizeLabel.Text = sprintf('X: %g\nY: %g\nZ: %g', ...
                obj.pixSize.x, obj.pixSize.y, obj.pixSize.z);

            obj.view.handles.InfoLabel.Text = ...
                sprintf('To shift the bounding box it is enough to provide one set of numbers: minimal or central.\nUpdate of both minimal and maximal values results in change of pixel size!');

            % update numeric min fields
            obj.view.handles.Xmin.Value = num2str(obj.bb(1));
            obj.view.handles.Ymin.Value = num2str(obj.bb(3));
            obj.view.handles.Zmin.Value = num2str(obj.bb(5));

            % clear text (optional) fields
            obj.view.handles.Xcenter.Value = '';
            obj.view.handles.Ycenter.Value = '';
            obj.view.handles.Xmax.Value  = '';
            obj.view.handles.Ymax.Value  = '';
            obj.view.handles.Zmax.Value  = '';
            obj.view.handles.StageRotationBias.Value = '';

            % update BatchOpt structure to match current state
            obj.BatchOpt.Xmin = num2str(obj.bb(1));
            obj.BatchOpt.Ymin = num2str(obj.bb(3));
            obj.BatchOpt.Zmin = num2str(obj.bb(5));
            obj.BatchOpt.Xcenter = '';
            obj.BatchOpt.Ycenter = '';
            obj.BatchOpt.Xmax = '';
            obj.BatchOpt.Ymax = '';
            obj.BatchOpt.Zmax = '';
            obj.BatchOpt.StageRotationBias = '';

            % update GUI widgets using the provided BatchOpt
            obj.view = utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        function addCallbacks(obj)
            % ADDCALLBACKS - Assign ValueChanged/ButtonPushed callbacks to all interactive widgets.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addCallbacks()
            %
            % Called once from the constructor after the view is created.
            %
            % Output Arguments:
            %   (none)
            %

            % Hook the window X-button so it triggers the same cleanup as
            % the explicit Close button (deletes listeners, fires CloseEvent).
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();

            handles = obj.view.handles;

            % edit fields - keep BatchOpt in sync with every keystroke
            handles.Xmin.ValueChangedFcn             = @obj.updateBatchOptFromGUI;
            handles.Ymin.ValueChangedFcn             = @obj.updateBatchOptFromGUI;
            handles.Zmin.ValueChangedFcn             = @obj.updateBatchOptFromGUI;
            handles.Xcenter.ValueChangedFcn          = @obj.updateBatchOptFromGUI;
            handles.Ycenter.ValueChangedFcn          = @obj.updateBatchOptFromGUI;
            handles.Xmax.ValueChangedFcn             = @obj.updateBatchOptFromGUI;
            handles.Ymax.ValueChangedFcn             = @obj.updateBatchOptFromGUI;
            handles.Zmax.ValueChangedFcn             = @obj.updateBatchOptFromGUI;
            handles.StageRotationBias.ValueChangedFcn = @obj.updateBatchOptFromGUI;

            % buttons
            handles.importBtn.ButtonPushedFcn  = @(~,~) obj.importBtn_Callback;
            handles.helpButton.ButtonPushedFcn = @(~,~) obj.helpButton_Callback;
            handles.applyButton.ButtonPushedFcn = @(~,~) obj.applyButton_Callback;
            handles.closeButton.ButtonPushedFcn = @(~,~) obj.closeButton_Callback;
        end

        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Return the BatchOpt structure to the Batch controller via the SyncBatch event.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.returnBatchOpt()
            %      obj.returnBatchOpt(BatchOptOut)
            %
            % Input Arguments:
            %   - **BatchOptOut** - *(optional)* local structure with Batch Options
            %     generated during the Apply callback; may contain more fields than
            %     ``obj.BatchOpt``.  When omitted, ``obj.BatchOpt`` is used.
            %
            % Output Arguments:
            %   (none)
            %

            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end  % remove id field
            % trigger syncBatch event to send BatchOptOut to mibBatchController
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        function updateBatchOptFromGUI(obj, hObject, valueChangedData)
            % UPDATEBATCHOPTFROMGUI - Update ``obj.BatchOpt`` from a GUI widget value-change event.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateBatchOptFromGUI(hObject, valueChangedData)
            %
            % Delegates to ``utils.updateBatchOptFromGUI_Shared``, which is common
            % to all tools compatible with batch mode.
            %
            % Input Arguments:
            %   - **hObject** - handle to the widget that changed; in AppDesigner
            %     callbacks this is ``event.Source``
            %   - **valueChangedData** - ``EventData`` object passed by AppDesigner
            %     ``ValueChangedFcn`` callbacks (not used directly here)
            %
            % Output Arguments:
            %   (none)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.BoundingBox.updateBatchOptFromGUI(%s): triggered\n', hObject.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        function importBtn_Callback(obj, batchModeSw)
            % IMPORTBTN_CALLBACK - Import bounding box information from the system clipboard.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.importBtn_Callback()
            %      obj.importBtn_Callback(batchModeSw)
            %
            % The clipboard is expected to contain ``key = value`` pairs, one per
            % line, as exported by Amira / FEI microscope software.  Recognised
            % keys: ``ScaleX``, ``ScaleY``, ``ScaleZ``, ``xPos``, ``yPos``,
            % ``Z Position``, ``Rotation``.
            %
            % Input Arguments:
            %   - **batchModeSw** - *(optional)* logical, default: ``0``; set to
            %     ``1`` when called from batch mode to suppress GUI widget updates
            %
            % Output Arguments:
            %   (none)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.BoundingBox.importBtn_Callback: triggered\n');
            end
            if nargin < 2; batchModeSw = 0; end

            str = clipboard('paste');
            % Normalize line endings - Windows clipboard uses \r\n
            str = strrep(str, sprintf('\r\n'), sprintf('\n'));
            str = strrep(str, sprintf('\r'), sprintf('\n'));
            str = [str sprintf('\n')];  % guarantee last line has a terminator

            lineFeeds  = strfind(str, sprintf('\n')); %#ok<SPRINTFN>
            equalSigns = strfind(str, '=');

            switch obj.mibModel.I{obj.BatchOpt.id}.image.pixSize.units
                case 'm';  coef = 1e6;
                case 'cm'; coef = 1e4;
                case 'mm'; coef = 1e3;
                case 'um'; coef = 1;
                case 'nm'; coef = 1e-3;
                otherwise; coef = 1;
            end

            % read pixel size X
            pos = strfind(str, 'ScaleX');
            if ~isempty(pos)
                ScaleX = str2double(str(equalSigns(find(equalSigns > pos(1), 1))+1 : lineFeeds(find(lineFeeds > pos(1), 1))));
                if ~isnan(ScaleX)
                    obj.pixSize.x = ScaleX;
                    dx = (max([obj.mibModel.I{obj.BatchOpt.id}.image.width  2]) - 1) * obj.pixSize.x * coef;
                    obj.bb(2) = obj.bb(1) + dx;
                end
            end
            % read pixel size Y
            pos = strfind(str, 'ScaleY');
            if ~isempty(pos)
                ScaleY = str2double(str(equalSigns(find(equalSigns > pos(1), 1))+1 : lineFeeds(find(lineFeeds > pos(1), 1))));
                if ~isnan(ScaleY)
                    obj.pixSize.y = ScaleY;
                    dy = (max([obj.mibModel.I{obj.BatchOpt.id}.image.height 2]) - 1) * obj.pixSize.y * coef;
                    obj.bb(4) = obj.bb(3) + dy;
                end
            end
            % read pixel size Z
            pos = strfind(str, 'ScaleZ');
            if ~isempty(pos)
                ScaleZ = str2double(str(equalSigns(find(equalSigns > pos(1), 1))+1 : lineFeeds(find(lineFeeds > pos(1), 1))));
                if ~isnan(ScaleZ)
                    if ScaleZ == 0
                        obj.pixSize.z = obj.pixSize.x;
                    else
                        obj.pixSize.z = ScaleZ;
                    end
                    dz = (max([obj.mibModel.I{obj.BatchOpt.id}.image.depth  2]) - 1) * obj.pixSize.z * coef;
                    obj.bb(6) = obj.bb(5) + dz;
                end
            end

            % read center X
            pos = strfind(str, 'xPos');
            if ~isempty(pos)
                centerX = str2double(str(equalSigns(find(equalSigns > pos(1), 1))+1 : lineFeeds(find(lineFeeds > pos(1), 1))));
                if ~isnan(centerX)
                    obj.BatchOpt.Xcenter = num2str(centerX);
                    if batchModeSw == 0
                        obj.view.handles.Xcenter.Value = num2str(centerX);
                    end
                end
            end

            % read center Y
            pos = strfind(str, 'yPos');
            if ~isempty(pos)
                centerY = str2double(str(equalSigns(find(equalSigns > pos(1), 1))+1 : lineFeeds(find(lineFeeds > pos(1), 1))));
                if ~isnan(centerY)
                    obj.BatchOpt.Ycenter = num2str(centerY);
                    if batchModeSw == 0
                        obj.view.handles.Ycenter.Value = num2str(centerY);
                    end
                end
            end

            % read Z
            pos = strfind(str, 'Z Position');
            if ~isempty(pos)
                posZ = str2double(str(equalSigns(find(equalSigns > pos(1), 1))+1 : lineFeeds(find(lineFeeds > pos(1), 1))));
                if ~isnan(posZ)
                    obj.BatchOpt.Zmin = num2str(posZ);
                    if batchModeSw == 0
                        obj.view.handles.Zmin.Value = posZ;
                    end
                end
            end

            % read Rotation
            pos = strfind(str, 'Rotation');
            if ~isempty(pos)
                rotationVal = str2double(str(equalSigns(find(equalSigns > pos(1), 1))+1 : lineFeeds(find(lineFeeds > pos(1), 1))));
                if ~isnan(rotationVal)
                    obj.BatchOpt.StageRotationBias = num2str(45 - rotationVal);
                    if batchModeSw == 0
                        obj.view.handles.StageRotationBias.Value = num2str(45 - rotationVal);
                    end
                end
            end

            if batchModeSw == 0
                obj.view.handles.BoundingBoxLabel.Text = ...
                    sprintf('xmin-xmax: %g - %g\nymin-ymax: %g - %g\nzmin-zmax: %g - %g', ...
                    obj.bb(1), obj.bb(2), obj.bb(3), obj.bb(4), obj.bb(5), obj.bb(6));
                obj.view.handles.pixSizeLabel.Text = sprintf('X: %g\nY: %g\nZ: %g', ...
                    obj.pixSize.x, obj.pixSize.y, obj.pixSize.z);
            end
        end

        function applyButton_Callback(obj, batchModeSw)
            % APPLYBUTTON_CALLBACK - Apply the edited bounding box to the current dataset.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.applyButton_Callback()
            %      obj.applyButton_Callback(batchModeSw)
            %
            % When only ``Xmin``/``Ymin``/``Zmin`` are filled in, the bounding box
            % is shifted without changing voxel size.  When ``Xcenter``/``Ycenter``
            % are filled in, the dataset is positioned so that the given point
            % becomes the centre of the XY extent.  When ``Xmax``/``Ymax``/``Zmax``
            % are also supplied, the voxel size is recalculated from the total
            % extent.  ``StageRotationBias`` corrects for a known stage rotation
            % (e.g. for 3View systems at 45 deg).
            %
            % Input Arguments:
            %   - **batchModeSw** - *(optional)* logical, default: ``0``; set to
            %     ``1`` when called from batch mode to suppress GUI widget updates
            %
            % Output Arguments:
            %   (none)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.BoundingBox.applyButton_Callback: triggered\n');
            end
            if nargin < 2; batchModeSw = 0; end

            if batchModeSw == 0; drawnow; end  % needed to fix callback after the key press

            minX = str2double(obj.BatchOpt.Xmin);
            minY = str2double(obj.BatchOpt.Ymin);
            minZ = str2double(obj.BatchOpt.Zmin);
            meanX = str2double(obj.BatchOpt.Xcenter);
            meanY = str2double(obj.BatchOpt.Ycenter);
            maxX  = str2double(obj.BatchOpt.Xmax);
            maxY  = str2double(obj.BatchOpt.Ymax);
            maxZ  = str2double(obj.BatchOpt.Zmax);
            rotXY = str2double(obj.BatchOpt.StageRotationBias);

            if isempty(rotXY) || isnan(rotXY); rotXY = 0; end

            if isnan(meanX)     % use the min point
                xyzShift(1) = minX - obj.bb(1);
            else                % use the center point
                halfWidth = abs((obj.bb(2) - obj.bb(1)) / 2);
                if rotXY ~= 0
                    tempX = sqrt(meanX^2 + meanY^2) * cosd(atan2d(meanY, meanX) - rotXY);
                    xyzShift(1) = tempX - halfWidth - obj.bb(1);
                else
                    xyzShift(1) = meanX - halfWidth - obj.bb(1);
                end
            end

            if isnan(meanY)     % use the min point
                xyzShift(2) = minY - obj.bb(3);
            else                % use the center point
                halfHeight = abs((obj.bb(4) - obj.bb(3)) / 2);
                if rotXY ~= 0
                    tempY = sqrt(meanX^2 + meanY^2) * sind(atan2d(meanY, meanX) - rotXY);
                    xyzShift(2) = tempY - halfHeight - obj.bb(3);
                else
                    xyzShift(2) = meanY - halfHeight - obj.bb(3);
                end
            end

            xyzShift(3) = minZ - obj.bb(5);

            ds = obj.mibModel.I{obj.BatchOpt.id};
            newPixSize = ds.image.pixSize;
            newPixSize.x = obj.pixSize.x;
            newPixSize.y = obj.pixSize.y;
            newPixSize.z = obj.pixSize.z;

            if ~isnan(maxX)  % recalculate pixSize.x
                newPixSize.x = (maxX - minX) / (max([ds.image.width  2]) - 1);
            end
            if ~isnan(maxY)  % recalculate pixSize.y
                newPixSize.y = (maxY - minY) / (max([ds.image.height 2]) - 1);
            end
            if ~isnan(maxZ)  % recalculate pixSize.z
                newPixSize.z = (maxZ - minZ) / (max([ds.image.depth  2]) - 1);
            end

            newPixSize.units = 'um';
            ds.setPixSize(newPixSize);
            obj.mibModel.I{obj.BatchOpt.id}.updateBoundingBox();
            obj.mibModel.I{obj.BatchOpt.id}.updateBoundingBox([], xyzShift);

            notify(obj.mibModel, 'UpdateImgInfo');

            % Persist bounding box to zarr3 file for BigData datasets (after user confirmation)
            if batchModeSw == 0
                ds = obj.mibModel.I{obj.BatchOpt.id};
                if strcmp(ds.image.type, 'bigdata') && endsWith(lower(ds.image.filename), '.zarr3')
                    fmtVec = @(v) strjoin(arrayfun(@(x) sprintf('%.4g', x), v(:)', ...
                        'UniformOutput', false), ', ');
                    question = { ...
                        'The bounding box will be written to the zarr3 file on disk:'; ...
                        ''; ...
                        'Bounding box [Xmin Xmax Ymin Ymax Zmin Zmax]'; ...
                        sprintf('from:  %s', fmtVec(obj.bb)); ...
                        sprintf('to:      %s', fmtVec(ds.image.boundingBox)); ...
                        ''; ...
                        'Update the file now?'};
                    questOpts = struct('WindowHeight', 250, 'WindowWidth', 500);
                    answer = utils.dlgs.inputQuestDlg(obj.view.gui, question, ...
                        'Update zarr3 file?', 'Update', 'Cancel', 'Update', questOpts);
                    if strcmp(answer, 'Update')
                        io.savers.Zarr3Saver.patchMetadata( ...
                            ds.image.filename, ds.image.pixSize, ds.image.boundingBox);
                    end
                end
            end

            if batchModeSw == 0
                obj.updateWidgets();
            %else
            %    notify(obj.mibModel, 'UpdateGuiWidgets');
            end

            obj.returnBatchOpt(obj.BatchOpt);
        end

        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open the help page for the Bounding Box dialog in a browser.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.helpButton_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.BoundingBox.helpButton_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'dataset', 'dataset-bb.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/dataset/dataset-bb.html');

        end

        function closeButton_Callback(obj)
            % CLOSEBUTTON_CALLBACK - Close the dialog without applying changes.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.closeButton_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.BoundingBox.closeButton_Callback: triggered\n');
            end
            obj.closeWindow();
        end

    end
end
