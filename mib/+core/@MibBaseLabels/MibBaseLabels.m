classdef MibBaseLabels < core.MibBaseImage 
    % classdef MibBaseLabels < MibBaseImage 
    % a base label class of MIB3
    % The class inherits properties and function of the parent class
    % (core.MibBaseImage). 
    % Constructor requires initialization as 
    % "obj = obj@core.MibBaseImage(img, meta, type);  % Call parent constructor" 

    properties
        labelsVariable
        % @em labelsVariable is a variable name in the mat-file to keep the 'Labels' layer'; default: 'labelsVariable'
        materialColors
        % a matrix of colors [0-1] for materials of the 'Model', [materialIndex, R G B]
        materialNames
        % an array of strings to define names of materials of Labels
    end

    methods
        function obj = MibBaseLabels(img, meta, type)
            
            if nargin < 3; type = 'labels'; end
            if nargin < 2; meta = []; end
            if nargin < 1; img = []; end

            obj = obj@core.MibBaseImage(img, meta, type);  % Call parent constructor
        end

        
    end
end