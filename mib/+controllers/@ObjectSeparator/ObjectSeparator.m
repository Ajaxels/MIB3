classdef ObjectSeparator < handle
% OBJECTSEPARATOR - Controller for watershed-based object separation.
%
% Performs seeded or standard watershed segmentation on the selection,
% mask, or model/labels layer. Supports 2D (current slice or full stack)
% and 3D modes with optional XY/Z binning.
%
% Launch as GUI tool::
%
%   .. code-block:: matlab
%
%       obj.mibController.startController('controllers.ObjectSeparator');
%
% Launch in batch mode::
%
%   .. code-block:: matlab
%
%       BatchOpt.Mode        = {'mode3dRadio', {'mode2dCurrentRadio','mode2dRadio','mode3dRadio','mode3dGridRadio'}};
%       BatchOpt.ObjectSource = {'Selection', {'Selection','Mask','Model'}};
%       obj.mibController.startController('controllers.ObjectSeparator', [], BatchOpt);
%
% Trigger return of default options::
%
%   .. code-block:: matlab
%
%       obj.mibController.startController('controllers.ObjectSeparator', [], NaN);
%

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% Part of Microscopy Image Browser, http://mib.helsinki.fi
% License: GNU General Public License v3, https://www.gnu.org/licenses/gpl-3.0.en.html

    properties
        mibModel
        % handle to MibModel
        view
        % handle to the view (views.ObjectSeparatorGUI)
        mibGUI
        % handle to the main MIB figure (used as parent for dialogs)
        listener
        % cell array of listener handles
        BatchOpt
        % structure compatible with batch processing; field names match widget Tags
    end

    events
        CloseEvent
        % fired when the window is closed
    end

    methods (Static)
        function ViewListner_Callback2(obj, ~, evnt)
            % VIEWLISTNER_CALLBACK2 - Static listener guard; safe even after close.
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
        % -----------------------------------------------------------
        function obj = ObjectSeparator(mibModel, varargin)
            % OBJECTSEPARATOR - Constructor.
            %
            % Syntax::
            %
            %   .. code-block:: matlab
            %
            %       obj = ObjectSeparator(mibModel)
            %       obj = ObjectSeparator(mibModel, [], BatchOpt)
            %       obj = ObjectSeparator(mibModel, [], NaN)
            %
            obj.mibModel = mibModel;
            obj.mibGUI   = mibModel.mibGUI;

            id = obj.mibModel.getActiveId();

            [height, width, depth] = obj.mibModel.I{id}.getDatasetDimensions('selection', 3);
            colorCount        = obj.mibModel.I{id}.image.colors;
            colorChannelList  = arrayfun(@(x) sprintf('Ch %d', x), 1:colorCount, 'UniformOutput', false);

            pixSize   = obj.mibModel.I{id}.image.pixSize;
            minPix    = min([pixSize.x pixSize.y pixSize.z]);
            aspectStr = sprintf('%.2f %.2f %.2f', pixSize.x/minPix, pixSize.y/minPix, pixSize.z/minPix);

            matNames = obj.mibModel.I{id}.labels.materialNames;

            %% Initialize BatchOpt
            obj.BatchOpt.id = id;

            obj.BatchOpt.Mode    = {'mode2dCurrentRadio'};
            obj.BatchOpt.Mode{2} = {'mode2dCurrentRadio', 'mode2dRadio', 'mode3dRadio', 'mode3dGridRadio'};
            obj.BatchOpt.ObjectSource    = {'Selection'};
            obj.BatchOpt.ObjectSource{2} = {'Selection', 'Mask', 'Model'};
            if isempty(matNames)
                obj.BatchOpt.ObjectMaterial    = {''};
                obj.BatchOpt.ObjectMaterial{2} = {''};
            else    
                obj.BatchOpt.ObjectMaterial    = matNames(1);
                obj.BatchOpt.ObjectMaterial{2} = matNames;
            end
            obj.BatchOpt.ReduceOversegmentation  = false;
            obj.BatchOpt.UseSeeds = false;
            obj.BatchOpt.SeedSource    = {'seedsSelection'};
            obj.BatchOpt.SeedSource{2} = {'seedsSelection', 'seedsMask', 'seedsModel'};
            if isempty(matNames)
                obj.BatchOpt.SeedMaterial    = {''};
                obj.BatchOpt.SeedMaterial{2} = {''};
            else    
                obj.BatchOpt.SeedMaterial    = matNames(1);
                obj.BatchOpt.SeedMaterial{2} = matNames;
            end
            obj.BatchOpt.WatershedSource    = {'Distance'};
            obj.BatchOpt.WatershedSource{2} = {'Distance', 'Intensity'};
            obj.BatchOpt.ColorChannel    = {colorChannelList{1}};
            obj.BatchOpt.ColorChannel{2} = colorChannelList;
            obj.BatchOpt.InvertImage    = {'white-on-black, signal is bright'};
            obj.BatchOpt.InvertImage{2} = {'white-on-black, signal is bright', 'black-on-white, signal is dark'};
            obj.BatchOpt.AspectRatio             = aspectStr;
            obj.BatchOpt.XSubarea = sprintf('1:%d', width);
            obj.BatchOpt.YSubarea = sprintf('1:%d', height);
            obj.BatchOpt.ZSubarea = sprintf('1:%d', depth);
            obj.BatchOpt.Binning  = '1; 1';
            obj.BatchOpt.showWaitbar = true;

            obj.BatchOpt.mibBatchSectionName = 'Ribbon -> Tools';
            obj.BatchOpt.mibBatchActionName  = 'Object separation';

            obj.BatchOpt.mibBatchTooltip.Mode                   = 'mode2dCurrentRadio=current slice only; mode2dRadio=all slices in Z range; mode3dRadio=full 3-D watershed; mode3dGridRadio=3-D grid (processed slice-by-slice)';
            obj.BatchOpt.mibBatchTooltip.ObjectSource           = 'Layer containing objects: Selection, Mask, or Model';
            obj.BatchOpt.mibBatchTooltip.ObjectMaterial         = 'Model material name to use as objects when ObjectSource=Model';
            obj.BatchOpt.mibBatchTooltip.UseSeeds               = 'true = seeded watershed; false = standard distance-transform watershed';
            obj.BatchOpt.mibBatchTooltip.SeedSource             = 'Layer containing seeds: seedsSelection, seedsMask, or seedsModel';
            obj.BatchOpt.mibBatchTooltip.SeedMaterial           = 'Model material name to use as seeds when SeedSource=seedsModel';
            obj.BatchOpt.mibBatchTooltip.WatershedSource        = 'Distance=distance transform; Intensity=image grey values';
            obj.BatchOpt.mibBatchTooltip.ColorChannel           = 'Color channel for intensity-based watershed, e.g. Ch 1';
            obj.BatchOpt.mibBatchTooltip.InvertImage            = 'white-on-black=bright objects on dark background (no inversion); black-on-white=dark objects, image is complemented before watershed';
            obj.BatchOpt.mibBatchTooltip.ReduceOversegmentation = 'Apply extended minima to suppress small catchment basins (standard watershed only)';
            obj.BatchOpt.mibBatchTooltip.AspectRatio            = 'Voxel aspect ratio for 3-D distance transform: space-separated x y z values';
            obj.BatchOpt.mibBatchTooltip.XSubarea               = 'X pixel range to process, e.g. 1:512';
            obj.BatchOpt.mibBatchTooltip.YSubarea               = 'Y pixel range to process, e.g. 1:512';
            obj.BatchOpt.mibBatchTooltip.ZSubarea               = 'Z slice range to process, e.g. 1:100';
            obj.BatchOpt.mibBatchTooltip.Binning                = 'Binning factors as "binXY; binZ", e.g. 1; 1 for no binning';
            obj.BatchOpt.mibBatchTooltip.showWaitbar            = 'Show the progress bar during execution';

            %% Batch / headless mode
            if numel(varargin) >= 2
                BatchOptIn = varargin{2};
                if ~isstruct(BatchOptIn)
                    if isnan(BatchOptIn)
                        obj.returnBatchOpt();
                    else
                        utils.dlgs.showErrorDialog([], 'A structure as the 3rd parameter is required!', 'BatchOpt Error');
                    end
                    notify(obj, 'CloseEvent');
                    return;
                end
                obj.BatchOpt = utils.updateBatchOptCombineFields_Shared(obj.BatchOpt, BatchOptIn);
                obj.doObjectSeparation();
                notify(obj, 'CloseEvent');
                return;
            end

            %% Virtual mode guard
            if strcmp(obj.mibModel.I{id}.datasetType, 'Virtual')
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.mibModel.getProgressBarParent(), '', {''}, ...
                    {sprintf('Object separation is not available in virtual stacking mode.\nPlease switch to the memory-resident mode and try again.')}, ...
                    'Not implemented', dlgOpt);
                notify(obj, 'CloseEvent');
                return;
            end

            %% GUI mode
            obj.view = core.ChildView(obj, 'views.ObjectSeparatorGUI');
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibGUI, 'left');

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.separateBtn.FontSize ~= Font.FontSize || ...
                    ~strcmp(obj.view.handles.separateBtn.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.addCallbacks();
            obj.updateWidgets();
            obj.view.gui.Visible = 'on';

            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(s,e) obj.ViewListner_Callback2(obj, s, e));
            obj.listener{2} = addlistener(obj.mibModel, 'NewDataset',       @(s,e) obj.ViewListner_Callback2(obj, s, e));
        end

        % -----------------------------------------------------------
        function addCallbacks(obj)
            % ADDCALLBACKS - Wire all widget callbacks after view creation.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            handles = obj.view.handles;

            % Button groups
            handles.modeButtonGroup.SelectionChangedFcn      = @(~,e) obj.modeButtonGroup_Callback(e);
            handles.watershedSourcePanel.SelectionChangedFcn = @(~,e) obj.watershedSourceChanged_Callback(e);
            handles.objectSourcePanel.SelectionChangedFcn    = @(~,e) obj.objectSourcePanel_Callback(e);
            handles.seedSourcePanel.SelectionChangedFcn      = @(~,e) obj.seedSourcePanel_Callback(e);

            % Dropdowns
            handles.ObjectMaterial.ValueChangedFcn = @(h,~) obj.updateBatchOptFromGUI(h);
            handles.SeedMaterial.ValueChangedFcn   = @(h,~) obj.updateBatchOptFromGUI(h);
            handles.ColorChannel.ValueChangedFcn   = @(h,~) obj.updateBatchOptFromGUI(h);

            % Checkboxes
            handles.UseSeeds.ValueChangedFcn             = @(~,~) obj.useSeedsCheck_Callback();
            handles.InvertImage.ValueChangedFcn          = @(h,~) obj.updateBatchOptFromGUI(h);
            handles.ReduceOversegmentation.ValueChangedFcn = @(h,~) obj.updateBatchOptFromGUI(h);

            % Text fields
            handles.AspectRatio.ValueChangedFcn = @(~,~) obj.aspectRatio_Callback();
            handles.XSubarea.ValueChangedFcn    = @(h,~) obj.checkDimensions(h);
            handles.YSubarea.ValueChangedFcn    = @(h,~) obj.checkDimensions(h);
            handles.ZSubarea.ValueChangedFcn    = @(h,~) obj.checkDimensions(h);
            handles.Binning.ValueChangedFcn     = @(~,~) obj.validateBinning();

            % Buttons
            handles.separateBtn.ButtonPushedFcn             = @(~,~) obj.doObjectSeparation();
            handles.resetDimsBtn.ButtonPushedFcn            = @(~,~) obj.resetDimsBtn_Callback();
            handles.currentViewBtn.ButtonPushedFcn          = @(~,~) obj.currentViewBtn_Callback();
            handles.subAreaFromSelectionBtn.ButtonPushedFcn = @(~,~) obj.subAreaFromSelectionBtn_Callback();
            handles.updateMaterialsBtn.ButtonPushedFcn      = @(~,~) obj.updateMaterialsBtn_Callback();
            handles.closeBtn.ButtonPushedFcn                = @(~,~) obj.closeWindow();
            handles.helpBtn.ButtonPushedFcn                 = @(~,~) obj.helpButton_Callback();

            obj.view.gui.KeyPressFcn = @(~,e) obj.figureKeyPress(e);
        end

        % -----------------------------------------------------------
        function figureKeyPress(obj, event)
            % FIGUREKEYPRESS - Forward key presses to the MIB main window shortcuts.
            if isempty(event.Character); return; end
            eventData = struct();
            eventData.eventdata = event;
            eventData = core.ToggleEventData(eventData);
            notify(obj.mibModel, 'KeyPressEvent', eventData);
        end

        % -----------------------------------------------------------
        function closeWindow(obj)
            % CLOSEWINDOW - Destroy view, delete listeners, fire CloseEvent.
            if ~isempty(obj.view) && isvalid(obj.view.gui); delete(obj.view.gui); end
            for i = 1:numel(obj.listener); delete(obj.listener{i}); end
            notify(obj, 'CloseEvent');
        end

        % -----------------------------------------------------------
        function returnBatchOpt(obj, BatchOptOut)
            % RETURNBATCHOPT - Send BatchOpt defaults to mibBatchController.
            if nargin < 2; BatchOptOut = obj.BatchOpt; end
            if isfield(BatchOptOut, 'id'); BatchOptOut = rmfield(BatchOptOut, 'id'); end
            notify(obj.mibModel, 'SyncBatch', core.ToggleEventData(BatchOptOut));
        end

        % -----------------------------------------------------------
        function updateBatchOptFromGUI(obj, hObject)
            % UPDATEBATCHOPTFROMGUI - Sync a single widget change into BatchOpt.
            obj.BatchOpt = utils.updateBatchOptFromGUI_Shared(obj.BatchOpt, hObject);
        end

        % -----------------------------------------------------------
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh all widgets from the current model state.
            id = obj.mibModel.getActiveId();
            obj.BatchOpt.id = id;

            % Block-mode guard
            if obj.mibModel.I{id}.blockModeSwitch
                dlgOpt.MsgBoxOnly = true;
                dlgOpt.Icon = 'puffin_warning';
                utils.dlgs.inputUniversalDlg(obj.view.gui, ...
                    'Please switch off the Block-mode!', ...
                    {''}, {'Use the corresponding button in the toolbar'}, ...
                    'Block-mode is detected', dlgOpt);
                obj.view.handles.separateBtn.Enable = 'off';
            else
                obj.view.handles.separateBtn.Enable = 'on';
            end

            % Aspect ratio from pixel size
            pixSize = obj.mibModel.I{id}.image.pixSize;
            minPix  = min([pixSize.x pixSize.y pixSize.z]);
            aspectStr = sprintf('%.2f %.2f %.2f', pixSize.x/minPix, pixSize.y/minPix, pixSize.z/minPix);
            obj.view.handles.AspectRatio.Value = aspectStr;
            obj.BatchOpt.AspectRatio = aspectStr;

            % Mode button group: restore selection and disable 3D when single slice
            if obj.mibModel.I{id}.image.depth < 2
                obj.view.handles.mode3dRadio.Enable = 'off';
                obj.view.handles.AspectRatio.Enable = 'off';
                obj.BatchOpt.Mode{1} = 'mode2dCurrentRadio';
            else
                obj.view.handles.mode3dRadio.Enable = 'on';
                obj.view.handles.AspectRatio.Enable = 'on';
            end
            obj.view.handles.modeButtonGroup.SelectedObject = obj.view.handles.(obj.BatchOpt.Mode{1});

            % Color channels
            colorCount       = obj.mibModel.I{id}.image.colors;
            colorChannelList = arrayfun(@(x) sprintf('Ch %d', x), 1:colorCount, 'UniformOutput', false);
            previousIndex = find(strcmp(colorChannelList, obj.BatchOpt.ColorChannel{1}), 1);
            if isempty(previousIndex); previousIndex = 1; end
            obj.view.handles.ColorChannel.Items = colorChannelList;
            obj.view.handles.ColorChannel.Value = colorChannelList{previousIndex};
            obj.BatchOpt.ColorChannel{1} = colorChannelList{previousIndex};
            obj.BatchOpt.ColorChannel{2} = colorChannelList;

            % Material lists
            obj.updateMaterialsBtn_Callback();

            % Mask availability
            if obj.mibModel.I{id}.maskExist == 0
                obj.view.handles.Mask.Enable         = 'off';
                obj.view.handles.Mask.Value          = false;
                obj.view.handles.Selection.Value     = true;
                obj.view.handles.seedsMask.Enable    = 'off';
                obj.view.handles.seedsMask.Value     = false;
                obj.view.handles.seedsSelection.Value = true;
                if strcmp(obj.BatchOpt.ObjectSource{1}, 'Mask')
                    obj.BatchOpt.ObjectSource{1} = 'Selection';
                end
                if strcmp(obj.BatchOpt.SeedSource{1}, 'seedsMask')
                    obj.BatchOpt.SeedSource{1} = 'seedsSelection';
                end
            else
                obj.view.handles.Mask.Enable      = 'on';
                obj.view.handles.seedsMask.Enable = 'on';
            end

            % Subarea limits — reset to full extent on dataset change
            [height, width, depth] = obj.mibModel.I{id}.getDatasetDimensions('selection', 3);
            obj.view.handles.XSubarea.Value = sprintf('1:%d', width);
            obj.view.handles.YSubarea.Value = sprintf('1:%d', height);
            obj.view.handles.ZSubarea.Value = sprintf('1:%d', depth);
            obj.BatchOpt.XSubarea = obj.view.handles.XSubarea.Value;
            obj.BatchOpt.YSubarea = obj.view.handles.YSubarea.Value;
            obj.BatchOpt.ZSubarea = obj.view.handles.ZSubarea.Value;

            % Seeds panel / watershed source / reduce-oversegmentation visibility
            obj.view.handles.seedsPanel.Visible             = obj.BatchOpt.UseSeeds;
            obj.view.handles.watershedSourcePanel.Visible   = obj.BatchOpt.UseSeeds;
            obj.view.handles.ReduceOversegmentation.Visible = ~obj.BatchOpt.UseSeeds;

            % Intensity-mode widgets visibility
            intensityVisibility = 'off';
            if strcmp(obj.BatchOpt.WatershedSource{1}, 'Intensity'); intensityVisibility = 'on'; end
            obj.view.handles.ColorchannelDropDownLabel.Visible = intensityVisibility;
            obj.view.handles.ColorChannel.Visible              = intensityVisibility;
            obj.view.handles.SignalDropDownLabel.Visible       = intensityVisibility;
            obj.view.handles.InvertImage.Visible               = intensityVisibility;
        end

        % -----------------------------------------------------------
        function updateMaterialsBtn_Callback(obj)
            % UPDATEMATERIALSBTN_CALLBACK - Repopulate material dropdowns from the current model.
            id            = obj.BatchOpt.id;
            materialNames = obj.mibModel.I{id}.labels.materialNames;
            modelExists   = obj.mibModel.I{id}.modelExist;

            if ~modelExists || isempty(materialNames)
                obj.view.handles.Model.Enable      = 'off';
                obj.view.handles.ObjectMaterial.Enable  = 'off';
                obj.view.handles.seedsModel.Enable = 'off';
                obj.view.handles.SeedMaterial.Enable    = 'off';
                if strcmp(obj.BatchOpt.ObjectSource{1}, 'Model')
                    obj.BatchOpt.ObjectSource{1} = 'Selection';
                    obj.view.handles.objectSourcePanel.SelectedObject = obj.view.handles.Selection;
                end
                if strcmp(obj.BatchOpt.SeedSource{1}, 'seedsModel')
                    obj.BatchOpt.SeedSource{1} = 'seedsSelection';
                    obj.view.handles.seedSourcePanel.SelectedObject = obj.view.handles.seedsSelection;
                end
            else
                selectedIndex = max(1, obj.mibModel.I{id}.selectedMaterial - 2);
                selectedIndex = min(selectedIndex, numel(materialNames));

                obj.view.handles.ObjectMaterial.Items = materialNames;
                obj.view.handles.ObjectMaterial.Value = materialNames{selectedIndex};
                obj.view.handles.SeedMaterial.Items   = materialNames;
                obj.view.handles.SeedMaterial.Value   = materialNames{selectedIndex};

                obj.BatchOpt.ObjectMaterial{1} = materialNames{selectedIndex};
                obj.BatchOpt.ObjectMaterial{2} = materialNames;
                obj.BatchOpt.SeedMaterial{1}   = materialNames{selectedIndex};
                obj.BatchOpt.SeedMaterial{2}   = materialNames;

                obj.view.handles.Model.Enable      = 'on';
                obj.view.handles.ObjectMaterial.Enable  = 'on';
                obj.view.handles.seedsModel.Enable = 'on';
                obj.view.handles.SeedMaterial.Enable    = 'on';
            end
        end

        % -----------------------------------------------------------
        function modeButtonGroup_Callback(obj, event)
            % MODEBUTTONGROUP_CALLBACK - Sync mode button group selection into BatchOpt.
            obj.BatchOpt.Mode{1} = event.NewValue.Tag;
        end

        % -----------------------------------------------------------
        function objectSourcePanel_Callback(obj, event)
            % OBJECTSOURCEPANEL_CALLBACK - Sync object-source button group into BatchOpt.
            obj.BatchOpt.ObjectSource{1} = event.NewValue.Tag;
        end

        % -----------------------------------------------------------
        function seedSourcePanel_Callback(obj, event)
            % SEEDSOURCEPANEL_CALLBACK - Sync seed-source button group into BatchOpt.
            obj.BatchOpt.SeedSource{1} = event.NewValue.Tag;
        end

        % -----------------------------------------------------------
        function watershedSourceChanged_Callback(obj, event)
            % WATERSHEDSOURCECHANGED_CALLBACK - Toggle intensity-widget visibility.
            obj.BatchOpt.WatershedSource{1} = event.NewValue.Tag;
            intensityVisibility = 'off';
            if strcmp(obj.BatchOpt.WatershedSource{1}, 'Intensity'); intensityVisibility = 'on'; end
            obj.view.handles.ColorchannelDropDownLabel.Visible = intensityVisibility;
            obj.view.handles.ColorChannel.Visible              = intensityVisibility;
            obj.view.handles.SignalDropDownLabel.Visible       = intensityVisibility;
            obj.view.handles.InvertImage.Visible               = intensityVisibility;
        end

        % -----------------------------------------------------------
        function useSeedsCheck_Callback(obj)
            % USESEEDSCHECK_CALLBACK - Toggle seeds panel vs reduce-oversegmentation checkbox.
            obj.BatchOpt.UseSeeds = obj.view.handles.UseSeeds.Value;
            obj.view.handles.seedsPanel.Visible             = obj.BatchOpt.UseSeeds;
            obj.view.handles.watershedSourcePanel.Visible   = obj.BatchOpt.UseSeeds;
            obj.view.handles.ReduceOversegmentation.Visible = ~obj.BatchOpt.UseSeeds;
        end

        % -----------------------------------------------------------
        function aspectRatio_Callback(obj)
            % ASPECTRATIO_CALLBACK - Validate the aspect ratio text field.
            textValue    = obj.view.handles.AspectRatio.Value;
            ratioValues  = str2num(textValue); %#ok<ST2NM>
            if isempty(ratioValues) || numel(ratioValues) ~= 3 || min(ratioValues) <= 0
                utils.dlgs.showErrorDialog(obj.view.gui, ...
                    sprintf('Wrong aspect ratio!\nPlease enter 3 positive numbers separated by spaces.'), ...
                    'Error!');
                pixSize  = obj.mibModel.I{obj.BatchOpt.id}.image.pixSize;
                minPix   = min([pixSize.x pixSize.y pixSize.z]);
                corrected = sprintf('%.3f %.3f %.3f', pixSize.x/minPix, pixSize.y/minPix, pixSize.z/minPix);
                obj.view.handles.AspectRatio.Value = corrected;
                obj.BatchOpt.AspectRatio = corrected;
                return;
            end
            obj.BatchOpt.AspectRatio = textValue;
        end

        % -----------------------------------------------------------
        function checkDimensions(obj, hObject)
            % CHECKDIMENSIONS - Validate a subarea text field (XSubarea, YSubarea, ZSubarea).
            textValue  = hObject.Value;
            typedValue = str2num(textValue); %#ok<ST2NM>
            id = obj.BatchOpt.id;
            [height, width, depth] = obj.mibModel.I{id}.getDatasetDimensions('selection', 3);
            switch hObject.Tag
                case 'XSubarea'; maxValue = width;
                case 'YSubarea'; maxValue = height;
                case 'ZSubarea'; maxValue = depth;
                otherwise;       return;
            end
            if isempty(typedValue) || min(typedValue) < 1 || max(typedValue) > maxValue
                corrected = sprintf('1:%d', maxValue);
                hObject.Value = corrected;
                obj.BatchOpt.(hObject.Tag) = corrected;
                utils.dlgs.showErrorDialog(obj.view.gui, 'Please check the values!', 'Wrong parameters!');
                return;
            end
            obj.BatchOpt.(hObject.Tag) = textValue;
        end

        % -----------------------------------------------------------
        function validateBinning(obj)
            % VALIDATEBINNING - Validate and normalise the Binning text field.
            textValue = obj.view.handles.Binning.Value;
            binValues = str2num(textValue); %#ok<ST2NM>
            if isempty(binValues) || numel(binValues) < 2 || isnan(binValues(1)) || min(binValues) <= 0.5
                binValues = [1; 1];
            else
                binValues = round(binValues(:));
            end
            corrected = sprintf('%d; %d', binValues(1), binValues(2));
            obj.view.handles.Binning.Value = corrected;
            obj.BatchOpt.Binning = corrected;
        end

        % -----------------------------------------------------------
        function resetDimsBtn_Callback(obj)
            % RESETDIMSBTN_CALLBACK - Reset subarea fields to the full dataset extent.
            id = obj.BatchOpt.id;
            [height, width, depth] = obj.mibModel.I{id}.getDatasetDimensions('selection', 3);
            newX = sprintf('1:%d', width);
            newY = sprintf('1:%d', height);
            newZ = sprintf('1:%d', depth);
            obj.view.handles.XSubarea.Value = newX;
            obj.view.handles.YSubarea.Value = newY;
            obj.view.handles.ZSubarea.Value = newZ;
            obj.view.handles.Binning.Value  = '1; 1';
            obj.BatchOpt.XSubarea = newX;
            obj.BatchOpt.YSubarea = newY;
            obj.BatchOpt.ZSubarea = newZ;
            obj.BatchOpt.Binning  = '1; 1';
        end

        % -----------------------------------------------------------
        function currentViewBtn_Callback(obj)
            % CURRENTVIEWBTN_CALLBACK - Set X/Y subarea from the currently visible viewport.
            id = obj.BatchOpt.id;
            [yMin, yMax, xMin, xMax] = obj.mibModel.I{id}.getCoordinatesOfShownImage();
            newX = sprintf('%d:%d', xMin, xMax);
            newY = sprintf('%d:%d', yMin, yMax);
            obj.view.handles.XSubarea.Value = newX;
            obj.view.handles.YSubarea.Value = newY;
            obj.BatchOpt.XSubarea = newX;
            obj.BatchOpt.YSubarea = newY;
        end

        % -----------------------------------------------------------
        function subAreaFromSelectionBtn_Callback(obj)
            % SUBAREAFROMESELECTIONBTN_CALLBACK - Derive subarea bounds from the selection bounding box.
            id = obj.BatchOpt.id;
            originalColor = obj.view.handles.subAreaFromSelectionBtn.BackgroundColor;
            obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = [1 0 0];
            drawnow;

            options.id = id;
            isCurrentSliceMode = strcmp(obj.BatchOpt.Mode{1}, 'mode2dCurrentRadio');

            if isCurrentSliceMode
                selectionImage = cell2mat(obj.mibModel.getData2D('selection', [], [], [], options));
                regionStats    = regionprops(selectionImage, 'BoundingBox');
                if isempty(regionStats)
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('Selection layer was not found!\nPlease make sure that the Selection layer is shown in the Image View panel.'), ...
                        'Missing Selection');
                    obj.resetDimsBtn_Callback();
                    obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = originalColor;
                    return;
                end
                bb  = regionStats(1).BoundingBox;
                newX = sprintf('%d:%d', ceil(bb(1)), ceil(bb(1)) + bb(3) - 1);
                newY = sprintf('%d:%d', ceil(bb(2)), ceil(bb(2)) + bb(4) - 1);
                obj.view.handles.XSubarea.Value = newX;
                obj.view.handles.YSubarea.Value = newY;
                obj.BatchOpt.XSubarea = newX;
                obj.BatchOpt.YSubarea = newY;
            else
                selectionVolume = cell2mat(obj.mibModel.getData3D('selection', [], 3, [], options));
                regionStats     = regionprops(selectionVolume, 'BoundingBox');
                if isempty(regionStats)
                    utils.dlgs.showErrorDialog(obj.view.gui, ...
                        sprintf('Selection layer was not found!\nPlease make sure that the Selection layer is shown in the Image View panel.'), ...
                        'Missing Selection');
                    obj.resetDimsBtn_Callback();
                    obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = originalColor;
                    return;
                end
                bb   = regionStats(1).BoundingBox;
                newX = sprintf('%d:%d', ceil(bb(1)), ceil(bb(1)) + bb(4) - 1);
                newY = sprintf('%d:%d', ceil(bb(2)), ceil(bb(2)) + bb(5) - 1);
                newZ = sprintf('%d:%d', ceil(bb(3)), ceil(bb(3)) + bb(6) - 1);
                obj.view.handles.XSubarea.Value = newX;
                obj.view.handles.YSubarea.Value = newY;
                obj.view.handles.ZSubarea.Value = newZ;
                obj.BatchOpt.XSubarea = newX;
                obj.BatchOpt.YSubarea = newY;
                obj.BatchOpt.ZSubarea = newZ;
            end
            obj.view.handles.subAreaFromSelectionBtn.BackgroundColor = originalColor;
        end

        % -----------------------------------------------------------
        function helpButton_Callback(obj)
            % HELPBUTTON_CALLBACK - Open the object separation documentation page.
            web(fullfile(obj.mibModel.mibPath, 'techdoc/html/ug_gui_menu_tools_objseparation.html'), '-helpbrowser');
        end

        % Main processing is in a separate file
        doObjectSeparation(obj)
    end
end
