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
% along with this program.  If not, see <https:% www.gnu.org/licenses/>

% Author: Ilya Belevich, University of Helsinki (ilya.belevich @ helsinki.fi)
% part of Microscopy Image Browser, http:\\mib.helsinki.fi 
% Date: 25.04.2023

classdef (ConstructOnLoad) ToggleEventData < event.EventData
    % TOGGLEEVENTDATA - Event data container for passing parameters with notifications.
    %
    % Wraps arbitrary parameters into event data for propagation through the event
    % notification system. Inherits from ``event.EventData`` for compatibility with
    % MATLAB's event framework.
    
    properties
        Parameters
    end
    
    methods
        function data = ToggleEventData(newParameter)
            % TOGGLEEVENTDATA - Constructor for event data wrapper.
            %
            % Syntax:
            %   .. code-block:: matlab
            %
            %       data = ToggleEventData(newParameter)
            %
            % Input Arguments:
            %   - **newParameter** — [any type] data to be passed to event listeners
            %
            % Output Arguments:
            %   - **data** — [ToggleEventData] event data object with wrapped parameter
            %
            
            data.Parameters = newParameter;
        end
    end
end
