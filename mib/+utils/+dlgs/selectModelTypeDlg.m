classdef selectModelTypeDlg < handle
% SELECTMODELTYPEDLG - Controller for the Select Model Type dialog.
%
% Displays a dialog with radio buttons that let the user choose
% the model type (63 / 255 / 16383 / 65535 / 4294967295 materials, and
% 1073741823 for BigData).
% A description text area updates to explain the selected type.
% Logic ported from MIB2 mibSelectModelTypeDlg.m.
%
% The 16383 radio button is not part of ``views.SelectModelTypeGUI``: it is
% created in ``initView``, which also grows the figure by one row, so the
% .mlapp did not have to change. The 1073741823 radio button (packed uint32
% instance model, BigData only) is created the same way, below 16383, and only
% when ``allowedTypes`` holds it, so the dialog of a Standard dataset keeps its
% five types.
%
% Usage:
%   Example 1::
%
%       dlg = utils.dlgs.selectModelTypeDlg(obj.mibModel.getProgressBarParent(), obj.mibModel.mibPath);
%       modelType = dlg.run();
%       if isempty(modelType); return; end
%
%   Example 2 - offer only the packed types, as for a BigData dataset::
%
%       dlg = utils.dlgs.selectModelTypeDlg(parentFig, mibPath, [63 16383 1073741823]);
%

    properties (Access = private)
        view            % handle to views.SelectModelTypeGUI App Designer app
        ParentFigure    % handle to the parent GUI figure
        mibPath         % path to MIB installation directory (for icons)
        material16383   % radio button for the packed uint16 instance model, created in initView
        material1073741823  % radio button for the packed uint32 instance model (BigData), created in initView when allowed; [] otherwise
        allowedTypes    % model types that can be selected; the other radio buttons are disabled
        typeButtons     % {modelType, radioButton} rows in display order, built in initView

        % Output state
        selectedModelType = 63;   % default; set to [] on Cancel
    end

    % Description strings, one per model type
    properties (Constant, Access = private)
        Descriptions = { ...
            63,         ['This model type is recommended for general use. ' ...
                         'It is limited to 63 materials but is the fastest in performance ' ...
                         'and requires less memory than all other model types.']; ...
            255,        ['This model type supports up to 255 materials. ' ...
                         'It requires additionally the same amount of memory ' ...
                         'as a loaded 8-bit dataset.']; ...
            16383,      ['This instance model supports up to 16383 objects. ' ...
                         'Objects, mask and selection share one 16-bit layer, so it requires ' ...
                         'additionally the same amount of memory as a loaded 16-bit dataset. ' ...
                         'It is the instance model available for BigData datasets.']; ...
            65535,      ['This model type supports up to 65535 materials. ' ...
                         'It requires additionally the same amount of memory ' ...
                         'as a loaded 16-bit dataset.']; ...
            4294967295, ['This model type supports up to 4294967295 materials. ' ...
                         'It requires additionally the same amount of memory ' ...
                         'as a loaded 32-bit dataset.']; ...
            1073741823, ['This instance model supports up to 1073741823 objects. ' ...
                         'Objects, mask and selection share one 32-bit layer, so the model ' ...
                         'store takes 4 bytes per voxel, twice the 16383 model. ' ...
                         'Available for BigData datasets only.'] }
    end

    methods
        function obj = selectModelTypeDlg(ParentFigure, mibPath, allowedTypes)
            % SELECTMODELTYPEDLG - Constructor.
            %
            % Syntax:
            %   function obj = selectModelTypeDlg(ParentFigure, mibPath, allowedTypes)
            %
            % Input Arguments:
            %   - **ParentFigure** - handle to the parent GUI (AppContainer or uifigure);
            %     used to center the dialog. In MIB pass ``obj.mibModel.getProgressBarParent()``
            %     so the dialog follows the active dataset window when it is undocked.
            %   - **mibPath** - *(optional)* char, path to the MIB installation directory;
            %     used to locate icon images.  Pass [] or '' to use auto-detection.
            %   - **allowedTypes** - *(optional)* numeric vector of the model types that
            %     can be selected; the radio buttons of the other types are disabled and
            %     the first allowed type is preselected. Default: the five types of a
            %     Standard dataset. Include ``1073741823`` to add the packed uint32
            %     instance model (BigData).
            %

            if nargin < 3 || isempty(allowedTypes); allowedTypes = [63 255 16383 65535 4294967295]; end
            if nargin < 2; mibPath = ''; end
            if nargin < 1; ParentFigure = []; end

            obj.ParentFigure = ParentFigure;
            obj.mibPath      = mibPath;
            obj.allowedTypes = allowedTypes;

            % Instantiate the App Designer view
            obj.view = views.SelectModelTypeGUI;
            utils.applyThemeColors(obj.view.Figure);   % adapt the standard dialog button colors to the light/dark theme

            % Wire up all widget callbacks and set initial state
            obj.initView();
            iconFile = fullfile(obj.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
            if exist(iconFile, 'file'); obj.view.Figure.Icon = iconFile; end
        end

        function modelType = run(obj)
            % RUN - Block execution and return the selected model type.
            %
            % Syntax:
            %   function modelType = run(obj)
            %
            % Output Arguments:
            %   - **modelType** - one of {63, 255, 16383, 1073741823, 65535, 4294967295},
            %     or [] if cancelled
            %

            obj.view.Figure.WindowStyle = 'modal';
            obj.view.Figure.Visible = 'on';
            uiwait(obj.view.Figure);

            % Handle abrupt window close (view deleted before uiresume)
            if ~isvalid(obj.view)
                modelType = [];
                return;
            end

            modelType = obj.selectedModelType;
            delete(obj.view);
        end
    end

    % -----------------------------------------------------------------------
    methods (Access = private)

        function initView(obj)
            % INITVIEW - Configure the view before it becomes visible.
            %
            % Syntax:
            %   function initView(obj)
            %

            fig = obj.view.Figure;
            fig.Name = 'Select model type';

            % Add the 16383 radio button between 255 and 65535: one more 22-px row.
            % The button group sits in the '1x' row of the grid, so growing the
            % figure grows the group; button positions are from its bottom edge.
            rowStep = 22;
            fig.Position(4) = fig.Position(4) + rowStep;
            obj.view.material63.Position(2)  = obj.view.material63.Position(2)  + rowStep;
            obj.view.material255.Position(2) = obj.view.material255.Position(2) + rowStep;
            obj.material16383 = uiradiobutton(obj.view.modelTypeButtonGroup, ...
                'Text', '16383 materials', ...
                'Position', [obj.view.material65535.Position(1), ...
                    obj.view.material65535.Position(2) + rowStep, 160, 22]);
            typeButtons = {63, obj.view.material63; 255, obj.view.material255; ...
                16383, obj.material16383; 65535, obj.view.material65535; ...
                4294967295, obj.view.material4294967295};

            % The packed uint32 instance model (BigData) goes between 65535 and
            % 4294967295, one more row, and only when the caller allows it
            if ismember(1073741823, obj.allowedTypes)
                fig.Position(4) = fig.Position(4) + rowStep;
                obj.view.material63.Position(2)    = obj.view.material63.Position(2)    + rowStep;
                obj.view.material255.Position(2)   = obj.view.material255.Position(2)   + rowStep;
                obj.material16383.Position(2)      = obj.material16383.Position(2)      + rowStep;
                obj.view.material65535.Position(2) = obj.view.material65535.Position(2) + rowStep;
                obj.material1073741823 = uiradiobutton(obj.view.modelTypeButtonGroup, ...
                    'Text', '1073741823 materials', ...
                    'Position', [obj.view.material4294967295.Position(1), ...
                        obj.view.material4294967295.Position(2) + rowStep, ...
                        max(160, obj.view.material4294967295.Position(3)), 22]);
                typeButtons = [typeButtons(1:4, :); {1073741823, obj.material1073741823}; typeButtons(5, :)];
            end

            obj.typeButtons = typeButtons;

            % disable the types the caller does not allow; preselect the first allowed
            for typeIndex = 1:size(typeButtons, 1)
                typeButtons{typeIndex, 2}.Enable = ismember(typeButtons{typeIndex, 1}, obj.allowedTypes);
            end
            firstAllowed = find(ismember([typeButtons{:, 1}], obj.allowedTypes), 1);
            typeButtons{firstAllowed, 2}.Value = true;

            % Center on parent
            utils.moveWindowOutside(fig, obj.ParentFigure, 'center', 'center');

            % Set icon - pick any available puffin_quest image
            mibDir = obj.mibPath;
            if isempty(mibDir)
                mibDir = fileparts(which('mib3'));
                if isempty(mibDir); mibDir = pwd; end
            end
            iconPath = fullfile(mibDir, 'assets', 'images', ...
                sprintf('puffin_quest_%d_96px.png', randi(7)));
            if exist(iconPath, 'file')
                obj.view.iconImage.ImageSource = iconPath;
            end

            % Show description for the preselected type
            obj.updateDescription(typeButtons{firstAllowed, 2});

            % Wire callbacks
            obj.view.modelTypeButtonGroup.SelectionChangedFcn = @(~, evt) obj.onSelectionChanged(evt);
            obj.view.okBtn.ButtonPushedFcn                    = @(~, ~)   obj.onOK();
            obj.view.cancelBtn.ButtonPushedFcn                = @(~, ~)   obj.onCancel();
            % WindowKeyPressFcn fires regardless of which widget has focus;
            % KeyPressFcn is a fallback for when the figure itself is focused.
            fig.WindowKeyPressFcn                             = @(~, evt) obj.onKeyPress(evt);
            fig.KeyPressFcn                                   = @(~, evt) obj.onKeyPress(evt);
            fig.CloseRequestFcn                               = @(~, ~)   obj.onCancel();
        end

        function updateDescription(obj, radioBtn)
            % UPDATEDESCRIPTION - Update the description text area for radioBtn.
            %
            % Syntax:
            %   function updateDescription(obj, radioBtn)
            %

            txt = '';
            modelType = obj.typeOfButton(radioBtn);
            if ~isempty(modelType)
                txt = obj.Descriptions{[obj.Descriptions{:, 1}] == modelType, 2};
            end
            obj.view.modelDescriptionText.Value = {txt};
        end

        function modelType = typeOfButton(obj, radioBtn)
            % TYPEOFBUTTON - model type of a radio button, [] when it is none of them
            modelType = [];
            for typeIndex = 1:size(obj.typeButtons, 1)
                if obj.typeButtons{typeIndex, 2} == radioBtn
                    modelType = obj.typeButtons{typeIndex, 1};
                    return;
                end
            end
        end

        % ---- Callbacks ----

        function onSelectionChanged(obj, event)
            obj.updateDescription(event.NewValue);
        end

        function onOK(obj)
            % ONOK - Read selected radio button and store result.
            %
            % Syntax:
            %   function onOK(obj)
            %
            obj.selectedModelType = obj.typeOfButton(obj.view.modelTypeButtonGroup.SelectedObject);
            if isempty(obj.selectedModelType); obj.selectedModelType = 63; end
            uiresume(obj.view.Figure);
        end

        function onCancel(obj)
            obj.selectedModelType = [];
            uiresume(obj.view.Figure);
        end

        function onKeyPress(obj, event)
            switch event.Key
                case 'return';  obj.onOK();
                case 'escape';  obj.onCancel();
            end
        end

    end
end
