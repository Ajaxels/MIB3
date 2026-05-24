classdef ImageFilters < handle
% IMAGEFILTERS - Controller for the Image Filters dialog.
%
% Launch as GUI tool::
%
%   obj.mibController.startController('controllers.ImageFilters');
%
% Launch with a pre-selected filter::
%
%   obj.mibController.startController('controllers.ImageFilters', 'Gaussian');
%
% Launch in batch mode::
%
%   BatchOpt.FilterName = {'Gaussian'};
%   obj.mibController.startController('controllers.ImageFilters', [], BatchOpt);

    % Updates
    %

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.ImageFiltersGUI)
        mibGUI
        % handle to main MIB figure (used as parent for modal dialogs)
        listener
        % cell array of listener handles
        BasicFiltersList
        % cell array with available basic filters
        EdgePreservingFiltersList
        % cell array with available edge-preserving filters
        ContrastFiltersList
        % cell array with available contrast adjustment filters
        BinarizationFiltersList
        % cell array with available binarization filters
        imageFiltersParams
        % structure with parameters for each filter (local copy of sessionSettings.ImageFilters)
        Filters3D
        % list of filter names that support 3D mode
        ParaHandles
        % cell array of dynamically created filter-parameter widget handles
        BatchOpt
        % structure compatible with batch processing; field names match widget Tags
        infoHtmlTempFile
        % path to the current InfoHTML temp file; deleted on next setInfoHtml call
    end

    events
        CloseEvent
        % fired when the window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static listener guard; safe even when view is invalid.
            if ~isvalid(obj) || isempty(obj.view) || ~isvalid(obj.view.gui)
                for i = 1:numel(obj.listener); delete(obj.listener{i}); end
                return;
            end
            switch evnt.EventName
                case 'UpdateGuiWidgets'
                    obj.updateWidgets();
                case 'SliceChanged'
                    if obj.view.handles.AutopreviewCheckBox.Value
                        obj.PreviewButtonPushed();
                    end
            end
        end
    end

    methods
        % External method file declarations
        updateSessionSettings(obj) % generate default session settings with filter settings

        % ---------------------------------------------------------------
        function obj = ImageFilters(mibModel, varargin)
            % IMAGEFILTERS - Constructor.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = ImageFilters(mibModel)
            %       obj = ImageFilters(mibModel, DesiredFilterName)
            %       obj = ImageFilters(mibModel, [], BatchOpt)
            %

            obj.mibModel = mibModel;
            obj.mibGUI = mibModel.mibGUI;
            
            % get default parameters for filters
            if ~isfield(obj.mibModel.sessionSettings, 'ImageFilters')
                obj.updateSessionSettings();
            end

            %% fill BatchOpt with defaults
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            DesiredFilterName = [];
            if nargin > 1
                if ~isempty(varargin{1}); DesiredFilterName = varargin{1}; end
            end

            obj.imageFiltersParams = obj.mibModel.sessionSettings.ImageFilters; % local copy

            % update certain parameters
            obj.imageFiltersParams.Bilateral.degreeOfSmoothing = num2str(obj.mibModel.I{obj.BatchOpt.id}.image.maxInt^2*.01);
            obj.BasicFiltersList = {'Average', 'Disk', 'DistanceMap', 'ElasticDistortion', 'Entropy', 'Frangi', 'Gaussian', 'Gradient', 'LoG', 'MathOps', 'Mode', 'Motion','Prewitt','Range', 'SaltAndPepper','Sobel','Std'};
            obj.EdgePreservingFiltersList = {'AnisotropicDiffusion', 'Bilateral', 'DNNdenoise', 'Median', 'NonLocalMeans', 'Wiener'};
            obj.ContrastFiltersList = {'AddNoise', 'FastLocalLaplacian', 'FlatfieldCorrection', 'LocalBrighten', 'LocalContrast', 'ReduceHaze', 'UnsharpMask'};
            obj.BinarizationFiltersList = {'Edge', 'SlicClustering', 'WatershedClustering'};
            obj.Filters3D = {'Average', 'DistanceMap', 'Frangi', 'Gaussian', 'Gradient', 'LoG', 'Median', 'Mode', 'Prewitt', 'SlicClustering', 'Sobel', 'WatershedClustering'};

            % add BMxD filter if available
            if ~isempty(obj.mibModel.preferences.ExternalDirs.bm3dInstallationPath)
                if exist(fullfile(obj.mibModel.preferences.ExternalDirs.bm3dInstallationPath, 'BM3D.m'), 'file') == 2
                    obj.EdgePreservingFiltersList{end+1} = 'BMxD';
                end
            end

            % determine desired filter and its group
            if isempty(DesiredFilterName) && ~isempty(obj.imageFiltersParams.DesiredFilterName)
                DesiredFilterName = obj.imageFiltersParams.DesiredFilterName;
            end

            if ~isempty(DesiredFilterName)
                if ismember(DesiredFilterName, obj.BasicFiltersList)
                    obj.BatchOpt.FilterGroup = {'Basic Image Filtering in the Spatial Domain'};
                    obj.BatchOpt.FilterName{2} = obj.BasicFiltersList;
                    obj.BatchOpt.FilterName(1) = obj.BatchOpt.FilterName{2}(ismember(obj.BasicFiltersList, DesiredFilterName));
                elseif ismember(DesiredFilterName, obj.EdgePreservingFiltersList)
                    obj.BatchOpt.FilterGroup = {'Edge-Preserving Filtering'};
                    obj.BatchOpt.FilterName{2} = obj.EdgePreservingFiltersList;
                    obj.BatchOpt.FilterName(1) = obj.BatchOpt.FilterName{2}(ismember(obj.EdgePreservingFiltersList, DesiredFilterName));
                elseif ismember(DesiredFilterName, obj.ContrastFiltersList)
                    obj.BatchOpt.FilterGroup = {'Contrast Adjustment'};
                    obj.BatchOpt.FilterName{2} = obj.ContrastFiltersList;
                    obj.BatchOpt.FilterName(1) = obj.BatchOpt.FilterName{2}(ismember(obj.ContrastFiltersList, DesiredFilterName));
                elseif ismember(DesiredFilterName, obj.BinarizationFiltersList)
                    obj.BatchOpt.FilterGroup = {'Image Binarization'};
                    obj.BatchOpt.FilterName{2} = obj.BinarizationFiltersList;
                    obj.BatchOpt.FilterName(1) = obj.BatchOpt.FilterName{2}(ismember(obj.BinarizationFiltersList, DesiredFilterName));
                end
            else
                obj.BatchOpt.FilterGroup = {'Basic Image Filtering in the Spatial Domain'};
                obj.BatchOpt.FilterName{2} = obj.BasicFiltersList;
                obj.BatchOpt.FilterName(1) = obj.BatchOpt.FilterName{2}(1);
            end
            obj.BatchOpt.FilterGroup{2} = {'Basic Image Filtering in the Spatial Domain', 'Edge-Preserving Filtering', 'Contrast Adjustment', 'Image Binarization'};

            obj.BatchOpt.Mode3D = false;
            obj.BatchOpt.DatasetType = {'2D, Slice'};
            obj.BatchOpt.DatasetType{2} = {'2D, Slice', '3D, Stack', '4D, Dataset'};
            PossibleColChannels = arrayfun(@(x) sprintf('%d', x), 1:obj.mibModel.I{obj.BatchOpt.id}.image.colors, 'UniformOutput', false);
            obj.BatchOpt.ColorChannel = {'All'};
            obj.BatchOpt.ColorChannel{2} = [{'All'}, {'Displayed'}, PossibleColChannels];
            obj.BatchOpt.SourceLayer = {'image'};
            obj.BatchOpt.SourceLayer{2} = {'image', 'labels', 'selection', 'mask'};
            obj.BatchOpt.MaterialIndex = '1';
            obj.BatchOpt.ActionToResult = {'Fitler image'};
            obj.BatchOpt.ActionToResult{2} = {'Fitler image', 'Filter and subtract','Filter and add'};
            obj.BatchOpt.UseParallelComputing = false;
            obj.BatchOpt.showWaitbar = true;
            obj.BatchOpt.id = obj.mibModel.getActiveId();

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Image -> Filters';
            obj.BatchOpt.mibBatchActionName = obj.BatchOpt.FilterName{1};
            obj.BatchOpt.mibBatchTooltip.FilterGroup = 'Specify image group of image filters';
            obj.BatchOpt.mibBatchTooltip.FilterName = 'Specify name of the filter';
            obj.BatchOpt.mibBatchTooltip.Mode3D = 'Apply the selected filter in 2D or 3D space';
            obj.BatchOpt.mibBatchTooltip.DatasetType = 'Specify whether to filter the shown slice (2D, Slice), whole stack (3D, Stack) or complete dataset (4D, Dataset)';
            obj.BatchOpt.mibBatchTooltip.ColorChannel = 'Specify color channel to be filtered';
            obj.BatchOpt.mibBatchTooltip.SourceLayer = 'Apply filter to the selected layer of MIB';
            obj.BatchOpt.mibBatchTooltip.MaterialIndex = 'Index of material to be filtered for SourceLayer==labels';
            obj.BatchOpt.mibBatchTooltip.ActionToResult = 'Depending on the choice, filter results can be shown as it is or Added/Subtracted from the dataset';
            obj.BatchOpt.mibBatchTooltip.UseParallelComputing = 'Use parallel computing for 2D filters';
            obj.BatchOpt.mibBatchTooltip.showWaitbar = 'Show or not waitbar';

            %% batch / headless mode
            if nargin == 3
                BatchOptIn = varargin{2};
                if isstruct(BatchOptIn) == 0
                    if isnan(BatchOptIn)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'Error');
                    end
                    notify(obj, 'CloseEvent');
                    return
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                obj.Filter([], 1);
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.ImageFiltersGUI');

            % add thumbnail image
            imshow(obj.mibModel.sessionSettings.ImageFilters.TestImg, 'Parent', obj.view.handles.ThumbnailView1);

            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'left');

            obj.ParaHandles = {};

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.FilterButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.FilterButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.updateWidgets();

            % sync GUI from BatchOpt and populate filter panel
            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
            obj.FilterGroupValueChanged();

            obj.addCallbacks();
            obj.view.gui.Visible = 'on';

            % add listeners
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
            obj.listener{2} = addlistener(obj.mibModel, 'SliceChanged',     @(src,evnt) obj.ViewListner_Callback2(obj, src, evnt));
        end

        % ---------------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks after view creation.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.handles.FilterGroup.ValueChangedFcn    = @(h,~) obj.FilterGroupValueChanged(h); %
            obj.view.handles.FilterName.ValueChangedFcn     = @(h,~) obj.FilterNameValueChanged(h); %
            obj.view.handles.Mode3D.ValueChangedFcn         = @(~,~) obj.Mode3DValueChanged(); %
            obj.view.handles.DatasetType.ValueChangedFcn    = @(h,e) obj.updateBatchOptFromGUI(e); %
            obj.view.handles.ColorChannel.ValueChangedFcn   = @(h,e) obj.updateBatchOptFromGUI(e); %
            obj.view.handles.SourceLayer.ValueChangedFcn    = @(h,e) obj.updateBatchOptFromGUI(e); %
            obj.view.handles.ActionToResult.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e); %
            obj.view.handles.MaterialIndex.ValueChangedFcn  = @(h,e) obj.updateBatchOptFromGUI(e); %
            obj.view.handles.UseParallelComputing.ValueChangedFcn = @(h,e) obj.updateBatchOptFromGUI(e); %
            obj.view.handles.PreviewButton.ButtonPushedFcn  = @(~,~) obj.PreviewButtonPushed(); % 
            obj.view.handles.FilterButton.ButtonPushedFcn   = @(~,~) obj.Filter(); % 
            obj.view.handles.HelpButton.ButtonPushedFcn     = @(~,~) obj.helpButton_Callback(); % 
            obj.view.handles.CloseButton.ButtonPushedFcn    = @(~,~) obj.closeWindow();  % 
            obj.view.gui.WindowScrollWheelFcn = @(~,e) obj.scrollWheel_Callback(e); %
            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
            obj.view.handles.InfoHTML.HTMLEventReceivedFcn = @(~,e) obj.infoHtmlDataChanged(e);
        end

        % ---------------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to MIB main window shortcuts.
            if isempty(event.Character); return; end

            eventData = struct();
            eventData.eventdata = event;
            eventData = core.ToggleEventData(eventData);
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % ---------------------------------------------------------------
        function infoHtmlDataChanged(obj, event)
            % INFOHTMLDATACHANGED - Handle events sent from the InfoHTML uihtml component.
            % In R2026a+ direct <a href> navigation is sandboxed; links are intercepted
            % by JavaScript and forwarded here via sendEventToMATLAB(eventName, data).
            % MATLAB receives them in HTMLEventReceivedFcn: event.HTMLEventData.url
            if strcmp(event.HTMLEventName, 'linkClicked') && isfield(event.HTMLEventData, 'url')
                web(event.HTMLEventData.url, '-browser');
            end
        end

      

        % ---------------------------------------------------------------
        function setInfoHtml(obj, infoText)
            % SETINFOHTML - Write info HTML to a unique temp file and load it into InfoHTML.
            % Inline HTMLSource strings block <script> in R2026a (CSP); a file path
            % allows scripts. tempname() gives a unique path each call so uihtml
            % always detects a change and reloads (same path = no reload).
            htmlContent = sprintf([...
                '<!DOCTYPE html><html><head><script>\n' ...
                'function setup(htmlComponent) {\n' ...
                '  document.addEventListener("click", function(e) {\n' ...
                '    var t = e.target;\n' ...
                '    while (t && t.tagName !== "A") { t = t.parentElement; }\n' ...
                '    if (t && t.href) {\n' ...
                '      e.preventDefault();\n' ...
                '      htmlComponent.sendEventToMATLAB("linkClicked", {url: t.href});\n' ...
                '    }\n' ...
                '  });\n' ...
                '}\n' ...
                '</script></head><body>\n' ...
                '<p style="font-family: Sans-serif; font-size: small;">%s</p>\n' ...
                '</body></html>'], infoText);

            if ~isempty(obj.infoHtmlTempFile) && isfile(obj.infoHtmlTempFile)
                delete(obj.infoHtmlTempFile);
            end
            tempFilePath = [tempname, '.html'];
            fid = fopen(tempFilePath, 'w', 'n', 'UTF-8');
            fprintf(fid, '%s', htmlContent);
            fclose(fid);
            obj.infoHtmlTempFile = tempFilePath;
            obj.view.handles.InfoHTML.HTMLSource = tempFilePath;
        end

        % ---------------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Save session settings, destroy view, fire CloseEvent.
            if ~isempty(obj.infoHtmlTempFile) && isfile(obj.infoHtmlTempFile)
                delete(obj.infoHtmlTempFile);
            end
            obj.mibModel.sessionSettings.ImageFilters = obj.imageFiltersParams;

            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end

            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end

            notify(obj, 'CloseEvent');
        end

        % ---------------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh widgets to reflect current model state.
            if isfield(obj.BatchOpt, 'id'); obj.BatchOpt.id = obj.mibModel.getActiveId(); end

            % update list of color channels if needed
            PossibleColChannels = arrayfun(@(x) sprintf('ColCh %d', x), 1:obj.mibModel.I{obj.BatchOpt.id}.image.colors, 'UniformOutput', false);
            if numel(PossibleColChannels)+2 ~= numel(obj.BatchOpt.ColorChannel{2})
                obj.BatchOpt.ColorChannel = {'All'};
                obj.BatchOpt.ColorChannel{2} = [{'All'}, {'Displayed'}, PossibleColChannels];
            end

            utils.updateGUIFromBatchOpt_Shared(obj.view, obj.BatchOpt);
        end

        % ---------------------------------------------------------------
        function updateBatchOptFromGUI(obj, event)
            % UPDATEBATCHOPTFROMGUI - Sync BatchOpt from a widget change event.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, event.Source);
        end

        % ---------------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt (with filter params) to mibBatchController.
            if nargin < 2
                BatchOptOut = obj.BatchOpt;
                ImageFiltersFields = fieldnames(obj.imageFiltersParams.(BatchOptOut.FilterName{1}));
                for i = 1:numel(ImageFiltersFields)
                    if ~isfield(BatchOptOut, ImageFiltersFields{i})
                        BatchOptOut.(ImageFiltersFields{i}) = obj.imageFiltersParams.(BatchOptOut.FilterName{1}).(ImageFiltersFields{i});
                    end
                end
            end

            % add tooltips for the current filter
            CurrentFilterTooltip = obj.imageFiltersParams.(BatchOptOut.FilterName{1}).mibBatchTooltip;
            fieldNames = fieldnames(CurrentFilterTooltip);
            for i = 1:numel(fieldNames)
                BatchOptOut.mibBatchTooltip.(fieldNames{i}) = CurrentFilterTooltip.(fieldNames{i});
            end
            BatchOptOut.mibBatchActionName = BatchOptOut.FilterName{1};
            BatchOptOut = rmfield(BatchOptOut, {'FilterGroup', 'id', 'FilterName'});

            eventdata = core.ToggleEventData(BatchOptOut);
            notify(obj.mibModel, 'SyncBatch', eventdata);
        end

        % ---------------------------------------------------------------
        function FilterGroupValueChanged(obj, event)
            % FILTERGROUPVALUECHANGED - Update FilterName list when FilterGroup changes.
            if nargin < 2; event = obj.view.handles.FilterGroup; end
            value = event.Value;
            switch value
                case 'Basic Image Filtering in the Spatial Domain'
                    obj.view.handles.FilterName.Items = obj.BasicFiltersList;
                    obj.BatchOpt.FilterName{2} = obj.BasicFiltersList;
                case 'Edge-Preserving Filtering'
                    obj.view.handles.FilterName.Items = obj.EdgePreservingFiltersList;
                    obj.BatchOpt.FilterName{2} = obj.EdgePreservingFiltersList;
                case 'Contrast Adjustment'
                    obj.view.handles.FilterName.Items = obj.ContrastFiltersList;
                    obj.BatchOpt.FilterName{2} = obj.ContrastFiltersList;
                case 'Image Binarization'
                    obj.view.handles.FilterName.Items = obj.BinarizationFiltersList;
                    obj.BatchOpt.FilterName{2} = obj.BinarizationFiltersList;
            end
            obj.BatchOpt.FilterName(1) = obj.BatchOpt.FilterName{2}(1);
            obj.BatchOpt.FilterGroup{1} = value;
            obj.FilterNameValueChanged();
        end

        % ---------------------------------------------------------------
        function scrollWheel_Callback(obj, event)
            % SCROLLWHEEL_CALLBACK - Adjust spinner / editfield value with mouse wheel.
            verticalScrollCount = event.VerticalScrollCount;
            h = obj.view.gui.CurrentObject;
            if isempty(h); return; end

            % determine multiplier
            modifier = obj.view.gui.CurrentModifier;
            isCtrl  = any(strcmp(modifier, 'control'));
            isShift = any(strcmp(modifier, 'shift'));

            if ~isCtrl && ~isShift; return; end

            if isCtrl && isShift
                multiplierFactor = 10;
            elseif isCtrl
                multiplierFactor = 0.1;
            elseif isShift
                multiplierFactor = 1;
            else
                return;
            end

            switch h.Type
                case 'uieditfield'
                    value = str2num(h.Value); %#ok<ST2NM>
                    if numel(value) > 1; return; end
                    h.Value = num2str(value - verticalScrollCount*multiplierFactor);
                case {'uispinner', 'uinumericeditfield'}
                    if multiplierFactor < 1
                        value = round(h.Value - verticalScrollCount*multiplierFactor, 3);
                    else
                        value = h.Value - verticalScrollCount*multiplierFactor;
                    end
                    value = max([h.Limits(1) value]);
                    value = min([h.Limits(2) value]);
                    h.Value = value;
            end
            obj.updateImageFiltersParameters(h, event);
        end

        % ---------------------------------------------------------------
        function updateImageFiltersParameters(obj, hWidget, ~)
            % UPDATEIMAGEFILTERSPARAMETERS - Sync ImageFilters struct when a parameter widget changes.
            subBatchOpt = obj.imageFiltersParams.(obj.view.handles.FilterName.Value);
            obj.imageFiltersParams.(obj.view.handles.FilterName.Value) = utils.updateBatchOptFromGUI_Shared(subBatchOpt, hWidget);
            try
                obj.renderThumbnailPreview();
                if obj.view.handles.AutopreviewCheckBox.Value
                    obj.PreviewButtonPushed();
                end
            catch
            end
        end

        % ---------------------------------------------------------------
        function FilterNameValueChanged(obj, event)
            % FILTERNAMEVALUECHANGED - Rebuild parameter widgets when FilterName changes.
            if nargin < 2; event = obj.view.handles.FilterName; end
            value = event.Value;

            % delete existing parameter widgets
            if ~isempty(obj.ParaHandles)
                for widgetId = 1:numel(obj.ParaHandles)
                    obj.ParaHandles{widgetId}.delete;
                end
                obj.ParaHandles = {};
            end

            hParent = obj.view.handles.GridLayoutParameters;
            noRows = numel(obj.view.handles.GridLayoutParameters.RowHeight);

            paraList = obj.imageFiltersParams.(value);
            Tooltips = paraList.mibBatchTooltip;
            paraList = rmfield(paraList, 'mibBatchTooltip');

            paraNames = fieldnames(paraList);
            index = 1;
            rowId = 1;
            colId = 1;
            for widgetId = 1:numel(paraNames)
                % add label (skip for logical — checkbox carries its own label)
                if ~islogical(paraList.(paraNames{widgetId}))
                    obj.ParaHandles{index} = uilabel(hParent, 'Text', paraNames{widgetId}, 'HorizontalAlignment', 'right');
                    obj.ParaHandles{index}.Layout.Column = colId;
                    obj.ParaHandles{index}.Layout.Row = rowId;
                    index = index + 1;
                end

                switch class(paraList.(paraNames{widgetId}))
                    case 'char'
                        obj.ParaHandles{index} = uieditfield(hParent, 'text', ...
                            'Value', paraList.(paraNames{widgetId}), ...
                            'Tooltip', Tooltips.(paraNames{widgetId}), ...
                            'ValueChangedFcn', @obj.updateImageFiltersParameters);
                    case 'cell'
                        if ~isnumeric(paraList.(paraNames{widgetId}){1})  % dropdown
                            obj.ParaHandles{index} = uidropdown(hParent, ...
                                'Items', paraList.(paraNames{widgetId}){2}, ...
                                'Value', paraList.(paraNames{widgetId}){1}, ...
                                'Tooltip', Tooltips.(paraNames{widgetId}), ...
                                'ValueChangedFcn', @obj.updateImageFiltersParameters);
                        else    % numeric spinner
                            if numel(paraList.(paraNames{widgetId})) > 2
                                RoundFractionalValues = paraList.(paraNames{widgetId}){3};
                            else
                                RoundFractionalValues = 'on';
                            end
                            if numel(paraList.(paraNames{widgetId})) > 1
                                Limits = paraList.(paraNames{widgetId}){2};
                            else
                                Limits = [-Inf Inf];
                            end
                            obj.ParaHandles{index} = uispinner(hParent, ...
                                'Value', paraList.(paraNames{widgetId}){1}, ...
                                'Limits', Limits, ...
                                'RoundFractionalValues', RoundFractionalValues, ...
                                'Tooltip', Tooltips.(paraNames{widgetId}), ...
                                'ValueChangedFcn', @obj.updateImageFiltersParameters);
                        end
                    case 'logical'
                        obj.ParaHandles{index} = uicheckbox(hParent, ...
                            'Value', paraList.(paraNames{widgetId}), ...
                            'Text', paraNames{widgetId}, ...
                            'Tooltip', Tooltips.(paraNames{widgetId}), ...
                            'ValueChangedFcn', @obj.updateImageFiltersParameters);
                end
                obj.ParaHandles{index}.Layout.Column = colId + 1;
                obj.ParaHandles{index}.Layout.Row = rowId;
                obj.ParaHandles{index}.Tag = paraNames{widgetId};
                index = index + 1;
                rowId = rowId + 1;
                if rowId > noRows
                    rowId = 1;
                    colId = colId + 2;
                end
            end

            % update filter info HTML
            obj.setInfoHtml(obj.mibModel.sessionSettings.ImageFilters.(value).mibBatchTooltip.Info);

            % enable/disable 3D checkbox
            if ismember(value, obj.Filters3D)
                obj.view.handles.Mode3D.Enable = 'on';
            else
                obj.view.handles.Mode3D.Enable = 'off';
                obj.view.handles.Mode3D.Value = false;
            end

            obj.BatchOpt.FilterName{1} = value;
            obj.BatchOpt.Mode3D = obj.view.handles.Mode3D.Value;

            % enable/disable preview buttons for 3D mode
            if obj.BatchOpt.Mode3D
                obj.view.handles.PreviewButton.Enable = 'off';
                obj.view.handles.AutopreviewCheckBox.Enable = 'off';
                obj.view.handles.AutopreviewCheckBox.Value = false;
            else
                obj.view.handles.PreviewButton.Enable = 'on';
                obj.view.handles.AutopreviewCheckBox.Enable = 'on';
                obj.renderThumbnailPreview();
                if obj.view.handles.AutopreviewCheckBox.Value; obj.PreviewButtonPushed(); end
            end
        end

        % ---------------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open documentation in browser.
            web(fullfile(obj.mibModel.mibPath, 'techdoc/html/user-interface/menu/image/image-filters.html'), '-browser');
        end

        % ---------------------------------------------------------------
        function Mode3DValueChanged(obj)
            % MODE3DVALUECHANGED - Toggle 3D mode; force DatasetType to >=3D Stack.
            val = obj.view.handles.Mode3D.Value;
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, obj.view.handles.Mode3D);
            if val && strcmp(obj.view.handles.DatasetType.Value, '2D, Slice')
                obj.view.handles.DatasetType.Value = '3D, Stack';
                obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, obj.view.handles.DatasetType);
            end

            if obj.view.handles.Mode3D.Value
                obj.view.handles.PreviewButton.Enable = 'off';
                obj.view.handles.AutopreviewCheckBox.Enable = 'off';
                obj.view.handles.AutopreviewCheckBox.Value = false;
            else
                obj.view.handles.PreviewButton.Enable = 'on';
                obj.view.handles.AutopreviewCheckBox.Enable = 'on';
            end
        end

        % ---------------------------------------------------------------
        function renderThumbnailPreview(obj)
            % RENDERTHUMBNAILPREVIEW - Apply filter to the test image and show in ThumbnailView2.
            if ismember(obj.BatchOpt.FilterName{1}, {'DNNdenoise'}) || obj.BatchOpt.Mode3D
                return;
            end

            img = obj.Filter(obj.mibModel.sessionSettings.ImageFilters.TestImg);

            if strcmp(obj.BatchOpt.FilterGroup{1}, 'Image Binarization')
                SourceLayer = 'selection';
            else
                SourceLayer = obj.BatchOpt.SourceLayer{1};
            end

            switch SourceLayer
                case 'selection'
                    if strcmp(obj.BatchOpt.FilterName{1}, 'Edge')
                        thumbImg = obj.mibModel.sessionSettings.ImageFilters.TestImg;
                        thumbImg(img>0) = 255;
                        imshow(thumbImg, 'Parent', obj.view.handles.ThumbnailView2);
                    else
                        imshow(img, [], 'Parent', obj.view.handles.ThumbnailView2);
                    end
                otherwise
                    imshow(img, 'Parent', obj.view.handles.ThumbnailView2);
            end
        end

        % ---------------------------------------------------------------
        function PreviewButtonPushed(obj)
            % PREVIEWBUTTONPUSHED - Apply filter to current view and display as overlay.
            getDataOptions.blockModeSwitch = 1;
            id = obj.mibModel.getActiveId();
            dataset = obj.mibModel.I{id};

            switch obj.BatchOpt.SourceLayer{1}
                case 'labels'
                    img = cell2mat(obj.mibModel.getData2D('labels', [], [], str2double(obj.BatchOpt.MaterialIndex), getDataOptions));
                case 'image'
                    switch obj.BatchOpt.ColorChannel{1}
                        case 'All';      ColCh = 0;
                        case 'Displayed'; ColCh = [];
                        otherwise;       ColCh = str2double(obj.BatchOpt.ColorChannel{1});
                    end
                    img = cell2mat(obj.mibModel.getData2D('image', [], [], ColCh, getDataOptions));
                otherwise
                    img = cell2mat(obj.mibModel.getData2D(obj.BatchOpt.SourceLayer{1}, [], [], [], getDataOptions));
            end

            if strcmp(obj.BatchOpt.FilterGroup{1}, 'Image Binarization') && size(img, 3) > 1
                utils.dlgs.showErrorDialog(obj.view.gui, 'Please select a single color channel before binarization', 'Too many color channels');
                return;
            end

            img = obj.Filter(img);
            if isempty(img); return; end

            if strcmp(obj.BatchOpt.FilterGroup{1}, 'Image Binarization')
                SourceLayer = 'selection';
                if ismember(obj.BatchOpt.FilterName{1}, {'SlicClustering', 'WatershedClustering'})
                    img = uint8(double(img) ./ double(max(img(:))) * 255);
                    showSettings.resizeToMagnification = true;
                    showSettings.sImgIn = img;
                    notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
                    return;
                end
            else
                SourceLayer = obj.BatchOpt.SourceLayer{1};
            end

            viewPort = dataset.image.viewPort;
            maxInt = dataset.image.maxInt;

            % Base RGB options: block mode, no resize so I has the same
            % pixel dimensions as img (both at dataset block resolution).
            % showImage/getRGBimage will apply magFactor scaling via sImgIn.
            getRGBimageOptions.blockModeSwitch = 1;
            getRGBimageOptions.resizeToMagnification = false;

            switch SourceLayer
                case 'selection'
                    currTransparency = obj.mibModel.preferences.Colors.SelectionTransparency;
                    obj.mibModel.preferences.Colors.SelectionTransparency = 1;
                    I = obj.mibModel.getRGBimage(getRGBimageOptions);
                    obj.mibModel.preferences.Colors.SelectionTransparency = currTransparency;
                    I(img==1) = 255;
                    showSettings.resizeToMagnification = true;
                    showSettings.sImgIn = I;
                    notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
                case 'mask'
                    currTransparency = obj.mibModel.preferences.Colors.MaskTransparency;
                    obj.mibModel.preferences.Colors.MaskTransparency = 1;
                    I = obj.mibModel.getRGBimage(getRGBimageOptions);
                    obj.mibModel.preferences.Colors.MaskTransparency = currTransparency;
                    I(img==1) = 255;
                    showSettings.resizeToMagnification = true;
                    showSettings.sImgIn = I;
                    notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
                case 'labels'
                    currTransparency = obj.mibModel.preferences.Colors.ModelTransparency;
                    obj.mibModel.preferences.Colors.ModelTransparency = 1;
                    I = obj.mibModel.getRGBimage(getRGBimageOptions);
                    obj.mibModel.preferences.Colors.ModelTransparency = currTransparency;
                    I(img==1) = 255;
                    showSettings.resizeToMagnification = true;
                    showSettings.sImgIn = I;
                    notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
                otherwise
                    % convert to 8-bit for display if needed
                    if ~isa(img, 'uint8')
                        if ~obj.mibModel.onFlyImageStretch
                            if size(img, 3) == 1
                                colCh = dataset.selectedColorChannel;
                                if viewPort.min(colCh) ~= 0 || viewPort.max(colCh) ~= maxInt || viewPort.gamma(colCh) ~= 1
                                    img = imadjust(img, [viewPort.min(colCh)/maxInt viewPort.max(colCh)/maxInt], [0 1], viewPort.gamma(colCh));
                                end
                            else
                                if max(viewPort.min) > 0 || min(viewPort.max) ~= maxInt || sum(viewPort.gamma) ~= 3
                                    for colCh = 1:3
                                        img(:,:,colCh) = imadjust(img(:,:,colCh), ...
                                            [viewPort.min(colCh)/maxInt viewPort.max(colCh)/maxInt], [0 1], viewPort.gamma(colCh));
                                    end
                                end
                            end
                            img = uint8(img/256);
                        end
                    end
                    showSettings.resizeToMagnification = true;
                    showSettings.sImgIn = img;
                    notify(obj.mibModel, 'ShowImage', core.ToggleEventData(showSettings));
            end
        end

    end
end
