classdef QuantificationProperties < handle
    % classdef QuantificationProperties < handle
    % controller for the property selection dialog used by Quantification
    %
    % Lets the user pick which shape and intensity properties to calculate
    % in a multi-property quantification run.  Displays a panel of
    % checkboxes matching the current 2D or 3D shape mode, plus an
    % intensity panel.
    %
    % @code
    % obj.startController('controllers.QuantificationProperties', obj, propertyList, obj3d);
    % @endcode

    % Updates
    %

    properties
        mibModel
        % handle to MibModel
        view
        % handle to core.ChildView (views.QuantificationPropertiesGUI)
        parentController
        % handle to the parent Quantification controller
        listener
        % cell array with handles to event listeners
        obj3d
        % logical flag: true for 3D mode, false for 2D mode
        propertyList
        % cell array of initially selected property names
    end

    events
        closeEvent
        % fires when the dialog is closed; caught by parent to clean up
    end

    methods

        function obj = QuantificationProperties(mibModel, varargin)
            % function obj = QuantificationProperties(mibModel, varargin)
            % constructor for QuantificationProperties controller
            %
            % Parameters:
            % mibModel: handle to MibModel
            % varargin{1}: handle to parent Quantification controller
            % varargin{2}: cell array of pre-selected property names
            % varargin{3}: logical — true for 3D shape mode
            %
            %|
            % @b Examples:
            % @code obj.startController('controllers.QuantificationProperties', obj, {'Area','Perimeter'}, false); @endcode

            % Updates
            %

            obj.mibModel = mibModel;

            obj.parentController = [];
            obj.propertyList = {};
            obj.obj3d = false;
            obj.listener = {};

            if numel(varargin) >= 1; obj.parentController = varargin{1}; end
            if numel(varargin) >= 2; obj.propertyList = varargin{2}; end
            if numel(varargin) >= 3; obj.obj3d = varargin{3}; end

            guiName = 'views.QuantificationPropertiesGUI';
            obj.view = core.ChildView(obj, guiName);

            obj.addCallbacks();

            % update font and size
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.CheckallButton.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.CheckallButton.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.updateWidgets();

            % position the dialog next to the parent Quantification window
            parentGui = obj.mibModel.mibGUI;
            if ~isempty(obj.parentController) && isvalid(obj.parentController) && ...
                    ~isempty(obj.parentController.view) && isvalid(obj.parentController.view.gui)
                parentGui = obj.parentController.view.gui;
            end
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, parentGui, 'right');
            obj.view.gui.Visible = 'on';
        end

        function addCallbacks(obj)
            % function addCallbacks(obj)
            % Wire all widget callbacks from the constructor.
            %
            % Connects button callbacks and the figure close/key-press handlers
            % for the QuantificationProperties dialog.
            %
            %|
            % @b Examples:
            % @code obj.addCallbacks(); @endcode

            % Updates
            %

            h = obj.view.handles;

            h.OKButton.ButtonPushedFcn         = @(~,~) obj.okBtn_Callback();
            h.CancelButton.ButtonPushedFcn     = @(~,~) obj.cancelBtn_Callback();
            h.CheckallButton.ButtonPushedFcn   = @(~,~) obj.checkallBtn_Callback();
            h.UncheckallButton.ButtonPushedFcn = @(~,~) obj.uncheckallBtn_Callback();

            obj.view.gui.CloseRequestFcn   = @(~,~) obj.cancelBtn_Callback();
            obj.view.gui.WindowKeyPressFcn = @(h,d) utils.childWindowKeyPressFcn(obj, h, d);
        end

        function updateWidgets(obj)
            % function updateWidgets(obj)
            % Show the correct shape panel and pre-check checkboxes from propertyList.
            %
            % In 3D mode the shapes2dPanel is hidden and the shapes3dPanel is
            % placed into the main grid layout at the same position.  Disabled
            % 3D-only checkboxes are enabled.  Each property name in
            % obj.propertyList is mapped to the corresponding checkbox and checked.
            %
            %|
            % @b Examples:
            % @code obj.updateWidgets(); @endcode

            % Updates
            %

            h = obj.view.handles;

            % --- swap panels for 3D mode ---
            if obj.obj3d
                h.shapes2dPanel.Visible = 'off';
                h.shapes3dPanel.Parent = h.mainGridLayout;
                h.shapes3dPanel.Layout.Row = 1;
                h.shapes3dPanel.Layout.Column = [1 2];
                h.shapes3dPanel.Visible = 'on';

                % enable checkboxes that are disabled by default in the mlapp
                h.ConvexVolume3d.Enable = 'on';
                h.EquivDiameter3d.Enable = 'on';
                h.Extent3d.Enable = 'on';
                h.Solidity3d.Enable = 'on';
                h.SurfaceArea3d.Enable = 'on';
            end

            % --- pre-check checkboxes matching propertyList ---
            tags = obj.propertyList;
            if isempty(tags); return; end

            % remove HolesArea — no checkbox for it
            tags(ismember(tags, 'HolesArea')) = [];

            % for 3D mode, shape property tags have a '3d' suffix
            if obj.obj3d
                intensityProps = {'Correlation','MinIntensity','MaxIntensity', ...
                    'MeanIntensity','SumIntensity','StdIntensity'};
                for i = 1:numel(tags)
                    if ~ismember(tags{i}, intensityProps)
                        tags{i} = [tags{i} '3d'];
                    end
                end
            end

            for i = 1:numel(tags)
                if isfield(obj.view.handles, tags{i})
                    obj.view.handles.(tags{i}).Value = true;
                end
            end
        end

        function okBtn_Callback(obj)
            % function okBtn_Callback(obj)
            % Collect selected properties, pass them to the parent, and close.
            %
            % Iterates over shape and intensity checkboxes.  For 3D mode the
            % trailing '3d' suffix is stripped from each tag to recover the
            % canonical property name.  If at least one property is selected the
            % list is forwarded to the parent controller via
            % applySelectedProperties before closing the dialog.
            %
            %|
            % @b Examples:
            % @code obj.okBtn_Callback(); @endcode

            % Updates
            %

            h = obj.view.handles;
            properties = {};

            % --- collect shape properties ---
            if obj.obj3d
                list = findall(h.shapes3dPanel, 'Type', 'uicheckbox');
                for i = 1:numel(list)
                    if list(i).Value
                        tag = list(i).Tag;
                        properties{end+1} = tag(1:end-2); %#ok<AGROW> strip '3d'
                    end
                end
            else
                list = findall(h.shapes2dPanel, 'Type', 'uicheckbox');
                for i = 1:numel(list)
                    if list(i).Value
                        properties{end+1} = list(i).Tag; %#ok<AGROW>
                    end
                end
            end

            % --- collect intensity properties ---
            list = findall(h.intensityPanel, 'Type', 'uicheckbox');
            for i = 1:numel(list)
                if list(i).Value
                    properties{end+1} = list(i).Tag; %#ok<AGROW>
                end
            end

            % --- pass result to parent and close ---
            if ~isempty(properties) && ~isempty(obj.parentController) && isvalid(obj.parentController)
                obj.parentController.applySelectedProperties(properties);
            end
            obj.closeWindow();
        end

        function cancelBtn_Callback(obj)
            % function cancelBtn_Callback(obj)
            % Close the dialog without updating the parent controller.
            %
            %|
            % @b Examples:
            % @code obj.cancelBtn_Callback(); @endcode

            % Updates
            %

            obj.closeWindow();
        end

        function checkallBtn_Callback(obj)
            % function checkallBtn_Callback(obj)
            % Check all enabled checkboxes, excluding specialty properties.
            %
            % Skips CurveLength, EndpointsLength (and their 3D variants), and
            % Correlation because these require special connectivity or dual
            % channels.  Disabled checkboxes are also skipped.
            %
            %|
            % @b Examples:
            % @code obj.checkallBtn_Callback(); @endcode

            % Updates
            %

            h = obj.view.handles;
            excludeList = {'CurveLength', 'EndpointsLength', 'EndpointsLength3d', 'Correlation'};

            % --- shape checkboxes ---
            if obj.obj3d
                list = findall(h.shapes3dPanel, 'Type', 'uicheckbox');
            else
                list = findall(h.shapes2dPanel, 'Type', 'uicheckbox');
            end
            for i = 1:numel(list)
                if list(i).Enable && ~ismember(list(i).Tag, excludeList)
                    list(i).Value = true;
                end
            end

            % --- intensity checkboxes ---
            list = findall(h.intensityPanel, 'Type', 'uicheckbox');
            for i = 1:numel(list)
                if ~ismember(list(i).Tag, excludeList)
                    list(i).Value = true;
                end
            end
        end

        function uncheckallBtn_Callback(obj)
            % function uncheckallBtn_Callback(obj)
            % Uncheck all checkboxes in all three panels.
            %
            %|
            % @b Examples:
            % @code obj.uncheckallBtn_Callback(); @endcode

            % Updates
            %

            h = obj.view.handles;
            list = findall(h.shapes2dPanel, 'Type', 'uicheckbox');
            set(list, 'Value', false);
            list = findall(h.shapes3dPanel, 'Type', 'uicheckbox');
            set(list, 'Value', false);
            list = findall(h.intensityPanel, 'Type', 'uicheckbox');
            set(list, 'Value', false);
        end

        function closeWindow(obj)
            % function closeWindow(obj)
            % Close the QuantificationProperties dialog and release all resources.
            %
            % Deletes the GUI figure, removes all event listeners, and fires
            % the closeEvent so the parent controller can purge this child.
            %
            %|
            % @b Examples:
            % @code obj.closeWindow(); @endcode

            % Updates
            %

            if isvalid(obj.view.gui)
                delete(obj.view.gui);
            end
            for i = 1:numel(obj.listener)
                delete(obj.listener{i});
            end
            notify(obj, 'closeEvent');
        end

    end % methods
end
