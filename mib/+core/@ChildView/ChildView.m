classdef ChildView < handle
    % CHILDVIEW - Base template class for View-type controller GUI components.
    %
    % Provides the foundation for all child dialog and panel views in MIB3.
    % Handles initialization of AppDesigner GUI components and manages
    % relationships with controller and model objects.
    
	% Updates
	%
    
    properties
        gui
        % handle to the main gui Figure
        mibModel
        % handles to the model
        Controller
        % handles to the controller
        handles
        % a list of handles for the gui
        Figure
        % handle to the for GUI made with AppDesigner
    end
    
    methods
        function obj = ChildView(controller, guiName)
            obj.Controller = controller;
            obj.mibModel = controller.mibModel;
            fh = str2func(guiName);     % string to function
            obj.gui = fh(obj.Controller);   % init the gui
            
            if isprop(obj.gui, 'Figure')  % appDesigner app

                % copy property names to Tag field, to have it similar to GUIDE usage
                propList = properties(obj.gui);
                for propId = 1:numel(propList)
                    if isprop(obj.gui.(propList{propId}), 'Tag')
                        obj.gui.(propList{propId}).Tag = propList{propId};
                    end
                end
                guiHandle = obj.gui.Figure;
                obj.getChildren(guiHandle);
                
                obj.Figure = obj.gui;
                obj.gui = obj.gui.Figure;
            else   % guide app
                % extract handles to widgets of the main GUI
                figHandles = findobj(obj.gui);
                for i=1:numel(figHandles)
                    if ~isempty(figHandles(i).Tag)  % some context menu comes without Tags
                        obj.handles.(figHandles(i).Tag) = figHandles(i);
                    end
                end
            end
            % add listner to obj.mibModel and call controller function as a callback
            %obj.Controller.listener{1} = addlistener(obj.mibModel, 'Id', 'PostSet', @(src,evnt) obj.Controller.ViewListner_Callback(obj.Controller, src, evnt));     % for static
            %obj.Controller.listener{2} = addlistener(obj.mibModel, 'newDatasetSwitch', 'PostSet', @(src,evnt) obj.Controller.ViewListner_Callback(obj.Controller, src, evnt));     % for static
        end
        
        function getChildren(obj, guiHandle)
            % GETCHILDREN - Recursively get handles to GUI element children.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.getChildren(guiHandle)
            %
            % Recursively traverses the GUI hierarchy and assigns all child widget handles
            % to the ``obj.handles`` structure for easy access by tag name.
            %
            % Input Arguments:
            %   - **guiHandle** — [handle] parent GUI element whose children to enumerate
            %
            childrenList = guiHandle.Children;
            for i=1:numel(childrenList)     % generate handles structure similar to guide
                obj.handles.(childrenList(i).Tag) = childrenList(i);
                switch childrenList(i).Type
                    case {'uigridlayout', 'uipanel', 'uibuttongroup', 'uitabgroup', 'uitab', 'uitree', 'uicontextmenu', 'uimenu'}
                        obj.getChildren(obj.handles.(childrenList(i).Tag));
                    otherwise
                        %childrenList(i).Type
                end
            end
        end
    end
end
