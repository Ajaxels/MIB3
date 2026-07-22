classdef VolRenAppViewer < handle
    % VOLRENAPPVIEWER - Viewer window controller for 3D volume rendering.
    %
    % Syntax:
    %   .. code-block:: matlab
    %
    %      obj.startController('controllers.VolRenAppViewer');
    %
    % **Example 1** — launch as interactive GUI tool:
    %
    %   .. code-block:: matlab
    %
    %      obj.startController('controllers.VolRenAppViewer');
    %
    % **Example 2** — launch in batch mode:
    %
    %   .. code-block:: matlab
    %
    %      BatchOpt.Parameter = 'test';
    %      BatchOpt.Checkbox = true;
    %      BatchOpt.Popup = {'value'};
    %      BatchOpt.Radio = {'Radio1'};
    %      BatchOpt.showWaitbar = true;
    %      obj.startController('controllers.VolRenAppViewer', [], BatchOpt);
    %
    % **Example 3** — trigger return of available options via ``syncBatch`` event:
    %
    %   .. code-block:: matlab
    %
    %      obj.startController('controllers.VolRenAppViewer', [], NaN);
    
	% Updates
	%     
    
    properties
        mibModel
        % handles to mibModel
        view
        % handle to the view / mibVolRenAppViewerGUI
        listener
        % a cell array with handles to listeners
    end
    
    events
        %> Description of events
        CloseEvent
        % event firing when window is closed
    end
    
    methods (Static)
        function ViewListner_Callback(obj, src, evnt)
            switch evnt.EventName
                case {'updateGuiWidgets'}
                    obj.updateWidgets();
            end
        end
    end
    
    methods
        function obj = VolRenAppViewer(mibModel, varargin)
            % VOLRENAPPVIEWER - Class constructor for the VolRenAppViewer controller.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj = VolRenAppViewer(mibModel)
            %      obj = VolRenAppViewer(mibModel, parentController)
            %
            % Input Arguments:
            %   - **mibModel** — [handle] handle to the MibModel instance
            %   - **varargin{1}** *(optional)* — [handle] handle to the parent VolRenApp controller
            %
            % **Example 1** — start VolRenAppViewer from a parent controller:
            %
            %   .. code-block:: matlab
            %
            %      utils.startController(obj, 'controllers.VolRenAppViewer', obj);
            %

            obj.mibModel = mibModel;    % assign model
            
            guiName = 'views.VolRenAppViewerGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            
            % move the window to the left hand side of the main window
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'center');
            
            obj.updateWidgets();
            %drawnow limitrate;
            %pause(1);

			% add listner to obj.mibModel and call controller function as a callback
            obj.listener{1} = addlistener(obj.mibModel, 'UpdateGuiWidgets', @(src,evnt) obj.ViewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
            
            % show the gui
            obj.view.gui.Visible = true;
            
            drawnow;

        end
        
        function closeWindow(obj)
            % CLOSEWINDOW - Close the VolRenAppViewer window and release resources.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.closeWindow()
            if obj.mibModel.preferences.System.DeveloperMode
                fprintf('controllers.VolRenAppViewer.closeWindow: triggered\n');
            end
            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end
            
            % delete listeners, otherwise they stay after deleting of the
            % controller
            for i=1:numel(obj.listener)
                delete(obj.listener{i});
            end
            
            notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
        end
        
        function updateWidgets(obj)
            % UPDATEWIDGETS - Refresh all widgets in the VolRenAppViewer panel.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets()
            
            %fprintf('childController:updateWidgets: %g\n', toc);
        end
        
        
    end
end