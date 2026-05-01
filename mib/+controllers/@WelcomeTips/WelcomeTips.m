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
% WELCOMETIPS - Controller for the Welcome Tips dialog — displays tips at startup.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.startController('WelcomeTips');
%
% The Welcome Tips dialog displays helpful tips to users. It can be launched
% as a GUI tool or in batch mode by providing a BatchOpt structure.     
    
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
        CloseEvent
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
            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.showTipsCheck.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.showTipsCheck.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end 

            obj.updateWidgets();
            obj.view.gui.Icon = fullfile(obj.mibModel.mibPath, 'assets', 'icons', 'mib_icon_16px.png');
            obj.view.gui.Visible = 'on';    % turn on the window 

			% add listener to obj.mibModel and call controller function as a callback
            %obj.listener{1} = addlistener(obj.mibModel, 'updateGuiWidgets', @(src,evnt) obj.ViewListner_Callback(obj, src, evnt));    % listen changes in number of ROIs
        end
        
        function closeWindow(obj)
            % CLOSEWINDOW - close the Welcome Tips window.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.closeWindow()
            %
            % **Example** — close the tips window:
            %
            %   .. code-block:: matlab
            %
            %      obj.closeWindow();
            %
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
            
            notify(obj, 'CloseEvent');      % notify mibController that this child window is closed
        end
        
        function updateWidgets(obj)
            % UPDATEWIDGETS - update the web browser display with the current tip.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       obj.updateWidgets()
            %
            % **Example** — refresh the tips display:
            %
            %   .. code-block:: matlab
            %
            %      obj.updateWidgets();
           
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
            % NEXTTIPBTN_CALLBACK - display the next tip.
            %
            % Syntax:
            %   function nextTipBtn_Callback(obj)
            %
            
            obj.mibModel.preferences.Tips.CurrentTipIndex = obj.mibModel.preferences.Tips.CurrentTipIndex + 1;
            if obj.mibModel.preferences.Tips.CurrentTipIndex > numel(obj.mibModel.preferences.Tips.Files)
                obj.mibModel.preferences.Tips.CurrentTipIndex = 1;
            end
            obj.updateWidgets();
        end
        
        function previousTipBtn_Callback(obj)
            % PREVIOUSTIPBTN_CALLBACK - display the previous tip.
            %
            % Syntax:
            %   function previousTipBtn_Callback(obj)
            %
            
            obj.mibModel.preferences.Tips.CurrentTipIndex = obj.mibModel.preferences.Tips.CurrentTipIndex - 1;
            if obj.mibModel.preferences.Tips.CurrentTipIndex == 0
                obj.mibModel.preferences.Tips.CurrentTipIndex = numel(obj.mibModel.preferences.Tips.Files);
            end
            obj.updateWidgets();
        end
        
    end
end
