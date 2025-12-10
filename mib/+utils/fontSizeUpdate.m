function fontSizeUpdate(hFig, Font)
% function fontSizeUpdate(hFig, fontSize)
% Update font size for text widgets
%
% Parameters:
% hFig: handle to the figure
% Font: - structure with font settings, possible fields
%   .FontName -> 'Arial'
%   .FontWeight -> 'normal'
%   .FontAngle -> 'normal'
%   .FontUnits -> 'points'
%   .FontSize -> 10
%
% Return values:
% 

%| 
% @b Examples:
% @code utils.fontSizeUpdate(obj.view.gui, obj.mibModel.preferences.System.Font);     // update the font properties from a child controller  @endcode

% Updates
% 

if ~isprop(hFig, 'RunningAppInstance')  % guide type of figure
    Font.FontSize = Font.FontSize - 4; % it looks that guide app font size is 4 units larger than corresponding appdesigner

    tempList = findall(hFig, 'Style', 'text');   % set font to text
    for i=1:numel(tempList)
        set(tempList(i), Font);
        % combine text and tooltip
        textStr = tempList(i).String;
        TooltipStr = tempList(i).TooltipString;
        if iscell(textStr)
            if isempty(TooltipStr) || numel(textStr{1}) > numel(TooltipStr) || strcmp(TooltipStr(1:numel(textStr{1})), textStr{1}) == 0
                tempList(i).TooltipString = sprintf('%s; %s', textStr{1}, TooltipStr);
            end
        else
            if isempty(TooltipStr) || numel(textStr) > numel(TooltipStr) || strcmp(TooltipStr(1:numel(textStr)), textStr) == 0
                if size(textStr,1) > 1  % reformat the char to lines
                    for ind = 2:size(textStr,1)
                        if ind==2
                            textOut = [strtrim(textStr(1,:)), '\n' strtrim(textStr(ind,:))];
                        else
                            textOut = [textOut, '\n' strtrim(textStr(ind,:))]; %#ok<AGROW>
                        end
                    end
                    textStr = textOut;
                end
                tempList(i).TooltipString = sprintf('%s; %s', textStr, TooltipStr);
                tempList(i).TooltipString = sprintf([textStr '; ' TooltipStr]);
            end
        end
    end

    tempList = findall(hFig,'Style','checkbox');    % set color to checkboxes
    for i=1:numel(tempList)
        set(tempList(i), Font);

        % combine text and tooltip
        textStr = tempList(i).String;
        if iscell(textStr); textStr = textStr{1}; end
        TooltipStr = tempList(i).TooltipString;
        tempList(i).TooltipString = sprintf('%s; %s', textStr, TooltipStr);
    end

    tempList = findall(hFig, 'Type', 'uipanel');    % set font to panels
    set(tempList, Font);

    tempList = findall(hFig, 'Style', 'radiobutton');    % set font to radiobuttons
    set(tempList, Font);

    tempList = findall(hFig, 'Type', 'uibuttongroup');    % set font to uibuttongroup
    set(tempList, Font);

    tempList = findall(hFig, 'Type', 'uicontrol');    % set font to buttons
    set(tempList, Font);

    tempList = findall(hFig, 'Type', 'uitable');    % set font to tables
    set(tempList, Font);
else    % app designer
    processChildren(hFig, Font);
end
end

function processChildren(h, Font)
% function processChildren(h, Font)
% iterate children of h and update their font name and size
%
% Parameters:
% h: handle to a child
% Font: - structure with font settings, possible fields
%   .FontName -> 'Arial'
%   .FontWeight -> 'normal'
%   .FontAngle -> 'normal'
%   .FontUnits -> 'points'
%   .FontSize -> 10

children = h.Children;
for i=1:numel(children)
    if isprop(children(i), 'FontName')
        children(i).FontName = Font.FontName;
        if isprop(children(i), 'FontSize') && ~strcmp(children(i).Type, 'uitabgroup')  % 'matlab.ui.container.Tab' does not have find size
            children(i).FontSize = Font.FontSize;  
        end
    end
    if isprop(children(i), 'Children')
        processChildren(children(i), Font); 
    end
end
end
