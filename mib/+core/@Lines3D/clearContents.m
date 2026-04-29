function clearContents(obj)
% CLEARCONTENTS - Set all elements of the class to default values.
%
% Syntax:
%   function clearContents(obj)
%
% Input Arguments:
%
% Output Arguments:
%
% Usage:
%   **Example 1**
%
%   .. code-block:: matlab
%
%
%     obj.mibModel.I{obj.mibModel.id}.Lines3D.clearContents();
%

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
