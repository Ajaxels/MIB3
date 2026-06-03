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

function stopFiji(mibGUI)
% STOPFIJI - Stop Fiji/ImageJ and close all images opened in it.
%
% Requires Fiji to be installed (http://fiji.sc/Fiji).
%
% Syntax:
%   .. code-block:: matlab
%
%      utils.fiji.stopFiji()
%      utils.fiji.stopFiji(mibGUI)
%
% Input Arguments:
%   - **mibGUI** *(optional)* — handle to the parent UIFigure used for
%     dialogs; pass ``[]`` or omit to fall back to standard dialogs
%
% Updates
% 01.10.2021 - added automatic closing of all windows in Fiji
%

if nargin < 1; mibGUI = []; end

questOpt.Icon = 'puffin_warning';
answer = utils.dlgs.inputQuestDlg(mibGUI, ...
    'You are going to close Fiji, all images opened there are going to be closed. Continue?', ...
    'Close Fiji', 'Close Fiji and all images', 'Cancel', 'Cancel', questOpt);
if strcmp(answer, 'Cancel'); return; end

try
    MIJ.closeAllWindows();
    list = MIJ.getListImages;
catch err
    isNullPointer = contains(err.message, 'java.lang.NullPointerException');
    if isfield(err, 'ExceptionObject')
        isNullPointer = strcmp(err.ExceptionObject, 'java.lang.NullPointerException');
    end
    if isNullPointer
        MIJ.exit();
        return;
    end
end

dlgOpt.MsgBoxOnly = true;
dlgOpt.Icon = 'puffin_warning';
dlgOpt.HeaderLines = 1;
utils.dlgs.inputUniversalDlg(mibGUI, ...
    'Please close all opened in Fiji windows before stopping!', {}, {}, 'Close windows in Fiji', dlgOpt);

end
