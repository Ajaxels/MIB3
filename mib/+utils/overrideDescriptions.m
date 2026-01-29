function stopped = overrideDescriptions(handles, developerMode, fieldPath)
% function stopped = overrideDescriptions(handles, developerMode, fieldPath, exclusionList)
% Override Description property of widgets to add the widget handle name to
% the beginning of the Description field depending on the developerMode
% setting.
%
% Parameters:
% handles: handles structure of the view class (obj.handles)
% developerMode: logical switch, when 
%   true  - adds the handle label to the beginning of the Description field that is shown as a tooltip
%   false - removes the handle label from the beginning of the Description field that is shown as a tooltip
% fieldPath: char, optional string to specify the parent name when
% generating the handle. This text will be added before the handle tag into
% the tooltip
%
% Return values:
% stopped: logical true if function exited early due to no change needed or first update done

%|
% @b Examples:
% @code
% // call inside the view class
% developerMode = true;
% utils.overrideDescriptions(obj.handles, developerMode); // add handle label to the tooltip
% @endcode

arguments (Input)
    handles
    developerMode (1,1) logical
    fieldPath char = 'obj.handles'
end

arguments (Output)
    stopped logical
end

if nargin < 3
    fieldPath = 'obj.handles';
end

if isempty(handles); return; end

fields = fieldnames(handles);
stopped = false;

for i = 1:numel(fields)
    fname = fields{i};
    current = handles.(fname);
    currentPath = sprintf('%s.%s', fieldPath, fname);

    if isstruct(current)
        % Recurse into nested struct
        stopped = utils.overrideDescriptions(current, developerMode, currentPath);
        if stopped; return; end % stop the function since no change is needed
    elseif isobject(current)
        % Check if object has 'Description'/'Tooltip'/'Text' property
        updateDescription = false;
        outputTypeCell = false;

        if isprop(current, 'Tooltip')  % appdesigner widget
            currentDescription = cell2mat(current.Tooltip);
            updateDescription = true;
            outputTypeCell = true; % currentDescription should be converted to cell
        elseif isprop(current, 'Description')  % AppContainers widget
            outputFieldName = 'Description';
            % quick access buttons
            if isa(current, 'matlab.ui.internal.toolstrip.qab.QABPushButton') || ...
                isa(current, 'matlab.ui.internal.toolstrip.impl.QABToggleButton')    
                outputFieldName = 'Text';
            end
            currentDescription = current.(outputFieldName);
            updateDescription = true;
        end
        
        if updateDescription
            prefix = [currentPath ': '];

            if developerMode % Add handle label to Description
                % Check if prefix is already present
                if ~isempty(currentDescription) && startsWith(currentDescription, prefix)
                    % Prefix already present => no change needed, stop
                    stopped = true;
                    return;
                else
                    currentDescription = sprintf('%s:\n%s', currentPath, currentDescription);
                end
            else % Remove handle label from Description
                if ~isempty(currentDescription) && startsWith(currentDescription, prefix)
                    % Remove handle path from Description
                    currentDescription = strrep(currentDescription, [currentPath ': '], '');
                else
                    % Prefix not present => no change needed, stop
                    stopped = true;
                    return;
                end
            end
            
            if ~outputTypeCell
                handles.(fname).(outputFieldName) = currentDescription;
            else
                handles.(fname).Tooltip = {currentDescription};
            end
        end
    end
end


end


