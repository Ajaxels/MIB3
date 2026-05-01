function createCentralMarker(obj, centerX, centerY, options)
% CREATECENTRALMARKER - create a central marker on the image axes.
%
% Syntax:
%   .. code-block:: matlab
%
%      obj.createCentralMarker(centerX, centerY)
%      obj.createCentralMarker(centerX, centerY, options)
%
% Creates a simple crosshair marker at the specified position on the
% currently selected image view. The marker is non-interactive and
% always displays on top of the image.
%
% Input Arguments:
%   - **centerX** — [double] X coordinate for marker position (in image data units)
%   - **centerY** — [double] Y coordinate for marker position (in image data units)
%   - **options** *(optional)* — [struct] marker appearance settings with fields:
%
%     - ``.Marker`` — [char] marker symbol (default: ``'+'``)
%
%       - ``'+'`` — crosshair
%       - ``'o'`` — circle
%       - ``'*'`` — asterisk
%       - ``'.'`` — point
%       - ``'x'`` — X mark
%       - ``'square'`` — square
%       - ``'diamond'`` — diamond
%
%     - ``.MarkerSize`` — [double] marker size in points (default: ``12``)
%     - ``.Color`` — [char|RGB] marker color (default: ``'y'`` yellow)
%     - ``.LineWidth`` — [double] marker line thickness (default: ``2``)
%
% **Example 1** — Place default marker at axes center:
%
%   .. code-block:: matlab
%
%      ax = obj.mibController.cImageDoc{obj.mibModel.Sets.selectedSet}.handles.imViewAxes;
%      centerX = mean(ax.XLim);
%      centerY = mean(ax.YLim);
%      obj.createCentralMarker(centerX, centerY);
%
% **Example 2** — Create custom red circle marker:
%
%   .. code-block:: matlab
%
%      opts.Marker = 'o';
%      opts.Color = 'r';
%      opts.MarkerSize = 15;
%      opts.LineWidth = 3;
%      obj.createCentralMarker(100, 200, opts);
%
% **Example 3** — Create cyan crosshair:
%
%   .. code-block:: matlab
%
%      opts.Color = [0 1 1];  % RGB cyan
%      obj.createCentralMarker(centerX, centerY, opts);
%

% Set default visualization parameters

defaultOptions = struct();
defaultOptions.Marker = '+';  % '+', 'o', '*', '.', 'x', 'square', 'diamond'
defaultOptions.MarkerSize = 12;
defaultOptions.Color = 'y';
defaultOptions.LineWidth = 2;

if nargin < 4
    options = defaultOptions; 
else
    options = utils.concatenateStructures(defaultOptions, options);
end

% Get axes handle for current image view
selectedSet = obj.mibModel.Sets.selectedSet;
axesHandle = obj.mibController.cImageDoc{selectedSet}.handles.imViewAxes;

% Delete old marker if it exists to prevent stacking
if isprop(obj.mibController.cImageDoc{selectedSet}, 'centralMarker') && ...
        ~isempty(obj.mibController.cImageDoc{selectedSet}.centralMarker) && ...
        isvalid(obj.mibController.cImageDoc{selectedSet}.centralMarker)
    delete(obj.mibController.cImageDoc{selectedSet}.centralMarker);
end

% Create marker as line object with no connecting line
obj.mibController.cImageDoc{selectedSet}.centralMarker = line(...
    axesHandle, ...
    centerX, centerY, ...
    'Marker', options.Marker, ...
    'MarkerSize', options.MarkerSize, ...
    'Color', options.Color, ...
    'LineStyle', 'none', ...
    'LineWidth', options.LineWidth, ...
    'PickableParts', 'none', ...
    'Tag', 'centralMarker');
end
