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
% Date: 03.06.2026

function startFiji(mibGUI)
% STARTFIJI - Start Fiji/ImageJ via Miji.
%
% Checks whether Miji is installed on the MATLAB path, then launches it in
% interactive mode (ImageJ toolbar visible). Skips the Miji check when
% running as a compiled standalone application.
%
% Requires Fiji to be installed (http://fiji.sc/Fiji).
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.fiji.startFiji()
%      utils.fiji.startFiji(mibGUI)
%
% Input Arguments:
%   - **mibGUI** *(optional)* - handle to the parent UIFigure used for
%     error dialogs; pass ``[]`` or omit to fall back to a standard dialog
%
% Updates
%

if nargin < 1; mibGUI = []; end

% link the Fiji libraries before probing for Miji: they are added lazily on
% the first use, so Fiji.app/scripts is not yet on the Matlab path here
utils.ensureJavaLibraries({'mij.jar', 'fiji'});

if ~isdeployed
    if isempty(which('Miji'))
        utils.dlgs.showErrorDialog(mibGUI, ...
            sprintf('Miji was not found!\n\nTo fix:\n1. Install Fiji (http://fiji.sc/Fiji)\n2. Add the Fiji.app location to MIB Preferences->External directories'), ...
            'Missing Miji!');
        return;
    end
end

if exist('MIJ', 'class') == 8
    if ~isempty(ij.gui.Toolbar.getInstance)
        ijInstance = char(ij.gui.Toolbar.getInstance.toString);
        % ij.gui.Toolbar[canvas1,3,41,548x27,invalid] - instance exists but window closed
        if contains(ijInstance, 'invalid')
            utils.fiji.Miji_wrapper(true);
        end
    else
        utils.fiji.Miji_wrapper(true);
    end
else
    utils.fiji.Miji_wrapper(true);
end

end
