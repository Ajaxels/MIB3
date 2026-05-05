classdef VolRenAppViewer < handle
    % @type VolRenAppViewer class is a template class for using with
    % GUI developed using appdesigner of Matlab
    %
    % @code
    % obj.startController('controllers.VolRenAppViewer'); // as GUI tool
    % @endcode
    % or 
    % @code 
    % // a code below was used for mibImageArithmeticController
    % BatchOpt.Parameter = 'test';  // fill edit boxes as strings
    % BatchOpt.Checkbox = true;     // fill checkboxes with logicals: true/false
    % BatchOpt.Popup = {'value'};        // value for the popups as a cell
    % BatchOpt.Radio = {'Radio1'};          // selection of radio buttons, as cell with the handle of the target radio button
    % BatchOpt.showWaitbar = true;  // show or not the waitbar
    % obj.startController('controllers.VolRenAppViewer', [], BatchOpt); // start VolRenAppViewer in the batch mode
    % @endcode
    % or
    % @code
    % // trigger return of the possible Options using returnBatchOpt function
    % // using notify syncBatch event
    % obj.startController('controllers.VolRenAppViewer', [], NaN);
    % @endcode
    
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
            % VOLRENAPPVIEWER - constructor for volume visualization window
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj = VolRenAppViewer(mibModel)
            %       obj = VolRenAppViewer(mibModel, parentController)
            %
            % Input Arguments:
            %   - **mibModel** — handle to MibModel
            %   - **varargin{1}** — handle to parent VolRenApp controller
            %
            % Usage:
            %   Example 1::
            %
            %     utils.startController(obj, 'controllers.VolRenAppViewer', obj);
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
            obj.view.gui.Visible = 'on';
            
            drawnow;

        end
        
        function closeWindow(obj)
            % closing VolRenAppViewer window
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
            % function updateWidgets(obj)
            % update widgets of this window
            
            %fprintf('childController:updateWidgets: %g\n', toc);
        end
        
        
    end
end