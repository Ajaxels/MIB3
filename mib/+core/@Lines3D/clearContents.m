function clearContents(obj)
% function clearContents(obj)
% Set all elements of the class to default values
%
% Parameters:
%
% Return values:

%|
% @b Examples:
% @code obj.mibModel.I{obj.mibModel.id}.Lines3D.clearContents(); @endcode

obj.G = [];
obj.noTrees = 0;
obj.treeLengths = [];
obj.activeNodeId = [];
obj.extraEdgeFields = [];
obj.extraEdgeFieldsNumeric = [];
obj.extraNodeFields = [];
obj.extraNodeFieldsNumeric = [];
obj.defaultNodeName = 'Node';
obj.defaultTreeName = 'Tree';
obj.filename = [];

obj.updateNodeStrel(obj.nodeRadius);     % update strel element

end
