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
        % .id              - index of the active dataset, refreshed from getActiveId at each run
        % .BigData_*       - output options for a BigData dataset, see controllers.BigDataOptions
        bigDataOptions
        % controllers.BigDataOptions - BigData_* BatchOpt fields, the BigData output panel and the BigData run
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
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            % BigData: the expression is evaluated band by band into a new store,
            % or into the mask / selection of the model (BigData_* fields, ignored otherwise).
            % The buffers the expression names are checked at each run, not here:
            % the active buffer can change while the dialog is open
            obj.bigDataOptions = controllers.BigDataOptions(obj, 'arithmetics');
            obj.BatchOpt = obj.bigDataOptions.addBatchOptFields(obj.BatchOpt);
            obj.bigDataOptions.ModelOutput = obj.isModelOutput_();

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
            utils.applyThemeColors(obj.view.gui);   % adapt the standard dialog button colors to the light/dark theme
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
            obj.updateWidgets();   % adds the BigData output panel for a BigData dataset

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
            if strcmp(hObject.Tag, 'OutputVariables')
                obj.bigDataOptions.setModelOutput(obj.isModelOutput_());
            end
        end

        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh dialog widgets from the current model state.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()
            %
            % Follows the active dataset: ``BatchOpt.id`` is refreshed and the
            % BigData output panel is shown for a BigData dataset and removed
            % otherwise (``controllers.BigDataOptions.updateWidgets``). The other
            % widgets do not depend on the dataset.
            %
            % Output Arguments:
            %   (none)
            %
            obj.BatchOpt.id = obj.mibModel.getActiveId();
            obj.bigDataOptions.updateWidgets();
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
            obj.bigDataOptions.setModelOutput(obj.isModelOutput_());
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
            % 1. Parse ``BatchOpt.InputVariables`` and ``BatchOpt.OutputVariables``
            %    (``parseVariables_``). When the active dataset is BigData, the
            %    expression is evaluated band by band instead (``runExpressionBigData_``)
            %    and the steps below do not apply.
            % 2. Refuse a Virtual or BigData buffer named by the expression: their
            %    layers are read on demand, so ``getData4D`` would read the whole
            %    volume at full resolution, and a BigData image is read-only. Every
            %    buffer is checked, not only the active one (``I2``, ``M3``...). An
            %    image result for another buffer is allowed whatever that buffer
            %    holds, because it replaces the buffer with a new Standard dataset.
            % 3. Fetch each input via ``mibModel.getData4D`` into workspace
            %    variables (``I``, ``O``, ``M``, ``S``, ``I2``, etc.); an image is
            %    ``[height, width, depth, colors]``, the other layers
            %    ``[height, width, depth]``.
            % 4. Evaluate ``BatchOpt.Expression`` with ``eval`` and pick up the
            %    resulting variable named in ``BatchOpt.OutputVariables``.
            % 5. Write the result back via
            %    ``mibModel.setData4D``.  When the target container differs from the
            %    source, a new ``core.MibDataset`` is created and ``NewDataset`` is fired.
            % 6. Store the expression in ``preferences.ImageArithmetic`` history and
            %    fire ``SyncBatch``.
            %
            % A refused buffer is reported in a dialog, or raised as
            % ``controllers:ImageArithmetics:datasetType`` when there is no
            % window to show it in, so a headless run never reports success.
            %
            % Output Arguments:
            %   (none)
            %

            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.ImageArithmetics.runExpressionBtn_Callback: triggered\n');
            end
            if isempty(obj.view)   % headless batch mode
                parentFigure = obj.mibModel.mibGUI;
            else
                parentFigure = obj.view.gui;
            end
            activeId = obj.mibModel.getActiveId();
            obj.BatchOpt.id = activeId;

            % Parse the variables
            inputVariables = obj.parseVariables_(obj.BatchOpt.InputVariables, activeId);
            obj.BatchOpt.OutputVariables = strtrim(obj.BatchOpt.OutputVariables);
            outputVariable = [];
            if ~isempty(obj.BatchOpt.OutputVariables)
                % only the first variable counts, as a letter with an optional buffer digit
                outputVariable = obj.parseVariables_(obj.BatchOpt.OutputVariables(1:min(2, end)), activeId);
                if isempty(outputVariable) || ~strcmp(outputVariable(1).name(1), obj.BatchOpt.OutputVariables(1))
                    utils.dlgs.showErrorDialog(parentFigure, ...
                        sprintf('!!! Error !!!\n\nWrong output variable:\n%s', obj.BatchOpt.OutputVariables), 'Error');
                    notify(obj.mibModel, 'StopProtocol');
                    return;
                end
                outputVariable = outputVariable(1);
            end

            if strcmp(obj.mibModel.I{activeId}.datasetType, 'BigData')
                obj.runExpressionBigData_(inputVariables, outputVariable, parentFigure);
                return;
            end

            % Refuse the Virtual and BigData buffers the expression names
            namedVariables = inputVariables;
            if ~isempty(outputVariable) && ~(strcmp(outputVariable.type, 'image') && outputVariable.id ~= activeId)
                namedVariables = [namedVariables, outputVariable];
            end
            for variable = namedVariables
                % a buffer that does not exist is reported by getData4D / setData4D below
                if variable.id > numel(obj.mibModel.I); continue; end
                datasetType = obj.mibModel.I{variable.id}.datasetType;
                if ~strcmp(datasetType, 'Standard')
                    obj.reportError_(parentFigure, 'controllers:ImageArithmetics:datasetType', sprintf( ...
                        ['%s refers to buffer %d, which holds a %s dataset.\n\nImage Arithmetics reads and writes ' ...
                        'the whole dataset in memory, so it needs memory-resident (Standard) datasets. ' ...
                        'A BigData dataset can be processed when it is the active one, with only "I" as input.'], ...
                        variable.name, variable.id, datasetType));
                    return;
                end
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
            getDataOptions.blockModeSwitch = 0;
            getDataOptions.id = activeId;   % fallback when InputVariables is empty
            for variable = inputVariables
                getDataOptions.id = variable.id;
                execString = sprintf('%s = cell2mat(obj.mibModel.getData4D(''%s'', 3, NaN, getDataOptions));', ...
                    variable.name, variable.type);
                try
                    eval(execString);
                catch err
                    warning(origState);
                    if obj.BatchOpt.showWaitbar; pwb.deletePoolWaitbar(); end
                    notify(obj.mibModel, 'StopProtocol');
                    utils.dlgs.showErrorDialog(parentFigure, ...
                        sprintf('Error in getData4D with input string: %s and type: %s!\n\nIdentifier: %s\nMessage: %s', ...
                        variable.name, variable.type, err.identifier, err.message), 'Wrong parameters');
                    return;
                end
            end

            warning(origState);
            if obj.BatchOpt.showWaitbar; pwb.increment(); end   % step 1/10

            % Output variable and type
            if ~isempty(outputVariable)
                outputType = outputVariable.type;
                datasetOutputString = outputVariable.name;
                setDataOptions.id = outputVariable.id;
                setDataOptions.blockModeSwitch = 0;
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

            % count user's points
            obj.mibModel.preferences.Users.Tiers.numberOfImageArithmetics = obj.mibModel.preferences.Users.Tiers.numberOfImageArithmetics + 1;
            notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));    % scale scoring by factor 2

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

        function modelOutput = isModelOutput_(obj)
            % ISMODELOUTPUT_ - True when the output variable is a mask or selection (``M``, ``S``...).
            %
            % Decides what the BigData output panel offers: a mask or selection
            % result goes into the model (only the level applies), anything else
            % to a new store.
            outputString = strtrim(obj.BatchOpt.OutputVariables);
            modelOutput = ~isempty(outputString) && any(outputString(1) == 'MS');
        end

        function runExpressionBigData_(obj, inputVariables, outputVariable, parentFigure)
            % RUNEXPRESSIONBIGDATA_ - Evaluate the expression on a BigData dataset, band by band.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.runExpressionBigData_(inputVariables, outputVariable, parentFigure)
            %
            % The image of a BigData dataset does not fit in memory and is
            % read-only, so the expression is evaluated on one band of rows at a
            % time, read at level ``BatchOpt.BigData_PyramidLevel``
            % (``io.savers.FilteredSliceProvider``):
            %
            % - an image result (``I``) is written to a new OME-Zarr store,
            %   or replaces the store with ``Current overwrite (BigData)``
            %   (``controllers.BigDataOptions.run``);
            % - a mask or selection result (``M``, ``S``) replaces that layer of
            %   the model, non-zero = set, no undo
            %   (``controllers.BigDataOptions.runToModel``).
            %
            % The whole dataset is processed. Each input variable holds the band
            % as ``[rows, width, 1, colors]``, the layout of an image of
            % ``getData4D`` with one slice, so channel indexing
            % ``I(:,:,:,2)`` means the same as on a Standard dataset.
            %
            % **Allowed variables.** Inputs: the image of this dataset only
            % (``I`` or ``I<id>``); reading another buffer or a model layer band
            % by band is not implemented. Output: the image, mask or selection of
            % this dataset; the buffer of an image result is chosen in Open in, so
            % ``I<n>`` of another buffer is refused rather than reinterpreted.
            %
            % **Band-wise check.** A band gives the whole-image result only when
            % the expression is pointwise along Y and Z. Before any data is read,
            % ``checkBandwise_`` evaluates the expression on a test block and on
            % its four quarters (two row halves, two slices) and refuses it when
            % the results differ: a statistic of the whole image
            % (``min(I(:))``, ``mean``), a flip or shift in Y or Z, row indices,
            % random numbers. Operations along X and between channels pass,
            % because a band holds whole rows and all channels.
            %
            % Errors are shown in a dialog, or raised as
            % ``controllers:ImageArithmetics:bigData`` when there is no window
            % (headless), so a failed run never reports success.
            %
            % Input Arguments:
            %   - **inputVariables** - struct array from ``parseVariables_``
            %   - **outputVariable** - struct from ``parseVariables_``, ``[]`` when none
            %   - **parentFigure** - window for the dialogs, ``[]`` when headless
            errorId = 'controllers:ImageArithmetics:bigData';
            activeId = obj.BatchOpt.id;
            dataset = obj.mibModel.I{activeId};
            if isempty(inputVariables)
                obj.reportError_(parentFigure, errorId, ...
                    'Please name the image of this dataset in Input variables, for example "I".');
                return;
            end
            for variable = inputVariables
                if ~strcmp(variable.type, 'image') || variable.id ~= activeId
                    obj.reportError_(parentFigure, errorId, sprintf(['On a BigData dataset the expression can read ' ...
                        'only the image of this dataset ("I" or "I%d"); "%s" is not available.'], activeId, variable.name));
                    return;
                end
            end
            if isempty(outputVariable)
                obj.reportError_(parentFigure, errorId, ['Please give an Output variable: on a BigData dataset the ' ...
                    'result is written to a new store ("I"), or to the mask ("M") or selection ("S").']);
                return;
            end
            if outputVariable.id ~= activeId
                obj.reportError_(parentFigure, errorId, sprintf(['On a BigData dataset the result belongs to this dataset: ' ...
                    'use "%s" as the Output variable. An image result is opened in the buffer chosen in "Open in".'], ...
                    outputVariable.name(1)));
                return;
            end
            if strcmp(outputVariable.type, 'labels')
                obj.reportError_(parentFigure, errorId, ['The model ("O") is not available as the output on a BigData ' ...
                    'dataset; use the image ("I"), the mask ("M") or the selection ("S").']);
                return;
            end

            expression = obj.BatchOpt.Expression;
            inputNames = {inputVariables.name};
            try
                level = obj.bigDataOptions.resolveLevel(obj.BatchOpt);
            catch err
                obj.reportError_(parentFigure, errorId, err.message);
                return;
            end
            width = dataset.image.pyramid.levelImageSizes(level, 2);
            message = obj.checkBandwise_(expression, inputNames, outputVariable, dataset.image.dataClass, ...
                width, dataset.image.colors);
            if ~isempty(message)
                obj.reportError_(parentFigure, errorId, message);
                return;
            end

            blockFunction = @(block) controllers.ImageArithmetics.evaluateBand_(block, expression, inputNames, ...
                outputVariable.name);
            try
                if strcmp(outputVariable.type, 'image')
                    fingerprint = jsonencode(struct('Expression', expression, 'InputVariables', {inputNames}, ...
                        'OutputVariables', outputVariable.name));
                    result = obj.bigDataOptions.run(obj.BatchOpt, blockFunction, Fingerprint = fingerprint);
                else
                    result = obj.bigDataOptions.runToModel(obj.BatchOpt, blockFunction, outputVariable.type);
                end
            catch err
                obj.reportError_(parentFigure, errorId, sprintf('Image Arithmetics on the BigData dataset failed:\n%s', err.message));
                return;
            end
            if isempty(result)      % cancelled before anything was written
                notify(obj.mibModel, 'StopProtocol');
                return;
            end

            if strcmp(outputVariable.type, 'image')
                obj.bigDataOptions.reportStoreResult(result, sprintf('Image Arithmetics "%s" of %s, level %s -> %s', ...
                    expression, dataset.image.filename, obj.BatchOpt.BigData_PyramidLevel{1}, result.outputPath));
            else
                if ~obj.bigDataOptions.reportModelResult(result, outputVariable.type)
                    return;     % cancelled during the write; reported
                end
                fprintf('Image Arithmetics "%s" of %s, level %s -> %s\n', expression, dataset.image.filename, ...
                    obj.BatchOpt.BigData_PyramidLevel{1}, outputVariable.type);
            end

            obj.storeExpressionInHistory_();
            obj.mibModel.preferences.Users.Tiers.numberOfImageArithmetics = obj.mibModel.preferences.Users.Tiers.numberOfImageArithmetics + 1;
            notify(obj.mibModel, 'UpdateUserScore', core.ToggleEventData(2));
            obj.returnBatchOpt(obj.BatchOpt);
        end

        function reportError_(obj, parentFigure, errorId, message)
            % REPORTERROR_ - Show the error in a dialog, or raise it when there is no window (headless).
            controllers.BigDataOptions.reportError(obj.mibModel, parentFigure, errorId, message, 'Image Arithmetics');
        end
    end

    methods (Static, Hidden)
        function out = evaluateBand_(block, expression, inputNames, outputName)
            % EVALUATEBAND_ - Block function of the BigData run: the expression on one band.
            %
            % ``block`` is ``[rows width colors]`` (see
            % ``io.savers.FilteredSliceProvider``); every input variable gets it
            % as ``[rows width 1 colors]``. Returns the output variable as
            % ``[rows width colors]``. Hidden rather than private: it is called
            % through a function handle from the store writer.
            band = reshape(block, size(block, 1), size(block, 2), 1, size(block, 3));
            out = controllers.ImageArithmetics.evaluateExpression_(expression, inputNames, band, outputName);
            out = reshape(out, size(out, 1), size(out, 2), size(out, 4));
        end
    end

    methods (Static, Access = private)
        function variables = parseVariables_(variableString, activeId)
            % PARSEVARIABLES_ - Variables named in an Input or Output variables string.
            %
            % Each of ``I O M S`` is a variable of the image, labels, mask or
            % selection layer; a digit right after it names the buffer
            % (``I2``), else the active buffer is meant. Other characters
            % (commas, spaces) are skipped, repeated names are listed once.
            %
            % Output Arguments:
            %   - **variables** - 1 x N struct array: ``name`` [char] (``'I'``,
            %     ``'M3'``), ``type`` [char] layer name, ``id`` [double] buffer
            variables = struct('name', {}, 'type', {}, 'id', {});
            layerTypes = dictionary(["I" "O" "M" "S"], ["image" "labels" "mask" "selection"]);
            for charIndex = 1:numel(variableString)
                letter = string(variableString(charIndex));
                if ~isKey(layerTypes, letter); continue; end
                name = char(letter);
                id = activeId;
                if charIndex < numel(variableString) && ~isnan(str2double(variableString(charIndex+1)))
                    id = str2double(variableString(charIndex+1));
                    name = [name num2str(id)]; %#ok<AGROW>
                end
                if ismember(name, {variables.name}); continue; end
                variables(end+1) = struct('name', name, 'type', char(layerTypes(letter)), 'id', id); %#ok<AGROW>
            end
        end

        function message = checkBandwise_(expression, inputNames, outputVariable, imageClass, width, colors)
            % CHECKBANDWISE_ - Why the expression cannot run band by band; '' when it can.
            %
            % Evaluates the expression on a test block ``[8 width 2 colors]`` of
            % class ``imageClass`` and on its four quarters (row halves x
            % slices). Each quarter has random values in its own range of the
            % class (5-17 %, 27-39 %, 49-61 %, 71-83 % of ``intmax``), so a
            % statistic of the block (min, max, mean, sum, numel...) differs from
            % the statistic of a quarter. A pointwise expression gives the
            % quarters' results reassembled; anything else is refused. The test
            % values come from a private random stream, so the global ``rng``
            % is not touched, and an expression that calls ``rand`` itself gives
            % different values for the block and the quarters and is refused.
            %
            % Also refused: an error on the test block, a missing output
            % variable, a result that changes the number of rows, the width or
            % the depth, a non-integer image result (MIB images are integer),
            % and a mask or selection result with more than one channel.
            message = '';
            refusal = sprintf(['The expression cannot be used on a BigData dataset:\n%%s\n\n' ...
                'On a BigData dataset the expression is applied to one band of rows at a time, so each pixel ' ...
                'must be computed from the same pixel of the inputs (for example "I = I * 2" or "M = I > 100"). ' ...
                'Statistics of the whole image (min(I(:)), mean...), flips and shifts along Y or Z, row and slice ' ...
                'indices and random numbers are not available.']);
            rows = 4;
            maxValue = double(intmax(imageClass));
            randomStream = RandStream('mt19937ar', 'Seed', 1);
            quarters = cell(2, 2);   % {row half, slice}
            for rowHalf = 1:2
                for slice = 1:2
                    lowFraction = 0.05 + 0.22 * ((rowHalf - 1) * 2 + slice - 1);
                    quarters{rowHalf, slice} = cast(maxValue * (lowFraction + 0.12 * ...
                        rand(randomStream, rows, width, 1, colors)), imageClass);
                end
            end
            block = [cat(3, quarters{1, 1}, quarters{1, 2}); cat(3, quarters{2, 1}, quarters{2, 2})];
            try
                blockResult = controllers.ImageArithmetics.evaluateExpression_(expression, inputNames, block, ...
                    outputVariable.name);
                quarterResults = cellfun(@(quarter) controllers.ImageArithmetics.evaluateExpression_( ...
                    expression, inputNames, quarter, outputVariable.name), quarters, 'UniformOutput', false);
            catch err
                message = sprintf(refusal, sprintf('it failed on a test block: %s', err.message));
                return;
            end
            if ~isequal(size(blockResult, 1:3), [2 * rows, width, 2])
                message = sprintf(refusal, sprintf(['the result must keep the size of the image, ' ...
                    'but a test block of %s gave %s.'], mat2str(size(block, 1:3)), mat2str(size(blockResult, 1:3))));
                return;
            end
            try
                reassembled = [cat(3, quarterResults{1, 1}, quarterResults{1, 2}); ...
                    cat(3, quarterResults{2, 1}, quarterResults{2, 2})];
                isBandwise = isequaln(blockResult, reassembled) && strcmp(class(blockResult), class(reassembled));
            catch
                isBandwise = false;   % the quarters' results do not even fit together
            end
            if ~isBandwise
                message = sprintf(refusal, 'a part of the image gives another result than the whole image.');
                return;
            end
            if strcmp(outputVariable.type, 'image') && ~isinteger(blockResult)
                message = sprintf(['The expression produced a "%s" result, but images must be an integer class ' ...
                    '(uint8, uint16, uint32).\n\nCast the result explicitly, for example:\n%s = uint8(...);'], ...
                    class(blockResult), outputVariable.name);
            elseif ~strcmp(outputVariable.type, 'image') && size(blockResult, 4) > 1
                message = sprintf(['The %s has one channel, but the expression gave %d; select one, ' ...
                    'for example "%s = I(:,:,:,1) > 100".'], outputVariable.type, size(blockResult, 4), outputVariable.name);
            end
        end

        function output = evaluateExpression_(expression__, inputNames__, value__, outputName__) %#ok<INUSD> value__ is read by eval
            % EVALUATEEXPRESSION_ - Evaluate the expression with every input name holding ``value__``.
            %
            % The local names end in ``__`` so an expression does not overwrite
            % them by chance. Errors with ``controllers:ImageArithmetics:noOutput``
            % when the expression does not assign the output variable.
            for index__ = 1:numel(inputNames__)
                eval([inputNames__{index__} ' = value__;']);
            end
            eval([expression__ ';']);
            if ~exist(outputName__, 'var')
                error('controllers:ImageArithmetics:noOutput', ...
                    'The expression did not assign the output variable "%s".', outputName__);
            end
            output = eval(outputName__);
        end
    end
end
