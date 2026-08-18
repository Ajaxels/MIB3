function strelSize = getStrelSizeString(obj)
% GETSTRELSIZESTRING - build the StrelSize string from the strel1/strel2 panel widgets.
%
% Syntax:
%   .. code-block:: matlab
%
%      strelSize = obj.getStrelSizeString()
%
% ``strel2`` (``obj.view.handles.panels.selection.handles.strel2``) is an
% optional numeric field (``AllowEmpty``); when left blank the result is a
% single-value isotropic size, when filled in it is appended as the second
% (anisotropic) radius for ``utils.parseStrelSize``.
%
% Output Arguments:
%   - **strelSize** - [char] ``'5'`` or ``'5 2'``, ready for ``utils.parseStrelSize``
%

% Updates
%

strelSize = num2str(obj.handles.strel1.Value);
if ~isempty(obj.handles.strel2.Value)
    strelSize = sprintf('%s %g', strelSize, obj.handles.strel2.Value);
end
end
