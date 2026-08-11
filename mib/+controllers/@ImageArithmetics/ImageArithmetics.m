classdef ImageArithmetics < handle
    % IMAGEARITHMETICS - Controller for image arithmetic operations in MIB3.
    %
    % Drives custom arithmetic on one or several open datasets.
    % Available from MIB -> Ribbon -> Image -> Tools for Images -> Image Arithmetics.
    %
    % .. code-block:: matlab
    %
    %   obj.startController('ImageArithmetics');                          % GUI mode
    %   obj.startController('ImageArithmetics', [], BatchOpt);            % headless batch
    %   obj.startController('ImageArithmetics', [], NaN);                 % query defaults

    properties
        mibModel
        % handle to the model
        view
        % handle to the view (core.ChildView)
        listener
        % cell array with handles to listeners
        BatchOpt
        % batch-compatible options structure:
        % .InputVariables  - input variable list string (I, O, M, S, I2, ...)
        % .OutputVariables - output variable string
        % .Expression      - arithmetic expression to evaluate
        % .showWaitbar     - logical, show progress bar
    end

    events
        CloseEvent
        % fired when the window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Guard callback: clean up stale listeners if the view was closed.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      ImageArithmetics.ViewListner_Callback2(obj, src, evnt)
            %
            % If the view window is no longer valid (closed before the listener was
            % removed), deletes all listeners and returns silently.  Otherwise
            % dispatches to ``updateWidgets`` for the relevant events.
            %
            % Input Arguments:
            %   - **obj** - handle to the ImageArithmetics controller instance
            %   - **src** - event source (handle to MibModel); ignored
            %   - **evnt** - event data; ``evnt.EventName`` identifies the event
            %
            % Output Arguments:
            %   (none)
            %
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
        function obj = ImageArithmetics(mibModel, varargin)
            % IMAGEARITHMETICS - Create and open the Image Arithmetics dialog.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = ImageArithmetics(mibModel)
            %      obj = ImageArithmetics(mibModel, extraController)
            %      obj = ImageArithmetics(mibModel, [], BatchOpt)
            %      obj = ImageArithmetics(mibModel, [], NaN)
            %
            % Supports three operational modes:
            %
            % - **GUI mode** - ``(mibModel)`` or ``(mibModel, extra)``: creates and
            %   shows the AppDesigner dialog.
            % - **Batch mode** - ``(mibModel, [], BatchOpt)``: evaluates the
            %   expression in ``BatchOpt.Expression`` headlessly and returns.
            % - **Query mode** - ``(mibModel, [], NaN)``: fires ``SyncBatch`` with
            %   the default ``BatchOpt`` so the Batch controller can read available options.
            %
            % Input Arguments:
            %   - **mibModel** - handle to the MibModel instance
            %   - **varargin** - *(optional)* extra arguments:
            %
            %     - ``varargin{1}`` - extra controller handle (unused, pass ``[]``)
            %     - ``varargin{2}`` - BatchOpt struct for batch mode, or ``NaN`` for query mode
            %
            % Output Arguments:
            %   - **obj** - handle to the new ImageArithmetics instance
            %
            if isdeployed
                utils.dlgs.showErrorDialog([], ...
                    'Image Arithmetics is only available in the MATLAB version of MIB', ...
                    'Not available');
                return;
            end

            obj.mibModel = mibModel;

            %% BatchOpt defaults
            obj.BatchOpt.InputVariables  = 'I';
            obj.BatchOpt.OutputVariables = 'I';
            obj.BatchOpt.Expression      = 'I = I*1.5';
            obj.BatchOpt.showWaitbar     = true;
            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image';
            obj.BatchOpt.mibBatchActionName  = 'Tools for Images -> Image Arithmetics';
            obj.BatchOpt.mibBatchTooltip.InputVariables  = 'A list with input variables: I-image; O-model; M-mask; S-selection; I2-image from container 2, M3-mask from container 3; if number is omitted, the currently selected container is used';
            obj.BatchOpt.mibBatchTooltip.OutputVariables = 'Output variable: I-image; O-model; M-mask; S-selection; I2-to container 2, M3-mask to container 3';
            obj.BatchOpt.mibBatchTooltip.Expression      = 'String with an arithmetic expression to execute, see help of the tool for details';
            obj.BatchOpt.mibBatchTooltip.showWaitbar     = 'Show or not the progress bar during execution';

            %% Virtual stacking guard
            activeId = obj.mibModel.getActiveId();
            if isprop(obj.mibModel.I{activeId}, 'Virtual') && obj.mibModel.I{activeId}.Virtual.virtual == 1
                dlgOpt.MsgBoxOnly  = true;
                dlgOpt.Icon        = 'puffin_warning';
                dlgOpt.HeaderLines = 1;
                utils.dlgs.inputUniversalDlg([], '!!! Warning !!!', {''}, ...
                    {'Image Arithmetic is not compatible with the virtual stacking mode! Please switch to the memory-resident mode and try again.'}, ...
                    'Not implemented', dlgOpt);
                obj.closeWindow();
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            %% Batch dispatch
            if nargin == 3
                BatchOptInput = varargin{2};
                if ~isstruct(BatchOptInput)
                    if isnan(BatchOptInput)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'BatchOpt Error');
                    end
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptInput);
                obj.runExpressionBtn_Callback();
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.ImageArithmeticsGUI');
            obj.addCallbacks();

            % Populate editable widgets
            obj.view.handles.InputVariables.Value  = obj.BatchOpt.InputVariables;
            obj.view.handles.OutputVariables.Value = obj.BatchOpt.OutputVariables;
            obj.view.handles.prevExpPopup.Items    = cellfun( ...
                @(x) strrep(x, newline, ''), ...
                obj.mibModel.preferences.ImageArithmetic.Actions, 'UniformOutput', false);
            obj.view.handles.Expression.Value      = strsplit(obj.BatchOpt.Expression, newline);

            % Static informational labels
            obj.view.handles.infoText.Text = sprintf(['Enter an arithmetic expression.\nImages are referred as "I", models as "O", ' ...
                'masks as "M", selection as "S".\nWhen letter is supplemented with a number, ' ...
                'that number indicates MIB container (e.g. I4 -> take image from container 4). ' ...
                'If number is omitted, the currently selected container is used.']);
            obj.view.handles.examplesText.Value = sprintf([ ...
                '"I = I * 2" - multiply current image by 2\n' ...
                '"I2 = I2 + 50" - increase image in container 2 by 50\n' ...
                '"I1 = I1 + I2" - add image 2 to image 1\n' ...
                '"I1=I1-min(I1(:))" - shift image 1 by its minimum value\n' ...
                '"I1=I1+uint8(randi(20,size(I1)))" - add random noise\n' ...
                '"I1(M1==1) = 0" - replace masked area in image 1 with 0']);

            % Font size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.infoText.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.infoText.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end
            obj.view.handles.Expression.FontSize = Font.FontSize + 2;

            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.view.gui.Visible = true;
        end

        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks; called once from the constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.addCallbacks()
            %
            % Sets ``CloseRequestFcn`` on the figure first, then assigns
            % ``ValueChangedFcn`` / ``ButtonPushedFcn`` to every interactive widget.
            %
            % Output Arguments:
            %   (none)
            %
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            handles = obj.view.handles;
            handles.InputVariables.ValueChangedFcn   = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            handles.OutputVariables.ValueChangedFcn  = @(hObj,~) obj.updateBatchOptFromGUI(hObj);
            handles.Expression.ValueChangedFcn       = @(hObj,~) obj.Expression_ValueChangedFcn(hObj);
            handles.prevExpPopup.ValueChangedFcn     = @(~,~) obj.prevExpPopup_Callback();
            handles.runExpressionBtn.ButtonPushedFcn = @(~,~) obj.runExpressionBtn_Callback();
            handles.closeBtn.ButtonPushedFcn         = @(~,~) obj.closeWindow();
            handles.helpBtn.ButtonPushedFcn          = @(~,~) obj.helpBtn_Callback();
        end

        function closeWindow(obj)
            % CLOSEWINDOW - Delete the dialog window and release all listeners.
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
                fprintf('controllers.ImageArithmetics.closeWindow: triggered\n');
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
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
            %   - **BatchOptOut** - *(optional)* local BatchOpt structure generated
            %     during the run callback; may contain more fields than ``obj.BatchOpt``.
            %     When omitted, ``obj.BatchOpt`` is used.
            %
            % Output Arguments:
            %   (none)
            %
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        function updateBatchOptFromGUI(obj, hObject)
            % UPDATEBATCHOPTFROMGUI - Update ``obj.BatchOpt`` from a GUI widget value-change event.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateBatchOptFromGUI(hObject)
            %
            % Delegates to ``utils.updateBatchOptFromGUI_Shared``, which is common
            % to all batch-compatible tools.
            %
            % Input Arguments:
            %   - **hObject** - handle to the widget that changed; in AppDesigner
            %     callbacks this is the event source (``event.Source``)
            %
            % Output Arguments:
            %   (none)
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageArithmetics.updateBatchOptFromGUI(%s): triggered\n', hObject.Tag);
            end
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        function updateWidgets(~)
            % UPDATEWIDGETS - Refresh dialog widgets from the current model state.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()
            %
            % This dialog has no model-driven widgets beyond what the constructor
            % populates, so the method is intentionally empty.
            %
            % Output Arguments:
            %   (none)
            %
        end

        function Expression_ValueChangedFcn(obj, hObject)
            % EXPRESSION_VALUECHANGEDFCN - Sync the Expression textarea value to BatchOpt.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.Expression_ValueChangedFcn(hObject)
            %
            % ``uitextarea.Value`` is a cell array of lines; joins them with
            % newlines before storing in ``obj.BatchOpt.Expression``.
            %
            % Input Arguments:
            %   - **hObject** - handle to the ``Expression`` uitextarea widget
            %
            % Output Arguments:
            %   (none)
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageArithmetics.Expression_ValueChangedFcn: triggered\n');
            end
            obj.BatchOpt.Expression = strjoin(hObject.Value, newline);
        end

        function prevExpPopup_Callback(obj)
            % PREVEXPPOPUP_CALLBACK - Restore a previously used expression from the history dropdown.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.prevExpPopup_Callback()
            %
            % The dropdown displays newline-stripped versions of stored expressions.
            % On selection the matching full expression (with embedded newlines) is
            % retrieved from ``preferences.ImageArithmetic.Actions`` and written back
            % to the Expression textarea and the BatchOpt fields.
            %
            % Output Arguments:
            %   (none)
            %
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageArithmetics.prevExpPopup_Callback: triggered\n');
            end
            displayItems = obj.view.handles.prevExpPopup.Items;
            displayValue = obj.view.handles.prevExpPopup.Value;
            idx = find(strcmp(displayItems, displayValue), 1);
            if isempty(idx); return; end
            selectedExpression = obj.mibModel.preferences.ImageArithmetic.Actions{idx};
            obj.BatchOpt.Expression      = selectedExpression;
            obj.view.handles.Expression.Value      = strsplit(selectedExpression, newline);
            obj.view.handles.InputVariables.Value  = obj.mibModel.preferences.ImageArithmetic.InputVars{idx};
            obj.BatchOpt.InputVariables            = obj.view.handles.InputVariables.Value;
            obj.view.handles.OutputVariables.Value = obj.mibModel.preferences.ImageArithmetic.OutputVars{idx};
            obj.BatchOpt.OutputVariables           = obj.view.handles.OutputVariables.Value;
        end

        function helpBtn_Callback(obj)
            % HELPBTN_CALLBACK - Open the Image Arithmetics help page in a browser.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.helpBtn_Callback()
            %
            % Output Arguments:
            %   (none)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageArithmetics.helpBtn_Callback: triggered\n');
            end
            helpFilPath = fullfile(fileparts(obj.mibModel.mibPath), 'docs', 'html', 'user-interface', 'ribbon', 'image', 'image-tools-arithmetic.html');
            utils.openHelpPage(helpFilPath, ...
                'http://mib.helsinki.fi/help/main3/user-interface/ribbon/image/image-tools-arithmetic.html');
        end

        function runExpressionBtn_Callback(obj)
            % RUNEXPRESSIONBTN_CALLBACK - Evaluate the arithmetic expression and write the result.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.runExpressionBtn_Callback()
            %
            % Operates in both GUI and headless batch mode.  Steps:
            %
            % 1. Parse ``BatchOpt.InputVariables`` and fetch each dataset via
            %    ``mibModel.getData4D`` into workspace variables (``I``, ``O``,
            %    ``M``, ``S``, ``I2``, etc.).
            % 2. Evaluate ``BatchOpt.Expression`` with ``eval`` and pick up the
            %    resulting variable named in ``BatchOpt.OutputVariables``.
            % 3. Write the result back via
            %    ``mibModel.setData4D``.  When the target container differs from the
            %    source, a new ``core.MibDataset`` is created and ``NewDataset`` is fired.
            % 4. Store the expression in ``preferences.ImageArithmetic`` history and
            %    fire ``SyncBatch``.
            %
            % Output Arguments:
            %   (none)
            %
            % Set up progress bar (works in both GUI and headless mode)
            
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageArithmetics.runExpressionBtn_Callback: triggered\n');
            end
            if isempty(obj.view)   % headless batch mode
                parentFigure = obj.mibModel.mibGUI;
            else
                parentFigure = obj.view.gui;
            end

            if obj.BatchOpt.showWaitbar
                pwb = core.PoolWaitbar(10, ...
                    sprintf('Performing:\n%s\nPlease wait...', obj.BatchOpt.Expression), ...
                    parentFigure, 'Image arithmetics', true);
            end

            % Suppress spurious warnings from blank spaces in expressions
            origState = warning;
            warning('off');

            % Obtain input datasets
            obtainedDatasets = {};
            getDataOptions.blockModeSwitch = 0;
            activeId = obj.mibModel.getActiveId();
            getDataOptions.id = activeId;   % fallback when InputVariables is empty

            for chId = 1:numel(obj.BatchOpt.InputVariables)
                switch obj.BatchOpt.InputVariables(chId)
                    case 'I';    inputType = 'image';
                    case 'O';    inputType = 'labels';
                    case 'M';    inputType = 'mask';
                    case 'S';    inputType = 'selection';
                    otherwise;   continue;
                end
                datasetInputString = obj.BatchOpt.InputVariables(chId);
                getDataOptions.id  = activeId;
                if chId < numel(obj.BatchOpt.InputVariables)
                    if ~isnan(str2double(obj.BatchOpt.InputVariables(chId+1)))
                        getDataOptions.id  = str2double(obj.BatchOpt.InputVariables(chId+1));
                        datasetInputString = [datasetInputString num2str(getDataOptions.id)]; %#ok<AGROW>
                    end
                end
                if ismember(datasetInputString, obtainedDatasets); continue; end
                obtainedDatasets = [obtainedDatasets; {datasetInputString}]; %#ok<AGROW>

                execString = sprintf('%s = cell2mat(obj.mibModel.getData4D(''%s'', 3, NaN, getDataOptions));', ...
                    datasetInputString, inputType);
                try
                    eval(execString);
                catch err
                    warning(origState);
                    if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                    notify(obj.mibModel, 'StopProtocol');
                    utils.dlgs.showErrorDialog(parentFigure, ...
                        sprintf('Error in getData4D with input string: %s and type: %s!\n\nIdentifier: %s\nMessage: %s', ...
                        datasetInputString, inputType, err.identifier, err.message), 'Wrong parameters');
                    return;
                end
            end

            warning(origState);
            if obj.BatchOpt.showWaitbar; pwb.increment(); end   % step 1/10

            % Determine output variable and type
            obj.BatchOpt.OutputVariables = strtrim(obj.BatchOpt.OutputVariables);
            if ~isempty(obj.BatchOpt.OutputVariables)
                switch obj.BatchOpt.OutputVariables(1)
                    case 'I';    outputType = 'image';
                    case 'O';    outputType = 'labels';
                    case 'M';    outputType = 'mask';
                    case 'S';    outputType = 'selection';
                    otherwise
                        if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                        utils.dlgs.showErrorDialog(parentFigure, ...
                            sprintf('!!! Error !!!\n\nWrong output variable:\n%s', obj.BatchOpt.OutputVariables), 'Error');
                        notify(obj.mibModel, 'StopProtocol');
                        return;
                end
                setDataOptions.id             = activeId;
                setDataOptions.blockModeSwitch = 0;
                datasetOutputString = obj.BatchOpt.OutputVariables(1);
                if numel(obj.BatchOpt.OutputVariables) > 1
                    if ~isnan(str2double(obj.BatchOpt.OutputVariables(2)))
                        setDataOptions.id   = str2double(obj.BatchOpt.OutputVariables(2));
                        datasetOutputString = [datasetOutputString obj.BatchOpt.OutputVariables(2)];
                    end
                end
            end

            if obj.BatchOpt.showWaitbar; pwb.increment(); end   % step 2/10

            % Evaluate the expression
            try
                eval(sprintf('%s;', obj.BatchOpt.Expression));
            catch err
                if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                notify(obj.mibModel, 'StopProtocol');
                utils.dlgs.showErrorDialog(parentFigure, ...
                    sprintf('!!! Error !!!\n\nWrong expression!\n%s\nPlease try again!', err.message), 'Error');
                return;
            end

            if obj.BatchOpt.showWaitbar; pwb.increment(); end   % step 3/10

            % If no output variable, just store expression and return
            if isempty(obj.BatchOpt.OutputVariables)
                obj.storeExpressionInHistory_();
                if obj.BatchOpt.showWaitbar
                    for k = 4:10; pwb.increment(); end
                    pwb.deletePoolWaitbar();
                end
                return;
            end

            % Fetch the evaluated result from the local workspace; the expression
            % was evaluated with eval() so the output variable (I, I2, M3, ...)
            % lives here under the name in datasetOutputString
            if ~exist(datasetOutputString, 'var')
                if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                notify(obj.mibModel, 'StopProtocol');
                utils.dlgs.showErrorDialog(parentFigure, ...
                    sprintf(['!!! Error !!!\n\nThe expression did not produce the output variable "%s"!\n\n' ...
                    'Make sure that the expression assigns a result to %s.'], ...
                    datasetOutputString, datasetOutputString), 'Error');
                return;
            end
            outputArray = eval(datasetOutputString);

            % MIB stores images as integer classes only; a floating-point result
            % (e.g. from "I2 = double(I1)./2") would break dataset initialization
            if strcmp(outputType, 'image') && ~isinteger(outputArray)
                if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                notify(obj.mibModel, 'StopProtocol');
                utils.dlgs.showErrorDialog(parentFigure, ...
                    sprintf(['!!! Error !!!\n\nThe expression produced a "%s" result, but images must be ' ...
                    'an integer class (uint8, uint16, uint32).\n\nCast the result explicitly, for example:\n%s = uint8(...);'], ...
                    class(outputArray), datasetOutputString), 'Error');
                return;
            end

            % Check cancel before the irreversible write
            if obj.BatchOpt.showWaitbar && pwb.getCancelState()
                pwb.deletePoolWaitbar();
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            if obj.BatchOpt.showWaitbar; pwb.increment(); end   % step 4/10

            if ~isempty(obj.view)   % skip backup in headless batch mode
                obj.mibModel.backup(outputType, 1, setDataOptions);
            end

            if obj.BatchOpt.showWaitbar; pwb.increment(); end   % step 5/10

            switch outputType
                case 'image'
                    if setDataOptions.id == activeId
                        setDataOptions.replaceDatasetSwitch = 1;
                        % Reinitialize labels if image dimensions changed.
                        % Both image and labels data are [H, W, Z, C, T], so
                        % the spatial+time dimensions to compare are [1 2 3 5]
                        labelsData = obj.mibModel.I{setDataOptions.id}.labels.data;
                        if ~isequal(size(outputArray, [1 2 3 5]), size(labelsData, [1 2 3 5]))
                            setDataOptions.keepModel = 0;
                        end
                        try
                            obj.mibModel.setData4D(outputArray, outputType, 3, NaN, setDataOptions);
                        catch err
                            if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                            utils.dlgs.showErrorDialog(parentFigure, ...
                                sprintf('Error in setData4D with %s!\n\nIdentifier: %s\nMessage: %s', ...
                                outputType, err.identifier, err.message), 'Wrong parameters');
                            notify(obj.mibModel, 'StopProtocol');
                            return;
                        end
                        notify(obj.mibModel, 'UpdateGuiWidgets');
                    else
                        meta = obj.mibModel.I{getDataOptions.id}.image.getMeta();
                        try
                            % meta is a dictionary with a 'cell' value type, so values
                            % must be assigned with brace indexing: meta{'key'} = value
                            outputClass = class(outputArray);
                            [outputHeight, outputWidth, outputDepth, outputColors, outputTime] = size(outputArray);
                            meta{'imgClass'} = outputClass;
                            meta{'MaxInt'}   = double(intmax(outputClass));
                            % MIB3 image data is [height, width, depth, colors, time]
                            meta{'Height'} = outputHeight;
                            meta{'Width'}  = outputWidth;
                            meta{'Depth'}  = outputDepth;
                            meta{'Colors'} = outputColors;
                            meta{'Time'}   = outputTime;
                            % drop per-slice metadata inherited from the source container
                            % when the new dataset has a different number of slices/channels
                            if numel(meta{'SliceName'}) ~= outputDepth
                                meta{'SliceName'} = [];
                                meta{'SliceSize'} = [];
                            end
                            if isKey(meta, 'lutColors') && size(meta{'lutColors'}, 1) ~= outputColors
                                meta{'lutColors'} = utils.defaults.generateLUT(outputColors);
                            end
                            % MibImage.initialize() upgrades grayscale -> multichannel but never
                            % the other way round, so downgrade an inherited multichannel type here
                            if outputColors == 1 && strcmp(meta{'ColorType'}, 'multichannel')
                                meta{'ColorType'} = 'grayscale';
                            end
                            obj.mibModel.I{setDataOptions.id} = core.MibDataset(outputArray, meta, 'Standard', 'labels63');
                            % keep Sets.datasetTypes in sync, otherwise the dataset-type
                            % dropdown still shows Virtual/BigData for the destination
                            targetSet     = floor((setDataOptions.id - 1) / obj.mibModel.Sets.datasetsInSet) + 1;
                            targetLocalId = mod(setDataOptions.id - 1, obj.mibModel.Sets.datasetsInSet) + 1;
                            obj.mibModel.Sets.datasetTypes{targetSet, targetLocalId} = ...
                                obj.mibModel.I{setDataOptions.id}.datasetType;
                        catch err
                            if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                            utils.dlgs.showErrorDialog(parentFigure, ...
                                sprintf('Error creating dataset in container %d!\n\nIdentifier: %s\nMessage: %s', ...
                                setDataOptions.id, err.identifier, err.message), 'Wrong parameters');
                            notify(obj.mibModel, 'StopProtocol');
                            return;
                        end
                        % listener_newDataset expects a struct with .index; passing a
                        % bare id makes it fall into the no-index branch and error out,
                        % skipping both the fit-to-screen and the Datasets panel refresh
                        notify(obj.mibModel, 'NewDataset', ...
                            core.ToggleEventData(struct('index', setDataOptions.id)));
                    end
                    obj.mibModel.I{setDataOptions.id}.image.updateActionLog('Image Arithmetics operation applied');

                case 'labels'
                    try
                        obj.mibModel.setData4D(outputArray, outputType, 3, NaN, setDataOptions);
                    catch err
                        if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                        utils.dlgs.showErrorDialog(parentFigure, ...
                            sprintf('Error in setData4D with %s!\n\nIdentifier: %s\nMessage: %s', ...
                            outputType, err.identifier, err.message), 'Wrong parameters');
                        notify(obj.mibModel, 'StopProtocol');
                        return;
                    end
                    obj.mibModel.I{setDataOptions.id}.labels.materialNames  = obj.mibModel.I{getDataOptions.id}.labels.materialNames;
                    obj.mibModel.I{setDataOptions.id}.labels.materialColors = obj.mibModel.I{getDataOptions.id}.labels.materialColors;
                    notify(obj.mibModel, 'UpdateGuiWidgets');

                otherwise  % mask, selection
                    try
                        obj.mibModel.setData4D(outputArray, outputType, 3, NaN, setDataOptions);
                    catch err
                        if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                        utils.dlgs.showErrorDialog(parentFigure, ...
                            sprintf('Error in setData4D with %s!\n\nIdentifier: %s\nMessage: %s', ...
                            outputType, err.identifier, err.message), 'Wrong parameters');
                        notify(obj.mibModel, 'StopProtocol');
                        return;
                    end
                    notify(obj.mibModel, 'UpdateGuiWidgets');
            end

            if obj.BatchOpt.showWaitbar; pwb.increment(); end   % step 6/10

            obj.storeExpressionInHistory_();

            if obj.BatchOpt.showWaitbar
                for k = 7:10; pwb.increment(); end
                pwb.deletePoolWaitbar();
            end

            notify(obj.mibModel, 'ShowImage');
            obj.returnBatchOpt(obj.BatchOpt);
        end
    end

    methods (Access = private)
        function storeExpressionInHistory_(obj)
            % STOREEXPRESSIONINHISTORY_ - Append the current expression to the stored history.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.storeExpressionInHistory_()
            %
            % If the expression is already present in
            % ``preferences.ImageArithmetic.Actions`` it is not duplicated.  When the
            % history exceeds ``NoStoredActions`` the oldest entry is dropped.
            % Refreshes the ``prevExpPopup`` dropdown when the GUI is open.
            %
            % Output Arguments:
            %   (none)
            %
            if ismember(obj.BatchOpt.Expression, obj.mibModel.preferences.ImageArithmetic.Actions)
                return;
            end
            obj.mibModel.preferences.ImageArithmetic.Actions(end+1)    = {obj.BatchOpt.Expression};
            obj.mibModel.preferences.ImageArithmetic.OutputVars(end+1) = {obj.BatchOpt.OutputVariables};
            obj.mibModel.preferences.ImageArithmetic.InputVars(end+1)  = {obj.BatchOpt.InputVariables};
            maxStored = obj.mibModel.preferences.ImageArithmetic.NoStoredActions;
            if numel(obj.mibModel.preferences.ImageArithmetic.Actions) > maxStored
                obj.mibModel.preferences.ImageArithmetic.Actions    = obj.mibModel.preferences.ImageArithmetic.Actions(2:end);
                obj.mibModel.preferences.ImageArithmetic.OutputVars = obj.mibModel.preferences.ImageArithmetic.OutputVars(2:end);
                obj.mibModel.preferences.ImageArithmetic.InputVars  = obj.mibModel.preferences.ImageArithmetic.InputVars(2:end);
            end
            if ~isempty(obj.view) && isvalid(obj.view.gui)
                obj.view.handles.prevExpPopup.Items = cellfun( ...
                    @(x) strrep(x, newline, ''), ...
                    obj.mibModel.preferences.ImageArithmetic.Actions, 'UniformOutput', false);
                obj.view.handles.prevExpPopup.Value = obj.view.handles.prevExpPopup.Items{end};
            end
        end
    end
end
