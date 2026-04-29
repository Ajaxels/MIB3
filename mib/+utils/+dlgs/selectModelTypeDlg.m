classdef selectModelTypeDlg < handle
% SELECTMODELTYPEDLG - Controller for the Select Model Type dialog.
%
% Displays a dialog with four radio buttons that let the user choose
% the model type (63 / 255 / 65535 / 4294967295 materials).
% A description text area updates to explain the selected type.
% Logic ported from MIB2 mibSelectModelTypeDlg.m.
%
% Usage:
%   Example 1::
%
%       dlg = utils.dlgs.selectModelTypeDlg(obj.mibModel.mibGUI, obj.mibModel.mibPath);
%       modelType = dlg.run();
%       if isempty(modelType); return; end
%

    properties (Access = private)
        view            % handle to views.SelectModelTypeGUI App Designer app
        ParentFigure    % handle to the parent GUI figure
        mibPath         % path to MIB installation directory (for icons)

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
            65535,      ['This model type supports up to 65535 materials. ' ...
                         'It requires additionally the same amount of memory ' ...
                         'as a loaded 16-bit dataset.']; ...
            4294967295, ['This model type supports up to 4294967295 materials. ' ...
                         'It requires additionally the same amount of memory ' ...
                         'as a loaded 32-bit dataset.'] }
    end

    methods
        function obj = selectModelTypeDlg(ParentFigure, mibPath)
            % SELECTMODELTYPEDLG - Constructor.
            %
            % Syntax:
            %   function obj = selectModelTypeDlg(ParentFigure, mibPath)
            %
            % Input Arguments:
            %   - **ParentFigure** — handle to the parent GUI (AppContainer or uifigure);
            %     used to center the dialog
            %   - **mibPath** — *(optional)* char, path to the MIB installation directory;
            %     used to locate icon images.  Pass [] or '' to use auto-detection.
            %

            if nargin < 2; mibPath = ''; end
            if nargin < 1; ParentFigure = []; end

            obj.ParentFigure = ParentFigure;
            obj.mibPath      = mibPath;

            % Instantiate the App Designer view
            obj.view = views.SelectModelTypeGUI;

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
            %   - **modelType** — one of {63, 255, 65535, 4294967295}, or [] if cancelled
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

            % Center on parent
            utils.moveWindowOutside(fig, obj.ParentFigure, 'center', 'center');

            % Set icon — pick any available puffin_quest image
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

            % Show description for the default selection (63)
            obj.updateDescription(obj.view.material63);

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

            switch radioBtn
                case obj.view.material63
                    txt = obj.Descriptions{1, 2};
                case obj.view.material255
                    txt = obj.Descriptions{2, 2};
                case obj.view.material65535
                    txt = obj.Descriptions{3, 2};
                case obj.view.material4294967295
                    txt = obj.Descriptions{4, 2};
                otherwise
                    txt = '';
            end
            obj.view.modelDescriptionText.Value = {txt};
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
            selected = obj.view.modelTypeButtonGroup.SelectedObject;
            switch selected
                case obj.view.material63
                    obj.selectedModelType = 63;
                case obj.view.material255
                    obj.selectedModelType = 255;
                case obj.view.material65535
                    obj.selectedModelType = 65535;
                case obj.view.material4294967295
                    obj.selectedModelType = 4294967295;
                otherwise
                    obj.selectedModelType = 63;
            end
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
