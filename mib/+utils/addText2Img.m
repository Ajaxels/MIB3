function img = addText2Img(img, textArray, positionList, options)
% function img = addText2Img(img, textArray, positionList, options)
% Add text label to the image, a new function introduced in MIB 2.22.
% Requires insertText and insertMarker functions from the Computer Vision System
% Toolbox. When these functions are not available mibAddText2Img is using
% an old function.
%
% Parameters:
%       img: image, 2D
%       textArray: a cell array with text, [textArray{1}=''label1''; textArray{2}=''label2'';]
%       positionList: position of a label [pointNo; x, y]
%       options: a structure with @em optional additional parameters
%           .color [@em optional, default color GREY] a number or a rgb-vector with a color for the text,
%                   @em for @em example: [1 0 0] - for red; or 0.5 - for grey
%           .fontSize [@em optional, default font size=2] a number with a font size from 1 to 7, that corresponds to pt8, 10 ... 20 of Ubuntu Mono font.
%           .markerText [@em an @em optional @em string, default
%                           'both'] when @b both show a label next to the position marker,
%                           when @b marker - show only the marker without the label, when
%                           @b text - show only text without marker
%           .AnchorPoint text box reference point, ''LeftTop'' (default) |
%           ''LeftCenter'' | ''LeftBottom'' | ''CenterTop'' | ''Center'' | ''CenterBottom'' | ''RightTop'' | ''RightCenter'' | ''RightBottom''
%
% Return values:
%   img: image 2D
%
% @note: if you need to print special characters generate them using
% char(dec_index) command. For example to replace all \mu with a proper u character use char(956) command:
% textArray = strrep(textArray, ''\mu'', char(956));
% see more codes: https://unicode-table.com/en/

%| 
% @b Examples:
% @code
% textArray{1}='label1';
% textArray{2}='label2';
% positionList(1,:) = [50, 75];
% positionList(2,:) = [150, 175];
% options.color = [1 0 0];
% options.fontSize = 3;
% selection(:,:,5) = utils.addText2Img(selection(:,:,5), textArray, positionList, options);      // add 2 labels to the selection layer
% @endcode

% Updates
% this is an updated version of the function that uses matlab functions
% insertMarker and insertText, which are available from R2013a

if ~isfield(options, 'AnchorPoint'); options.AnchorPoint = 'LeftTop'; end
if ~isfield(options, 'color'); options.color = [0.5 0.5 0.5]; end
if ~isfield(options, 'fontSize'); options.fontSize = 2; end
if ~isfield(options, 'markerText'); options.markerText = 'Label + Value'; end

maxVal = double(intmax(class(img)));

fontSize = 2*options.fontSize+6;

% Always draw the position marker regardless of display mode
img = insertMarker(img, positionList, '+', 'color', options.color*maxVal, 'size', 2);

% Draw text for modes that include a label, value, or both
if ismember(options.markerText, {'Label + Value', 'Label', 'Value'})
    img = insertText(img, positionList, textArray, 'FontSize', fontSize, ...
        'BoxOpacity',0, 'TextColor', options.color*maxVal, 'AnchorPoint', options.AnchorPoint);
end
end