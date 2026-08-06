function img = addText2Img(img, textArray, positionList, options)
% ADDTEXT2IMG - Add text labels to a 2D image using Computer Vision Toolbox functions.
%
% Syntax:
%
%   .. code-block:: matlab
%
%      img = addText2Img(img, textArray, positionList, options)
%
% Requires ``insertText`` and ``insertMarker`` from the Computer Vision
% Toolbox.  Falls back to a legacy implementation when those are unavailable.
%
% Input Arguments:
%   - **img** - [numeric] 2D image to annotate
%   - **textArray** - [cell] labels to render, e.g. ``{'label1'; 'label2'}``
%   - **positionList** - [numeric] label positions ``[pointNo; x, y]``
%   - **options** *(optional)* - struct with rendering settings:
%
%     - ``.color``       - [numeric] text colour as an RGB vector or scalar grey value (default: ``0.5``)
%     - ``.fontSize``    - [numeric] font size index 1-7, mapping to pt 8-20 of Ubuntu Mono (default: ``2``)
%     - ``.markerText``  - [char] marker+text visibility: ``'Label + Value'`` *(default)*, ``'Label'`` (only label, no value), or ``'Value'`` (only value, no label)
%     - ``.markerShow``  - [logical] ``true`` - *(default)* show marker; ``false`` - do not show marker
%     - ``.AnchorPoint`` - [char] text-box reference point: ``'LeftTop'`` *(default)*, ``'LeftCenter'``, ``'LeftBottom'``, ``'CenterTop'``, ``'Center'``, ``'CenterBottom'``, ``'RightTop'``, ``'RightCenter'``, ``'RightBottom'``
%
% Output Arguments:
%   - **img** - [numeric] annotated 2D image
%
% .. note::
%    To print special characters, generate them with ``char(dec_index)``.
%    For example, replace ``\mu`` with the proper symbol:
%
%    .. code-block:: matlab
%
%       textArray = strrep(textArray, '\mu', char(956));
%
%    See https://unicode-table.com/en/ for character codes.
%
% Usage:
%
%   **Example 1** - add two coloured labels at specified positions
%
%   .. code-block:: matlab
%
%      textArray{1} = 'label1';
%      textArray{2} = 'label2';
%      positionList(1,:) = [50, 75];
%      positionList(2,:) = [150, 175];
%      options.color = [1 0 0];
%      options.fontSize = 3;
%      selection(:,:,5) = utils.addText2Img(selection(:,:,5), textArray, positionList, options);
%

% Updates
% this is an updated version of the function that uses matlab functions
% insertMarker and insertText, which are available from R2013a

if ~isfield(options, 'AnchorPoint'); options.AnchorPoint = 'LeftTop'; end
if ~isfield(options, 'color'); options.color = [0.5 0.5 0.5]; end
if ~isfield(options, 'fontSize'); options.fontSize = 2; end
if ~isfield(options, 'markerText'); options.markerText = 'Label + Value'; end
if ~isfield(options, 'markerShow'); options.markerShow = true; end

maxVal = double(intmax(class(img)));

fontSize = 2*options.fontSize+6;

% Always draw the position marker regardless of display mode
if options.markerShow
    img = insertMarker(img, positionList, '+', 'color', options.color*maxVal, 'size', 2);
end

% Draw text for modes that include a label, value, or both
if ismember(options.markerText, {'Label + Value', 'Label', 'Value'})
    img = insertText(img, positionList, textArray, 'FontSize', fontSize, ...
        'BoxOpacity',0, 'TextColor', options.color*maxVal, 'AnchorPoint', options.AnchorPoint);
end
end
