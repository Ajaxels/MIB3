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

classdef About < handle
% ABOUT - Controller for the About dialog window.

    properties
        mibModel
        % handle to the model
        view
        % handle to the view
    end

    events
        CloseEvent
        % fires when the window is closed
    end

    methods

        function obj = About(mibModel, versionText)
        % ABOUT - Constructor for the About dialog controller.
        %
        % Syntax:
        %
        %   .. code-block:: matlab
        %
        %      controller = controllers.About(mibModel, versionText)
        %
        % Input Arguments:
        %   - **mibModel** — handle to the MibModel instance
        %   - **versionText** — [char] full version string, e.g.
        %     ``'Microscopy Image Browser ver. 2025.12 / 05.12.2025'``
        %
        % Output Arguments:
        %   - **controller** — handle to the constructed ``About`` controller

            obj.mibModel = mibModel;

            % get MATLAB release year for the copyright line
            matlabVersion = ver('Matlab');
            matlabYear = matlabVersion.Date(end-3:end);
            mathworksString = sprintf('MATLAB(r). (c) 1984 - %s The MathWorks, Inc.', matlabYear);

            obj.view = core.ChildView(obj, 'views.AboutGUI');

            % load splash image and overlay version date text
            %mibPath = obj.mibModel.mibPath;
            %splashImage = imread(fullfile(mibPath, 'assets', 'images', 'about_splash_410px.png'));
            % textOptions.color = [1 1 0];
            % textOptions.fontSize = 6;
            % textOptions.markerText = 'Label';
            % textOptions.AnchorPoint = 'LeftBottom';
            % textOptions.markerShow = false;
            %extraText = '';
            %if isdeployed
            %     splashImage = utils.addText2Img(splashImage, obj.mibModel.mibVersion, [10, 486], textOptions);
            %     splashImage = utils.addText2Img(splashImage, 'for Academic research', [10, 510], textOptions);
            %     extraText = 'deployed version for Academic research';
            %else
            %     splashImage = utils.addText2Img(splashImage, obj.mibModel.mibVersion, [10, 508], textOptions);
            %end
            % update splash image
            %obj.view.handles.splashImage.ImageSource = splashImage;
            obj.view.gui.Name = 'About Microscopy Image Browser';

            % populate text widgets
            if isdeployed
                extraText = 'deployed version for Academic research';
                obj.view.handles.titleText.Text = sprintf('Microscopy Image Browser\n%s\n%s', extraText, obj.mibModel.mibVersion);
            else
                obj.view.handles.titleText.Text = sprintf('Microscopy Image Browser\n%s', obj.mibModel.mibVersion);
            end
            
            % get computer name for override default settings file
            computerName = utils.identifyComputerName();

            obj.view.handles.descriptionText.Value = {
                'image segmentation and beyond'
                'http://mib.helsinki.fi'
                ''
                'Core developer:'
                '     Ilya Belevich'
                '     ilya.belevich@helsinki.fi'
                ''
                'Developers:'
                '     Merja Joensuu'
                '     Darshan Kumar'
                '     Helena Vihinen'
                '     Eija Jokitalo'
                ''
                'Electron Microscopy Unit'
                'Institute of Biotechnology'
                'University of Helsinki'
                'Finland'
                ''
                mathworksString
                ''
                sprintf('Computer name: %s', computerName)
                };

            Font = obj.mibModel.preferences.System.Font;
            if obj.view.handles.descriptionText.FontSize ~= Font.FontSize ...
                    || ~strcmp(obj.view.handles.descriptionText.FontName, Font.FontName)
                utils.fontSizeUpdate(obj.view.gui, Font);
            end

            obj.addCallbacks();

            obj.view.gui = utils.moveWindowOutside(obj.view.gui, obj.mibModel.mibGUI, 'center', 'center');  % center on screen
            obj.view.gui.WindowStyle = 'modal';
            obj.view.gui.Visible = true;
        end

        function addCallbacks(obj)
        % ADDCALLBACKS - Wire all widget callbacks for the About dialog.
            obj.view.gui.CloseRequestFcn = @(~,~) obj.closeWindow();
            obj.view.handles.closeBtn.ButtonPushedFcn = @(~,~) obj.closeWindow();
            obj.view.handles.homepageBtn.ButtonPushedFcn = @(~,~) web('http://mib.helsinki.fi', '-browser');
            obj.view.handles.licenseButton.ButtonPushedFcn = @(~,~) web('https://mib.helsinki.fi/license.html', '-browser');

        end

        function closeWindow(obj)
        % CLOSEWINDOW - Close the About dialog and fire CloseEvent.
            if isvalid(obj.view.gui); delete(obj.view.gui); end
            notify(obj, 'CloseEvent');
        end

    end
end
