classdef MibLabels < core.MibImage 
    % classdef MibLabels < MibImage 
    % a base label class of MIB3
    % The class inherits properties and function of the parent class
    % (core.MibImage). 
    % Constructor requires initialization as 
    % "obj = obj@core.MibImage(img, meta);  % Call parent constructor" 

    properties
        labelsVariable
        % @em labelsVariable is a variable name in the mat-file to keep the 'Labels' layer'; default: 'labelsVariable'
        materialColors
        % a matrix of colors [0-1] for materials of the 'Model', [materialIndex, R G B]
        materialNames
        % an array of strings to define names of materials of Labels
        maxMaterials = 255;   % can also be 127 (with negative part), 32767 (with negative part), 65535
        % maximal number of materials available in this model type
    end

    methods
        
        fnOut = save(obj, filename, options)        % Override of MibImage.save(); adds materialNames/materialColors/labelsVariable to metadata before dispatching to io.SaverFactory

        function obj = MibLabels(img, meta)
            % function obj = MibLabels(img, meta)
            % constructor of MibLabels class, inherits properties and
            % methods of MibImage
            %
            % Parameters:
            % img: an 2D-5D image stack
            % meta: a structure with parameters of the dataset, can be @e []
            
            if nargin < 2; meta = utils.defaults.initializeImgInfo(); end
            if nargin < 1; img = []; end
            
            obj = obj@core.MibImage(img, meta);  % Call parent constructor
            obj.filename = 'Labels_none.model';
        end
    end
end