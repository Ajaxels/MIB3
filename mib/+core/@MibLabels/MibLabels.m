classdef MibLabels < core.MibImage 
    % classdef MibLabels < MibImage 
    % a base label class of MIB3
    % The class inherits properties and function of the parent class
    % (core.MibImage). 
    % Constructor requires initialization as 
    % "obj = obj@core.MibImage(img, meta, type);  % Call parent constructor" 

    properties
        labelsVariable
        % @em labelsVariable is a variable name in the mat-file to keep the 'Labels' layer'; default: 'labelsVariable'
        materialColors
        % a matrix of colors [0-1] for materials of the 'Model', [materialIndex, R G B]
        materialNames
        % an array of strings to define names of materials of Labels
    end

    methods
        function obj = MibLabels(img, meta, type)
            % function obj = MibLabels(img, meta, type)
            % constructor of MibLabels class, inherits properties and
            % methods of MibImage
            %
            % Parameters:
            % img: an 2D-5D image stack
            % meta: a structure with parameters of the dataset, can be @e []
            % type: type of the img, 'model', 'labels', 'labels63'

            if nargin < 3; type = []; end
            if nargin < 2; meta = []; end
            if nargin < 1; img = []; end
            type = 'labels';

            obj = obj@core.MibImage(img, meta, type);  % Call parent constructor
        end

        
    end
end