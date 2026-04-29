function options = getOptions(obj)
% GETOPTIONS - get options of the class.
%
% Syntax:
%   function options = getOptions(obj)
%
% Output Arguments:
%   - **options** — a structure with options
%

options = struct();
options.clipExtraThickness = obj.clipExtraThickness;
options.edgeActiveColor = obj.edgeActiveColor;
options.edgeColor = obj.edgeColor;
options.edgeThickness = obj.edgeThickness;
options.nodeActiveColor = obj.nodeActiveColor;
options.nodeColor = obj.nodeColor;
options.nodeRadius = obj.nodeRadius;

end
