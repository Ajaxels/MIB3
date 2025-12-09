% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <https://www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi 
% Date: 25.04.2023

classdef WelcomeTips < handle
    % @type WelcomeTips class is a template class for using with
    % GUI developed using appdesigner of Matlab
    %
    % @code
    % obj.startController('WelcomeTips'); // as GUI tool
    % @endcode
    % or 
    % @code 
    % // a code below was used for mibImageArithmeticController
    % BatchOpt.Parameter = 'test';  // fill edit boxes as strings
    % BatchOpt.Checkbox = true;     // fill checkboxes with logicals: true/false
    % BatchOpt.Popup = {'value'};        // value for the popups as a cell
    % BatchOpt.Radio = {'Radio1'};          // selection of radio buttons, as cell with the handle of the target radio button
    % BatchOpt.showWaitbar = true;  // show or not the waitbar
    % obj.startController('WelcomeTips', [], BatchOpt); // start WelcomeTips in the batch mode
    % @endcode
    % or
    % @code
    % // trigger return of the possible Options using returnBatchOpt function
    % // using notify syncBatch event
    % obj.startController('WelcomeTips', [], NaN);
    % @endcode
    
	% Updates
	%     
    
    properties
        mibModel
        % handles to mibModel
        view
        % handle to the view / TipsAppGUI
        listener
        % a cell array with handles to listeners
    end
    
    events
        %> Description of events
        closeEvent
        % event firing when window is closed
    end
    
    methods (Static)
        % function ViewListner_Callback(obj, src, evnt)
        %     switch evnt.EventName
        %         case {'updateGuiWidgets'}
        %             obj.updateWidgets();
        %     end
        % end
    end
    
    methods
        function obj = WelcomeTips(mibModel, varargin)
            obj.mibModel = mibModel;    % assign model
            
            guiName = 'views.TipsAppGUI';
            obj.view = core.ChildView(obj, guiName); % initialize the view
            
            obj.view.handles.showTipsCheck.Value = obj.mibModel.preferences.Tips.ShowTips;

            % move the window to the left hand side of the main window
            % USE "obj.mibModel.mibGUI.WindowBounds" as the parent window
            % positions
            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'center', 'center');
            
            % update font and size
            % you may need to replace "obj.view.handles.text1" with tag of any text field of your own GUI
            % % this function is not yet
            if obj.view.handles.showTipsCheck.FontSize ~= obj.mibModel.preferences.System.Font.FontSize ...
                    || ~strcmp(obj.view.handles.showTipsCheck.FontName, obj.mibModel.preferences.System.Font.FontName)
                utils.updateFontSize(obj.view.gui, obj.mibModel.preferences.System.Font);
            end 

            obj.updateWidgets();
			
			% add listener to obj.mibModel and call controller function as a callback
            %obj.listener{1} = addlistener(obj.mibModel, 'updateGuiWidgets', @(src,evnt) obj.ViewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
        end
        
        function closeWindow(obj)
            obj.mibModel.preferences.Tips.ShowTips = obj.view.handles.showTipsCheck.Value;
            obj.mibModel.preferences.Tips.CurrentTipIndex = obj.mibModel.preferences.Tips.CurrentTipIndex + 1;
            if obj.mibModel.preferences.Tips.CurrentTipIndex > numel(obj.mibModel.preferences.Tips.Files)
                obj.mibModel.preferences.Tips.CurrentTipIndex = 1;
            end
            
            % closing WelcomeTips window
            if isvalid(obj.view.gui)
                delete(obj.view.gui);   % delete childController window
            end
            
            % delete listeners, otherwise they stay after deleting of the
            % controller
            for i=1:numel(obj.listener)
                delete(obj.listener{i});
            end
            
            notify(obj, 'closeEvent');      % notify mibController that this child window is closed
        end
        
        function updateWidgets(obj)
            % function updateWidgets(obj)
            % update widgets of this window
           
            fnIndex = max([1, obj.mibModel.preferences.Tips.CurrentTipIndex]);
            
            % on PC path is file://c:/... or //ad.xxxxx.xxx.xx
            % on Mac file:///Volumes/Transcend/...
%             if ispc
%                 if obj.mibModel.preferences.Tips.Files{fnIndex}(1) == '\'
%                     fileText = 'file:'; 
%                 else
%                     fileText = 'file:/'; 
%                 end    % check for a installation in the network path \\ad.xxxx
%             else
%                 fileText = 'file://';
%             end
            filename = obj.mibModel.preferences.Tips.Files{fnIndex};
%             linkURL = strrep([fileText filename],'\','/');
            obj.view.handles.webBrowser.HTMLSource = filename;
        end

        function nextTipBtn_Callback(obj)
            % function nextTipBtn_Callback(obj)
            % display the next tip
            
            obj.mibModel.preferences.Tips.CurrentTipIndex = obj.mibModel.preferences.Tips.CurrentTipIndex + 1;
            if obj.mibModel.preferences.Tips.CurrentTipIndex > numel(obj.mibModel.preferences.Tips.Files)
                obj.mibModel.preferences.Tips.CurrentTipIndex = 1;
            end
            obj.updateWidgets();
        end
        
        function previousTipBtn_Callback(obj)
            % function previousTipBtn_Callback(obj)
            % display the previous tip
            
            obj.mibModel.preferences.Tips.CurrentTipIndex = obj.mibModel.preferences.Tips.CurrentTipIndex - 1;
            if obj.mibModel.preferences.Tips.CurrentTipIndex == 0
                obj.mibModel.preferences.Tips.CurrentTipIndex = numel(obj.mibModel.preferences.Tips.Files);
            end
            obj.updateWidgets();
        end
        
    end
end