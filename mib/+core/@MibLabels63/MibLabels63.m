classdef MibLabels63 < core.MibImage 
    % classdef MibLabels63 < MibImage 
    % memory optimized label class of MIB3 capable to encode 63 materials,
    % mask and selection layers within the same 8-bit container.
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
        % declaration of methods
        dataset = getData(obj, type, orient, materialIndex, options)        % get dataset

        result = setData(obj, dataset, type, orient, materialIndex, options)        % update contents of the class

        function obj = MibLabels63(img, meta, type)
            % function obj = MibLabels63(img, meta, type)
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
            type = 'labels63';

            % init the class using core.MibImage and forcing the type to be labels63
            obj = obj@core.MibImage(img, meta, type);  % Call parent constructor
            
        end
    end
end
