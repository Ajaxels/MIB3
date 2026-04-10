function options = getOptions(obj)
% function options = getOptions(obj)
% get options of the class
%
% Return values:
% options: a structure with options

options = struct();
options.clipExtraThickness = obj.clipExtraThickness;
options.edgeActiveColor = obj.edgeActiveColor;
options.edgeColor = obj.edgeColor;
options.edgeThickness = obj.edgeThickness;
options.nodeActiveColor = obj.nodeActiveColor;
options.nodeColor = obj.nodeColor;
options.nodeRadius = obj.nodeRadius;

end
